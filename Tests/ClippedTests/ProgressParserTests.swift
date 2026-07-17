import XCTest
@testable import Clipped

final class ProgressParserTests: XCTestCase {
    func testParsesYTDLPProgress() throws {
        let progress = try XCTUnwrap(YTDLPProgress.parse(line: "CLIPPED_PROGRESS|250|1000|7"))
        XCTAssertEqual(progress.downloadedBytes, 250)
        XCTAssertEqual(progress.totalBytes, 1_000)
        XCTAssertEqual(progress.etaSeconds, 7)
        XCTAssertEqual(progress.fractionCompleted, 0.25)
    }

    func testYTDLPProgressAllowsUnknownTotals() throws {
        let progress = try XCTUnwrap(YTDLPProgress.parse(line: "CLIPPED_PROGRESS|250|NA|NA"))
        XCTAssertNil(progress.totalBytes)
        XCTAssertNil(progress.etaSeconds)
        XCTAssertNil(progress.fractionCompleted)
    }

    func testParsesFFmpegMicrosecondProgress() {
        var parser = FFmpegProgressParser(durationSeconds: 10)
        XCTAssertEqual(parser.consume(line: "out_time_us=2500000"), 0.25)
        XCTAssertEqual(parser.consume(line: "progress=end"), 1)
        XCTAssertNil(parser.consume(line: "frame=10"))
    }
}
