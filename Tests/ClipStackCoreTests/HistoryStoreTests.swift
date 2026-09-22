import XCTest
@testable import ClipStackCore

final class HistoryStoreTests: XCTestCase {

    // MARK: - 增 / 查

    func testSaveAndFetchRoundTrip() throws {
        let store = try HistoryStore.inMemory()
        let saved = try store.save(ClipboardItem(type: .text, content: "hello", sourceApp: "Xcode"))

        XCTAssertNotNil(saved.id, "保存后应回填自增主键 id")

        let all = try store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "hello")
        XCTAssertEqual(all.first?.sourceApp, "Xcode")
    }

    func testFetchOrderIsNewestFirst() throws {
        let store = try HistoryStore.inMemory()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        try store.save(ClipboardItem(type: .text, content: "old", createdAt: t0))
        try store.save(ClipboardItem(type: .text, content: "new", createdAt: t1))

        let all = try store.all()
        XCTAssertEqual(all.map(\.content), ["new", "old"], "应按拷贝时间倒序，最新在前")
    }

    // MARK: - 去重（连续相同内容只更新时间，不新建）

    func testConsecutiveDuplicateUpdatesTimestampInsteadOfInserting() throws {
        let store = try HistoryStore.inMemory()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        try store.save(ClipboardItem(type: .text, content: "same", createdAt: t0))
        try store.save(ClipboardItem(type: .text, content: "same", createdAt: t1))

        let all = try store.all()
        XCTAssertEqual(all.count, 1, "连续复制相同内容不应新建记录")
        XCTAssertEqual(all.first?.createdAt, t1, "应更新为最新拷贝时间")
    }

    func testNonConsecutiveSameContentCreatesNewRecord() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "A", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.save(ClipboardItem(type: .text, content: "B", createdAt: Date(timeIntervalSince1970: 2000)))
        try store.save(ClipboardItem(type: .text, content: "A", createdAt: Date(timeIntervalSince1970: 3000)))

        let all = try store.all()
        XCTAssertEqual(all.count, 3, "非连续的相同内容应各自成条")
        XCTAssertEqual(all.map(\.content), ["A", "B", "A"])
    }

    func testSameContentDifferentTypeIsNotDeduplicated() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "/tmp/x", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.save(ClipboardItem(type: .file, content: "/tmp/x", createdAt: Date(timeIntervalSince1970: 2000)))

        XCTAssertEqual(try store.all().count, 2, "内容相同但类型不同不应去重")
    }

    // MARK: - 容量控制

    func testEnforceCapacityDeletesOldestBeyondLimit() throws {
        let store = try HistoryStore.inMemory(maxItems: 3)
        for i in 0..<5 {
            try store.save(ClipboardItem(
                type: .text,
                content: "item-\(i)",
                createdAt: Date(timeIntervalSince1970: Double(1000 + i))
            ))
        }

        let deleted = try store.enforceCapacity()
        XCTAssertEqual(deleted.map(\.content), ["item-0", "item-1"], "应删除最旧的两条并返回它们")

        let all = try store.all()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map(\.content), ["item-4", "item-3", "item-2"])
    }

    func testEnforceCapacityNoOpWhenUnderLimit() throws {
        let store = try HistoryStore.inMemory(maxItems: 500)
        try store.save(ClipboardItem(type: .text, content: "only"))
        XCTAssertTrue(try store.enforceCapacity().isEmpty, "未超限时不删除任何记录")
    }

    // MARK: - 分类过滤

    func testFilterByType() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "t", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.save(ClipboardItem(type: .image, content: "/img/a.png", createdAt: Date(timeIntervalSince1970: 2000)))
        try store.save(ClipboardItem(type: .file, content: "/f/b.zip", createdAt: Date(timeIntervalSince1970: 3000)))

        let images = try store.items(matching: HistoryFilter(type: .image))
        XCTAssertEqual(images.map(\.content), ["/img/a.png"])
    }

    // MARK: - 搜索

    func testSearchByContentSubstringCaseInsensitive() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "Hello World", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.save(ClipboardItem(type: .text, content: "Goodbye", createdAt: Date(timeIntervalSince1970: 2000)))

        let hits = try store.items(matching: HistoryFilter(searchText: "hello"))
        XCTAssertEqual(hits.map(\.content), ["Hello World"], "搜索应大小写不敏感的子串匹配")
    }

    func testSearchCombinedWithTypeFilter() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "report.txt", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.save(ClipboardItem(type: .file, content: "report.pdf", createdAt: Date(timeIntervalSince1970: 2000)))

        let hits = try store.items(matching: HistoryFilter(type: .file, searchText: "report"))
        XCTAssertEqual(hits.map(\.content), ["report.pdf"], "类型与搜索条件应同时生效")
    }

    func testImageWithSameContentHashDeduplicatesEvenWhenNotLatest() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "between", createdAt: Date(timeIntervalSince1970: 2000)))
        try store.save(ClipboardItem(
            type: .image,
            content: "/images/a.png",
            createdAt: Date(timeIntervalSince1970: 1000),
            contentHash: "hash-a"
        ))
        try store.save(ClipboardItem(type: .text, content: "after", createdAt: Date(timeIntervalSince1970: 3000)))

        let saved = try store.save(ClipboardItem(
            type: .image,
            content: "/images/a-copy.png",
            createdAt: Date(timeIntervalSince1970: 4000),
            contentHash: "hash-a"
        ))

        let all = try store.all()
        XCTAssertEqual(all.count, 3, "相同哈希图片应复用已有记录，不新建")
        XCTAssertEqual(saved.content, "/images/a.png", "已有文件仍存在时应继续引用原路径")
        XCTAssertEqual(all.first?.content, "/images/a.png", "重复图片应更新到最新位置")
    }

    func testImageHashDeduplicationReplacesMissingPathWithAvailablePath() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(
            type: .image,
            content: "/images/missing.png",
            createdAt: Date(timeIntervalSince1970: 1000),
            contentHash: "hash-a"
        ))

        let saved = try store.save(ClipboardItem(
            type: .image,
            content: Bundle(for: HistoryStoreTests.self).bundlePath,
            createdAt: Date(timeIntervalSince1970: 2000),
            contentHash: "hash-a"
        ))

        XCTAssertEqual(saved.content, Bundle(for: HistoryStoreTests.self).bundlePath)
    }

    func testBackfillImageHashes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageStorage = ImageStorage(storageDirectory: tempDir)
        let imagePath = try imageStorage.save(pngData: Data("image-data".utf8))
        let expectedHash = ImageStorage.sha256Hex(Data("image-data".utf8))
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .image, content: imagePath))

        try store.backfillImageHashes(with: imageStorage)

        XCTAssertEqual(try store.all().first?.contentHash, expectedHash)
    }

    func testEnforceCapacityAndCleanupImagesDeletesOrphans() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageStorage = ImageStorage(storageDirectory: tempDir)
        let referencedImage = try imageStorage.save(pngData: Data("referenced".utf8))
        let orphanImage = tempDir.appendingPathComponent("orphan.png")
        try Data("orphan".utf8).write(to: orphanImage)

        let store = try HistoryStore.inMemory(maxItems: 1)
        try store.save(ClipboardItem(type: .text, content: "old", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.save(ClipboardItem(
            type: .image,
            content: referencedImage,
            createdAt: Date(timeIntervalSince1970: 2000),
            contentHash: "hash"
        ))

        try store.enforceCapacityAndCleanupImages(imageStorage: imageStorage)

        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedImage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanImage.path))
    }

    func testFavoriteItemsSurviveCapacityAndExpiration() throws {
        let store = try HistoryStore.inMemory(maxItems: 1)
        let old = try store.save(ClipboardItem(type: .text, content: "favorite", createdAt: Date(timeIntervalSince1970: 1000)))
        try store.updateFavorite(id: try XCTUnwrap(old.id), isFavorite: true)
        try store.save(ClipboardItem(type: .text, content: "normal-1", createdAt: Date(timeIntervalSince1970: 2000)))
        try store.save(ClipboardItem(type: .text, content: "normal-2", createdAt: Date(timeIntervalSince1970: 3000)))

        _ = try store.deleteExpired(olderThan: Date(timeIntervalSince1970: 2500))
        _ = try store.enforceCapacity()

        let all = try store.all()
        XCTAssertTrue(all.contains { $0.content == "favorite" && $0.isFavorite })
        XCTAssertFalse(all.contains { $0.content == "normal-1" })
    }

    func testSearchMatchesOCRTextAndUpdatePersists() throws {
        let store = try HistoryStore.inMemory()
        let item = try store.save(ClipboardItem(type: .image, content: "/tmp/image.png", contentHash: "hash"))
        try store.updateOCRText(id: try XCTUnwrap(item.id), text: "invoice A-1024")

        let hits = try store.items(matching: HistoryFilter(searchText: "a-1024"))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.ocrText, "invoice A-1024")
    }

    // MARK: - 清空

    func testDeleteAll() throws {
        let store = try HistoryStore.inMemory()
        try store.save(ClipboardItem(type: .text, content: "x"))
        try store.deleteAll()
        XCTAssertTrue(try store.all().isEmpty)
    }
}
