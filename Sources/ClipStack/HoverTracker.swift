import SwiftUI
import AppKit

/// 悬停监听层。
///
/// 灵动岛用的是 `.nonactivatingPanel`（点击不激活应用），SwiftUI 的 `.onHover`
/// 依赖应用激活状态，在这种浮层上不一定触发；这里用 `.activeAlways` 的
/// NSTrackingArea 自己实现，跟窗口是否激活无关。
///
/// `hitTest` 返回 nil，所以这层只负责监听悬停，不会拦截点击（行点击、拖拽照常）。
struct HoverTracker: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
    }
}

final class HoverTrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    /// 只监听悬停，不吃事件。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
