import XCTest
@testable import ClipStackCore

final class ClipStackCoreTests: XCTestCase {
    func testClipboardItemTapBehaviorKeepsTextAndFilesSelected() {
        XCTAssertEqual(
            ClipboardItemTapBehavior.action(for: ClipboardItem(type: .file, content: "/tmp/report.pdf")),
            .select
        )
        XCTAssertEqual(
            ClipboardItemTapBehavior.action(for: ClipboardItem(type: .text, content: "hello")),
            .select
        )
        XCTAssertEqual(
            ClipboardItemTapBehavior.action(for: ClipboardItem(type: .image, content: "/tmp/image.png")),
            .preview
        )
    }

    func testClipboardItemCreation() {
        let item = ClipboardItem(
            type: .text,
            content: "Hello",
            sourceApp: "TestApp"
        )
        XCTAssertEqual(item.type, .text)
        XCTAssertEqual(item.content, "Hello")
        XCTAssertEqual(item.sourceApp, "TestApp")
        XCTAssertFalse(item.isSensitive)
    }
}
