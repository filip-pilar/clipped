import XCTest
@testable import Clipped

final class MediaFailureTests: XCTestCase {
    func testClassifiesCommonPlatformFailures() {
        let cases: [(String, MediaFailureKind)] = [
            ("ERROR: This video is unavailable", .unavailable),
            ("Login required. Use --cookies to authenticate", .authenticationRequired),
            ("HTTP Error 429: Too Many Requests", .rateLimited),
            ("This video is not available in your country", .geoRestricted),
            ("Could not resolve host: example.com", .network),
            ("Unsupported URL: https://example.com/post", .unsupported)
        ]

        for (diagnostic, expected) in cases {
            XCTAssertEqual(
                MediaFailurePresentation.classify(diagnostic: diagnostic, context: .source).kind,
                expected,
                diagnostic
            )
        }
    }

    func testTypedSourceFailuresHaveSpecificGuidance() {
        let invalid = MediaFailurePresentation.classify(MetadataServiceError.invalidURL, context: .source)
        XCTAssertEqual(invalid.kind, .invalidURL)
        XCTAssertEqual(invalid.title, "Check the URL")

        let live = MediaFailurePresentation.classify(MetadataServiceError.liveSourceUnsupported, context: .source)
        XCTAssertEqual(live.kind, .liveUnsupported)
        XCTAssertTrue(live.message.contains("fixed duration"))
    }

    func testPreviewConversionFailureKeepsManualTimecodePathClear() {
        let failure = MediaFailurePresentation.classify(
            PreviewServiceError.normalizationFailed("ffmpeg stopped"),
            context: .preview
        )
        XCTAssertEqual(failure.kind, .conversion)
        XCTAssertEqual(failure.title, "Preview preparation failed")
        XCTAssertTrue(failure.message.contains("enter clip times manually"))
        XCTAssertEqual(failure.diagnostic, "ffmpeg stopped")
    }

    func testUnknownDiagnosticIsConcise() {
        let diagnostic = String(repeating: "x", count: 300)
        let failure = MediaFailurePresentation.classify(diagnostic: diagnostic, context: .source)
        XCTAssertEqual(failure.kind, .unknown)
        XCTAssertEqual(failure.diagnostic?.count, 180)
        XCTAssertTrue(failure.diagnostic?.hasSuffix("…") == true)
    }

    func testPreviewProgressMapsToUnderstandableStates() {
        XCTAssertEqual(
            PreviewState.progress(.init(stage: .downloading, fractionCompleted: 0.25)),
            .downloading(fractionCompleted: 0.25)
        )
        XCTAssertEqual(
            PreviewState.progress(.init(stage: .normalizing, fractionCompleted: nil)),
            .preparing
        )
        XCTAssertEqual(
            PreviewState.progress(.init(stage: .ready, fractionCompleted: 1)),
            .preparing
        )
    }
}
