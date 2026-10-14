import SwiftUI
import ClipStackCore

/// 让图片 / 文件历史项可以直接拖进系统「选择文件」对话框或其它应用，
/// 从而把只存在于剪贴板的截图、文件原样上传，无需手动另存到本地。
extension View {
    @ViewBuilder
    func draggableHistoryItem(_ item: ClipboardItem) -> some View {
        let urls = item.draggableFileURLs
        if urls.isEmpty {
            self
        } else {
            // SwiftUI 的 onDrag 只返回一个 NSItemProvider，多文件时拖第一个。
            // 用 contentsOf 让落点把它识别成真实文件而非普通文本。
            self.onDrag {
                NSItemProvider(contentsOf: urls[0]) ?? NSItemProvider()
            }
        }
    }
}
