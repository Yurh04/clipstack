import XCTest
@testable import ClipStackCore

final class SequentialPasteQueueTests: XCTestCase {
    func testOrderAndCompletionDoNotWrap() {
        var queue = SequentialPasteQueue()
        queue.start(ids: [4, 2, 9])
        XCTAssertEqual(queue.nextID, 4)
        queue.advance()
        XCTAssertEqual(queue.nextID, 2)
        queue.advance()
        XCTAssertEqual(queue.nextID, 9)
        queue.advance()
        queue.advance()
        XCTAssertNil(queue.nextID)
        XCTAssertEqual(queue.position, 3)
    }
    func testFailureRetainsItemAndRestartResetsProgress() {
        var queue = SequentialPasteQueue()
        queue.start(ids: [1, 2])
        XCTAssertEqual(queue.nextID, 1) // Failure: caller does not advance.
        queue.advance()
        queue.start(ids: [7])
        XCTAssertEqual(queue.position, 0)
        XCTAssertEqual(queue.nextID, 7)
        queue.stop()
        XCTAssertNil(queue.nextID)
        XCTAssertTrue(queue.ids.isEmpty)
    }
}
