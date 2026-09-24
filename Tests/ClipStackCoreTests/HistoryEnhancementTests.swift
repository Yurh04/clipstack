import XCTest
@testable import ClipStackCore

final class HistoryEnhancementTests: XCTestCase {
    func testDeletionIsHiddenAndUndoPreservesMetadata() throws {
        let store = try HistoryStore.inMemory()
        let now = Date(timeIntervalSince1970: 100000)
        let saved = try store.save(ClipboardItem(type: .text, content: "hello", isFavorite: true, note: "note"))
        let id = try XCTUnwrap(saved.id)
        try store.updateTags(id: id, tags: "工作, Work, 工作")
        try store.scheduleDeletion(id: id, now: now)
        XCTAssertTrue(try store.all().isEmpty)
        XCTAssertTrue(try store.items(matching: HistoryFilter(searchText: "hello")).isEmpty)
        XCTAssertEqual(try store.all(includingPendingDeletion: true).count, 1)
        XCTAssertTrue(try store.undoDeletion(id: id, now: now.addingTimeInterval(9)))
        let restored = try XCTUnwrap(store.all().first)
        XCTAssertEqual(restored.note, "note")
        XCTAssertEqual(restored.tagNames, ["工作", "Work"])
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970, saved.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(restored.isFavorite)
    }

    func testPendingDeletionSurvivesMaintenanceAndExpires() throws {
        let store = try HistoryStore.inMemory(maxItems: 0)
        let now = Date(timeIntervalSince1970: 100000)
        let item = try store.save(ClipboardItem(type: .text, content: "old"))
        let id = try XCTUnwrap(item.id)
        try store.scheduleDeletion(id: id, now: now)
        _ = try store.deleteExpired(olderThan: .distantFuture)
        _ = try store.enforceCapacity()
        try store.finalizeDeletions(now: now.addingTimeInterval(9))
        XCTAssertEqual(try store.all(includingPendingDeletion: true).count, 1)
        XCTAssertFalse(try store.undoDeletion(id: id, now: now.addingTimeInterval(10)))
        try store.finalizeDeletions(now: now.addingTimeInterval(10))
        XCTAssertTrue(try store.all(includingPendingDeletion: true).isEmpty)
    }

    func testPendingDeletionPersistsAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("history.sqlite").path
        let store = try HistoryStore(path: path)
        let now = Date(timeIntervalSince1970: 100000)
        let item = try store.save(ClipboardItem(type: .text, content: "delete"))
        try store.scheduleDeletion(id: XCTUnwrap(item.id), now: now)
        let reopened = try HistoryStore(path: path)
        XCTAssertTrue(try reopened.all().isEmpty)
        try reopened.finalizeDeletions(now: now.addingTimeInterval(11))
        XCTAssertTrue(try reopened.all(includingPendingDeletion: true).isEmpty)
    }

    func testRecaptureDoesNotReusePendingDeletion() throws {
        let store = try HistoryStore.inMemory()
        let item = ClipboardItem(type: .image, content: "/tmp/image.png", contentHash: "hash")
        let saved = try store.save(item)
        try store.scheduleDeletion(id: XCTUnwrap(saved.id))
        let recaptured = try store.save(item)
        XCTAssertNotEqual(saved.id, recaptured.id)
        XCTAssertEqual(try store.all().count, 1)
    }

    func testPendingImageIsKeptUntilDeletionFinalizes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ImageStorage(storageDirectory: directory)
        let path = try storage.save(pngData: Data("image payload".utf8))
        let store = try HistoryStore.inMemory(maxItems: 0)
        let item = try store.save(ClipboardItem(type: .image, content: path))
        let now = Date(timeIntervalSince1970: 100000)
        try store.scheduleDeletion(id: XCTUnwrap(item.id), now: now)
        try store.enforceCapacityAndCleanupImages(imageStorage: storage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        try store.finalizeDeletions(now: now.addingTimeInterval(11))
        try store.enforceCapacityAndCleanupImages(imageStorage: storage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testSearchCombinesFiltersAndQuotedPhrases() {
        let now = Date()
        var item = ClipboardItem(type: .image, content: "/tmp/a.png", sourceApp: "Google Chrome", createdAt: now.addingTimeInterval(-86400), ocrText: "Invoice Alpha", note: "学习资料")
        item.tags = "工作, 学习"
        XCTAssertTrue(HistorySearch.matches(item, query: "app:\"Google Chrome\" type:image after:7d tag:学习 \"invoice alpha\"", now: now))
        XCTAssertFalse(HistorySearch.matches(item, query: "type:text", now: now))
        XCTAssertFalse(HistorySearch.matches(item, query: "after:0d", now: now))
        XCTAssertFalse(HistorySearch.matches(item, query: "tag:学", now: now))
        XCTAssertTrue(HistorySearch.matches(item, query: "学习资料", now: now))
        XCTAssertTrue(HistorySearch.matches(item, query: "", now: now))
    }

    func testFileStatusReportsOnlyMissingPaths() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("test".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let missing = url.path + "-missing"
        let item = ClipboardItem(type: .file, content: url.path + "\n" + missing)
        XCTAssertEqual(item.missingFilePaths, [missing])
        XCTAssertTrue(ClipboardItem(type: .text, content: missing).missingFilePaths.isEmpty)
    }
}
