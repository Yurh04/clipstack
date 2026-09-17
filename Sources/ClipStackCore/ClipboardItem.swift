import Foundation

/// 剪贴板条目类型
public enum ClipboardItemType: String, Codable, Sendable, CaseIterable {
    /// 纯文本
    case text
    /// 图片（content 存落盘路径）
    case image
    /// 文件（content 存落盘路径或文件 URL）
    case file
}

/// 一条剪贴板历史记录
public struct ClipboardItem: Identifiable, Equatable, Sendable, Codable {
    public var id: Int64?
    /// 内容类型
    public var type: ClipboardItemType
    /// 文本内容，或图片 / 文件的落盘路径
    public var content: String
    /// 来源应用名（用于展示）
    public var sourceApp: String?
    /// 拷贝时间
    public var createdAt: Date
    /// 是否敏感内容（标记，正常不落盘存密码）
    public var isSensitive: Bool

    public init(
        id: Int64? = nil,
        type: ClipboardItemType,
        content: String,
        sourceApp: String? = nil,
        createdAt: Date = Date(),
        isSensitive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.isSensitive = isSensitive
    }
}
