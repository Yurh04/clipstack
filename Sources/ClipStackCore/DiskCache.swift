import Foundation

/// Bounded cache for regenerable data. Only files with this cache's extension are touched.
public actor DiskCache {
    private let directory: URL
    private let limit: Int
    public init(directory: URL, limit: Int = 64 * 1024 * 1024) {
        self.directory = directory
        self.limit = max(0, limit)
    }
    private func url(_ key: String) -> URL {
        directory.appendingPathComponent(ImageStorage.sha256Hex(Data(key.utf8)) + ".cache")
    }
    public func data(for key: String) -> Data? {
        let path = url(key)
        guard let data = try? Data(contentsOf: path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        return data
    }
    public func put(_ data: Data, for key: String, trimAfterWrite: Bool = true) throws {
        guard data.count <= limit else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(key), options: .atomic)
        if trimAfterWrite { try trim() }
    }
    public func trimToLimit() throws { try trim() }
    public func size() throws -> Int {
        try entries().reduce(0) { $0 + $1.size }
    }
    public func clear() throws {
        for entry in try entries() { try FileManager.default.removeItem(at: entry.url) }
    }
    private func entries() throws -> [(url: URL, size: Int, date: Date)] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]).compactMap { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard url.pathExtension == "cache", values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }
    private func trim() throws {
        let files = try entries().sorted { $0.date < $1.date }
        var total = files.reduce(0) { $0 + $1.size }
        for entry in files where total > limit {
            try FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
