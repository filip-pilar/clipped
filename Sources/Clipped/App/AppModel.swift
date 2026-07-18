import AppKit
import Foundation

struct AppIssue: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(_ presentation: MediaFailurePresentation) {
        title = presentation.title
        message = presentation.alertMessage
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceText = ""
    @Published private(set) var media: LoadedMedia?
    @Published private(set) var selectedVideo: VideoQualityChoice?
    @Published private(set) var selectedAudio: AudioQualityChoice?
    @Published private(set) var ranges: [ClipRange] = []
    @Published var selectedRangeID: UUID?
    @Published private(set) var playheadSeconds: Double = 0
    @Published private(set) var draftRange: DraftRange?
    @Published private(set) var trimSession: TrimSession?
    @Published private(set) var editorStatusMessage: String?
    @Published private(set) var timelineZoomRequest: TimelineZoomRequest?

    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var previewState: PreviewState = .idle

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
    private weak var undoManager: UndoManager?
    private var keyboardMonitor: LocalKeyEventMonitor?

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
        if let mode = environment["CLIPPED_UI_TEST_MODE"], mode != "initial" {
            installUITestMedia(mode: mode)
        }
        #endif

        player.timeUpdateHandler = { [weak self] seconds in
            guard let self, self.trimSession == nil else { return }
            self.playheadSeconds = self.clampedPlayhead(seconds)
        }

        keyboardMonitor = LocalKeyEventMonitor { [weak self] event in
            self?.handleEditorKeyEvent(event) ?? false
        }
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

    var chapters: [YTDLPChapter] {
        guard let media else { return [] }
        return media.metadata.normalizedChapters(maximumSeconds: media.maximumWholeSecond)
    }

    var canCommitDraft: Bool { draftRange?.committedRange != nil }
    var isPreviewReady: Bool {
        if case .ready = previewState { return true }
        return false
    }

    var selectedRange: ClipRange? {
        ranges.first(where: { $0.id == selectedRangeID })
    }

    var canSetSelectedStartFromPlayhead: Bool {
        guard let selectedRange else { return false }
        return roundedPlayhead < selectedRange.endSeconds
    }

    var canSetSelectedEndFromPlayhead: Bool {
        guard let selectedRange else { return false }
        return roundedPlayhead > selectedRange.startSeconds
    }

    var roundedPlayhead: Int {
        clampedSecond(Int(playheadSeconds.rounded()))
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
        if count == 0 { return "Download Clips" }
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
        selectedRangeID = nil
        draftRange = nil
        trimSession = nil
        playheadSeconds = 0
        editorStatusMessage = nil
        undoManager?.removeAllActions(withTarget: self)
        invalidTimecodeFields.removeAll()
        completedOutputs = []
        exportProgress = nil
        previewState = .idle
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
                issue = AppIssue(MediaFailurePresentation.classify(error, context: .source))
            }
        }
    }

    func attachUndoManager(_ manager: UndoManager?) {
        undoManager = manager
    }

    func removeRange(id: UUID) {
        guard let index = ranges.firstIndex(where: { $0.id == id }) else { return }
        performEditorMutation(actionName: "Delete Clip") {
            ranges.remove(at: index)
            invalidTimecodeFields = invalidTimecodeFields.filter { !$0.hasPrefix(id.uuidString) }
            if selectedRangeID == id {
                selectedRangeID = ranges.indices.contains(index) ? ranges[index].id : ranges.last?.id
            }
        }
    }

    func removeSelectedRange() {
        guard let selectedRangeID else { return }
        removeRange(id: selectedRangeID)
    }

    func selectRange(id: UUID) {
        guard ranges.contains(where: { $0.id == id }) else { return }
        selectedRangeID = id
    }

    @discardableResult
    func commitStart(_ seconds: Int, for id: UUID) -> Bool {
        guard let index = ranges.firstIndex(where: { $0.id == id }),
              seconds >= 0, seconds < ranges[index].endSeconds else { return false }
        let value = clampedSecond(seconds)
        guard value < ranges[index].endSeconds else { return false }
        performEditorMutation(actionName: "Change Clip Start") {
            ranges[index].startSeconds = value
        }
        return true
    }

    @discardableResult
    func commitEnd(_ seconds: Int, for id: UUID) -> Bool {
        guard let index = ranges.firstIndex(where: { $0.id == id }),
              seconds > ranges[index].startSeconds,
              let media, seconds <= media.maximumWholeSecond else { return false }
        performEditorMutation(actionName: "Change Clip End") {
            ranges[index].endSeconds = seconds
        }
        return true
    }

    func setStartToPlayhead(for id: UUID) {
        _ = commitStart(roundedPlayhead, for: id)
    }

    func setEndToPlayhead(for id: UUID) {
        _ = commitEnd(roundedPlayhead, for: id)
    }

    func duplicateRange(id: UUID) {
        guard let index = ranges.firstIndex(where: { $0.id == id }) else { return }
        let copy = ClipRange(
            startSeconds: ranges[index].startSeconds,
            endSeconds: ranges[index].endSeconds
        )
        performEditorMutation(actionName: "Duplicate Clip") {
            ranges.insert(copy, at: index + 1)
            selectedRangeID = copy.id
        }
    }

    func markIn() {
        guard media != nil else { return }
        performEditorMutation(actionName: "Mark In") {
            let out = draftRange?.outSeconds
            draftRange = DraftRange(
                inSeconds: roundedPlayhead,
                outSeconds: out.flatMap { $0 > roundedPlayhead ? $0 : nil }
            )
            editorStatusMessage = "In marked at \(Timecode.display(roundedPlayhead))"
        }
    }

    func markOut() {
        guard var draftRange else {
            editorStatusMessage = "Mark In before marking Out."
            return
        }
        guard roundedPlayhead > draftRange.inSeconds else {
            editorStatusMessage = "Out must be after In."
            return
        }
        performEditorMutation(actionName: "Mark Out") {
            draftRange.outSeconds = roundedPlayhead
            self.draftRange = draftRange
            editorStatusMessage = "Out marked at \(Timecode.display(roundedPlayhead))"
        }
    }

    func commitDraft() {
        guard let range = draftRange?.committedRange else { return }
        performEditorMutation(actionName: "Add Clip") {
            ranges.append(range)
            selectedRangeID = range.id
            draftRange = nil
            editorStatusMessage = "Clip added."
        }
    }

    func cancelDraftOrTrim() {
        if trimSession != nil {
            cancelTrim()
        } else if draftRange != nil {
            draftRange = nil
            editorStatusMessage = "Draft cancelled."
        }
    }

    func beginTrim(id: UUID, edge: ClipEdge) {
        guard trimSession == nil,
              let range = ranges.first(where: { $0.id == id }) else { return }
        selectedRangeID = id
        let wasPlaying = player.pause()
        let boundary = edge == .start ? range.startSeconds : range.endSeconds
        trimSession = TrimSession(
            clipID: id,
            edge: edge,
            originalRange: range,
            savedPlayhead: playheadSeconds,
            wasPlaying: wasPlaying,
            boundarySeconds: boundary
        )
    }

    func updateTrim(to seconds: Int) {
        guard var session = trimSession,
              let index = ranges.firstIndex(where: { $0.id == session.clipID }),
              let media else { return }
        let boundary: Int
        switch session.edge {
        case .start:
            boundary = min(max(0, seconds), ranges[index].endSeconds - 1)
            ranges[index].startSeconds = boundary
        case .end:
            boundary = max(ranges[index].startSeconds + 1, min(media.maximumWholeSecond, seconds))
            ranges[index].endSeconds = boundary
        }
        session.boundarySeconds = boundary
        trimSession = session
        player.showBoundaryFrame(at: Double(boundary))
    }

    func endTrim() {
        guard let session = trimSession else { return }
        trimSession = nil
        player.restorePreview(to: session.savedPlayhead, resumePlayback: session.wasPlaying)
        guard let current = ranges.first(where: { $0.id == session.clipID }),
              current != session.originalRange else { return }

        var before = editorSnapshot
        if let index = before.ranges.firstIndex(where: { $0.id == session.clipID }) {
            before.ranges[index] = session.originalRange
        }
        registerUndo(to: before, actionName: "Trim Clip")
    }

    func cancelTrim() {
        guard let session = trimSession else { return }
        if let index = ranges.firstIndex(where: { $0.id == session.clipID }) {
            ranges[index] = session.originalRange
        }
        trimSession = nil
        player.restorePreview(to: session.savedPlayhead, resumePlayback: session.wasPlaying)
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
        seek(to: Double(seconds))
    }

    func seek(to seconds: Double) {
        let value = clampedPlayhead(seconds)
        playheadSeconds = value
        if isPreviewReady { player.seek(to: value) }
    }

    func movePlayhead(by seconds: Int) {
        seek(to: playheadSeconds + Double(seconds))
    }

    func togglePlayback() {
        guard isPreviewReady, trimSession == nil else { return }
        player.togglePlayback()
    }

    private func handleEditorKeyEvent(_ event: NSEvent) -> Bool {
        if let eventWindow = event.window, eventWindow !== NSApp.keyWindow { return false }
        guard media != nil, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandLike = modifiers.intersection([.command, .control, .option])

        if modifiers.contains(.command),
           modifiers.intersection([.control, .option]).isEmpty {
            switch event.charactersIgnoringModifiers {
            case "=", "+": timelineZoomRequest = TimelineZoomRequest(action: .zoomIn); return true
            case "-": timelineZoomRequest = TimelineZoomRequest(action: .zoomOut); return true
            default: return false
            }
        }

        guard commandLike.isEmpty else { return false }
        switch event.keyCode {
        case 49: togglePlayback(); return true
        case 123: movePlayhead(by: modifiers.contains(.shift) ? -5 : -1); return true
        case 124: movePlayhead(by: modifiers.contains(.shift) ? 5 : 1); return true
        case 34: markIn(); return true
        case 31: markOut(); return true
        case 36, 76:
            guard canCommitDraft else { return false }
            commitDraft(); return true
        case 51, 117:
            guard selectedRangeID != nil else { return false }
            removeSelectedRange(); return true
        case 53:
            guard trimSession != nil || draftRange != nil else { return false }
            cancelDraftOrTrim(); return true
        default: return false
        }
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
                issue = AppIssue(MediaFailurePresentation.classify(error, context: .export))
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
        ranges = []
        selectedRangeID = nil
        draftRange = nil
        trimSession = nil
        playheadSeconds = Double(
            YouTubeTimestamp.initialSeconds(
                metadataStartTime: loaded.metadata.startTime,
                url: loaded.requestedURL,
                maximumSeconds: loaded.maximumWholeSecond
            )
        )
        player.configure(duration: loaded.metadata.duration ?? 0)
        editorStatusMessage = nil
        undoManager?.removeAllActions(withTarget: self)
    }

    private func preparePreview(for loaded: LoadedMedia) {
        guard let previewService else { return }
        previewState = .downloading(fractionCompleted: nil)
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await previewService.prepare(media: loaded) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.media?.requestedURL == loaded.requestedURL else { return }
                        self.previewState = .progress(progress)
                    }
                }
                try Task.checkCancellation()
                guard media?.requestedURL == loaded.requestedURL else { return }
                previewState = .ready(url)
                player.load(
                    url: url,
                    duration: loaded.metadata.duration ?? 0,
                    initialTime: playheadSeconds
                )
            } catch is CancellationError {
                // Loading another source owns the next preview state.
            } catch {
                guard media?.requestedURL == loaded.requestedURL else { return }
                previewState = .failed(MediaFailurePresentation.classify(error, context: .preview))
            }
        }
    }

    private func stopSourceWork() {
        sourceTask?.cancel()
        previewTask?.cancel()
        sourceTask = nil
        previewTask = nil
    }

    private var editorSnapshot: EditorSnapshot {
        EditorSnapshot(ranges: ranges, selectedRangeID: selectedRangeID, draftRange: draftRange)
    }

    private func performEditorMutation(actionName: String, _ mutation: () -> Void) {
        let before = editorSnapshot
        mutation()
        guard before != editorSnapshot else { return }
        registerUndo(to: before, actionName: actionName)
    }

    private func registerUndo(to snapshot: EditorSnapshot, actionName: String) {
        guard let undoManager else { return }
        let ownsGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if ownsGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { target in
            let inverse = target.editorSnapshot
            target.apply(snapshot: snapshot)
            target.registerUndo(to: inverse, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        if ownsGroup { undoManager.endUndoGrouping() }
    }

    private func apply(snapshot: EditorSnapshot) {
        ranges = snapshot.ranges
        selectedRangeID = snapshot.selectedRangeID
        draftRange = snapshot.draftRange
        invalidTimecodeFields = invalidTimecodeFields.filter { key in
            ranges.contains { key.hasPrefix($0.id.uuidString) }
        }
    }

    private func clampedPlayhead(_ seconds: Double) -> Double {
        min(Double(media?.maximumWholeSecond ?? Int.max), max(0, seconds))
    }

    private func clampedSecond(_ seconds: Int) -> Int {
        min(media?.maximumWholeSecond ?? seconds, max(0, seconds))
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
    private func installUITestMedia(mode: String) {
        let json = #"""
        {
          "id":"ui-test",
          "title":"City Lights — Camera Test",
          "duration":122,
          "webpage_url":"https://www.youtube.com/watch?v=ui-test&t=31s",
          "extractor":"test",
          "extractor_key":"Test",
          "chapters":[
            {"title":"Opening","start_time":0,"end_time":30},
            {"title":"Main section","start_time":30,"end_time":90},
            {"title":"Closing","start_time":90,"end_time":122}
          ],
          "formats":[
            {"format_id":"299","ext":"mp4","vcodec":"avc1.64002a","acodec":"none","width":1920,"height":1080,"fps":60,"filesize_approx":90000000,"vbr":4500,"dynamic_range":"SDR"},
            {"format_id":"22","ext":"mp4","vcodec":"avc1.64001f","acodec":"mp4a.40.2","width":1280,"height":720,"fps":30,"filesize_approx":42000000,"vbr":2200,"abr":128,"audio_channels":2,"dynamic_range":"SDR"},
            {"format_id":"140","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":128,"audio_channels":2,"language":"en","filesize_approx":2200000},
            {"format_id":"258","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":384,"audio_channels":6,"language":"en","filesize_approx":6200000}
          ]
        }
        """#
        guard let metadata = try? JSONDecoder().decode(YTDLPMetadata.self, from: Data(json.utf8)),
              let url = URL(string: "https://www.youtube.com/watch?v=ui-test&t=31s") else { return }
        sourceText = url.absoluteString
        applyLoadedMedia(LoadedMedia(requestedURL: url, metadata: metadata, catalog: .build(from: metadata.formats)))
        if mode == "overlap" {
            ranges = [
                ClipRange(startSeconds: 5, endSeconds: 45),
                ClipRange(startSeconds: 20, endSeconds: 65),
                ClipRange(startSeconds: 35, endSeconds: 80),
                ClipRange(startSeconds: 85, endSeconds: 105)
            ]
            selectedRangeID = ranges[1].id
        }
        if mode == "loading" {
            previewState = .downloading(fractionCompleted: 0.42)
        } else {
            previewState = .failed(
                MediaFailurePresentation(
                    kind: .unsupported,
                    title: "Preview unavailable",
                    message: "Preview is disabled during interface tests.",
                    diagnostic: nil
                )
            )
        }
    }
    #endif
}
