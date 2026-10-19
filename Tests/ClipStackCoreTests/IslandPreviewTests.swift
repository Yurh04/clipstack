import XCTest
@testable import ClipStackCore

final class IslandPreviewTests: XCTestCase {
    private func item(
        _ type: ClipboardItemType,
        _ content: String,
        createdAt: TimeInterval,
        id: Int64? = nil,
        deletionDeadline: Date? = nil
    ) -> ClipboardItem {
        var item = ClipboardItem(
            id: id,
            type: type,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
        item.deletionDeadline = deletionDeadline
        return item
    }

    // MARK: - recent

    func testRecentSortsByNewestFirstAndTruncatesToLimit() {
        let items = (1...7).map { index in
            item(.text, "第 \(index) 条", createdAt: TimeInterval(index))
        }
        let recent = IslandPreview.recent(items, limit: 5)
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.map(\.content), ["第 7 条", "第 6 条", "第 5 条", "第 4 条", "第 3 条"])
    }

    func testRecentSkipsItemsPendingDeletion() {
        let items = [
            item(.text, "保留", createdAt: 1),
            item(.text, "待删除", createdAt: 2, deletionDeadline: Date(timeIntervalSince1970: 3))
        ]
        XCTAssertEqual(IslandPreview.recent(items).map(\.content), ["保留"])
    }

    func testRecentUsesIdentifierToKeepEqualTimestampsStable() {
        let items = [
            item(.text, "旧 id", createdAt: 5, id: 1),
            item(.text, "新 id", createdAt: 5, id: 2)
        ]
        XCTAssertEqual(IslandPreview.recent(items).map(\.content), ["新 id", "旧 id"])
    }

    func testRecentWithZeroLimitReturnsEmpty() {
        XCTAssertTrue(IslandPreview.recent([item(.text, "x", createdAt: 1)], limit: 0).isEmpty)
    }

    // MARK: - preview

    func testPreviewKeepsFirstNonEmptyLineAndCollapsesWhitespace() {
        let text = "\n   \n第一行内容\n第二行内容"
        XCTAssertEqual(IslandPreview.preview(for: item(.text, text, createdAt: 1)), "第一行内容")
    }

    func testPreviewTruncatesLongTextWithEllipsis() {
        let long = String(repeating: "a", count: 60)
        let preview = IslandPreview.preview(for: item(.text, long, createdAt: 1), maxCharacters: 10)
        XCTAssertEqual(preview, "aaaaaaaaaa…")
    }

    func testPreviewOfEmptyText() {
        XCTAssertEqual(IslandPreview.preview(for: item(.text, "   \n\n", createdAt: 1)), "(空)")
    }

    func testPreviewOfImageIsPlaceholder() {
        XCTAssertEqual(IslandPreview.preview(for: item(.image, "/tmp/a.png", createdAt: 1)), "图片")
    }

    func testPreviewOfSingleFileShowsFileName() {
        XCTAssertEqual(IslandPreview.preview(for: item(.file, "/Users/me/Docs/report.pdf", createdAt: 1)), "report.pdf")
    }

    func testPreviewOfMultipleFilesShowsCount() {
        let content = "/tmp/a.txt\n/tmp/b.txt\n/tmp/c.txt"
        XCTAssertEqual(IslandPreview.preview(for: item(.file, content, createdAt: 1)), "3 个文件")
    }
}
