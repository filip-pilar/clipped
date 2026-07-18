import AppKit
import SwiftUI

struct MainView: View {
    @StateObject private var model = AppModel()
    @FocusState private var sourceFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            sourceBar

            if let media = model.media {
                EditorView(model: model, media: media)
            } else if model.isLoadingMetadata {
                loadingState
            } else {
                emptyState
            }
        }
        .padding(22)
        .frame(minWidth: 820, minHeight: 680)
        .alert(item: $model.issue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onDisappear { model.shutdown() }
    }

    private var sourceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("Video or audio URL", text: $model.sourceText)
                .textFieldStyle(.plain)
                .focused($sourceFieldFocused)
                .onSubmit(model.loadSource)
                .accessibilityIdentifier("source-url")

            if !model.sourceText.isEmpty {
                Button {
                    model.sourceText = ""
                    sourceFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear URL")
            }

            Button(action: model.loadSource) {
                if model.isLoadingMetadata {
                    ProgressView().controlSize(.small).frame(width: 42)
                } else {
                    Text("Load").frame(minWidth: 42)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canLoad)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("load-source")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "scissors")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Paste a URL to start").font(.title3.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("empty-state")
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Reading source").font(.headline)
            Text("Fetching details and available formats")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("loading-source")
        .accessibilityLabel("Reading source. Fetching details and available formats.")
    }
}

private struct EditorView: View {
    @ObservedObject var model: AppModel
    let media: LoadedMedia

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                sourceSummary
                PreviewPane(model: model, media: media)
                    .frame(maxWidth: .infinity)
                transportToolbar
                timelineCard
                rangesCard
                exportCard
            }
        }
        .scrollIndicators(.automatic)
        .onAppear { model.attachUndoManager(undoManager) }
    }

    private var sourceSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(media.metadata.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("source-title")
                Text(Timecode.display(media.maximumWholeSecond))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CompactFormatControls(model: model, media: media)
        }
    }

    private var transportToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    endTextEditing()
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isPreviewReady || model.trimSession != nil)
                .help("Play or pause (Space)")
                .accessibilityLabel(model.player.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("transport-play-pause")

                Text(Timecode.display(model.roundedPlayhead))
                    .font(.callout.monospacedDigit().bold())
                    .frame(width: 70, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { model.playheadSeconds },
                        set: {
                            endTextEditing()
                            model.seek(to: $0)
                        }
                    ),
                    in: 0...Double(max(1, media.maximumWholeSecond)),
                    step: 1
                )
                .accessibilityLabel("Source playhead")
                .accessibilityValue(Timecode.display(model.roundedPlayhead))
                .accessibilityHint("Adjusts in one second steps")
                .accessibilityIdentifier("transport-playhead")

                Text(Timecode.display(media.maximumWholeSecond))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Divider().frame(height: 24)

                Button("Mark In") {
                    endTextEditing()
                    model.markIn()
                }
                    .help("Mark draft start (I)")
                    .accessibilityIdentifier("mark-in")
                Button("Mark Out") {
                    endTextEditing()
                    model.markOut()
                }
                    .help("Mark draft end (O)")
                    .accessibilityIdentifier("mark-out")
                Button {
                    endTextEditing()
                    model.commitDraft()
                } label: {
                    Label("Add Clip", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canCommitDraft)
                .accessibilityHint("Commits the marked draft range")
                .accessibilityIdentifier("add-clip")
            }

            if let message = model.editorStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("editor-status")
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transport-toolbar")
    }

    private var timelineCard: some View {
        ClipTimeline(
            sourceID: media.requestedURL.absoluteString,
            ranges: model.ranges,
            draftRange: model.draftRange,
            chapters: model.chapters,
            duration: media.maximumWholeSecond,
            playhead: model.playheadSeconds,
            selectedRangeID: model.selectedRangeID,
            trimSession: model.trimSession,
            zoomRequest: model.timelineZoomRequest,
            onSelect: {
                endTextEditing()
                model.selectRange(id: $0)
            },
            onSeek: {
                endTextEditing()
                model.seek(to: $0)
            },
            onBeginTrim: {
                endTextEditing()
                model.beginTrim(id: $0, edge: $1)
            },
            onUpdateTrim: model.updateTrim,
            onEndTrim: model.endTrim
        )
        .cardStyle()
    }

    private func endTextEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var rangesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clips").font(.headline).accessibilityIdentifier("clips-heading")
                Spacer()
                Text("\(model.ranges.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            ForEach(Array(model.ranges.enumerated()), id: \.element.id) { index, range in
                if index > 0 { Divider().padding(.vertical, 4) }
                ClipRangeRow(
                    model: model,
                    range: range,
                    index: index,
                    colorIndex: index % ClipPalette.count
                )
            }

            if model.ranges.isEmpty {
                Text("Find a moment, mark In and Out, then add the clip.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("empty-clips")
            }
        }
        .cardStyle()
    }

    private var exportCard: some View {
        VStack(spacing: 10) {
            if model.isExporting {
                HStack(spacing: 12) {
                    ProgressView(value: model.exportProgress?.overallFraction)
                    Text(model.exportStatusText ?? "Starting")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 170, alignment: .leading)
                    Button(model.isCancellingExport ? "Cancelling…" : "Cancel", action: model.cancelExport)
                        .disabled(model.isCancellingExport)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloads").font(.callout.weight(.medium))
                        Text("\(Timecode.display(model.totalSelectedSeconds)) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.completedOutputs.isEmpty {
                        Text("Saved \(model.completedOutputs.count)").foregroundStyle(.green)
                        Button("Show in Finder", action: model.revealOutputs)
                            .accessibilityIdentifier("reveal-outputs")
                    }
                    Button(model.exportButtonTitle, action: model.export)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canExport)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .accessibilityIdentifier("download-clips")
                }
            }
        }
        .cardStyle()
    }

}

private struct PreviewPane: View {
    @ObservedObject var model: AppModel
    let media: LoadedMedia

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black)

            switch model.previewState {
            case .ready:
                NativePlayerView(player: model.player.player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("preview-ready")
                if media.metadata.isAudioOnly {
                    Image(systemName: "waveform")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                        .allowsHitTesting(false)
                }

            case .downloading(let fractionCompleted):
                PreviewProgressState(
                    title: "Downloading preview",
                    detail: "You can mark and arrange clips while the preview is prepared.",
                    fractionCompleted: fractionCompleted,
                    identifier: "preview-downloading"
                )

            case .preparing:
                PreviewProgressState(
                    title: "Preparing preview",
                    detail: "Timeline and timestamp controls are ready to use.",
                    fractionCompleted: nil,
                    identifier: "preview-preparing"
                )

            case .failed(let failure):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 34, weight: .light))
                    Text(failure.title).font(.callout.weight(.semibold))
                    Text(failure.message).font(.caption).multilineTextAlignment(.center).lineLimit(3)
                    Text("You can still set timestamps and download clips.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("preview-failure")

            case .idle:
                VStack(spacing: 10) {
                    Image(systemName: media.metadata.isAudioOnly ? "waveform" : "play.rectangle")
                        .font(.system(size: 34, weight: .light))
                    Text("Waiting for preview").font(.callout)
                }
                .foregroundStyle(.white.opacity(0.65))
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview-pane")
    }
}

private struct PreviewProgressState: View {
    let title: String
    let detail: String
    let fractionCompleted: Double?
    let identifier: String

    var body: some View {
        VStack(spacing: 10) {
            if let fractionCompleted {
                ProgressView(value: fractionCompleted).frame(width: 180)
                Text(fractionCompleted, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
            } else {
                ProgressView().controlSize(.large)
            }
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.75))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct CompactFormatControls: View {
    @ObservedObject var model: AppModel
    let media: LoadedMedia

    @State private var videoPopover = false
    @State private var audioPopover = false
    @State private var outputPopover = false

    var body: some View {
        HStack(spacing: 8) {
            formatButton(
                title: "Video",
                value: model.selectedVideo?.primaryLabel ?? "None",
                identifier: "format-video",
                isPresented: $videoPopover
            ) { videoChoices }
            formatButton(
                title: "Audio",
                value: audioSummary,
                identifier: "format-audio",
                isPresented: $audioPopover
            ) { audioChoices }
            formatButton(
                title: "Output",
                value: media.catalog.isAudioOnly ? "M4A" : "MP4",
                identifier: "format-output",
                isPresented: $outputPopover
            ) { outputDetails }
        }
    }

    private var audioSummary: String {
        if model.selectedVideo?.hasEmbeddedAudio == true { return "Included" }
        return model.selectedAudio?.primaryLabel ?? "None"
    }

    private func formatButton<Content: View>(
        title: String,
        value: String,
        identifier: String,
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Button { isPresented.wrappedValue.toggle() } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(value).font(.callout.weight(.medium)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .frame(minWidth: 92, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: isPresented, arrowEdge: .bottom) { content() }
        .accessibilityLabel("\(title) format")
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private var videoChoices: some View {
        FormatChoicePopover(title: "Video", choices: media.catalog.videoChoices, selectedID: model.selectedVideoID) { choice in
            model.selectedVideoID = choice.id
            videoPopover = false
        }
    }

    @ViewBuilder
    private var audioChoices: some View {
        if model.selectedVideo?.hasEmbeddedAudio == true {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio").font(.headline)
                Label("Included with the selected video", systemImage: "speaker.wave.2")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
        } else {
            FormatChoicePopover(title: "Audio", choices: media.catalog.audioChoices, selectedID: model.selectedAudioID) { choice in
                model.selectedAudioID = choice.id
                audioPopover = false
            }
        }
    }

    private var outputDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output").font(.headline)
            Label(media.catalog.isAudioOnly ? "AAC audio · M4A" : "H.264 video · AAC audio · MP4", systemImage: "film")
            if let video = model.selectedVideo {
                Text("Resolution follows \(video.primaryLabel).")
            }
            Text("Each clip is normalized into its own editing-ready file in Downloads.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}

private struct FormatChoicePopover<Choice: Identifiable>: View where Choice.ID == String {
    let title: String
    let choices: [Choice]
    let selectedID: String
    let primary: (Choice) -> String
    let detail: (Choice) -> String
    let onSelect: (Choice) -> Void

    init(
        title: String,
        choices: [Choice],
        selectedID: String,
        primary: @escaping (Choice) -> String,
        detail: @escaping (Choice) -> String,
        onSelect: @escaping (Choice) -> Void
    ) {
        self.title = title
        self.choices = choices
        self.selectedID = selectedID
        self.primary = primary
        self.detail = detail
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(choices) { choice in
                        Button { onSelect(choice) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: choice.id == selectedID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(choice.id == selectedID ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(primary(choice)).font(.callout.weight(.medium))
                                    Text(detail(choice)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(7)
                        .background(choice.id == selectedID ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .frame(maxHeight: 330)
        }
        .padding(14)
        .frame(width: 440)
    }
}

private extension FormatChoicePopover where Choice == VideoQualityChoice {
    init(title: String, choices: [Choice], selectedID: String, onSelect: @escaping (Choice) -> Void) {
        self.init(
            title: title,
            choices: choices,
            selectedID: selectedID,
            primary: { $0.primaryLabel },
            detail: { $0.detailLabel },
            onSelect: onSelect
        )
    }
}

private extension FormatChoicePopover where Choice == AudioQualityChoice {
    init(title: String, choices: [Choice], selectedID: String, onSelect: @escaping (Choice) -> Void) {
        self.init(
            title: title,
            choices: choices,
            selectedID: selectedID,
            primary: { $0.primaryLabel },
            detail: { $0.detailLabel },
            onSelect: onSelect
        )
    }
}

private struct ClipRangeRow: View {
    @ObservedObject var model: AppModel
    let range: ClipRange
    let index: Int
    let colorIndex: Int

    @State private var isHovered = false
    @FocusState private var rowFocused: Bool

    private var color: Color { ClipPalette.color(colorIndex) }
    private var isSelected: Bool { model.selectedRangeID == range.id }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .frame(width: 25, height: 25)
                .background(color.opacity(isSelected ? 1 : 0.75), in: Circle())
                .foregroundStyle(.white)
                .overlay { Circle().stroke(Color.primary.opacity(isSelected ? 0.8 : 0), lineWidth: 2) }
                .accessibilityLabel("Clip \(index + 1), \(ClipPalette.name(colorIndex))")

            TimecodeField(
                value: range.startSeconds,
                fieldKey: "\(range.id.uuidString)-start",
                accessibilityIdentifier: "clip-\(index)-start",
                onCommit: { model.commitStart($0, for: range.id) },
                onValidityChange: { model.setTimecodeFieldValidity(key: "\(range.id.uuidString)-start", isValid: $0) }
            )

            Text("to").foregroundStyle(.secondary)

            TimecodeField(
                value: range.endSeconds,
                fieldKey: "\(range.id.uuidString)-end",
                accessibilityIdentifier: "clip-\(index)-end",
                onCommit: { model.commitEnd($0, for: range.id) },
                onValidityChange: { model.setTimecodeFieldValidity(key: "\(range.id.uuidString)-end", isValid: $0) }
            )

            Text(Timecode.display(max(0, range.durationSeconds)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(model.rangeError(range) == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                .frame(width: 76, alignment: .trailing)

            Spacer()

            if isSelected || isHovered {
                Menu {
                    Button("Set start from playhead") { model.setStartToPlayhead(for: range.id) }
                        .disabled(model.roundedPlayhead >= range.endSeconds)
                    Button("Set end from playhead") { model.setEndToPlayhead(for: range.id) }
                        .disabled(model.roundedPlayhead <= range.startSeconds)
                    Divider()
                    Button("Duplicate") { model.duplicateRange(id: range.id) }
                    Button("Delete", role: .destructive) { model.removeRange(id: range.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .accessibilityLabel("Clip \(index + 1) actions")
                .accessibilityIdentifier("clip-\(index)-menu")
                .onHover { hovering in
                    if hovering && !isSelected { model.selectRange(id: range.id) }
                }
            } else {
                Color.clear.frame(width: 28, height: 22)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(color.opacity(isSelected ? 0.13 : isHovered ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? color.opacity(0.7) : .clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectRange(id: range.id) }
        .onHover { isHovered = $0 }
        .focusable()
        .focused($rowFocused)
        .onChange(of: rowFocused) { _, focused in
            if focused { model.selectRange(id: range.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip-row-\(index)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
    }
}
