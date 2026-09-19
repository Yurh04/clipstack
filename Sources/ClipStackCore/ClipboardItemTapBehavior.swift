/// 单击历史记录时的动作；文本和文件必须由复制按钮或快捷键触发。
public enum ClipboardItemTapBehavior: Equatable {
    case select
    case paste
    case preview

    public static func action(for item: ClipboardItem) -> Self {
        switch item.type {
        case .file: return .select
        case .text: return .select
        case .image: return .preview
        }
    }
}
