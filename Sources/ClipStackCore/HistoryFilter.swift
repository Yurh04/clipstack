import Foundation

/// 剪贴板历史查询过滤器
public struct HistoryFilter: Sendable {
    /// 按类型过滤（nil 表示不限）
    public var type: ClipboardItemType?
    /// 按内容搜索（nil 表示不搜索）
    public var searchText: String?

    public init(type: ClipboardItemType? = nil, searchText: String? = nil) {
        self.type = type
        self.searchText = searchText
    }
}
