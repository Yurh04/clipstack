import Foundation

/// 识别剪贴板敏感内容（如密码管理器复制的密码），用于跳过存储。
///
/// 业界约定（http://nspasteboard.org）：密码类内容会带上
/// `org.nspasteboard.ConcealedType` 或 `org.nspasteboard.TransientType` 标记。
/// 各家 App 命名可能有大小写或前后缀差异，这里用忽略大小写的子串匹配兜底。
public enum SensitiveContentDetector {

    /// 敏感标记关键字（小写）
    private static let sensitiveMarkers = ["concealed", "transient"]

    /// 判断一组剪贴板类型标识是否包含敏感标记
    /// - Parameter pasteboardTypes: NSPasteboard 上该条目的 type 列表（原始字符串）
    /// - Returns: 命中任一敏感标记则为 true
    public static func isSensitive(pasteboardTypes: [String]) -> Bool {
        for type in pasteboardTypes {
            let lower = type.lowercased()
            for marker in sensitiveMarkers where lower.contains(marker) {
                return true
            }
        }
        return false
    }
}
