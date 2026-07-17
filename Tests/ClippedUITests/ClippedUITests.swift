import XCTest

final class ClippedUITests: XCTestCase {
    @MainActor
    func testInitialWindowExposesMinimalURLWorkflow() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "initial"
        app.launch()

        let urlField = app.textFields["source-url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))

        let loadButton = app.buttons["load-source"]
        XCTAssertTrue(loadButton.exists)
        XCTAssertFalse(loadButton.isEnabled)

        urlField.click()
        urlField.typeText("https://example.com/video")
        XCTAssertTrue(loadButton.isEnabled)
    }

    @MainActor
    func testLoadedSourceSupportsDynamicFormatsAndMultipleRanges() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "loaded"
        app.launch()

        XCTAssertTrue(app.staticTexts["source-title"].waitForExistence(timeout: 5))

        let video = app.popUpButtons["video-quality"]
        let audio = app.popUpButtons["audio-quality"]
        XCTAssertTrue(video.exists)
        XCTAssertTrue(audio.exists)
        XCTAssertTrue(String(describing: video.value).contains("1080p"))
        XCTAssertTrue(String(describing: video.value).contains("60 fps"))
        XCTAssertTrue(String(describing: audio.value).contains("5.1"))

        let download = app.buttons["download-clips"]
        XCTAssertTrue(download.isEnabled)
        XCTAssertEqual(download.label, "Download Clip")

        app.buttons["add-clip"].click()
        let secondStart = app.textFields["clip-1-start"]
        let secondEnd = app.textFields["clip-1-end"]
        XCTAssertTrue(secondStart.waitForExistence(timeout: 2))
        XCTAssertEqual(download.label, "Download 2 Clips")

        replaceText(in: secondStart, with: "01:00")
        XCTAssertFalse(download.isEnabled)

        replaceText(in: secondEnd, with: "01:10")
        XCTAssertTrue(download.isEnabled)

        app.buttons["remove-clip-1"].click()
        XCTAssertFalse(secondStart.exists)
        XCTAssertEqual(download.label, "Download Clip")
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with value: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        field.typeKey(.return, modifierFlags: [])
    }
}
