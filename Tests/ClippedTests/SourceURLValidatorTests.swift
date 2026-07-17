import XCTest
@testable import Clipped

final class SourceURLValidatorTests: XCTestCase {
    func testAcceptsHTTPAndHTTPS() throws {
        XCTAssertEqual(try SourceURLValidator.validate("https://example.com/video").scheme, "https")
        XCTAssertEqual(try SourceURLValidator.validate(" http://example.com/a ").scheme, "http")
    }

    func testRejectsLocalAndMalformedInputs() {
        for value in ["", "example.com", "file:///tmp/video.mp4", "javascript:alert(1)", "https://"] {
            XCTAssertThrowsError(try SourceURLValidator.validate(value), "Expected \(value) to fail")
        }
    }

    func testShellCharactersRemainURLData() throws {
        let url = try SourceURLValidator.validate("https://example.com/video;touch=/tmp/pwned")
        XCTAssertTrue(url.absoluteString.contains(";touch="))
    }
}
