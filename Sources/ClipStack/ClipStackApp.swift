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
    private var pasteService: PasteService!

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

        if !PasteService.hasAccessibilityPermission {
            PasteService.requestAccessibilityPermission()
        }
        clipboardMonitor.start()
        let store = historyStore!, storage = imageStorage!
        deletionCleanupTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                    try await ClipboardPipeline.shared.finalizeDeletions(store: store, storage: storage)
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

        // 全局快捷键 ⌘⌃J
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.toggleWindow()
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
            (AppSettings.shared.paused ? "恢复记录" : "暂停记录", #selector(toggleRecording)),
            ("设置…", #selector(openSettings)),
            ("退出 ClipStack", #selector(quitApp))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @objc private func openPanel() { showWindow() }
    @objc private func toggleRecording() { AppSettings.shared.togglePause() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: ClipStackSettingsView())
            let w = NSWindow(contentViewController: controller)
            w.title = "ClipStack 设置"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
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
            w.isMovableByWindowBackground = true
            w.hidesOnDeactivate = false
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 320)
            w.delegate = self

            let hostingView = NSHostingView(rootView: HistoryPanelView(
                historyStore: historyStore,
                imageStorage: imageStorage,
                onPaste: { [weak self] item in
                    guard let self else { return }
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
