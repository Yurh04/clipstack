import Foundation

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

    /// 保存图片数据，返回落盘的绝对路径
    public func save(imageData: Data) throws -> String {
        let filename = "\(UUID().uuidString).png"
        let fileURL = storageDirectory.appendingPathComponent(filename)
        try imageData.write(to: fileURL)
        return fileURL.path
    }

    /// 读取指定路径的图片数据
    public func load(path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// 删除指定路径的图片文件（文件不存在时静默返回，不报错）
    public func delete(path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
