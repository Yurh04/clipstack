import Foundation

/// Copies external file and image paths into ClipStack-owned storage when favorited.
public final class FavoriteStorage: Sendable {
    private let directory: URL

    public init(directory: URL = FavoriteStorage.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipStack", isDirectory: true)
            .appendingPathComponent("favorites", isDirectory: true)
    }

    public func materialize(_ item: ClipboardItem) throws -> ClipboardItem {
        guard item.type != .text else { return item }
        let paths = item.type == .image
            ? [item.content]
            : item.content.split(separator: "\n").map(String.init)
        var copied: [String] = []
        for path in paths {
            let source = URL(fileURLWithPath: path)
            if source.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") {
                copied.append(source.path)
                continue
            }
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: source.path])
            }
            let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: destination)
            copied.append(destination.path)
        }
        var result = item
        result.content = copied.joined(separator: "\n")
        return result
    }

    /// Migrates existing favorited external paths once at startup.
    public func materializeFavorites(in store: HistoryStore) throws {
        for item in try store.all() where item.isFavorite && item.type != .text {
            let materialized = try materialize(item)
            if materialized.content != item.content, let id = item.id {
                try store.updateContent(id: id, content: materialized.content)
            }
        }
    }
}
