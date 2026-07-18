import XCTest
@testable import Clipped

@MainActor
final class AppModelEditorTests: XCTestCase {
    func testLoadedSourceStartsEmptyAtYouTubeTimestamp() {
        let model = makeModel()
        XCTAssertTrue(model.ranges.isEmpty)
        XCTAssertNil(model.selectedRangeID)
        XCTAssertEqual(model.roundedPlayhead, 31)
        XCTAssertEqual(model.chapters.count, 3)
    }

    func testDraftDoesNotCommitUntilExplicitAction() {
        let model = makeModel()
        model.markIn()
        XCTAssertEqual(model.draftRange, DraftRange(inSeconds: 31, outSeconds: nil))

        model.seek(to: 45)
        model.markOut()
        XCTAssertTrue(model.ranges.isEmpty)
        XCTAssertTrue(model.canCommitDraft)

        model.commitDraft()
        XCTAssertEqual(model.ranges.map { [$0.startSeconds, $0.endSeconds] }, [[31, 45]])
        XCTAssertNil(model.draftRange)
        XCTAssertEqual(model.selectedRangeID, model.ranges.first?.id)
    }

    func testInvalidOutLeavesDraftUnchanged() {
        let model = makeModel()
        model.markIn()
        model.seek(to: 20)
        model.markOut()
        XCTAssertEqual(model.draftRange, DraftRange(inSeconds: 31, outSeconds: nil))
        XCTAssertEqual(model.editorStatusMessage, "Out must be after In.")
    }

    func testCommitUndoRestoresDraftAndRedoRestoresClip() {
        let model = makeModel()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.attachUndoManager(undoManager)
        model.markIn()
        model.seek(to: 42)
        model.markOut()
        model.commitDraft()

        XCTAssertEqual(model.ranges.count, 1)
        undoManager.undo()
        XCTAssertTrue(model.ranges.isEmpty)
        XCTAssertEqual(model.draftRange, DraftRange(inSeconds: 31, outSeconds: 42))

        undoManager.redo()
        XCTAssertEqual(model.ranges.count, 1)
        XCTAssertNil(model.draftRange)
    }

    func testDuplicateAndDeletePreserveDeterministicSelection() {
        let model = makeModelWithClip(start: 10, end: 20)
        let originalID = try! XCTUnwrap(model.selectedRangeID)
        model.duplicateRange(id: originalID)
        XCTAssertEqual(model.ranges.count, 2)
        XCTAssertNotEqual(model.ranges[0].id, model.ranges[1].id)
        XCTAssertEqual(model.selectedRangeID, model.ranges[1].id)

        model.removeSelectedRange()
        XCTAssertEqual(model.ranges.count, 1)
        XCTAssertEqual(model.selectedRangeID, originalID)
    }

    func testBoundaryCommandsDoNotMoveOppositeEndpoint() {
        let model = makeModelWithClip(start: 10, end: 20)
        let id = try! XCTUnwrap(model.selectedRangeID)
        model.seek(to: 19)
        model.setStartToPlayhead(for: id)
        XCTAssertEqual(model.ranges.first, ClipRange(id: id, startSeconds: 19, endSeconds: 20))

        model.seek(to: 10)
        model.setEndToPlayhead(for: id)
        XCTAssertEqual(model.ranges.first, ClipRange(id: id, startSeconds: 19, endSeconds: 20))
    }

    func testTrimKeepsPersistentPlayheadAndCancelRestoresRange() {
        let model = makeModelWithClip(start: 10, end: 20)
        let id = try! XCTUnwrap(model.selectedRangeID)
        model.seek(to: 50)
        model.beginTrim(id: id, edge: .start)
        model.updateTrim(to: 15)
        XCTAssertEqual(model.playheadSeconds, 50)
        XCTAssertEqual(model.ranges.first?.startSeconds, 15)
        XCTAssertEqual(model.trimSession?.boundarySeconds, 15)

        model.cancelTrim()
        XCTAssertEqual(model.ranges.first, ClipRange(id: id, startSeconds: 10, endSeconds: 20))
        XCTAssertEqual(model.playheadSeconds, 50)
        XCTAssertNil(model.trimSession)
    }

    func testCompletedTrimIsOneUndoableEdit() {
        let model = makeModelWithClip(start: 10, end: 20)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.attachUndoManager(undoManager)
        let id = try! XCTUnwrap(model.selectedRangeID)
        model.beginTrim(id: id, edge: .end)
        model.updateTrim(to: 25)
        model.updateTrim(to: 30)
        model.endTrim()
        XCTAssertEqual(model.ranges.first?.endSeconds, 30)

        undoManager.undo()
        XCTAssertEqual(model.ranges.first?.endSeconds, 20)
        undoManager.redo()
        XCTAssertEqual(model.ranges.first?.endSeconds, 30)
    }

    private func makeModel() -> AppModel {
        AppModel(environment: ["CLIPPED_UI_TEST_MODE": "loaded"])
    }

    private func makeModelWithClip(start: Int, end: Int) -> AppModel {
        let model = makeModel()
        model.seek(to: start)
        model.markIn()
        model.seek(to: end)
        model.markOut()
        model.commitDraft()
        return model
    }
}
