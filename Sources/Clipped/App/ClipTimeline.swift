import SwiftUI

struct ClipTimeline: View {
    let ranges: [ClipRange]
    let duration: Int
    let playhead: Double
    @Binding var selectedRangeID: UUID?
    let onSeek: (Int) -> Void
    let onChange: (ClipRange) -> Void

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.13))
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("clip-timeline"))
                                .onChanged { value in onSeek(seconds(at: value.location.x, width: width)) }
                        )

                    ForEach(ranges) { range in
                        TimelineRangeSegment(
                            range: range,
                            duration: duration,
                            width: width,
                            isSelected: selectedRangeID == range.id,
                            onSelect: { selectedRangeID = range.id },
                            onChange: onChange,
                            onSeek: onSeek
                        )
                    }

                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 1.5, height: 42)
                        .offset(x: playheadX(width: width))
                        .allowsHitTesting(false)
                }
                .frame(height: 42)
                .coordinateSpace(name: "clip-timeline")
            }
            .frame(height: 42)

            HStack {
                Text(Timecode.display(Int(max(0, playhead).rounded(.down))))
                Spacer()
                Text(Timecode.display(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip-timeline")
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Int {
        Int((min(max(0, x), width) / width * CGFloat(max(1, duration))).rounded())
    }

    private func playheadX(width: CGFloat) -> CGFloat {
        let fraction = min(1, max(0, playhead / Double(max(1, duration))))
        return width * fraction
    }
}

private struct TimelineRangeSegment: View {
    let range: ClipRange
    let duration: Int
    let width: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onChange: (ClipRange) -> Void
    let onSeek: (Int) -> Void

    var body: some View {
        let start = x(for: range.startSeconds)
        let end = x(for: range.endSeconds)
        let segmentWidth = max(8, end - start)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isSelected ? 0.9 : 0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(isSelected ? 0.8 : 0.35), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                    onSeek(range.startSeconds)
                }

            handle(at: 0, isStart: true)
            handle(at: segmentWidth - 8, isStart: false)
        }
        .frame(width: segmentWidth, height: 30)
        .offset(x: start)
        .accessibilityLabel("Clip from \(Timecode.display(range.startSeconds)) to \(Timecode.display(range.endSeconds))")
    }

    private func handle(at offset: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 8, height: 22)
            .overlay {
                Capsule().fill(Color.accentColor).frame(width: 2, height: 10)
            }
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("clip-timeline"))
                    .onChanged { value in
                        onSelect()
                        let second = seconds(at: value.location.x)
                        var updated = range
                        if isStart {
                            updated.startSeconds = min(max(0, second), max(0, range.endSeconds - 1))
                            onSeek(updated.startSeconds)
                        } else {
                            updated.endSeconds = max(range.startSeconds + 1, min(duration, second))
                            onSeek(updated.endSeconds)
                        }
                        onChange(updated)
                    }
            )
    }

    private func x(for seconds: Int) -> CGFloat {
        width * CGFloat(min(duration, max(0, seconds))) / CGFloat(max(1, duration))
    }

    private func seconds(at x: CGFloat) -> Int {
        Int((min(max(0, x), width) / width * CGFloat(max(1, duration))).rounded())
    }
}
