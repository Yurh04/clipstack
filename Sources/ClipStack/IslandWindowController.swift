import AppKit
import SwiftUI
import ClipStackCore

/// 灵动岛的三种形态。
enum IslandState: Equatable {
    case hidden
    case peek(ClipboardItem)
    case expanded
}

/// 灵动岛需要的外部动作，由 AppDelegate 注入实现。
struct IslandActions {
    var onPaste: (ClipboardItem) -> Void
    var onCopy: (ClipboardItem) -> Void
    var onFavorite: (ClipboardItem) -> Void
    var onDownload: (ClipboardItem) -> Void
    var onDownloadTo: (ClipboardItem) -> Void
}

/// 顶部浮层（“灵动岛”）窗口控制器。
///
/// - 剪贴板记录成功后 `showRecorded()` 自动弹出并展示最新一条，3 秒后收起；
/// - 鼠标悬停展开最近 5 条，移开立即收起；
/// - 面板用 `.nonactivatingPanel`，点击不会把 ClipStack 激活到前台，
///   因此展开态点击条目可以用 `PasteService.pasteIntoCurrentApplication` 贴回原应用。
@MainActor
final class IslandWindowController {
    private let historyStore: HistoryStore
    private let imageStorage: ImageStorage
    private let actions: IslandActions

    private var panel: IslandPanel?
    private var hostingView: NSHostingView<DynamicIslandView>?
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    private(set) var state: IslandState = .hidden
    private var items: [ClipboardItem] = []
    private var isHovering = false

    /// 是否启用（设置与菜单栏可切换）。
    var isEnabled = true

    private static let peekDuration: Duration = .seconds(3)
    private static let itemLimit = 5
    /// 距屏幕可视区顶边的间距，落在菜单栏下方、不遮刘海。
    private static let topInset: CGFloat = 6

    init(historyStore: HistoryStore, imageStorage: ImageStorage, actions: IslandActions) {
        self.historyStore = historyStore
        self.imageStorage = imageStorage
        self.actions = actions
        // 插拔显示器 / 换分辨率后重新定位到当前屏幕顶部。
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resizeAndPosition() }
        }
    }

    // MARK: - 对外接口

    /// 有新记录写入历史时调用：弹出浮层显示最新内容，并安排自动收起。
    func showRecorded() {
        guard isEnabled, !AppSettings.shared.panelVisible else { return }
        reloadItems()
        guard let latest = items.first else {
            hide()
            return
        }
        // 鼠标已经停在浮层上时保持展开，避免新内容把用户正在看的列表收起来。
        isHovering = isMouseInsidePanel()
        state = isHovering ? .expanded : .peek(latest)
        render(orderFront: true)
        if isHovering { watchHoverExit() } else { scheduleCollapse() }
    }

    func toggleEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { hide() }
    }

    func hide() {
        collapseTask?.cancel()
        collapseTask = nil
        isHovering = false
        state = .hidden
        panel?.orderOut(nil)
    }

    // MARK: - 状态流转

    private func handleHover(_ hovering: Bool) {
        guard state != .hidden else {
            isHovering = hovering
            return
        }
        if hovering {
            isHovering = true
            collapseTask?.cancel()
            let wasExpanded = state == .expanded
            state = .expanded
            if !wasExpanded { render(orderFront: false) }
            watchHoverExit()
        } else {
            // 重新渲染 / 窗口改尺寸时追踪区会重建，可能发出“假的”离开事件，
            // 以鼠标真实位置为准；真离开由 watchHoverExit 兜底收起。
            guard !isMouseInsidePanel() else { return }
            hide()
        }
    }

    /// 展开期间轮询鼠标位置：离开浮层即收起，防止离开事件丢失或被忽略。
    private func watchHoverExit() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                if !self.isMouseInsidePanel() {
                    self.hide()
                    return
                }
            }
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration)
            guard !Task.isCancelled else { return }
            guard let self, !self.isHovering else { return }
            self.hide()
        }
    }

    private func reloadItems() {
        let stored = (try? historyStore.all()) ?? []
        items = IslandPreview.recent(stored, limit: Self.itemLimit)
    }

    /// 鼠标当前是否停在浮层上。面板还没创建或已收起时算没有悬停。
    private func isMouseInsidePanel() -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    // MARK: - 窗口

    private func render(orderFront: Bool) {
        guard state != .hidden else { return }
        let hosting = ensureHostingView()
        hosting.rootView = makeView()
        resizeAndPosition()
        if orderFront {
            panel?.orderFrontRegardless()
        }
    }

    private func makeView() -> DynamicIslandView {
        DynamicIslandView(
            state: state,
            items: items,
            imageStorage: imageStorage,
            onPaste: actions.onPaste,
            onCopy: actions.onCopy,
            onFavorite: actions.onFavorite,
            onDownload: actions.onDownload,
            onDownloadTo: actions.onDownloadTo,
            onHover: { [weak self] in self?.handleHover($0) }
        )
    }

    private func ensureHostingView() -> NSHostingView<DynamicIslandView> {
        if let hostingView { return hostingView }

        let hosting = NSHostingView(rootView: makeView())
        let panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        // 只有点中需要键盘的控件时才成为 key，避免抢走前台应用的输入焦点。
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
        return hosting
    }

    private func resizeAndPosition() {
        guard state != .hidden, let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 300, height: 40)
        }
        let visible = currentScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - Self.topInset - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func currentScreen() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }
}

/// 无边框浮层面板：可以成为 key window 以便点击控件，但不会激活应用。
fileprivate final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
