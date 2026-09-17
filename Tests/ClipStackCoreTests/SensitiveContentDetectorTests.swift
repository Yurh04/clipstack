import XCTest
@testable import ClipStackCore

final class SensitiveContentDetectorTests: XCTestCase {

    func testConcealedTypeIsSensitive() {
        // 1Password 等密码管理器标记
        XCTAssertTrue(SensitiveContentDetector.isSensitive(
            pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
        ))
    }

    func testTransientTypeIsSensitive() {
        XCTAssertTrue(SensitiveContentDetector.isSensitive(
            pasteboardTypes: ["org.nspasteboard.TransientType"]
        ))
    }

    func testMatchIsCaseInsensitiveAndSubstring() {
        // 各家 App 大小写 / 命名可能有出入，用子串+忽略大小写兜底
        XCTAssertTrue(SensitiveContentDetector.isSensitive(pasteboardTypes: ["com.example.CONCEALED.data"]))
        XCTAssertTrue(SensitiveContentDetector.isSensitive(pasteboardTypes: ["some-transient-marker"]))
    }

    func testNormalTextIsNotSensitive() {
        XCTAssertFalse(SensitiveContentDetector.isSensitive(
            pasteboardTypes: ["public.utf8-plain-text", "public.html"]
        ))
    }

    func testEmptyTypesIsNotSensitive() {
        XCTAssertFalse(SensitiveContentDetector.isSensitive(pasteboardTypes: []))
    }
}
