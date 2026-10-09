import XCTest
@testable import ClipStackCore

final class FavoriteStorageTests: XCTestCase {
    func testMaterializeFileSurvivesOriginalDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let favorites = root.appendingPathComponent("favorites")
        let original = root.appendingPathComponent("source.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("important".utf8).write(to: original)
        let item = ClipboardItem(type: .file, content: original.path)
        let copied = try FavoriteStorage(directory: favorites).materialize(item)
        try FileManager.default.removeItem(at: original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.content))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: copied.content)), Data("important".utf8))
    }

    func testMaterializeMultipleFilesPreservesOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let favorites = root.appendingPathComponent("favorites")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.txt")
        let second = root.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: first)
        try Data("b".utf8).write(to: second)
        let item = ClipboardItem(type: .file, content: "\(first.path)\n\(second.path)")
        let copied = try FavoriteStorage(directory: favorites).materialize(item)
        let paths = copied.content.split(separator: "\n").map(String.init)
        XCTAssertEqual(paths.count, 2)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: paths[0])), Data("a".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: paths[1])), Data("b".utf8))
    }
}
