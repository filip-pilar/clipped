import XCTest
@testable import Clipped

final class MediaSelectionTests: XCTestCase {
    func testPairsVideoOnlyFormatWithSelectedAudio() throws {
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(
            video: media.catalog.videoChoices.first(where: { $0.formatID == "299" }),
            audio: media.catalog.audioChoices.first
        )
        XCTAssertEqual(try selection.ytDLPSelector(), "299+258")
        XCTAssertEqual(selection.audioBitrateKilobits, 384)
    }

    func testEmbeddedAudioDoesNotAddASecondTrack() throws {
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(
            video: media.catalog.videoChoices.first(where: { $0.formatID == "18" }),
            audio: media.catalog.audioChoices.first
        )
        XCTAssertEqual(try selection.ytDLPSelector(), "18")
        XCTAssertEqual(selection.expectedAudioChannels, 2)
        XCTAssertEqual(selection.audioBitrateKilobits, 192)
    }

    func testAudioOnlyRequiresAChoice() {
        XCTAssertThrowsError(try MediaSelection(video: nil, audio: nil).ytDLPSelector())
    }
}
