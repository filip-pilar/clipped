import XCTest
@testable import Clipped

final class LivePipelineIntegrationTests: XCTestCase {
    func testPublicSourceExercisesPreviewMultiRangeAndChannelLayouts() async throws {
        guard ProcessInfo.processInfo.environment["CLIPPED_RUN_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set CLIPPED_RUN_NETWORK_TESTS=1 to run the public-network pipeline test.")
        }

        let tools = try Toolchain.locate()
        let runner = ProcessRunner()
        let probe = MediaProbeService(tools: tools, processRunner: runner)
        let metadataService = MetadataService(tools: tools, processRunner: runner)
        let media = try await metadataService.load(
            sourceText: "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippedLivePipeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let previewProgress = LockedRecorder<PreviewPreparationProgress>()
        let previewService = PreviewService(
            tools: tools,
            processRunner: runner,
            probeService: probe,
            cache: PreviewCache(rootDirectory: root.appendingPathComponent("PreviewCache", isDirectory: true))
        )
        let previewURL = try await previewService.prepare(media: media) {
            previewProgress.append($0)
        }
        let previewResult = try await probe.inspect(previewURL)
        XCTAssertEqual(previewURL.pathExtension, "mp4")
        XCTAssertEqual(previewResult.videoStream?.codecName, "h264")
        XCTAssertEqual(previewResult.audioStream?.codecName, "aac")
        XCTAssertGreaterThan(previewResult.duration ?? 0, 1)
        XCTAssertTrue(previewProgress.values.contains { $0.stage == .ready })

        let cachedPreviewURL = try await previewService.prepare(media: media) { _ in }
        XCTAssertEqual(cachedPreviewURL, previewURL)

        let video = try XCTUnwrap(media.catalog.videoChoices.first {
            $0.height == 1080 && ($0.framesPerSecond ?? 0) >= 59
        })
        let surroundAudio = try XCTUnwrap(media.catalog.audioChoices.first { ($0.channels ?? 0) >= 6 })
        let stereoAudio = try XCTUnwrap(media.catalog.audioChoices.first { $0.channels == 2 })
        let surroundSelection = MediaSelection(video: video, audio: surroundAudio)
        let ranges = [
            ClipRange(startSeconds: 5, endSeconds: 8),
            ClipRange(startSeconds: 10, endSeconds: 13)
        ]

        let service = ExportService(
            tools: tools,
            processRunner: runner,
            probeService: probe,
            workingRoot: root.appendingPathComponent("Work", isDirectory: true)
        )
        let exportProgress = LockedRecorder<ExportProgress>()
        let clips = try await service.export(
            media: media,
            selection: surroundSelection,
            ranges: ranges,
            outputDirectory: root.appendingPathComponent("SurroundDownloads", isDirectory: true)
        ) {
            exportProgress.append($0)
        }

        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(exportProgress.values.filter { $0.stage == .completed }.count, 2)
        for (clip, range) in zip(clips, ranges) {
            let result = try await probe.inspect(clip.url)
            XCTAssertEqual(result.videoStream?.codecName, "h264")
            XCTAssertEqual(result.videoStream?.codecTag, "avc1")
            XCTAssertEqual(result.audioStream?.codecName, "aac")
            XCTAssertEqual(result.audioStream?.channels, surroundAudio.channels)
            XCTAssertEqual(result.duration ?? 0, Double(range.durationSeconds), accuracy: 0.15)
            let filenameRange = "\(Timecode.filename(range.startSeconds))_to_\(Timecode.filename(range.endSeconds))"
            XCTAssertTrue(clip.url.lastPathComponent.contains(filenameRange))
        }

        let stereoRange = ClipRange(startSeconds: 15, endSeconds: 17)
        let stereoClips = try await service.export(
            media: media,
            selection: MediaSelection(video: video, audio: stereoAudio),
            ranges: [stereoRange],
            outputDirectory: root.appendingPathComponent("StereoDownloads", isDirectory: true)
        ) { _ in }
        let stereoClip = try XCTUnwrap(stereoClips.first)
        let stereoResult = try await probe.inspect(stereoClip.url)
        XCTAssertEqual(stereoResult.videoStream?.codecName, "h264")
        XCTAssertEqual(stereoResult.audioStream?.codecName, "aac")
        XCTAssertEqual(stereoResult.audioStream?.channels, 2)
        XCTAssertEqual(stereoResult.duration ?? 0, 2, accuracy: 0.15)
    }
}
