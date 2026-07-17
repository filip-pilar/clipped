import XCTest
@testable import Clipped

final class MediaCommandTests: XCTestCase {
    private let tools = ToolPaths(
        ytDLP: URL(fileURLWithPath: "/tools/yt-dlp"),
        deno: URL(fileURLWithPath: "/tools/deno"),
        ffmpeg: URL(fileURLWithPath: "/tools/ffmpeg"),
        ffprobe: URL(fileURLWithPath: "/tools/ffprobe")
    )

    func testMetadataCommandUsesExplicitPathsAndNoShell() throws {
        let source = try XCTUnwrap(URL(string: "https://example.com/watch?v=abc;touch=/tmp/pwned"))
        let command = MediaCommands.metadata(sourceURL: source, tools: tools)

        XCTAssertEqual(command.executableURL.path, "/tools/yt-dlp")
        XCTAssertTrue(command.arguments.contains("deno:/tools/deno"))
        XCTAssertTrue(command.arguments.contains("/tools"))
        XCTAssertTrue(command.arguments.contains("--retries"))
        XCTAssertTrue(command.arguments.contains("--fragment-retries"))
        XCTAssertEqual(command.arguments.suffix(2), ["--", source.absoluteString])
        XCTAssertFalse(command.arguments.contains("sh"))
        XCTAssertFalse(command.arguments.contains("-c"))
    }

    func testRangedCommandUsesOneRangeAsOneArgument() throws {
        let source = try XCTUnwrap(URL(string: "https://example.com/video"))
        let range = ClipRange(startSeconds: 65, endSeconds: 92)
        let command = MediaCommands.rangedDownload(
            sourceURL: source,
            selector: "299+258",
            range: range,
            outputTemplate: URL(fileURLWithPath: "/tmp/acquisition.%(ext)s"),
            tools: tools
        )

        let sectionIndex = try XCTUnwrap(command.arguments.firstIndex(of: "--download-sections"))
        XCTAssertEqual(command.arguments[sectionIndex + 1], "*65-92")
        XCTAssertTrue(command.arguments.contains("299+258"))
    }

    func testVideoNormalizationIsExactAndEditingCompatible() {
        let command = MediaCommands.normalizedVideo(
            input: URL(fileURLWithPath: "/tmp/input.webm"),
            output: URL(fileURLWithPath: "/tmp/output.mp4"),
            durationSeconds: 12,
            audioBitrateKilobits: 384,
            tools: tools
        )

        XCTAssertEqual(command.executableURL.path, "/tools/ffmpeg")
        XCTAssertTrue(command.arguments.contains("h264_videotoolbox"))
        XCTAssertTrue(command.arguments.contains("yuv420p"))
        XCTAssertTrue(command.arguments.contains("384k"))
        XCTAssertTrue(command.arguments.contains("+faststart"))
        XCTAssertEqual(command.arguments.last, "/tmp/output.mp4")

        let durationIndex = command.arguments.firstIndex(of: "-t")!
        XCTAssertEqual(command.arguments[durationIndex + 1], "12")
    }

    func testAudioNormalizationDoesNotRequestVideo() {
        let command = MediaCommands.normalizedAudio(
            input: URL(fileURLWithPath: "/tmp/input.webm"),
            output: URL(fileURLWithPath: "/tmp/output.m4a"),
            durationSeconds: 8,
            tools: tools
        )
        XCTAssertTrue(command.arguments.contains("-vn"))
        XCTAssertFalse(command.arguments.contains("h264_videotoolbox"))
    }
}
