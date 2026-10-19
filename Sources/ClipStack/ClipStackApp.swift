import SwiftUI
import AppKit
import ClipStackCore
import KeyboardShortcuts

@main
struct ClipStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let windowOriginDefaultsKey = "ClipStack.windowOrigin"

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var window: NSWindow?
    private var historyStore: HistoryStore!
    private var imageStorage: ImageStorage!
    private var clipboardMonitor: ClipboardMonitor!
    private var deletionCleanupTask: Task<Void, Never>?
    private var pasteQueue = SequentialPasteQueue()
    private var lastSequencePaste = Date.distantPast
    private var pasteService: PasteService!
    private var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅作为菜单栏应用运行：不显示 Dock 图标和 App 切换器图标。
        NSApp.setActivationPolicy(.accessory)

        let dbPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipStack", isDirectory: true)
            .appendingPathComponent("history.db")
            .path
        imageStorage = ImageStorage(storageDirectory: ImageStorage.defaultDirectory())
        do {
            historyStore = try HistoryStore(path: dbPath, maxItems: 500)
            Task {
                do { try await ClipboardPipeline.shared.bootstrap(store: historyStore, storage: imageStorage) }
                catch { AppSettings.shared.message = "启动整理失败：\(error.localizedDescription)" }
            }
        } catch {
            fatalError("初始化数据库失败: \(error)")
        }
        clipboardMonitor = ClipboardMonitor(store: historyStore, imageStorage: imageStorage)
        pasteService = PasteService(imageStorage: imageStorage)

        // 不在启动时请求辅助功能权限：记录剪贴板不需要它，
        // 无条件请求会导致每次启动都弹系统授权框并跳转「系统设置」。
        // 真正要模拟 ⌘V 时才提示（见 ensureAccessibilityPermission）。
        clipboardMonitor.start()
        setUpIslandWindow()
        let store = historyStore!, storage = imageStorage!
        deletionCleanupTask = Task {
            var revision: Int?
            var nextDeadline: Date?
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                    let currentRevision = try store.changeCount()
                    if currentRevision != revision {
                        nextDeadline = try store.nextDeletionDeadline()
                        revision = currentRevision
                    }
                    if let deadline = nextDeadline, deadline <= Date() {
                        try await ClipboardPipeline.shared.finalizeDeletions(store: store, storage: storage)
                        nextDeadline = try store.nextDeletionDeadline()
                        revision = try store.changeCount()
                    }
                } catch is CancellationError { return }
                catch { AppSettings.shared.message = "删除清理失败：\(error.localizedDescription)" }
            }
        }

        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = ClipStackIcon.menuBarImage()
            button.action = #selector(statusClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ClipStack · 左键打开，右键设置"
        }
        AppSettings.shared.onPauseChange = { [weak self] paused in
            if paused { self?.clipboardMonitor.stop() }
            else { self?.clipboardMonitor.start() }
            self?.statusItem.button?.appearsDisabled = paused
        }
        AppSettings.shared.onMaintenance = { [weak self] in self?.performMaintenance() }
        AppSettings.shared.onStorageRefresh = { [weak self] in self?.refreshStorageSummary() }
        AppSettings.shared.onClearHistory = { [weak self] includingFavorites in self?.clearHistory(includingFavorites: includingFavorites) }
        AppSettings.shared.onClearCache = { [weak self] in self?.clearRegenerableCaches() }
        AppSettings.shared.onIslandChange = { [weak self] enabled in self?.islandController?.toggleEnabled(enabled) }

        AppSettings.shared.onStartSequence = { [weak self] ids in
            guard let self, !ids.isEmpty else { return }
            self.pasteQueue.start(ids: ids)
            AppSettings.shared.sequenceActive = true
            self.updateSequenceStatus()
            self.closeWindow()
            self.pasteService.restorePreviousApplication()
        }
        AppSettings.shared.onStopSequence = { [weak self] in self?.stopSequence() }
        KeyboardShortcuts.onKeyUp(for: .pasteNext) { [weak self] in self?.pasteNextInSequence() }

        // 全局快捷键 ⌘⌃J
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.toggleWindow()
        }
    }

    private func updateSequenceStatus() {
        AppSettings.shared.sequenceNextID = pasteQueue.nextID
        let status = "顺序粘贴 \(pasteQueue.position)/\(pasteQueue.ids.count) · ⌘⌃V 下一条"
        AppSettings.shared.sequenceStatus = status
        statusItem.button?.title = " \(pasteQueue.position)/\(pasteQueue.ids.count)"
        statusItem.button?.toolTip = status
    }

    @objc private func stopSequence() {
        pasteQueue.stop()
        AppSettings.shared.sequenceNextID = nil
        AppSettings.shared.sequenceActive = false
        AppSettings.shared.sequenceStatus = ""
        statusItem.button?.title = ""
        statusItem.button?.toolTip = "ClipStack · 左键打开，右键设置"
    }

    private func pasteNextInSequence() {
        guard let id = pasteQueue.nextID else {
            AppSettings.shared.sequenceStatus = "请先选择正序或倒序，再点击“开始顺序粘贴”"
            AppSettings.shared.message = "顺序粘贴尚未启动。"
            showWindow()
            return
        }
        guard Date().timeIntervalSince(lastSequencePaste) > 0.4 else { return }
        guard PasteService.hasAccessibilityPermission else {
            AppSettings.shared.sequenceStatus = "请先授予辅助功能权限，再按 ⌘⌃V 重试"
            showSequenceError()
            NSSound.beep()
            return
        }
        do {
            guard let item = try historyStore.all().first(where: { $0.id == id }),
                  item.missingFilePaths.isEmpty else {
                AppSettings.shared.sequenceStatus = "下一条已删除或文件失效，队列未前进；请停止后重新选择"
                showSequenceError()
                NSSound.beep()
                return
            }
            let sent = pasteService.pasteIntoCurrentApplication(item: item)
            clipboardMonitor.ignorePasteboardChangeCount(NSPasteboard.general.changeCount)
            guard sent else {
                AppSettings.shared.sequenceStatus = "未发送粘贴，请聚焦目标应用的输入框后重试"
                showSequenceError()
                NSSound.beep()
                return
            }
            lastSequencePaste = Date()
            pasteQueue.advance()
            updateSequenceStatus()
            if pasteQueue.nextID == nil {
                let count = pasteQueue.ids.count
                stopSequence()
                AppSettings.shared.sequenceStatus = "已发送全部 \(count) 条粘贴"
            }
        } catch {
            AppSettings.shared.sequenceStatus = "读取失败：\(error.localizedDescription)"
            showSequenceError()
        }
    }

    private func showSequenceError() {
        let alert = NSAlert()
        alert.messageText = "顺序粘贴未发送"
        alert.informativeText = AppSettings.shared.sequenceStatus
        alert.addButton(withTitle: "知道了")
        let needsPermission = !PasteService.hasAccessibilityPermission
        if needsPermission { alert.addButton(withTitle: "打开辅助功能设置") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window {
            persistWindowOrigin(window.frame.origin)
        }
        deletionCleanupTask?.cancel()
        clipboardMonitor.stop()
    }

    private func performMaintenance() {
        let store = historyStore!, storage = imageStorage!
        AppSettings.shared.busy = true
        Task {
            do {
                try await ClipboardPipeline.shared.maintain(store: store, storage: storage, retentionDays: AppSettings.shared.retentionDays)
                AppSettings.shared.message = "普通历史已按规则整理。"
                refreshStorageSummary()
            } catch { AppSettings.shared.message = "整理失败：\(error.localizedDescription)" }
            AppSettings.shared.busy = false
        }
    }

    private func refreshStorageSummary() {
        let storage = imageStorage!
        Task {
            let managed = (try? storage.managedStorageBytes()) ?? 0
            let cache = (try? await ImageProcessing.shared.cacheBytes()) ?? 0
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            AppSettings.shared.storageSummary = "托管图片：\(formatter.string(fromByteCount: Int64(managed)))；可再生缓存：\(formatter.string(fromByteCount: Int64(cache)))。本地原文件不计入且不会删除。"
        }
    }

    private func clearHistory(includingFavorites: Bool) {
        let store = historyStore!, storage = imageStorage!
        AppSettings.shared.busy = true
        Task {
            defer { AppSettings.shared.busy = false }
            do {
                try await ClipboardPipeline.shared.clearHistory(store: store, storage: storage, includingFavorites: includingFavorites)
                AppSettings.shared.message = includingFavorites ? "全部历史已清空。" : "普通历史已清空，收藏已保留。"
                refreshStorageSummary()
            } catch { AppSettings.shared.message = "清空失败：\(error.localizedDescription)" }
        }
    }

    private func clearRegenerableCaches() {
        AppSettings.shared.busy = true
        Task {
            do { try await ImageProcessing.shared.clearCaches(); AppSettings.shared.message = "缩略图与 OCR 缓存已清理，需要时会重新生成。" }
            catch { AppSettings.shared.message = "缓存清理失败：\(error.localizedDescription)" }
            AppSettings.shared.busy = false
            refreshStorageSummary()
        }
    }

    // MARK: - 窗口控制

    @objc private func statusClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else { toggleWindow(); return }
        let menu = NSMenu()
        for (title, action) in [
            ("打开面板", #selector(openPanel)),
            (AppSettings.shared.paused ? "恢复记录" : "暂停记录", #selector(toggleRecording))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        // 灵动岛开关：用勾选状态显示当前是否开启。
        let islandItem = NSMenuItem(title: "灵动岛", action: #selector(toggleIsland), keyEquivalent: "")
        islandItem.target = self
        islandItem.state = AppSettings.shared.islandEnabled ? .on : .off
        menu.addItem(islandItem)
        for (title, action) in [
            ("设置…", #selector(openSettings)),
            ("退出 ClipStack", #selector(quitApp))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if AppSettings.shared.sequenceActive {
            menu.addItem(.separator())
            let stop = NSMenuItem(title: "停止顺序粘贴", action: #selector(stopSequence), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @objc private func openPanel() { showWindow() }
    @objc private func toggleRecording() { AppSettings.shared.togglePause() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func toggleIsland() { AppSettings.shared.toggleIsland() }

    /// 创建顶部浮层（灵动岛）并接线：新记录到达时弹出展示。
    private func setUpIslandWindow() {
        let island = IslandWindowController(
            historyStore: historyStore,
            imageStorage: imageStorage,
            actions: IslandActions(
                onPaste: { [weak self] item in
                    guard let self, self.ensureAccessibilityPermission() else { return }
                    // 不切换前台应用，直接贴回当前光标处。
                    _ = self.pasteService.pasteIntoCurrentApplication(item: item)
                    self.clipboardMonitor.ignorePasteboardChangeCount(NSPasteboard.general.changeCount)
                },
                onCopy: { [weak self] item in
                    guard let self else { return }
                    _ = self.pasteService.copyToPasteboard(item: item)
                    self.clipboardMonitor.ignorePasteboardChangeCount(NSPasteboard.general.changeCount)
                },
                onFavorite: { [weak self] item in self?.toggleFavoriteFromIsland(item) },
                onDownload: { [weak self] item in self?.downloadFromIsland(item) },
                onDownloadTo: { [weak self] item in self?.downloadFromIslandToChosenFolder(item) }
            )
        )
        island.isEnabled = AppSettings.shared.islandEnabled
        islandController = island
        clipboardMonitor.onItemsRecorded = { [weak self] _ in self?.islandController?.showRecorded() }
    }

    /// 岛内收藏：与面板一致，收藏时把图片/文件复制成本地副本，避免原文件失效。
    private func toggleFavoriteFromIsland(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        do {
            if !item.isFavorite {
                let materialized = try FavoriteStorage().materialize(item)
                try historyStore.updateContent(id: id, content: materialized.content)
            }
            try historyStore.updateFavorite(id: id, isFavorite: !item.isFavorite)
            AppSettings.shared.message = item.isFavorite ? "已取消收藏。" : "已收藏并保留。"
        } catch {
            AppSettings.shared.message = "收藏失败：文件或图片无法复制到本地：\(error.localizedDescription)"
        }
    }

    private func downloadFromIsland(_ item: ClipboardItem) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        performIslandDownload(item, to: downloads)
    }

    private func downloadFromIslandToChosenFolder(_ item: ClipboardItem) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "下载到此处"
        panel.message = "选择要保存到的文件夹"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        performIslandDownload(item, to: directory)
    }

    private func performIslandDownload(_ item: ClipboardItem, to directory: URL) {
        do {
            let written = try HistoryDownloader.download(item, to: directory)
            AppSettings.shared.message = written.count == 1
                ? "已下载到：\(written[0].path)"
                : "已下载 \(written.count) 个文件到：\(directory.path)"
        } catch {
            AppSettings.shared.message = "下载失败：\(error.localizedDescription)"
        }
    }

    /// 模拟 ⌘V 需要辅助功能权限。缺失时提示一次并引导去系统设置授权，
    /// 返回 false 表示这次粘贴无法进行（不再静默失败）。
    private func ensureAccessibilityPermission() -> Bool {
        guard !PasteService.hasAccessibilityPermission else { return true }
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "ClipStack 需要辅助功能权限才能模拟 ⌘V，把内容粘贴到其他应用。授权后请重新打开 ClipStack。"
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PasteService.requestAccessibilityPermission()
        }
        return false
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: ClipStackSettingsView())
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 610),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.contentViewController = controller
            w.title = "ClipStack 设置"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 480, height: 480)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleWindow() {
        if let window, window.isVisible {
            // 窗口已经是当前 key window 时，点击图标表示隐藏；
            // 窗口只是打开但被其他应用挡住时，点击图标在原位置重新置前。
            if window.isKeyWindow && NSApp.isActive {
                closeWindow()
            } else {
                showWindow()
            }
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        pasteService.rememberFrontmostApp()
        // 主面板打开时不再显示灵动岛，避免两个界面同时出现。
        islandController?.hide()

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.level = (UserDefaults.standard.object(forKey: "ClipStack.pinned") as? Bool ?? true) ? .floating : .normal
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // 关闭背景拖窗，否则拖拽图片/文件项时会把整个面板一起拖走。
            // 顶部透明标题栏区域仍可拖动窗口。
            w.isMovableByWindowBackground = false
            w.hidesOnDeactivate = false
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 320)
            w.delegate = self

            let hostingView = NSHostingView(rootView: HistoryPanelView(
                historyStore: historyStore,
                imageStorage: imageStorage,
                onPaste: { [weak self] item in
                    guard let self else { return }
                    guard self.ensureAccessibilityPermission() else { return }
                    _ = self.pasteService.paste(item: item)
                    // 成功写入或失败后恢复原剪贴板，均忽略这次由 ClipStack
                    // 产生的 changeCount，避免把内部操作重新记录进历史。
                    self.clipboardMonitor.ignorePasteboardChangeCount(NSPasteboard.general.changeCount)
                    // 选择任何类型的历史项后都保留面板，方便继续浏览或连续粘贴。
                },
                onCopy: { [weak self] item in
                    guard let self else { return }
                    _ = self.pasteService.copyToPasteboard(item: item)
                    self.clipboardMonitor.ignorePasteboardChangeCount(NSPasteboard.general.changeCount)
                },
                onPinnedChange: { [weak self] isPinned in
                    self?.setWindowPinned(isPinned)
                }
            ))
            w.contentView = hostingView
            hostingView.autoresizingMask = [.width, .height]
            window = w
            if let encoded = UserDefaults.standard.string(forKey: "ClipStack.windowSize") {
                let size = NSSizeFromString(encoded)
                if size.width.isFinite, size.height.isFinite, size.width >= 420, size.height >= 320 {
                    let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 900)
                    w.setContentSize(NSSize(width: min(size.width, screen.width), height: min(size.height, screen.height - 30)))
                }
            }

            if let savedOrigin = persistedWindowOrigin(for: w.frame.size) {
                w.setFrameOrigin(savedOrigin)
            } else {
                positionWindow()
            }
        } else if let window, !window.isVisible, let savedOrigin = persistedWindowOrigin(for: window.frame.size) {
            window.setFrameOrigin(savedOrigin)
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        AppSettings.shared.panelVisible = true
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === window else { return }
        UserDefaults.standard.set(NSStringFromSize(w.contentRect(forFrameRect: w.frame).size), forKey: "ClipStack.windowSize")
    }

    func windowDidMove(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === window else { return }
        persistWindowOrigin(w.frame.origin)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if closingWindow === window {
            AppSettings.shared.panelVisible = false
        }
        persistWindowOrigin(closingWindow.frame.origin)
    }

    private func positionWindow() {
        guard let panel = window else { return }

        let panelSize = panel.frame.size
        let mouseLocation = NSEvent.mouseLocation
        // 鼠标坐标和 NSScreen.frame 使用同一个全局屏幕坐标系（原点在左下角）。
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }

        var x = mouseLocation.x - panelSize.width / 2
        var y = mouseLocation.y - panelSize.height / 2

        // 不超出屏幕边界
        let visibleFrame = screen.visibleFrame
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - panelSize.width - 4))
        y = max(visibleFrame.minY + 4, min(y, visibleFrame.maxY - panelSize.height - 4))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func closeWindow() {
        if let window {
            persistWindowOrigin(window.frame.origin)
        }
        window?.orderOut(nil)
        AppSettings.shared.panelVisible = false
    }

    private func setWindowPinned(_ isPinned: Bool) {
        // .floating 会显示在普通窗口之上；取消置顶后回到普通窗口层级。
        // 点击菜单栏图标时仍会临时把它重新置前。
        window?.level = isPinned ? .floating : .normal
    }

    // MARK: - 窗口位置持久化

    private func persistWindowOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(
            NSStringFromPoint(origin),
            forKey: Self.windowOriginDefaultsKey
        )
    }

    private func persistedWindowOrigin(for windowSize: NSSize) -> NSPoint? {
        guard let encoded = UserDefaults.standard.string(forKey: Self.windowOriginDefaultsKey) else {
            return nil
        }
        let origin = NSPointFromString(encoded)
        let frame = NSRect(origin: origin, size: windowSize)

        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return nil }

        let x = max(
            visibleFrame.minX,
            min(origin.x, visibleFrame.maxX - windowSize.width)
        )
        let y = max(
            visibleFrame.minY,
            min(origin.y, visibleFrame.maxY - windowSize.height)
        )
        return NSPoint(x: x, y: y)
    }
}
