import Foundation

enum ExportStage: Equatable, Sendable {
    case downloading
    case normalizing
    case validating
    case completed
}

struct ExportProgress: Equatable, Sendable {
    let rangeID: UUID
    let clipIndex: Int
    let clipCount: Int
    let stage: ExportStage
    let fractionCompleted: Double?
    let completedURL: URL?

    var overallFraction: Double? {
        guard let fractionCompleted, clipCount > 0 else { return nil }
        return min(1, (Double(clipIndex) + fractionCompleted) / Double(clipCount))
    }
}

struct ExportedClip: Equatable, Sendable {
    let range: ClipRange
    let url: URL
}

struct ExportService: Sendable {
    let tools: ToolPaths
    let processRunner: any ProcessExecuting
    let probeService: MediaProbeService
    let workingRoot: URL
    let maximumDownloadAttempts: Int
    let downloadRetryDelayNanoseconds: UInt64

    init(
        tools: ToolPaths,
        processRunner: any ProcessExecuting,
        probeService: MediaProbeService,
        workingRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("ClippedExports", isDirectory: true),
        maximumDownloadAttempts: Int = 3,
        downloadRetryDelayNanoseconds: UInt64 = 750_000_000
    ) {
        self.tools = tools
        self.processRunner = processRunner
        self.probeService = probeService
        self.workingRoot = workingRoot
        self.maximumDownloadAttempts = max(1, maximumDownloadAttempts)
        self.downloadRetryDelayNanoseconds = downloadRetryDelayNanoseconds
    }

    func export(
        media: LoadedMedia,
        selection: MediaSelection,
        ranges: [ClipRange],
        outputDirectory: URL = .downloadsDirectory,
        onProgress: @escaping @Sendable (ExportProgress) -> Void
    ) async throws -> [ExportedClip] {
        guard !ranges.isEmpty else { throw ExportServiceError.noRanges }
        let validatedRanges = try ranges.map { try $0.validated(maximumSeconds: media.maximumWholeSecond) }
        let selector = try selection.ytDLPSelector()
        try FileManager.default.createDirectory(at: workingRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var completed: [ExportedClip] = []
        for (index, range) in validatedRanges.enumerated() {
            try Task.checkCancellation()
            let directory = workingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let template = directory.appendingPathComponent("acquisition.%(ext)s")
            let download = MediaCommands.rangedDownload(
                sourceURL: media.requestedURL,
                selector: selector,
                range: range,
                outputTemplate: template,
                tools: tools
            )
            let downloadResult = try await runDownloadWithRetries(download, in: directory) { event in
                guard event.stream == .standardOutput,
                      let progress = YTDLPProgress.parse(line: event.line) else { return }
                onProgress(ExportProgress(
                    rangeID: range.id,
                    clipIndex: index,
                    clipCount: validatedRanges.count,
                    stage: .downloading,
                    fractionCompleted: progress.fractionCompleted.map { $0 * 0.45 },
                    completedURL: nil
                ))
            }
            guard downloadResult.succeeded else {
                throw ExportServiceError.downloadFailed(Self.conciseError(downloadResult.standardError))
            }

            let acquisition = try MediaFileDiscovery.firstMediaFile(in: directory)
            let acquisitionProbe = try await probeService.inspect(acquisition)
            let actualChannels = selection.expectedAudioChannels ?? acquisitionProbe.audioStream?.channels
            let audioBitrate = Self.audioBitrate(channels: actualChannels)
            let outputExtension = selection.isAudioOnly ? "m4a" : "mp4"
            let normalized = directory.appendingPathComponent("normalized").appendingPathExtension(outputExtension)
            let normalization = selection.isAudioOnly
                ? MediaCommands.normalizedAudio(
                    input: acquisition,
                    output: normalized,
                    durationSeconds: range.durationSeconds,
                    audioBitrateKilobits: audioBitrate,
                    tools: tools
                )
                : MediaCommands.normalizedVideo(
                    input: acquisition,
                    output: normalized,
                    durationSeconds: range.durationSeconds,
                    audioBitrateKilobits: audioBitrate,
                    tools: tools
                )
            let tracker = FFmpegProgressTracker(durationSeconds: Double(range.durationSeconds))
            let normalizationResult = try await processRunner.run(normalization) { event in
                guard event.stream == .standardOutput,
                      let fraction = tracker.consume(line: event.line) else { return }
                onProgress(ExportProgress(
                    rangeID: range.id,
                    clipIndex: index,
                    clipCount: validatedRanges.count,
                    stage: .normalizing,
                    fractionCompleted: 0.45 + fraction * 0.5,
                    completedURL: nil
                ))
            }
            guard normalizationResult.succeeded else {
                throw ExportServiceError.normalizationFailed(Self.conciseError(normalizationResult.standardError))
            }

            onProgress(ExportProgress(
                rangeID: range.id,
                clipIndex: index,
                clipCount: validatedRanges.count,
                stage: .validating,
                fractionCompleted: 0.97,
                completedURL: nil
            ))
            let outputProbe = try await probeService.inspect(normalized)
            try OutputValidator.validate(
                outputProbe,
                expectedDuration: Double(range.durationSeconds),
                selection: selection
            )

            let destination = FileNaming.uniqueURL(
                in: outputDirectory,
                title: media.metadata.title,
                range: range,
                fileExtension: outputExtension
            )
            try FileManager.default.moveItem(at: normalized, to: destination)
            let exported = ExportedClip(range: range, url: destination)
            completed.append(exported)
            onProgress(ExportProgress(
                rangeID: range.id,
                clipIndex: index,
                clipCount: validatedRanges.count,
                stage: .completed,
                fractionCompleted: 1,
                completedURL: destination
            ))
        }

        return completed
    }

    private func runDownloadWithRetries(
        _ command: ProcessCommand,
        in directory: URL,
        onEvent: @escaping @Sendable (ProcessOutputEvent) -> Void
    ) async throws -> ProcessResult {
        var lastResult = ProcessResult(
            terminationStatus: -1,
            standardOutput: "",
            standardError: "The download did not start."
        )

        for attempt in 0..<maximumDownloadAttempts {
            if attempt > 0 {
                try Task.checkCancellation()
                try Self.removeContents(of: directory)
                if downloadRetryDelayNanoseconds > 0 {
                    try await Task.sleep(
                        nanoseconds: downloadRetryDelayNanoseconds * UInt64(attempt)
                    )
                }
            }

            lastResult = try await processRunner.run(command, onEvent: onEvent)
            if lastResult.succeeded {
                return lastResult
            }
        }

        return lastResult
    }

    private static func removeContents(of directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    private static func audioBitrate(channels: Int?) -> Int {
        switch channels {
        case .some(let value) where value >= 6:
            min(512, value * 64)
        case 1:
            128
        default:
            192
        }
    }

    private static func conciseError(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Unknown media-tool error"
    }
}

enum OutputValidator {
    static func validate(
        _ media: ProbedMedia,
        expectedDuration: Double,
        selection: MediaSelection
    ) throws {
        guard let duration = media.duration,
              abs(duration - expectedDuration) <= 0.15 else {
            throw OutputValidationError.inexactDuration(actual: media.duration, expected: expectedDuration)
        }

        if selection.isAudioOnly {
            guard media.videoStream == nil, media.audioStream?.codecName == "aac" else {
                throw OutputValidationError.unexpectedCodecs
            }
        } else {
            guard let video = media.videoStream,
                  video.codecName == "h264",
                  video.codecTag == nil || video.codecTag == "avc1",
                  video.pixelFormat == nil || video.pixelFormat == "yuv420p" else {
                throw OutputValidationError.unexpectedCodecs
            }
            if let expectedWidth = selection.video?.width,
               let width = video.width,
               width > expectedWidth {
                throw OutputValidationError.upscaled
            }
            if let expectedHeight = selection.video?.height,
               let height = video.height,
               height > expectedHeight {
                throw OutputValidationError.upscaled
            }
        }

        if selection.audio != nil || selection.video?.hasEmbeddedAudio == true {
            guard let audio = media.audioStream, audio.codecName == "aac" else {
                throw OutputValidationError.unexpectedCodecs
            }
            if let expectedChannels = selection.expectedAudioChannels,
               let actualChannels = audio.channels,
               expectedChannels != actualChannels {
                throw OutputValidationError.channelLayoutChanged
            }
        }
    }
}

enum OutputValidationError: Error, LocalizedError {
    case inexactDuration(actual: Double?, expected: Double)
    case unexpectedCodecs
    case upscaled
    case channelLayoutChanged

    var errorDescription: String? {
        switch self {
        case .inexactDuration:
            "The exported clip did not have the requested duration."
        case .unexpectedCodecs:
            "The exported clip was not a compatible H.264/AAC file."
        case .upscaled:
            "The exported clip was unexpectedly upscaled."
        case .channelLayoutChanged:
            "The exported clip did not preserve its selected audio channels."
        }
    }
}

enum ExportServiceError: Error, LocalizedError {
    case noRanges
    case downloadFailed(String)
    case normalizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRanges:
            "Add at least one clip range."
        case .downloadFailed(let message), .normalizationFailed(let message):
            message
        }
    }
}
