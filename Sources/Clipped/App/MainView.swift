import SwiftUI

struct MainView: View {
    @StateObject private var model = AppModel()
    @FocusState private var sourceFieldFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
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
            Image(systemName: "link")
                .foregroundStyle(.secondary)
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
            Text("Paste a URL to start")
                .font(.title3.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("empty-state")
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Reading source")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("loading-source")
    }
}

private struct EditorView: View {
    @ObservedObject var model: AppModel
    let media: LoadedMedia

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                HStack(alignment: .top, spacing: 16) {
                    PreviewPane(model: model, media: media)
                        .frame(maxWidth: .infinity)
                    FormatPane(model: model, media: media)
                        .frame(width: 300)
                }

                timelineCard
                rangesCard
                exportCard
            }
        }
        .scrollIndicators(.automatic)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(media.metadata.title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .accessibilityIdentifier("source-title")
            Spacer()
            Text(Timecode.display(media.maximumWholeSecond))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timeline").font(.headline)
                Spacer()
                Text("Drag the clip edges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ClipTimeline(
                ranges: model.ranges,
                duration: media.maximumWholeSecond,
                playhead: model.player.currentTime,
                selectedRangeID: $model.selectedRangeID,
                onSeek: model.seek,
                onChange: model.updateRange
            )
        }
        .cardStyle()
    }

    private var rangesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clips")
                    .font(.headline)
                    .accessibilityIdentifier("clips-heading")
                Spacer()
                Button(action: model.addRange) {
                    Label("Add Clip", systemImage: "plus")
                }
                .accessibilityIdentifier("add-clip")
            }
            .padding(.bottom, 6)

            ForEach(Array(model.ranges.enumerated()), id: \.element.id) { index, range in
                Divider().padding(.vertical, 6)
                ClipRangeRow(model: model, range: range, index: index)
            }

            if model.ranges.isEmpty {
                Text("Add a clip range to download.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
                        Text("Downloads")
                            .font(.callout.weight(.medium))
                        Text("\(Timecode.display(model.totalSelectedSeconds)) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.completedOutputs.isEmpty {
                        Text("Saved \(model.completedOutputs.count)")
                            .foregroundStyle(.green)
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)

            if model.previewURL != nil {
                NativePlayerView(player: model.player.player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if media.metadata.isAudioOnly {
                    Image(systemName: "waveform")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                        .allowsHitTesting(false)
                }
            } else if model.isPreparingPreview {
                VStack(spacing: 12) {
                    ProgressView(value: model.previewProgress?.fractionCompleted)
                        .frame(width: 180)
                    Text(previewStatus)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: media.metadata.isAudioOnly ? "waveform" : "play.rectangle")
                        .font(.system(size: 34, weight: .light))
                    Text(model.previewErrorMessage ?? "Preview unavailable")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(.white.opacity(0.65))
                .padding()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityIdentifier("preview-pane")
    }

    private var previewStatus: String {
        switch model.previewProgress?.stage {
        case .normalizing: "Preparing preview"
        case .ready: "Ready"
        default: "Loading preview"
        }
    }
}

private struct FormatPane: View {
    @ObservedObject var model: AppModel
    let media: LoadedMedia

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Format").font(.headline)

            if !media.catalog.videoChoices.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Video").font(.caption).foregroundStyle(.secondary)
                    Picker("Video", selection: $model.selectedVideoID) {
                        ForEach(media.catalog.videoChoices) { choice in
                            Text("\(choice.primaryLabel) — \(choice.detailLabel)")
                                .tag(choice.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("video-quality")
                }
            }

            if model.selectedVideo?.hasEmbeddedAudio == true {
                Label("Audio included with video", systemImage: "speaker.wave.2")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !media.catalog.audioChoices.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Audio").font(.caption).foregroundStyle(.secondary)
                    Picker("Audio", selection: $model.selectedAudioID) {
                        ForEach(media.catalog.audioChoices) { choice in
                            Text("\(choice.primaryLabel) — \(choice.detailLabel)")
                                .tag(choice.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("audio-quality")
                }
            } else {
                Label("No audio track", systemImage: "speaker.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Label(media.catalog.isAudioOnly ? "AAC · M4A" : "H.264 · AAC · MP4", systemImage: "film")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Editing-ready output")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }
}

private struct ClipRangeRow: View {
    @ObservedObject var model: AppModel
    let range: ClipRange
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.selectedRangeID = range.id
                model.seek(to: range.startSeconds)
            } label: {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(model.selectedRangeID == range.id ? Color.accentColor : Color.secondary.opacity(0.16), in: Circle())
                    .foregroundStyle(model.selectedRangeID == range.id ? .white : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select clip \(index + 1)")

            TimecodeField(
                value: range.startSeconds,
                fieldKey: "\(range.id.uuidString)-start",
                accessibilityIdentifier: "clip-\(index)-start",
                onCommit: { model.updateStart($0, for: range.id) },
                onValidityChange: { model.setTimecodeFieldValidity(key: "\(range.id.uuidString)-start", isValid: $0) }
            )
            Button { model.setStartToPlayhead(for: range.id) } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .buttonStyle(.borderless)
            .help("Set start to playhead")

            Text("to").foregroundStyle(.secondary)

            TimecodeField(
                value: range.endSeconds,
                fieldKey: "\(range.id.uuidString)-end",
                accessibilityIdentifier: "clip-\(index)-end",
                onCommit: { model.updateEnd($0, for: range.id) },
                onValidityChange: { model.setTimecodeFieldValidity(key: "\(range.id.uuidString)-end", isValid: $0) }
            )
            Button { model.setEndToPlayhead(for: range.id) } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .buttonStyle(.borderless)
            .help("Set end to playhead")

            Text(Timecode.display(max(0, range.durationSeconds)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(model.rangeError(range) == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                .frame(width: 76, alignment: .trailing)

            Spacer()

            Button(role: .destructive) { model.removeRange(id: range.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("remove-clip-\(index)")
            .accessibilityLabel("Remove clip \(index + 1)")
        }
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
