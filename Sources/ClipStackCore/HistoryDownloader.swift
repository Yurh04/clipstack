import Foundation

/// 把图片 / 文件历史项另存到下载文件夹。截图这类只在剪贴板里的内容也能一键落盘。
public enum HistoryDownloader {
    public enum DownloadError: LocalizedError {
        case notDownloadable
        case missingFiles

        public var errorDescription: String? {
            switch self {
            case .notDownloadable: return "该记录不是图片或文件，无法下载。"
            case .missingFiles: return "文件已不存在或无法访问，请检查原文件位置。"
            }
        }
    }

    /// 将条目涉及的文件复制到 `directory`，自动避免重名覆盖。
    /// - Returns: 实际写入的目标文件 URL 列表。
    @discardableResult
    public static func download(
        _ item: ClipboardItem,
        to directory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard item.type != .text else { throw DownloadError.notDownloadable }
        let sources = item.draggableFileURLs
        guard !sources.isEmpty else { throw DownloadError.missingFiles }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        for source in sources {
            let destination = uniqueDestination(for: source.lastPathComponent, in: directory, fileManager: fileManager)
            try fileManager.copyItem(at: source, to: destination)
            written.append(destination)
        }
        return written
    }

    /// 为避免覆盖已有文件，必要时在文件名后追加 "-1"、"-2"……
    static func uniqueDestination(
        for filename: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 1
        while true {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let url = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
