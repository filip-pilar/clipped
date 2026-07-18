import AppKit
import SwiftUI

struct TimelineTick: Equatable, Identifiable, Sendable {
    let seconds: Int
    let isMajor: Bool

    var id: Int { seconds }
}

enum TimelineScale {
    private static let preferredMajorSteps = [
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600, 900, 1_800,
        3_600, 7_200, 14_400, 21_600
    ]

    static func majorStep(duration: Int, width: CGFloat) -> Int {
        majorStep(pointsPerSecond: width / CGFloat(max(1, duration)))
    }

    static func majorStep(pointsPerSecond: CGFloat) -> Int {
        let minimumStep = 92 / max(0.0001, Double(pointsPerSecond))
        if let preferred = preferredMajorSteps.first(where: { Double($0) >= minimumStep }) {
            return preferred
        }
        return max(3_600, Int(ceil(minimumStep / 3_600)) * 3_600)
    }

    static func ticks(duration: Int, width: CGFloat) -> [TimelineTick] {
        ticks(duration: duration, pointsPerSecond: width / CGFloat(max(1, duration)))
    }

    static func ticks(
        duration: Int,
        pointsPerSecond: CGFloat,
        visibleSeconds: ClosedRange<Int>? = nil
    ) -> [TimelineTick] {
        let safeDuration = max(1, duration)
        let major = majorStep(pointsPerSecond: pointsPerSecond)
        let minor = minorStep(for: major)
        let visible = visibleSeconds ?? 0...safeDuration
        let first = max(0, (visible.lowerBound / minor - 1) * minor)
        let last = min(safeDuration, visible.upperBound + minor)
        var ticks: [TimelineTick] = []
        var second = first
        while second <= last {
            ticks.append(TimelineTick(seconds: second, isMajor: second.isMultiple(of: major)))
            second += minor
        }
        if visible.contains(safeDuration), ticks.last?.seconds != safeDuration {
            ticks.append(TimelineTick(seconds: safeDuration, isMajor: safeDuration.isMultiple(of: major)))
        }
        return ticks
    }

    private static func minorStep(for major: Int) -> Int {
        if major >= 10, major.isMultiple(of: 5) { return major / 5 }
        if major >= 4, major.isMultiple(of: 2) { return major / 2 }
        return 1
    }
}

struct TimelineViewport: Equatable, Sendable {
    let duration: Int
    let viewportWidth: CGFloat
    var pointsPerSecond: CGFloat
    var scrollOffset: CGFloat

    var fitScale: CGFloat { viewportWidth / CGFloat(max(1, duration)) }
    var maximumScale: CGFloat { max(fitScale * 8, 64) }
    var contentWidth: CGFloat { max(viewportWidth, CGFloat(max(1, duration)) * pointsPerSecond) }

    func clampedScale(_ proposed: CGFloat) -> CGFloat {
        min(maximumScale, max(fitScale, proposed))
    }

    func fitSelected(_ range: ClipRange) -> CGFloat {
        clampedScale(viewportWidth * 0.8 / CGFloat(max(1, range.durationSeconds)))
    }

    func offset(afterZoomingTo scale: CGFloat, anchorSeconds: Double) -> CGFloat {
        let oldAnchorX = CGFloat(anchorSeconds) * pointsPerSecond
        let visibleAnchor = oldAnchorX >= scrollOffset && oldAnchorX <= scrollOffset + viewportWidth
            ? oldAnchorX - scrollOffset
            : viewportWidth / 2
        let newWidth = max(viewportWidth, CGFloat(max(1, duration)) * scale)
        let proposed = CGFloat(anchorSeconds) * scale - visibleAnchor
        return min(max(0, proposed), max(0, newWidth - viewportWidth))
    }
}

enum TimelineZoomAction: Equatable, Sendable {
    case zoomIn
    case zoomOut
    case fitSource
    case fitSelected
}

struct TimelineZoomRequest: Equatable, Sendable {
    let id = UUID()
    let action: TimelineZoomAction
}

struct TimelineRangePlacement: Equatable, Identifiable, Sendable {
    let range: ClipRange
    let index: Int
    let lane: Int
    let colorIndex: Int

    var id: UUID { range.id }
}

struct ClipTimelineLayout: Equatable, Sendable {
    let placements: [TimelineRangePlacement]
    let laneCount: Int

    static func make(ranges: [ClipRange]) -> ClipTimelineLayout {
        let sorted = ranges.enumerated().sorted { lhs, rhs in
            if lhs.element.startSeconds != rhs.element.startSeconds {
                return lhs.element.startSeconds < rhs.element.startSeconds
            }
            if lhs.element.endSeconds != rhs.element.endSeconds {
                return lhs.element.endSeconds < rhs.element.endSeconds
            }
            return lhs.offset < rhs.offset
        }

        var laneEnds: [Int] = []
        var lanesByID: [UUID: Int] = [:]
        for item in sorted {
            let lane = laneEnds.firstIndex(where: { $0 <= item.element.startSeconds }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(item.element.endSeconds) }
            else { laneEnds[lane] = item.element.endSeconds }
            lanesByID[item.element.id] = lane
        }

        return ClipTimelineLayout(
            placements: ranges.enumerated().map { index, range in
                TimelineRangePlacement(
                    range: range,
                    index: index,
                    lane: lanesByID[range.id] ?? 0,
                    colorIndex: index % ClipPalette.count
                )
            },
            laneCount: max(1, laneEnds.count)
        )
    }
}

enum ClipPalette {
    static let count = 8

    static func color(_ index: Int) -> Color {
        switch ((index % count) + count) % count {
        case 0: Color(red: 0.12, green: 0.48, blue: 0.98)
        case 1: Color(red: 0.87, green: 0.27, blue: 0.38)
        case 2: Color(red: 0.10, green: 0.66, blue: 0.48)
        case 3: Color(red: 0.62, green: 0.34, blue: 0.91)
        case 4: Color(red: 0.95, green: 0.55, blue: 0.12)
        case 5: Color(red: 0.06, green: 0.65, blue: 0.76)
        case 6: Color(red: 0.86, green: 0.34, blue: 0.72)
        default: Color(red: 0.48, green: 0.62, blue: 0.12)
        }
    }

    static func name(_ index: Int) -> String {
        switch ((index % count) + count) % count {
        case 0: "Blue"
        case 1: "Red"
        case 2: "Green"
        case 3: "Purple"
        case 4: "Orange"
        case 5: "Teal"
        case 6: "Pink"
        default: "Olive"
        }
    }
}

struct ClipTimeline: View {
    let sourceID: String
    let ranges: [ClipRange]
    let draftRange: DraftRange?
    let chapters: [YTDLPChapter]
    let duration: Int
    let playhead: Double
    let selectedRangeID: UUID?
    let trimSession: TrimSession?
    let zoomRequest: TimelineZoomRequest?
    let onSelect: (UUID) -> Void
    let onSeek: (Int) -> Void
    let onBeginTrim: (UUID, ClipEdge) -> Void
    let onUpdateTrim: (Int) -> Void
    let onEndTrim: () -> Void

    @State private var pointsPerSecond: CGFloat = 1
    @State private var isFitSource = true
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollOffset: CGFloat = 0
    @State private var visibleWidth: CGFloat = 1
    @State private var magnificationStart: CGFloat?

    private let rulerHeight: CGFloat = 32
    private let laneHeight: CGFloat = 32
    private let laneSpacing: CGFloat = 5
    private let trackPadding: CGFloat = 7
    private let draftHeight: CGFloat = 18

    var body: some View {
        let layout = ClipTimelineLayout.make(ranges: ranges)
        let trackHeight = trackPadding * 2 + draftHeight + 5
            + CGFloat(layout.laneCount) * laneHeight
            + CGFloat(max(0, layout.laneCount - 1)) * laneSpacing

        VStack(spacing: 8) {
            timelineToolbar

            GeometryReader { geometry in
                let viewportWidth = max(1, geometry.size.width)
                let viewport = makeViewport(width: viewportWidth)
                let contentWidth = viewport.contentWidth
                let visibleSeconds = visibleSecondRange(contentWidth: contentWidth)
                let ticks = TimelineScale.ticks(
                    duration: duration,
                    pointsPerSecond: viewport.pointsPerSecond,
                    visibleSeconds: visibleSeconds
                )

                ScrollView(.horizontal) {
                    VStack(spacing: 5) {
                        ruler(ticks: ticks, width: contentWidth)
                            .frame(width: contentWidth, height: rulerHeight)

                        track(
                            layout: layout,
                            ticks: ticks,
                            width: contentWidth,
                            height: trackHeight
                        )
                        .frame(width: contentWidth, height: trackHeight)
                        .coordinateSpace(name: "clip-timeline-track")
                    }
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                    ScrollMetrics(offset: geometry.contentOffset.x, width: geometry.containerSize.width)
                } action: { _, metrics in
                    scrollOffset = max(0, metrics.offset)
                    visibleWidth = max(1, metrics.width)
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = magnificationStart ?? pointsPerSecond
                            if magnificationStart == nil { magnificationStart = start }
                            setScale(start * value.magnification, viewportWidth: viewportWidth)
                        }
                        .onEnded { _ in magnificationStart = nil }
                )
                .onAppear {
                    visibleWidth = viewportWidth
                    fitSource(viewportWidth: viewportWidth)
                }
                .onChange(of: viewportWidth) { oldWidth, newWidth in
                    visibleWidth = newWidth
                    if isFitSource { fitSource(viewportWidth: newWidth) }
                    else if oldWidth != newWidth {
                        pointsPerSecond = makeViewport(width: newWidth).clampedScale(pointsPerSecond)
                    }
                }
            }
            .frame(height: rulerHeight + trackHeight + 8)

            HStack {
                Label(Timecode.display(Int(max(0, playhead).rounded())), systemImage: "playhead")
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Playhead \(Timecode.display(Int(max(0, playhead).rounded())))")
                Spacer()
                Text("Duration \(Timecode.display(duration))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
        }
        .onChange(of: sourceID) { _, _ in fitSource(viewportWidth: visibleWidth) }
        .onChange(of: zoomRequest) { _, request in
            guard let request else { return }
            perform(request.action, viewportWidth: visibleWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip-timeline")
    }

    private var timelineToolbar: some View {
        HStack(spacing: 8) {
            Text("Timeline").font(.headline)
            Spacer()
            Button { perform(.zoomOut, viewportWidth: visibleWidth) } label: {
                Image(systemName: "minus")
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom out (Command Minus)")
            .accessibilityLabel("Zoom out timeline")
            .accessibilityIdentifier("timeline-zoom-out")

            Button { perform(.zoomIn, viewportWidth: visibleWidth) } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("+", modifiers: .command)
            .help("Zoom in (Command Plus)")
            .accessibilityLabel("Zoom in timeline")
            .accessibilityIdentifier("timeline-zoom-in")

            Button("Fit Source") { perform(.fitSource, viewportWidth: visibleWidth) }
                .accessibilityIdentifier("timeline-fit-source")
            Button("Fit Selected") { perform(.fitSelected, viewportWidth: visibleWidth) }
                .disabled(selectedRangeID == nil)
                .accessibilityIdentifier("timeline-fit-selected")
        }
        .controlSize(.small)
    }

    private func ruler(ticks: [TimelineTick], width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks) { tick in
                Rectangle()
                    .fill(Color.secondary.opacity(tick.isMajor ? 0.75 : 0.4))
                    .frame(width: 1, height: tick.isMajor ? 10 : 5)
                    .offset(x: x(for: tick.seconds), y: rulerHeight - (tick.isMajor ? 10 : 5))

                if tick.isMajor {
                    Text(Timecode.display(tick.seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(
                            x: min(max(30, x(for: tick.seconds)), max(30, width - 30)),
                            y: 8
                        )
                }
            }

            ForEach(chapters) { chapter in
                let second = Int(chapter.startTime.rounded())
                Button { onSeek(second) } label: {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: x(for: second) - 4, y: rulerHeight - 19)
                .help("\(chapter.title ?? "Chapter") · \(Timecode.display(second))")
                .accessibilityLabel("\(chapter.title ?? "Chapter"), \(Timecode.display(second))")
                .accessibilityHint("Seek to chapter")
                .accessibilityIdentifier("chapter-\(second)")
            }
        }
    }

    private func track(
        layout: ClipTimelineLayout,
        ticks: [TimelineTick],
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .named("clip-timeline-track"))
                        .onEnded { value in onSeek(seconds(at: value.location.x)) }
                )

            ForEach(ticks) { tick in
                Rectangle()
                    .fill(Color.secondary.opacity(tick.isMajor ? 0.18 : 0.09))
                    .frame(width: tick.isMajor ? 1 : 0.5, height: height)
                    .offset(x: x(for: tick.seconds))
                    .allowsHitTesting(false)
            }

            draftOverlay(width: width)
                .offset(y: trackPadding)
                .zIndex(1)

            ForEach(layout.placements) { placement in
                TimelineRangeSegment(
                    placement: placement,
                    duration: duration,
                    pointsPerSecond: pointsPerSecond,
                    isSelected: selectedRangeID == placement.range.id,
                    isTrimming: trimSession?.clipID == placement.range.id,
                    onSelect: { onSelect(placement.range.id) },
                    onFit: {
                        onSelect(placement.range.id)
                        fit(placement.range, viewportWidth: visibleWidth)
                    },
                    onBeginTrim: { onBeginTrim(placement.range.id, $0) },
                    onUpdateTrim: onUpdateTrim,
                    onEndTrim: onEndTrim
                )
                .offset(y: trackPadding + draftHeight + 5 + CGFloat(placement.lane) * (laneHeight + laneSpacing))
                .zIndex(selectedRangeID == placement.range.id ? 3 : 2)
            }

            if let trimSession {
                trimMarker(second: trimSession.boundarySeconds, height: height)
                    .zIndex(5)
            }

            playheadMarker(height: height)
                .zIndex(4)
        }
    }

    @ViewBuilder
    private func draftOverlay(width: CGFloat) -> some View {
        if let draftRange {
            let provisionalEnd = draftRange.outSeconds ?? max(draftRange.inSeconds, Int(playhead.rounded()))
            let startX = x(for: draftRange.inSeconds)
            let endX = x(for: provisionalEnd)
            let stripeWidth = max(draftRange.outSeconds == nil ? 3 : 10, endX - startX)
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.cyan.opacity(0.16))
                Canvas { context, size in
                    var path = Path()
                    for offset in stride(from: -size.height, through: size.width, by: 8) {
                        path.move(to: CGPoint(x: offset, y: size.height))
                        path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                    }
                    context.stroke(path, with: .color(.cyan.opacity(0.8)), lineWidth: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                RoundedRectangle(cornerRadius: 4).stroke(Color.cyan, lineWidth: 1.5)
            }
            .frame(width: min(width - startX, stripeWidth), height: draftHeight)
            .offset(x: startX)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("timeline-draft")
            .accessibilityLabel("Draft clip")
            .accessibilityValue(
                draftRange.outSeconds.map {
                    "\(Timecode.display(draftRange.inSeconds)) to \(Timecode.display($0))"
                } ?? "In at \(Timecode.display(draftRange.inSeconds)), Out not marked"
            )
        }
    }

    private func playheadMarker(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.orange).frame(width: 3, height: height)
            Circle().fill(Color.orange).stroke(Color.white, lineWidth: 1.5).frame(width: 11, height: 11).offset(y: -3)
        }
        .frame(width: 12, height: height, alignment: .top)
        .offset(x: x(for: playhead) - 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func trimMarker(second: Int, height: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(Timecode.display(second))
                .font(.caption2.monospacedDigit().bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
            Rectangle().fill(Color.white).frame(width: 2, height: max(0, height - 20))
        }
        .fixedSize()
        .offset(x: x(for: second) - 28, y: 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trim position \(Timecode.display(second))")
        .accessibilityIdentifier("timeline-trim-position")
    }

    private func makeViewport(width: CGFloat) -> TimelineViewport {
        TimelineViewport(
            duration: duration,
            viewportWidth: max(1, width),
            pointsPerSecond: max(pointsPerSecond, width / CGFloat(max(1, duration))),
            scrollOffset: scrollOffset
        )
    }

    private func perform(_ action: TimelineZoomAction, viewportWidth: CGFloat) {
        switch action {
        case .zoomIn: setScale(pointsPerSecond * 1.5, viewportWidth: viewportWidth)
        case .zoomOut: setScale(pointsPerSecond / 1.5, viewportWidth: viewportWidth)
        case .fitSource: fitSource(viewportWidth: viewportWidth)
        case .fitSelected:
            guard let range = ranges.first(where: { $0.id == selectedRangeID }) else { return }
            fit(range, viewportWidth: viewportWidth)
        }
    }

    private func setScale(_ proposed: CGFloat, viewportWidth: CGFloat) {
        let viewport = makeViewport(width: viewportWidth)
        let newScale = viewport.clampedScale(proposed)
        let newOffset = viewport.offset(afterZoomingTo: newScale, anchorSeconds: playhead)
        pointsPerSecond = newScale
        isFitSource = abs(newScale - viewport.fitScale) < 0.001
        scrollPosition.scrollTo(x: newOffset)
    }

    private func fitSource(viewportWidth: CGFloat) {
        let width = max(1, viewportWidth)
        pointsPerSecond = width / CGFloat(max(1, duration))
        scrollOffset = 0
        isFitSource = true
        scrollPosition.scrollTo(x: 0)
    }

    private func fit(_ range: ClipRange, viewportWidth: CGFloat) {
        let viewport = makeViewport(width: viewportWidth)
        pointsPerSecond = viewport.fitSelected(range)
        isFitSource = false
        let center = CGFloat(range.startSeconds + range.endSeconds) / 2 * pointsPerSecond
        let offset = min(
            max(0, center - viewportWidth / 2),
            max(0, CGFloat(duration) * pointsPerSecond - viewportWidth)
        )
        scrollPosition.scrollTo(x: offset)
    }

    private func visibleSecondRange(contentWidth: CGFloat) -> ClosedRange<Int> {
        let scale = max(0.0001, pointsPerSecond)
        let lower = max(0, Int(floor(scrollOffset / scale)))
        let upper = min(duration, Int(ceil((scrollOffset + visibleWidth) / scale)))
        return lower...max(lower, upper)
    }

    private func x(for seconds: Int) -> CGFloat { CGFloat(seconds) * pointsPerSecond }
    private func x(for seconds: Double) -> CGFloat { CGFloat(seconds) * pointsPerSecond }
    private func seconds(at x: CGFloat) -> Int {
        min(duration, max(0, Int((x / max(0.0001, pointsPerSecond)).rounded())))
    }
}

private struct ScrollMetrics: Equatable {
    let offset: CGFloat
    let width: CGFloat
}

private struct TimelineRangeSegment: View {
    let placement: TimelineRangePlacement
    let duration: Int
    let pointsPerSecond: CGFloat
    let isSelected: Bool
    let isTrimming: Bool
    let onSelect: () -> Void
    let onFit: () -> Void
    let onBeginTrim: (ClipEdge) -> Void
    let onUpdateTrim: (Int) -> Void
    let onEndTrim: () -> Void

    @State private var hoveredEdge: ClipEdge?
    @FocusState private var segmentFocused: Bool

    private var range: ClipRange { placement.range }
    private var color: Color { ClipPalette.color(placement.colorIndex) }
    private var segmentAccessibilityLabel: String {
        "Clip \(placement.index + 1), \(ClipPalette.name(placement.colorIndex))"
    }
    private var segmentAccessibilityValue: String {
        "Lane \(placement.lane + 1), \(Timecode.display(range.startSeconds)) to \(Timecode.display(range.endSeconds))"
    }

    var body: some View {
        let start = CGFloat(range.startSeconds) * pointsPerSecond
        let end = CGFloat(range.endSeconds) * pointsPerSecond
        let segmentWidth = max(12, end - start)

        segmentContent(width: segmentWidth)
            .frame(width: segmentWidth, height: 32)
            .offset(x: start)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-clip-\(placement.index)")
            .accessibilityLabel(segmentAccessibilityLabel)
            .accessibilityValue(segmentAccessibilityValue)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAction(named: "Select clip", onSelect)
            .accessibilityAction(named: "Fit clip in timeline", onFit)
            .focusable()
            .focused($segmentFocused)
            .onChange(of: segmentFocused) { _, focused in
                if focused { onSelect() }
            }
    }

    private func segmentContent(width segmentWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(isSelected ? 1 : 0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : color.opacity(0.85), lineWidth: isSelected ? 2.5 : 1)
                }
                .shadow(color: isSelected ? color.opacity(0.55) : .clear, radius: 4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: onFit)
                .onTapGesture(perform: onSelect)
                .accessibilityHidden(true)

            if segmentWidth >= 28 {
                Text("\(placement.index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }

            trimHandle(edge: .start, offset: -7)
            trimHandle(edge: .end, offset: segmentWidth - 9)
        }
    }

    private func trimHandle(edge: ClipEdge, offset: CGFloat) -> some View {
        let isHovered = hoveredEdge == edge
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(isHovered || isSelected || isTrimming ? 1 : 0.72))
            .frame(width: 16, height: isHovered || isSelected || isTrimming ? 30 : 24)
            .overlay { Capsule().fill(color).frame(width: 3, height: 14) }
            .contentShape(Rectangle())
            .offset(x: offset)
            .onHover { hovering in
                hoveredEdge = hovering ? edge : nil
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("clip-timeline-track"))
                    .onChanged { value in
                        onSelect()
                        onBeginTrim(edge)
                        let second = min(duration, max(0, Int((value.location.x / max(0.0001, pointsPerSecond)).rounded())))
                        onUpdateTrim(second)
                    }
                    .onEnded { _ in onEndTrim() }
            )
            .accessibilityLabel("Clip \(placement.index + 1) \(edge == .start ? "start" : "end")")
            .accessibilityValue(Timecode.display(edge == .start ? range.startSeconds : range.endSeconds))
            .accessibilityHint("Adjusts in one second steps")
            .focusable()
            .accessibilityAdjustableAction { direction in
                let current = edge == .start ? range.startSeconds : range.endSeconds
                switch direction {
                case .increment:
                    onBeginTrim(edge); onUpdateTrim(current + 1); onEndTrim()
                case .decrement:
                    onBeginTrim(edge); onUpdateTrim(current - 1); onEndTrim()
                @unknown default: break
                }
            }
    }
}
