import Foundation

/// 灵动岛浮层的展示逻辑：挑哪几条、每条显示什么文字。
/// 全部是纯函数，方便单元测试。
public enum IslandPreview {
    /// 浮层里展示的最近记录：剔除待删除项，按时间倒序取前 limit 条。
    public static func recent(_ items: [ClipboardItem], limit: Int = 5) -> [ClipboardItem] {
        guard limit > 0 else { return [] }
        return items
            .filter { $0.deletionDeadline == nil }
            .sorted { lhs, rhs in
                // 时间相同的记录（同一次批量导入）按 id 倒序，保证顺序稳定。
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// 单条记录的单行预览文案。
    public static func preview(for item: ClipboardItem, maxCharacters: Int = 42) -> String {
        switch item.type {
        case .text:
            let firstLine = item.content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            guard let firstLine else { return "(空)" }
            return truncated(firstLine, maxCharacters: maxCharacters)

        case .image:
            return "图片"

        case .file:
            let paths = item.content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            if paths.count == 1 { return URL(fileURLWithPath: paths[0]).lastPathComponent }
            return "\(paths.count) 个文件"
        }
    }

    private static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0, text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters)) + "…"
    }
}
