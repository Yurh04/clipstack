import Foundation
import CryptoKit

/// 图片文件落盘存储。
/// 数据库只记录路径，图片二进制存到磁盘目录，避免撑大 SQLite。
public final class ImageStorage: Sendable {
    private let storageDirectory: URL

    /// - Parameter storageDirectory: 图片存放目录，初始化时自动创建
    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
        try? FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }

    /// 默认存储目录：~/Library/Application Support/ClipStack/images/
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ClipStack", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
    }

    /// 保存已标准化的 PNG 数据，返回按 SHA-256 哈希命名的落盘路径。
    /// 相同内容重复保存时复用同一个文件，不重复占用硬盘。
    public func save(pngData: Data) throws -> String {
        let filename = "\(Self.sha256Hex(pngData)).png"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try pngData.write(to: fileURL)
        }
        return fileURL.path
    }

    /// 读取指定路径的图片数据。本地图片文件和 ClipStack 托管图片都可读取。
    public func load(path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func managedStorageBytes() throws -> Int {
        guard FileManager.default.fileExists(atPath: storageDirectory.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]).reduce(0) { sum, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return sum + (values.isRegularFile == true ? values.fileSize ?? 0 : 0)
        }
    }

    /// 删除指定路径的图片文件（文件不存在时静默返回，不报错）
    public func delete(path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// 删除 ClipStack images 目录中没有任何数据库记录引用的 PNG。
    /// 本地图片文件在托管目录之外，不会被这个方法删除。
    @discardableResult
    public func deleteUnreferencedFiles(validPaths: Set<String>) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let children = try FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: Array(resourceKeys)
        )
        let resolvedValidPaths = Set(validPaths.map(standardizedPath))

        var deletedFiles: [URL] = []
        for fileURL in children {
            let values = try? fileURL.resourceValues(forKeys: resourceKeys)
            guard values?.isRegularFile == true,
                  fileURL.pathExtension.lowercased() == "png",
                  !resolvedValidPaths.contains(standardizedPath(fileURL.path)) else {
                continue
            }

            try FileManager.default.removeItem(at: fileURL)
            deletedFiles.append(fileURL)
        }
        return deletedFiles
    }

    public static func sha256File(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
