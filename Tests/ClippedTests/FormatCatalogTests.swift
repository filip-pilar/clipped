import XCTest
@testable import Clipped

final class FormatCatalogTests: XCTestCase {
    func testBuildsHumanReadableDynamicChoices() throws {
        let metadata = try decodeFixture()
        let catalog = FormatCatalog.build(from: metadata.formats)

        XCTAssertEqual(catalog.videoChoices.map(\.primaryLabel), [
            "1080p · 60 fps",
            "720p · 60 fps",
            "360p · 30 fps"
        ])
        XCTAssertEqual(catalog.videoChoices.first?.codec, "H.264")
        XCTAssertEqual(catalog.videoChoices.first?.formatID, "299")
        XCTAssertEqual(catalog.audioChoices.first?.primaryLabel, "5.1 · 388 kbps")
        XCTAssertEqual(catalog.audioChoices.last?.primaryLabel, "Stereo · 129 kbps")
        XCTAssertFalse(catalog.videoChoices.contains(where: { $0.formatID == "sb0" }))
    }

    func testAudioOnlyCatalog() throws {
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(audioOnlyFixture.utf8))
        let catalog = FormatCatalog.build(from: metadata.formats)

        XCTAssertTrue(catalog.isAudioOnly)
        XCTAssertEqual(catalog.audioChoices.count, 2)
        XCTAssertEqual(catalog.defaultAudioChoice?.formatID, "high")
    }

    func testMissingOptionalPropertiesDoNotDiscardAFormat() throws {
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(minimalFixture.utf8))
        let choice = try XCTUnwrap(FormatCatalog.build(from: metadata.formats).defaultVideoChoice)
        XCTAssertEqual(choice.primaryLabel, "480p")
        XCTAssertEqual(choice.detailLabel, "VP9 · WEBM")
    }

    private func decodeFixture() throws -> YTDLPMetadata {
        try JSONDecoder().decode(YTDLPMetadata.self, from: Data(videoFixture.utf8))
    }

    private let videoFixture = #"""
    {
      "id": "sample",
      "title": "Sample",
      "duration": 635,
      "formats": [
        {"format_id":"sb0","ext":"mhtml","protocol":"mhtml","vcodec":"images","acodec":"none","width":160,"height":90,"format_note":"storyboard"},
        {"format_id":"18","ext":"mp4","vcodec":"avc1.42001E","acodec":"mp4a.40.2","width":640,"height":360,"fps":30,"tbr":360,"filesize_approx":28526904,"dynamic_range":"SDR"},
        {"format_id":"134","ext":"mp4","vcodec":"avc1.4d401e","acodec":"none","width":640,"height":360,"fps":30,"vbr":231,"filesize":18294110,"dynamic_range":"SDR"},
        {"format_id":"398","ext":"mp4","vcodec":"av01.0.08M.08","acodec":"none","width":1280,"height":720,"fps":60,"vbr":899,"filesize":71283827,"dynamic_range":"SDR"},
        {"format_id":"298","ext":"mp4","vcodec":"avc1.4d4020","acodec":"none","width":1280,"height":720,"fps":60,"vbr":1898,"filesize":150524867,"dynamic_range":"SDR"},
        {"format_id":"303","ext":"webm","vcodec":"vp9","acodec":"none","width":1920,"height":1080,"fps":60,"vbr":2127,"filesize":168736189,"dynamic_range":"SDR"},
        {"format_id":"299","ext":"mp4","vcodec":"avc1.64002a","acodec":"none","width":1920,"height":1080,"fps":60,"vbr":3248,"filesize":257619653,"dynamic_range":"SDR"},
        {"format_id":"140","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":129.481,"asr":44100,"audio_channels":2,"filesize":10271496},
        {"format_id":"258","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":387.853,"asr":48000,"audio_channels":6,"filesize":30767611}
      ]
    }
    """#

    private let audioOnlyFixture = #"""
    {
      "id": "audio",
      "title": "Audio",
      "duration": 120,
      "formats": [
        {"format_id":"low","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":96,"audio_channels":2},
        {"format_id":"high","ext":"webm","vcodec":"none","acodec":"opus","abr":160,"audio_channels":2}
      ]
    }
    """#

    private let minimalFixture = #"""
    {
      "id": "minimal",
      "title": "Minimal",
      "formats": [
        {"format_id":"v","ext":"webm","vcodec":"vp9","acodec":"none","height":480}
      ]
    }
    """#
}
