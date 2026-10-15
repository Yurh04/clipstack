import SwiftUI
import AppKit

/// AppKit 拖拽源：把「真实文件 URL」写入拖拽板，而不是经由 SwiftUI
/// 的临时目录中转。这样拖进 macOS「选择文件」面板时会像从 Finder 拖拽一样
/// 自动跳转到文件所在的真实文件夹并选中它；拖到网页上传框、Finder 同样是真实文件。
///
/// 作为透明层覆盖在目标视图上：
/// - 在空白区域按住拖动即可发起文件拖拽（移动超过阈值才触发，避免误触）。
/// - 没有发生拖动时，把单击 / 双击分别转发给 onClick / onDoubleClick，
///   以保留原有的选中、预览行为。
/// - SwiftUI 中更靠前的按钮（收藏、复制等）仍在本层之上，点击不受影响。
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    var image: NSImage?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> FileDragSourceNSView {
        let view = FileDragSourceNSView()
        view.apply(urls: urls, image: image, onClick: onClick, onDoubleClick: onDoubleClick)
        return view
    }

    func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.apply(urls: urls, image: image, onClick: onClick, onDoubleClick: onDoubleClick)
    }
}

final class FileDragSourceNSView: NSView, NSDraggingSource {
    private var urls: [URL] = []
    private var dragImage: NSImage?
    private var onClick: (() -> Void)?
    private var onDoubleClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?

    func apply(urls: [URL], image: NSImage?, onClick: (() -> Void)?, onDoubleClick: (() -> Void)?) {
        self.urls = urls
        self.dragImage = image
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, !urls.isEmpty else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard (dx * dx + dy * dy) > 16 else { return }  // 超过约 4pt 才算拖动
        mouseDownEvent = nil

        let items: [NSDraggingItem] = urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let thumb = dragImage ?? NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(bounds, contents: thumb)
            return item
        }
        beginDraggingSession(with: items, event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil {
            if event.clickCount >= 2 { onDoubleClick?() } else { onClick?() }
        }
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
