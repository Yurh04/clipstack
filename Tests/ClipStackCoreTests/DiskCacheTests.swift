import XCTest
@testable import ClipStackCore

final class DiskCacheTests: XCTestCase {
    func testCacheTrimsLeastRecentlyUsedEntries() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = DiskCache(directory: dir, limit: 10)
        try await cache.put(Data(repeating: 1, count: 6), for: "old")
        try await Task.sleep(for: .milliseconds(10))
        try await cache.put(Data(repeating: 2, count: 6), for: "new")
        let old = await cache.data(for: "old")
        let new = await cache.data(for: "new")
        XCTAssertNil(old)
        XCTAssertEqual(new?.count, 6)
    }

    func testClearRemovesOnlyCacheFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let unrelated = dir.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let cache = DiskCache(directory: dir)
        try await cache.put(Data("cache".utf8), for: "key")
        try await cache.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        let cached = await cache.data(for: "key")
        XCTAssertNil(cached)
    }
}
