import XCTest
@testable import Clipped

final class EditorStateTests: XCTestCase {
    func testYouTubeTimestampParsesSupportedForms() throws {
        XCTAssertEqual(YouTubeTimestamp.parse("90"), 90)
        XCTAssertEqual(YouTubeTimestamp.parse("90s"), 90)
        XCTAssertEqual(YouTubeTimestamp.parse("1m30s"), 90)
        XCTAssertEqual(YouTubeTimestamp.parse("1h2m3s"), 3_723)
        XCTAssertNil(YouTubeTimestamp.parse("1:30"))
        XCTAssertNil(YouTubeTimestamp.parse("later"))

        let query = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=abc&t=1m30s"))
        let fragment = try XCTUnwrap(URL(string: "https://youtu.be/abc#t=42s"))
        let unrelated = try XCTUnwrap(URL(string: "https://example.com/watch?t=90"))
        XCTAssertEqual(YouTubeTimestamp.timestampValue(from: query), 90)
        XCTAssertEqual(YouTubeTimestamp.timestampValue(from: fragment), 42)
        XCTAssertNil(YouTubeTimestamp.timestampValue(from: unrelated))
    }

    func testMetadataStartTimeTakesPrecedenceAndClamps() throws {
        let url = try XCTUnwrap(URL(string: "https://youtube.com/watch?v=x&t=10"))
        XCTAssertEqual(
            YouTubeTimestamp.initialSeconds(metadataStartTime: 72.6, url: url, maximumSeconds: 100),
            73
        )
        XCTAssertEqual(
            YouTubeTimestamp.initialSeconds(metadataStartTime: 500, url: url, maximumSeconds: 100),
            100
        )
        XCTAssertEqual(
            YouTubeTimestamp.initialSeconds(metadataStartTime: nil, url: url, maximumSeconds: 100),
            10
        )
    }

    func testChaptersDecodeNormalizeSortAndClamp() throws {
        let json = #"""
        {
          "id":"chapters","title":"Chapters","duration":100,
          "chapters":[
            {"title":"Late","start_time":80,"end_time":150},
            {"title":"Start","start_time":0,"end_time":20},
            {"title":"Past end","start_time":120,"end_time":130}
          ],
          "formats":[]
        }
        """#
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(json.utf8))
        let chapters = metadata.normalizedChapters(maximumSeconds: 100)
        XCTAssertEqual(chapters.map(\.title), ["Start", "Late"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 80])
        XCTAssertEqual(chapters.last?.endTime, 100)
    }

    func testDraftRequiresAnOutAfterIn() {
        XCTAssertNil(DraftRange(inSeconds: 10, outSeconds: nil).committedRange)
        XCTAssertNil(DraftRange(inSeconds: 10, outSeconds: 10).committedRange)
        XCTAssertEqual(
            DraftRange(inSeconds: 10, outSeconds: 20).committedRange?.durationSeconds,
            10
        )
    }
}
