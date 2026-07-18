import XCTest
@testable import Clipped

final class TimelineLayoutTests: XCTestCase {
    func testScaleUsesReadableDurationAwareIntervals() {
        XCTAssertEqual(TimelineScale.majorStep(duration: 120, width: 920), 15)
        XCTAssertEqual(TimelineScale.majorStep(duration: 7_200, width: 920), 900)

        let ticks = TimelineScale.ticks(duration: 122, width: 920)
        XCTAssertEqual(ticks.first, TimelineTick(seconds: 0, isMajor: true))
        XCTAssertEqual(ticks.last?.seconds, 122)
        XCTAssertTrue(ticks.contains(TimelineTick(seconds: 60, isMajor: true)))
        XCTAssertTrue(ticks.contains(where: { !$0.isMajor }))
    }

    func testOverlappingRangesReceiveSeparateCompactLanes() {
        let ranges = [
            ClipRange(startSeconds: 0, endSeconds: 30),
            ClipRange(startSeconds: 10, endSeconds: 20),
            ClipRange(startSeconds: 20, endSeconds: 40),
            ClipRange(startSeconds: 40, endSeconds: 50)
        ]
        let layout = ClipTimelineLayout.make(ranges: ranges)

        XCTAssertEqual(layout.laneCount, 2)
        XCTAssertEqual(layout.placements.map(\.lane), [0, 1, 1, 0])
    }

    func testTouchingRangesCanShareALane() {
        let ranges = [
            ClipRange(startSeconds: 0, endSeconds: 10),
            ClipRange(startSeconds: 10, endSeconds: 20),
            ClipRange(startSeconds: 20, endSeconds: 30)
        ]
        let layout = ClipTimelineLayout.make(ranges: ranges)

        XCTAssertEqual(layout.laneCount, 1)
        XCTAssertEqual(layout.placements.map(\.lane), [0, 0, 0])
    }

    func testClipColorsFollowStableListOrder() {
        let ranges = (0..<10).map { index in
            ClipRange(startSeconds: index * 10, endSeconds: index * 10 + 5)
        }
        let layout = ClipTimelineLayout.make(ranges: ranges)

        XCTAssertEqual(layout.placements.map(\.colorIndex), [0, 1, 2, 3, 4, 5, 6, 7, 0, 1])
        XCTAssertEqual(ClipPalette.name(layout.placements[1].colorIndex), "Red")
    }

    func testViewportClampsZoomAndFitsSelectedClip() {
        let viewport = TimelineViewport(
            duration: 1_000,
            viewportWidth: 1_000,
            pointsPerSecond: 1,
            scrollOffset: 0
        )
        XCTAssertEqual(viewport.fitScale, 1)
        XCTAssertEqual(viewport.maximumScale, 64)
        XCTAssertEqual(viewport.clampedScale(0.1), 1)
        XCTAssertEqual(viewport.clampedScale(100), 64)
        XCTAssertEqual(
            viewport.fitSelected(ClipRange(startSeconds: 100, endSeconds: 120)),
            40
        )
    }

    func testZoomKeepsVisiblePlayheadAtItsViewportPosition() {
        let viewport = TimelineViewport(
            duration: 1_000,
            viewportWidth: 800,
            pointsPerSecond: 2,
            scrollOffset: 300
        )
        XCTAssertEqual(viewport.offset(afterZoomingTo: 4, anchorSeconds: 250), 800)
    }

    func testScaleAdaptsTicksAtDeepZoom() {
        XCTAssertEqual(TimelineScale.majorStep(pointsPerSecond: 64), 2)
        let ticks = TimelineScale.ticks(
            duration: 7_200,
            pointsPerSecond: 64,
            visibleSeconds: 100...110
        )
        XCTAssertTrue(ticks.allSatisfy { $0.seconds >= 99 && $0.seconds <= 111 })
        XCTAssertTrue(ticks.contains(TimelineTick(seconds: 100, isMajor: true)))
    }
}
