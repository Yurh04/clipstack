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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var historyStore: HistoryStore!
    private var imageStorage: ImageStorage!
    private var clipboardMonitor: ClipboardMonitor!
    private var pasteService: PasteService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dbPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipStack", isDirectory: true)
            .appendingPathComponent("history.db")
            .path
        do {
            historyStore = try HistoryStore(path: dbPath, maxItems: 500)
        } catch {
            fatalError("初始化数据库失败: \(error)")
        }
        imageStorage = ImageStorage(storageDirectory: ImageStorage.defaultDirectory())
        clipboardMonitor = ClipboardMonitor(store: historyStore, imageStorage: imageStorage)
        pasteService = PasteService(imageStorage: imageStorage)

        if !PasteService.hasAccessibilityPermission {
            PasteService.requestAccessibilityPermission()
        }
        clipboardMonitor.start()

        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = ClipStackIcon.menuBarImage()
            button.action = #selector(toggleWindow)
            button.target = self
        }

        // 全局快捷键 ⌘⌃J
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.toggleWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
    }

    // MARK: - 窗口控制

    @objc private func toggleWindow() {
        if let w = window, w.isVisible {
            closeWindow()
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
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isMovableByWindowBackground = true
            w.hidesOnDeactivate = false
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 320)

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
                }
            ))
            w.contentView = hostingView
            hostingView.autoresizingMask = [.width, .height]
            window = w
        }

        // 定位到当前鼠标位置
        positionWindow()

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

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
        window?.orderOut(nil)
    }
}
