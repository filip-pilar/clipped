import XCTest

final class ClippedUITests: XCTestCase {
    @MainActor
    func testInitialWindowExposesMinimalURLWorkflow() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "initial"
        app.launch()

        let urlField = app.textFields["source-url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))

        urlField.click()
        urlField.typeKey("a", modifierFlags: .command)
        urlField.typeKey(.delete, modifierFlags: [])

        let loadButton = app.buttons["load-source"]
        XCTAssertTrue(loadButton.exists)
        XCTAssertFalse(loadButton.isEnabled)

        urlField.click()
        urlField.typeText("https://example.com/video")
        XCTAssertTrue(loadButton.isEnabled)
    }

    @MainActor
    func testFailedSourceExplainsTheProblem() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "initial"
        app.launch()

        let urlField = app.textFields["source-url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.click()
        urlField.typeText("https://example.com/video")
        app.buttons["load-source"].click()

        XCTAssertTrue(app.staticTexts["Source not supported"].waitForExistence(timeout: 5))
        let explanation = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "Clipped couldn’t")
        ).firstMatch
        XCTAssertTrue(explanation.exists)
    }

    @MainActor
    func testLoadedSourceExposesCompactFormatsAndStartsWithoutClips() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "loaded"
        app.launch()

        XCTAssertTrue(app.staticTexts["source-title"].waitForExistence(timeout: 5))

        let video = app.buttons["format-video"]
        let audio = app.buttons["format-audio"]
        let output = app.buttons["format-output"]
        XCTAssertTrue(video.exists)
        XCTAssertTrue(audio.exists)
        XCTAssertTrue(output.exists)
        XCTAssertTrue(String(describing: video.value).contains("1080p"))
        XCTAssertTrue(String(describing: audio.value).contains("5.1"))
        XCTAssertTrue(String(describing: output.value).contains("MP4"))

        XCTAssertTrue(app.descendants(matching: .any)["preview-failure"].exists)
        XCTAssertTrue(app.staticTexts["empty-clips"].exists)

        let download = app.buttons["download-clips"]
        XCTAssertFalse(download.isEnabled)
        XCTAssertEqual(download.label, "Download Clips")
        XCTAssertTrue(app.buttons["timeline-zoom-in"].exists)
        XCTAssertTrue(app.buttons["timeline-fit-source"].exists)
        XCTAssertFalse(app.buttons["timeline-fit-selected"].isEnabled)
        XCTAssertTrue(app.buttons["chapter-30"].exists)
    }

    @MainActor
    func testVisibleDraftWorkflowAndCompactClipMenu() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "loaded"
        app.launch()
        XCTAssertTrue(app.buttons["mark-in"].waitForExistence(timeout: 5))

        app.buttons["mark-in"].click()
        XCTAssertTrue(app.descendants(matching: .any)["timeline-draft"].exists)
        XCTAssertFalse(app.buttons["add-clip"].isEnabled)

        app.buttons["chapter-90"].click()
        app.buttons["mark-out"].click()
        XCTAssertTrue(app.buttons["add-clip"].isEnabled)
        XCTAssertFalse(app.textFields["clip-0-start"].exists)

        app.buttons["add-clip"].click()
        let firstStart = app.textFields["clip-0-start"]
        let firstEnd = app.textFields["clip-0-end"]
        XCTAssertTrue(firstStart.waitForExistence(timeout: 2))
        XCTAssertTrue(firstEnd.exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline-draft"].exists)
        XCTAssertEqual(app.buttons["download-clips"].label, "Download Clip")
        XCTAssertTrue(app.buttons["timeline-fit-selected"].isEnabled)

        firstStart.click()
        firstStart.typeKey("i", modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["timeline-draft"].exists)
        firstStart.typeKey(.escape, modifierFlags: [])

        XCTAssertFalse(app.buttons["clip-0-set-start"].exists)
        XCTAssertFalse(app.buttons["clip-0-set-end"].exists)
        let menu = app.menuButtons["clip-0-menu"]
        XCTAssertTrue(menu.exists)
    }

    @MainActor
    func testOverlappingClipsRemainSeparatelyVisible() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "overlap"
        app.launch()

        XCTAssertTrue(app.staticTexts["source-title"].waitForExistence(timeout: 5))
        for index in 0..<4 {
            let segment = app.descendants(matching: .any)["timeline-clip-\(index)"]
            XCTAssertTrue(segment.exists, "Missing timeline segment \(index)")
        }

        let selected = app.descendants(matching: .any)["timeline-clip-1"]
        XCTAssertEqual(selected.label, "Clip 2, Red")
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(app.buttons["download-clips"].label, "Download 4 Clips")
    }

    @MainActor
    func testPreviewLoadingStillAllowsMarking() {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPPED_UI_TEST_MODE"] = "loading"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["preview-downloading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["transport-play-pause"].isEnabled)
        XCTAssertTrue(app.buttons["mark-in"].isEnabled)
        app.buttons["mark-in"].click()
        XCTAssertTrue(app.descendants(matching: .any)["timeline-draft"].exists)
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with value: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        field.typeKey(.return, modifierFlags: [])
    }
}
