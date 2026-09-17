import XCTest
@testable import ClipStackCore

final class ClipStackCoreTests: XCTestCase {
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
