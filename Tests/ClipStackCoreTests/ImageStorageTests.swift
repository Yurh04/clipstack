import XCTest
@testable import ClipStackCore

final class ImageStorageTests: XCTestCase {

    var tempDir: URL!
    var storage: ImageStorage!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = ImageStorage(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() throws {
        // 构造一张 1x1 白色 PNG
        let whitePixel = validPNGData()

        let path = try storage.save(pngData: whitePixel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(path.hasSuffix(".png"))

        let loaded = try storage.load(path: path)
        XCTAssertEqual(loaded, whitePixel)
    }

    func testSameImageDataReusesFile() throws {
        let data = validPNGData()
        let path1 = try storage.save(pngData: data)
        let path2 = try storage.save(pngData: data)

        XCTAssertEqual(path1, path2, "相同图片内容应复用同一个哈希文件")
    }

    func testDifferentImageDataUsesDifferentFiles() throws {
        let path1 = try storage.save(pngData: Data("image-a".utf8))
        let path2 = try storage.save(pngData: Data("image-b".utf8))

        XCTAssertNotEqual(path1, path2)
    }

    func testDeleteRemovesFile() throws {
        let data = validPNGData()
        let path = try storage.save(pngData: data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        try storage.delete(path: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testDeleteNonExistentPathDoesNotThrow() {
        let fakePath = tempDir.appendingPathComponent("nonexistent.png").path
        XCTAssertNoThrow(try storage.delete(path: fakePath))
    }

    func testDeleteUnreferencedFilesOnlyRemovesOrphans() throws {
        let referencedPath = try storage.save(pngData: validPNGData())
        let orphanPath = tempDir.appendingPathComponent("orphan.png")
        try Data("orphan".utf8).write(to: orphanPath)

        let deleted = try storage.deleteUnreferencedFiles(validPaths: [referencedPath])

        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanPath.path))
        XCTAssertEqual(deleted.map(\.lastPathComponent), ["orphan.png"])
    }

    private func validPNGData() -> Data {
        Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG 签名
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  // IHDR
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
            0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,  // IDAT
            0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F, 0x00,
            0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59, 0xE7,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,  // IEND
            0xAE, 0x42, 0x60, 0x82
        ])
    }
}
