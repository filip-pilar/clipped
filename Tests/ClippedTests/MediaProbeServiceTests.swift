import XCTest
@testable import Clipped

final class MediaProbeServiceTests: XCTestCase {
    func testDecodesProbeResponse() async throws {
        let runner = TestProcessExecutor { _, _ in
            ProcessResult(
                terminationStatus: 0,
                standardOutput: TestFixtures.normalizedProbeJSON,
                standardError: ""
            )
        }
        let service = MediaProbeService(tools: TestFixtures.tools, processRunner: runner)
        let media = try await service.inspect(URL(fileURLWithPath: "/tmp/clip.mp4"))

        XCTAssertEqual(media.duration, 3)
        XCTAssertEqual(media.videoStream?.codecName, "h264")
        XCTAssertEqual(media.videoStream?.width, 1_920)
        XCTAssertEqual(media.audioStream?.channels, 6)
        XCTAssertTrue(media.formatNames.contains("mp4"))
    }

    func testRejectsInvalidProbeJSON() async {
        let runner = TestProcessExecutor { _, _ in
            ProcessResult(terminationStatus: 0, standardOutput: "not-json", standardError: "")
        }
        let service = MediaProbeService(tools: TestFixtures.tools, processRunner: runner)
        do {
            _ = try await service.inspect(URL(fileURLWithPath: "/tmp/clip.mp4"))
            XCTFail("Expected invalid response")
        } catch is MediaProbeError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
