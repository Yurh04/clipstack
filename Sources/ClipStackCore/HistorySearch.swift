import Foundation

/// Space-separated terms are combined with AND; quoted phrases stay together.
public enum HistorySearch {
    public static func matches(_ item: ClipboardItem, query: String, now: Date = Date()) -> Bool {
        let expression = try! NSRegularExpression(pattern: "(?:[^\\s\"]|\"[^\"]*\")+")
        let tokens = expression.matches(in: query, range: NSRange(query.startIndex..., in: query)).compactMap {
            Range($0.range, in: query).map { String(query[$0]).replacingOccurrences(of: "\"", with: "") }
        }
        let searchable = [item.content, item.note ?? "", item.ocrText ?? "", item.tags ?? ""].joined(separator: "\n")
        func contains(_ text: String, _ value: String) -> Bool {
            text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return tokens.allSatisfy { token in
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let value = parts[1]
                switch parts[0].lowercased() {
                case "app": return contains(item.sourceApp ?? "", value)
                case "type": return item.type.rawValue == value.lowercased()
                case "tag": return item.tagNames.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
                case "after":
                    if value.hasSuffix("d"), let days = Int(value.dropLast()), days >= 0 {
                        return item.createdAt >= now.addingTimeInterval(-Double(days) * 86400)
                    }
                default: break
                }
            }
            return contains(searchable, token)
        }
    }
}

extension ClipboardItem {
    public var tagNames: [String] {
        (tags ?? "").components(separatedBy: CharacterSet(charactersIn: ",，")).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.reduce(into: []) { result, tag in
            if !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { result.append(tag) }
        }
    }

    public var missingFilePaths: [String] {
        guard type != .text else { return [] }
        let paths = type == .image ? [content] : content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return paths.filter { !FileManager.default.fileExists(atPath: $0) }
    }
}
