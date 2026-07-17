import XCTest
@testable import Clipped

final class ClipRangeTests: XCTestCase {
    func testValidRange() throws {
        let range = ClipRange(startSeconds: 12, endSeconds: 37)
        XCTAssertEqual(try range.validated(maximumSeconds: 60), range)
        XCTAssertEqual(range.durationSeconds, 25)
    }

    func testRejectsInvalidRanges() {
        XCTAssertThrowsError(try ClipRange(startSeconds: -1, endSeconds: 4).validated(maximumSeconds: 10)) {
            XCTAssertEqual($0 as? ClipRangeValidationError, .negativeStart)
        }
        XCTAssertThrowsError(try ClipRange(startSeconds: 4, endSeconds: 4).validated(maximumSeconds: 10)) {
            XCTAssertEqual($0 as? ClipRangeValidationError, .nonPositiveDuration)
        }
        XCTAssertThrowsError(try ClipRange(startSeconds: 4, endSeconds: 11).validated(maximumSeconds: 10)) {
            XCTAssertEqual($0 as? ClipRangeValidationError, .exceedsSourceDuration)
        }
    }

    func testOverlappingRangesRemainValid() throws {
        let first = try ClipRange(startSeconds: 5, endSeconds: 15).validated(maximumSeconds: 30)
        let second = try ClipRange(startSeconds: 10, endSeconds: 20).validated(maximumSeconds: 30)
        XCTAssertEqual(first.durationSeconds, 10)
        XCTAssertEqual(second.durationSeconds, 10)
    }
}
