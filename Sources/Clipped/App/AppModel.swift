import AppKit
import Foundation

struct AppIssue: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceText = ""
    @Published private(set) var media: LoadedMedia?
    @Published private(set) var selectedVideo: VideoQualityChoice?
    @Published private(set) var selectedAudio: AudioQualityChoice?
    @Published private(set) var ranges: [ClipRange] = []
    @Published var selectedRangeID: UUID?

    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var isPreparingPreview = false
    @Published private(set) var previewProgress: PreviewPreparationProgress?
    @Published private(set) var previewURL: URL?
    @Published private(set) var previewErrorMessage: String?

    @Published private(set) var isExporting = false
    @Published private(set) var isCancellingExport = false
    @Published private(set) var exportProgress: ExportProgress?
    @Published private(set) var completedOutputs: [URL] = []
    @Published var issue: AppIssue?

    let player = PlayerController()

    private let sourceRunner: ProcessRunner
    private let exportRunner: ProcessRunner
    private let metadataService: MetadataService?
    private let previewService: PreviewService?
    private let exportService: ExportService?
    private var sourceTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var invalidTimecodeFields: Set<String> = []

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let sourceRunner = ProcessRunner()
        let exportRunner = ProcessRunner()
        self.sourceRunner = sourceRunner
        self.exportRunner = exportRunner

        do {
            let tools = try Self.resolveTools(environment: environment)
            let sourceProbe = MediaProbeService(tools: tools, processRunner: sourceRunner)
            let exportProbe = MediaProbeService(tools: tools, processRunner: exportRunner)
            metadataService = MetadataService(tools: tools, processRunner: sourceRunner)
            previewService = PreviewService(
                tools: tools,
                processRunner: sourceRunner,
                probeService: sourceProbe,
                cache: PreviewCache()
            )
            exportService = ExportService(
                tools: tools,
                processRunner: exportRunner,
                probeService: exportProbe
            )
        } catch {
            metadataService = nil
            previewService = nil
            exportService = nil
            issue = AppIssue(
                title: "Media tools unavailable",
                message: error.localizedDescription
            )
        }

        #if DEBUG
        if environment["CLIPPED_UI_TEST_MODE"] == "loaded" {
            installUITestMedia()
        }
        #endif
    }

    var canLoad: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoadingMetadata
            && !isExporting
    }

    var selectedVideoID: String {
        get { selectedVideo?.id ?? "" }
        set {
            selectedVideo = media?.catalog.videoChoices.first(where: { $0.id == newValue })
        }
    }

    var selectedAudioID: String {
        get { selectedAudio?.id ?? "" }
        set {
            selectedAudio = media?.catalog.audioChoices.first(where: { $0.id == newValue })
        }
    }

    var totalSelectedSeconds: Int {
        ranges.reduce(0) { $0 + max(0, $1.durationSeconds) }
    }

    var canExport: Bool {
        guard let media, exportService != nil, !ranges.isEmpty,
              !isLoadingMetadata, !isExporting, invalidTimecodeFields.isEmpty else {
            return false
        }
        guard ranges.allSatisfy({ (try? $0.validated(maximumSeconds: media.maximumWholeSecond)) != nil }) else {
            return false
        }
        if selectedVideo == nil && selectedAudio == nil { return false }
        if selectedVideo?.hasEmbeddedAudio == false,
           selectedAudio == nil,
           !media.catalog.audioChoices.isEmpty {
            return false
        }
        return true
    }

    var exportButtonTitle: String {
        let count = ranges.count
        return count == 1 ? "Download Clip" : "Download \(count) Clips"
    }

    var exportStatusText: String? {
        guard let progress = exportProgress else { return nil }
        let clip = "Clip \(progress.clipIndex + 1) of \(progress.clipCount)"
        switch progress.stage {
        case .downloading: return "\(clip) · Downloading"
        case .normalizing: return "\(clip) · Preparing MP4"
        case .validating: return "\(clip) · Checking output"
        case .completed: return "\(clip) · Complete"
        }
    }

    func loadSource() {
        guard canLoad else { return }
        guard let metadataService else {
            issue = AppIssue(title: "Media tools unavailable", message: "Reinstall Clipped with its bundled media tools.")
            return
        }

        stopSourceWork()
        exportTask?.cancel()
        player.clear()
        media = nil
        ranges = []
        invalidTimecodeFields.removeAll()
        completedOutputs = []
        exportProgress = nil
        previewURL = nil
        previewProgress = nil
        previewErrorMessage = nil
        isLoadingMetadata = true
        let input = sourceText

        sourceTask = Task { [weak self] in
            guard let self else { return }
            await sourceRunner.cancelAll()
            do {
                let loaded = try await metadataService.load(sourceText: input)
                try Task.checkCancellation()
                applyLoadedMedia(loaded)
                isLoadingMetadata = false
                preparePreview(for: loaded)
            } catch is CancellationError {
                isLoadingMetadata = false
            } catch {
                isLoadingMetadata = false
                issue = AppIssue(title: "Couldn’t load source", message: error.localizedDescription)
            }
        }
    }

    func addRange() {
        guard let media else { return }
        let maximum = media.maximumWholeSecond
        let playhead = min(maximum, max(0, Int(player.currentTime.rounded(.down))))
        let suggested = playhead > 0 ? playhead : (ranges.last?.endSeconds ?? 0)
        let start = min(max(0, suggested), max(0, maximum - 1))
        let end = min(maximum, start + 10)
        guard end > start else { return }
        let range = ClipRange(startSeconds: start, endSeconds: end)
        ranges.append(range)
        selectedRangeID = range.id
    }

    func removeRange(id: UUID) {
        ranges.removeAll { $0.id == id }
        invalidTimecodeFields = invalidTimecodeFields.filter { !$0.hasPrefix(id.uuidString) }
        if selectedRangeID == id { selectedRangeID = ranges.first?.id }
    }

    func updateRange(_ updated: ClipRange) {
        guard let index = ranges.firstIndex(where: { $0.id == updated.id }) else { return }
        ranges[index] = updated
    }

    func updateStart(_ seconds: Int, for id: UUID) {
        guard let index = ranges.firstIndex(where: { $0.id == id }) else { return }
        ranges[index].startSeconds = seconds
    }

    func updateEnd(_ seconds: Int, for id: UUID) {
        guard let index = ranges.firstIndex(where: { $0.id == id }) else { return }
        ranges[index].endSeconds = seconds
    }

    func setStartToPlayhead(for id: UUID) {
        guard let media, let index = ranges.firstIndex(where: { $0.id == id }) else { return }
        let value = min(max(0, Int(player.currentTime.rounded())), max(0, media.maximumWholeSecond - 1))
        ranges[index].startSeconds = value
        if ranges[index].endSeconds <= value {
            ranges[index].endSeconds = min(media.maximumWholeSecond, value + 10)
        }
    }

    func setEndToPlayhead(for id: UUID) {
        guard let media, let index = ranges.firstIndex(where: { $0.id == id }) else { return }
        let value = min(media.maximumWholeSecond, max(1, Int(player.currentTime.rounded())))
        ranges[index].endSeconds = value
        if ranges[index].startSeconds >= value {
            ranges[index].startSeconds = max(0, value - 10)
        }
    }

    func setTimecodeFieldValidity(key: String, isValid: Bool) {
        if isValid {
            invalidTimecodeFields.remove(key)
        } else {
            invalidTimecodeFields.insert(key)
        }
        objectWillChange.send()
    }

    func rangeError(_ range: ClipRange) -> String? {
        guard let media else { return nil }
        do {
            _ = try range.validated(maximumSeconds: media.maximumWholeSecond)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func seek(to seconds: Int) {
        player.seek(to: Double(seconds))
    }

    func export() {
        guard canExport, let media, let exportService else { return }
        let selection = MediaSelection(video: selectedVideo, audio: selectedAudio)
        let exportRanges = ranges
        completedOutputs = []
        exportProgress = nil
        isExporting = true
        isCancellingExport = false

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outputs = try await exportService.export(
                    media: media,
                    selection: selection,
                    ranges: exportRanges,
                    outputDirectory: .downloadsDirectory
                ) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        self.exportProgress = progress
                        if let url = progress.completedURL,
                           !self.completedOutputs.contains(url) {
                            self.completedOutputs.append(url)
                        }
                    }
                }
                try Task.checkCancellation()
                completedOutputs = outputs.map(\.url)
                isExporting = false
                isCancellingExport = false
            } catch is CancellationError {
                isExporting = false
                isCancellingExport = false
            } catch {
                isExporting = false
                isCancellingExport = false
                issue = AppIssue(title: "Export stopped", message: error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        isCancellingExport = true
        exportTask?.cancel()
        Task { await exportRunner.cancelAll() }
    }

    func revealOutputs() {
        guard !completedOutputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(completedOutputs)
    }

    func openDownloads() {
        NSWorkspace.shared.open(.downloadsDirectory)
    }

    func shutdown() {
        stopSourceWork()
        exportTask?.cancel()
        player.shutdown()
        Task {
            await sourceRunner.cancelAll()
            await exportRunner.cancelAll()
        }
    }

    private func applyLoadedMedia(_ loaded: LoadedMedia) {
        media = loaded
        selectedVideo = loaded.catalog.defaultVideoChoice
        selectedAudio = loaded.catalog.defaultAudioChoice
        let end = min(10, loaded.maximumWholeSecond)
        let initial = ClipRange(startSeconds: 0, endSeconds: max(1, end))
        ranges = [initial]
        selectedRangeID = initial.id
    }

    private func preparePreview(for loaded: LoadedMedia) {
        guard let previewService else { return }
        isPreparingPreview = true
        previewErrorMessage = nil
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await previewService.prepare(media: loaded) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.media?.requestedURL == loaded.requestedURL else { return }
                        self.previewProgress = progress
                    }
                }
                try Task.checkCancellation()
                guard media?.requestedURL == loaded.requestedURL else { return }
                previewURL = url
                isPreparingPreview = false
                player.load(url: url, duration: loaded.metadata.duration ?? 0)
            } catch is CancellationError {
                isPreparingPreview = false
            } catch {
                isPreparingPreview = false
                previewErrorMessage = error.localizedDescription
            }
        }
    }

    private func stopSourceWork() {
        sourceTask?.cancel()
        previewTask?.cancel()
        sourceTask = nil
        previewTask = nil
    }

    private static func resolveTools(environment: [String: String]) throws -> ToolPaths {
        #if DEBUG
        if environment["CLIPPED_UI_TEST_MODE"] != nil {
            let noOp = URL(fileURLWithPath: "/usr/bin/true")
            return ToolPaths(ytDLP: noOp, deno: noOp, ffmpeg: noOp, ffprobe: noOp)
        }
        #endif
        return try Toolchain.locate(environment: environment)
    }

    #if DEBUG
    private func installUITestMedia() {
        let json = #"""
        {
          "id":"ui-test",
          "title":"City Lights — Camera Test",
          "duration":122,
          "webpage_url":"https://example.com/video",
          "extractor":"test",
          "extractor_key":"Test",
          "formats":[
            {"format_id":"299","ext":"mp4","vcodec":"avc1.64002a","acodec":"none","width":1920,"height":1080,"fps":60,"filesize_approx":90000000,"vbr":4500,"dynamic_range":"SDR"},
            {"format_id":"22","ext":"mp4","vcodec":"avc1.64001f","acodec":"mp4a.40.2","width":1280,"height":720,"fps":30,"filesize_approx":42000000,"vbr":2200,"abr":128,"audio_channels":2,"dynamic_range":"SDR"},
            {"format_id":"140","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":128,"audio_channels":2,"language":"en","filesize_approx":2200000},
            {"format_id":"258","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":384,"audio_channels":6,"language":"en","filesize_approx":6200000}
          ]
        }
        """#
        guard let metadata = try? JSONDecoder().decode(YTDLPMetadata.self, from: Data(json.utf8)),
              let url = URL(string: "https://example.com/video") else { return }
        sourceText = url.absoluteString
        applyLoadedMedia(LoadedMedia(requestedURL: url, metadata: metadata, catalog: .build(from: metadata.formats)))
        previewErrorMessage = "Preview is disabled during interface tests."
    }
    #endif
}
