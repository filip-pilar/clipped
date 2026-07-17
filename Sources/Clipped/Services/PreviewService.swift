import Foundation

struct PreviewSelection: Equatable, Sendable {
    let selector: String
    let audioOnly: Bool

    static func choose(from metadata: YTDLPMetadata) throws -> PreviewSelection {
        let usable = metadata.formats.filter { !$0.isStoryboard }

        if !metadata.isAudioOnly {
            let progressive = usable
                .filter {
                    $0.containsVideo
                        && $0.containsAudio
                        && ($0.height ?? .max) <= 480
                        && CodecName.video($0.videoCodec) == "H.264"
                        && CodecName.audio($0.audioCodec) == "AAC"
                        && $0.fileExtension?.lowercased() == "mp4"
                }
                .max(by: previewVideoPrecedes)
            if let progressive {
                return PreviewSelection(selector: progressive.formatID, audioOnly: false)
            }

            let allVideo = usable.filter { $0.containsVideo && $0.height != nil }
            let withinLimit = allVideo.filter { ($0.height ?? .max) <= 480 }
            let pool = withinLimit.isEmpty
                ? allVideo.sorted { ($0.height ?? .max) < ($1.height ?? .max) }.prefix(1).map { $0 }
                : withinLimit
            guard let video = pool.max(by: previewVideoPrecedes) else {
                throw PreviewServiceError.noPreviewFormat
            }
            let audio = usable
                .filter { $0.containsAudio && !$0.containsVideo }
                .max { ($0.audioBitrate ?? 0) < ($1.audioBitrate ?? 0) }
            let selector = audio.map { "\(video.formatID)+\($0.formatID)" } ?? video.formatID
            return PreviewSelection(selector: selector, audioOnly: false)
        }

        guard let audio = usable
            .filter(\.containsAudio)
            .max(by: { ($0.audioBitrate ?? 0) < ($1.audioBitrate ?? 0) }) else {
            throw PreviewServiceError.noPreviewFormat
        }
        return PreviewSelection(selector: audio.formatID, audioOnly: true)
    }

    private static func previewVideoPrecedes(_ lhs: YTDLPFormat, _ rhs: YTDLPFormat) -> Bool {
        let lhsHeight = lhs.height ?? 0
        let rhsHeight = rhs.height ?? 0
        if lhsHeight != rhsHeight { return lhsHeight < rhsHeight }
        let lhsCodec = CodecName.videoPreference(lhs.videoCodec)
        let rhsCodec = CodecName.videoPreference(rhs.videoCodec)
        if lhsCodec != rhsCodec { return lhsCodec < rhsCodec }
        return (lhs.videoBitrate ?? lhs.totalBitrate ?? 0) < (rhs.videoBitrate ?? rhs.totalBitrate ?? 0)
    }
}

enum PreviewPreparationStage: Equatable, Sendable {
    case downloading
    case normalizing
    case ready
}

struct PreviewPreparationProgress: Equatable, Sendable {
    let stage: PreviewPreparationStage
    let fractionCompleted: Double?
}

struct PreviewService: Sendable {
    let tools: ToolPaths
    let processRunner: any ProcessExecuting
    let probeService: MediaProbeService
    let cache: PreviewCache

    func prepare(
        media: LoadedMedia,
        onProgress: @escaping @Sendable (PreviewPreparationProgress) -> Void
    ) async throws -> URL {
        let selection = try PreviewSelection.choose(from: media.metadata)
        let key = PreviewCache.key(for: media)
        if let cached = await cache.cachedURL(for: key, audioOnly: selection.audioOnly) {
            onProgress(PreviewPreparationProgress(stage: .ready, fractionCompleted: 1))
            return cached
        }

        let workingDirectory = try await cache.makeWorkingDirectory(for: key)
        defer { Task { await cache.discardWorkingDirectory(workingDirectory) } }

        let outputTemplate = workingDirectory.appendingPathComponent("source.%(ext)s")
        let download = MediaCommands.previewDownload(
            sourceURL: media.requestedURL,
            selector: selection.selector,
            outputTemplate: outputTemplate,
            tools: tools
        )
        let downloadResult = try await processRunner.run(download) { event in
            guard event.stream == .standardOutput,
                  let progress = YTDLPProgress.parse(line: event.line) else { return }
            onProgress(PreviewPreparationProgress(stage: .downloading, fractionCompleted: progress.fractionCompleted))
        }
        guard downloadResult.succeeded else {
            throw PreviewServiceError.downloadFailed(Self.conciseError(downloadResult.standardError))
        }

        let downloaded = try MediaFileDiscovery.firstMediaFile(in: workingDirectory)
        let probe = try await probeService.inspect(downloaded)
        let finalWorkingURL = workingDirectory.appendingPathComponent(selection.audioOnly ? "preview.m4a" : "preview.mp4")

        if Self.isDirectlyPlayable(probe: probe, url: downloaded, audioOnly: selection.audioOnly) {
            try FileManager.default.moveItem(at: downloaded, to: finalWorkingURL)
        } else {
            onProgress(PreviewPreparationProgress(stage: .normalizing, fractionCompleted: nil))
            let progressTracker = FFmpegProgressTracker(durationSeconds: media.metadata.duration ?? 1)
            let command = selection.audioOnly
                ? MediaCommands.normalizedPreviewAudio(input: downloaded, output: finalWorkingURL, tools: tools)
                : MediaCommands.normalizedPreviewVideo(input: downloaded, output: finalWorkingURL, tools: tools)
            let result = try await processRunner.run(command) { event in
                guard event.stream == .standardOutput,
                      let fraction = progressTracker.consume(line: event.line) else { return }
                onProgress(PreviewPreparationProgress(stage: .normalizing, fractionCompleted: fraction))
            }
            guard result.succeeded else {
                throw PreviewServiceError.normalizationFailed(Self.conciseError(result.standardError))
            }
        }

        let finalURL = try await cache.commit(finalWorkingURL, key: key, audioOnly: selection.audioOnly)
        onProgress(PreviewPreparationProgress(stage: .ready, fractionCompleted: 1))
        return finalURL
    }

    private static func isDirectlyPlayable(probe: ProbedMedia, url: URL, audioOnly: Bool) -> Bool {
        if audioOnly {
            return probe.videoStream == nil
                && probe.audioStream?.codecName == "aac"
                && url.pathExtension.lowercased() == "m4a"
        }
        return probe.videoStream?.codecName == "h264"
            && (probe.audioStream == nil || probe.audioStream?.codecName == "aac")
            && url.pathExtension.lowercased() == "mp4"
    }

    private static func conciseError(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Unknown media-tool error"
    }
}

enum PreviewServiceError: Error, LocalizedError {
    case noPreviewFormat
    case downloadFailed(String)
    case normalizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPreviewFormat:
            "No previewable format was found for this source."
        case .downloadFailed:
            "The preview could not be downloaded."
        case .normalizationFailed:
            "The preview could not be prepared."
        }
    }
}

enum MediaFileDiscovery {
    static func firstMediaFile(in directory: URL) throws -> URL {
        let excludedExtensions: Set<String> = ["part", "ytdl", "json", "temp", "tmp"]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            guard !excludedExtensions.contains(url.pathExtension.lowercased()),
                  !url.lastPathComponent.hasSuffix(".part") else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted { lhs, rhs in
            let lhsSize = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let rhsSize = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return lhsSize > rhsSize
        }

        guard let first = files.first else {
            throw MediaFileDiscoveryError.noMediaFile
        }
        return first
    }
}

enum MediaFileDiscoveryError: Error, LocalizedError {
    case noMediaFile

    var errorDescription: String? {
        "The downloader finished without producing a media file."
    }
}
