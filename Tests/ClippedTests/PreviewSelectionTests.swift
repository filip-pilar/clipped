import XCTest
@testable import Clipped

final class PreviewSelectionTests: XCTestCase {
    func testPrefersProgressiveH264AACAtOrBelow480p() throws {
        let media = try TestFixtures.loadedVideo()
        XCTAssertEqual(
            try PreviewSelection.choose(from: media.metadata),
            PreviewSelection(selector: "18", audioOnly: false)
        )
    }

    func testFallsBackToSeparateLowResolutionVideoAndAudio() throws {
        let json = #"""
        {
          "id":"x","title":"x","duration":60,"formats":[
            {"format_id":"v","ext":"webm","vcodec":"vp9","acodec":"none","width":854,"height":480,"fps":30},
            {"format_id":"a","ext":"webm","vcodec":"none","acodec":"opus","abr":128,"audio_channels":2}
          ]
        }
        """#
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(
            try PreviewSelection.choose(from: metadata),
            PreviewSelection(selector: "v+a", audioOnly: false)
        )
    }

    func testChoosesBestAudioForAudioOnlySource() throws {
        let json = #"""
        {
          "id":"x","title":"x","duration":60,"formats":[
            {"format_id":"a1","ext":"m4a","vcodec":"none","acodec":"aac","abr":96,"audio_channels":2},
            {"format_id":"a2","ext":"webm","vcodec":"none","acodec":"opus","abr":160,"audio_channels":2}
          ]
        }
        """#
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(
            try PreviewSelection.choose(from: metadata),
            PreviewSelection(selector: "a2", audioOnly: true)
        )
    }
}
