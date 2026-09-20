import XCTest
@testable import ClipStackCore

final class ImageFileClassifierTests: XCTestCase {
    func testImageExtensionsAreClassifiedAsImages() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot.PNG")
        XCTAssertTrue(ImageFileClassifier.isImageFile(at: url))
    }

    func testNonImageExtensionsAreNotClassifiedAsImages() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("report.pdf")
        XCTAssertFalse(ImageFileClassifier.isImageFile(at: url))
    }

    func testMissingExtensionIsNotClassifiedAsImage() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-item")
        XCTAssertFalse(ImageFileClassifier.isImageFile(at: url))
    }
}
