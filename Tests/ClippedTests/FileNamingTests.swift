import XCTest
@testable import Clipped

final class FileNamingTests: XCTestCase {
    func testSanitizesUnsafeCharactersAndWhitespace() {
        XCTAssertEqual(FileNaming.sanitizedTitle("  A / strange:  title?  "), "A strange-title")
        XCTAssertEqual(FileNaming.sanitizedTitle("///"), "Untitled")
    }

    func testFilenameContainsSafeRange() {
        let range = ClipRange(startSeconds: 83, endSeconds: 125)
        XCTAssertEqual(
            FileNaming.baseFilename(title: "Source", range: range),
            "Source_00-01-23_to_00-02-05"
        )
    }

    func testCollisionSuffixNeverOverwrites() {
        let range = ClipRange(startSeconds: 1, endSeconds: 2)
        let existing = Set([
            "/tmp/Source_00-00-01_to_00-00-02.mp4",
            "/tmp/Source_00-00-01_to_00-00-02-2.mp4"
        ])
        let url = FileNaming.uniqueURL(
            in: URL(fileURLWithPath: "/tmp"),
            title: "Source",
            range: range,
            fileExtension: "mp4",
            fileExists: { existing.contains($0) }
        )
        XCTAssertEqual(url.lastPathComponent, "Source_00-00-01_to_00-00-02-3.mp4")
    }

    func testTitleRespectsByteLimit() {
        let output = FileNaming.sanitizedTitle(String(repeating: "é", count: 200), maxUTF8Bytes: 31)
        XCTAssertLessThanOrEqual(output.utf8.count, 31)
        XCTAssertFalse(output.isEmpty)
    }
}
