import XCTest
@testable import Clipped

final class ExportServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippedExportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testExportsValidatedClipWithCollisionSafeFilename() async throws {
        let runner = makeRunner()
        let probeService = MediaProbeService(tools: TestFixtures.tools, processRunner: runner)
        let service = ExportService(
            tools: TestFixtures.tools,
            processRunner: runner,
            probeService: probeService,
            workingRoot: root.appendingPathComponent("work", isDirectory: true)
        )
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(
            video: media.catalog.videoChoices.first(where: { $0.formatID == "299" }),
            audio: media.catalog.audioChoices.first
        )
        let range = ClipRange(startSeconds: 5, endSeconds: 8)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let progress = LockedRecorder<ExportProgress>()

        let outputs = try await service.export(
            media: media,
            selection: selection,
            ranges: [range],
            outputDirectory: downloads,
            onProgress: progress.append
        )

        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(outputs[0].url.lastPathComponent, "A Source-Title_00-00-05_to_00-00-08.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputs[0].url.path))
        XCTAssertEqual(progress.values.last?.stage, .completed)
        XCTAssertEqual(progress.values.last?.overallFraction, 1)

        let commands = await runner.recordedCommands()
        let download = try XCTUnwrap(commands.first(where: { $0.executableURL.lastPathComponent == "yt-dlp" }))
        XCTAssertTrue(download.arguments.contains("299+258"))
        let normalization = try XCTUnwrap(commands.first(where: {
            $0.executableURL.lastPathComponent == "ffmpeg" && $0.arguments.contains("h264_videotoolbox")
        }))
        XCTAssertTrue(normalization.arguments.contains("384k"))
    }

    func testRejectsInvalidRangeBeforeLaunchingTools() async throws {
        let runner = makeRunner()
        let probeService = MediaProbeService(tools: TestFixtures.tools, processRunner: runner)
        let service = ExportService(
            tools: TestFixtures.tools,
            processRunner: runner,
            probeService: probeService,
            workingRoot: root.appendingPathComponent("work", isDirectory: true)
        )
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(video: media.catalog.defaultVideoChoice, audio: media.catalog.defaultAudioChoice)

        do {
            _ = try await service.export(
                media: media,
                selection: selection,
                ranges: [ClipRange(startSeconds: 99, endSeconds: 101)],
                outputDirectory: root
            ) { _ in }
            XCTFail("Expected validation failure")
        } catch is ClipRangeValidationError {
            // Expected.
        }
        let commands = await runner.recordedCommands()
        XCTAssertTrue(commands.isEmpty)
    }

    func testRetriesTransientDownloadFailureBeforeExporting() async throws {
        let attempts = DownloadAttemptState()
        let runner = makeRunner(downloadFailures: 1, attempts: attempts)
        let probeService = MediaProbeService(tools: TestFixtures.tools, processRunner: runner)
        let service = ExportService(
            tools: TestFixtures.tools,
            processRunner: runner,
            probeService: probeService,
            workingRoot: root.appendingPathComponent("work", isDirectory: true),
            downloadRetryDelayNanoseconds: 0
        )
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(
            video: media.catalog.videoChoices.first(where: { $0.formatID == "299" }),
            audio: media.catalog.audioChoices.first
        )

        let outputs = try await service.export(
            media: media,
            selection: selection,
            ranges: [ClipRange(startSeconds: 5, endSeconds: 8)],
            outputDirectory: root.appendingPathComponent("Downloads", isDirectory: true)
        ) { _ in }

        XCTAssertEqual(outputs.count, 1)
        let downloadAttemptCount = await attempts.value
        XCTAssertEqual(downloadAttemptCount, 2)
    }

    private func makeRunner(
        downloadFailures: Int = 0,
        attempts: DownloadAttemptState = DownloadAttemptState()
    ) -> TestProcessExecutor {
        TestProcessExecutor { command, onEvent in
            switch command.executableURL.lastPathComponent {
            case "yt-dlp":
                let attempt = await attempts.next()
                if attempt <= downloadFailures {
                    return ProcessResult(
                        terminationStatus: 1,
                        standardOutput: "",
                        standardError: "ERROR: temporary media-server failure"
                    )
                }
                let template = command.arguments[command.arguments.firstIndex(of: "--output")! + 1]
                let path = template.replacingOccurrences(of: "%(ext)s", with: "mp4")
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("acquisition".utf8).write(to: URL(fileURLWithPath: path))
                onEvent(ProcessOutputEvent(stream: .standardOutput, line: "CLIPPED_PROGRESS|50|100|1"))
                return ProcessResult(terminationStatus: 0, standardOutput: "", standardError: "")
            case "ffmpeg":
                let output = URL(fileURLWithPath: command.arguments.last!)
                try Data("normalized".utf8).write(to: output)
                onEvent(ProcessOutputEvent(stream: .standardOutput, line: "out_time_us=3000000"))
                onEvent(ProcessOutputEvent(stream: .standardOutput, line: "progress=end"))
                return ProcessResult(terminationStatus: 0, standardOutput: "", standardError: "")
            case "ffprobe":
                let input = command.arguments.last!
                let json = input.contains("normalized")
                    ? TestFixtures.normalizedProbeJSON
                    : TestFixtures.acquisitionProbeJSON
                return ProcessResult(terminationStatus: 0, standardOutput: json, standardError: "")
            default:
                return ProcessResult(terminationStatus: 1, standardOutput: "", standardError: "unexpected tool")
            }
        }
    }
}

private actor DownloadAttemptState {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
