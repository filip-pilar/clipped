import XCTest
@testable import Clipped

final class TimecodeTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(Timecode.display(0), "00:00:00")
        XCTAssertEqual(Timecode.display(3_661), "01:01:01")
        XCTAssertEqual(Timecode.filename(3_661), "01-01-01")
    }

    func testParsingAcceptedForms() throws {
        XCTAssertEqual(try Timecode.parse("75"), 75)
        XCTAssertEqual(try Timecode.parse("01:15"), 75)
        XCTAssertEqual(try Timecode.parse("1:01:15"), 3_675)
        XCTAssertEqual(try Timecode.parse(" 00:00:09 "), 9)
    }

    func testParsingRejectsMalformedValues() {
        for value in ["", "1::2", "1:60", "1:02:60", "-1", "hello", "1:2:3:4"] {
            XCTAssertThrowsError(try Timecode.parse(value), "Expected \(value) to fail")
        }
    }
}
