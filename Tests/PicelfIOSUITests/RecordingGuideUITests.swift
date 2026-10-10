// RecordingGuideUITests.swift
// PicelfIOSUITests — UI tests for the recording guide sheet flow

import XCTest

final class RecordingGuideUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        throw XCTSkip("Control Center recording entry has been removed from the public iOS UI.")
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Sheet Presentation

    func test_tappingRecordCard_showsGuideSheet() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Capture"].tap()

        // Tap the "录屏拼接" card
        let recordButton = app.buttons["capture.record.button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 3))
        recordButton.tap()

        // Sheet should appear with the title
        let sheetTitle = app.staticTexts["录屏拼接"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 3),
                      "Recording guide sheet should show '录屏拼接' title")
    }

    func test_guideSheet_showsAllFourSteps() {
        openGuideSheet()

        // Verify all 4 step titles are visible
        XCTAssertTrue(app.staticTexts["打开控制中心"].waitForExistence(timeout: 3),
                      "Step 1 title should be visible")
        XCTAssertTrue(app.staticTexts["长按录屏按钮"].exists,
                      "Step 2 title should be visible")
        XCTAssertTrue(app.staticTexts["滚动目标页面"].exists,
                      "Step 3 title should be visible")
        XCTAssertTrue(app.staticTexts["停止录屏"].exists,
                      "Step 4 title should be visible")
    }

    func test_guideSheet_showsStepSubtitles() {
        openGuideSheet()

        XCTAssertTrue(app.staticTexts["从屏幕右上角下滑"].waitForExistence(timeout: 3),
                      "Step 1 subtitle should be visible")
        XCTAssertTrue(app.staticTexts["选择 Picelf 开始录制"].exists,
                      "Step 2 subtitle should be visible")
    }

    func test_guideSheet_showsImportVideoLink() {
        openGuideSheet()

        let importLink = app.buttons["recording.guide.import.button"]
        XCTAssertTrue(importLink.waitForExistence(timeout: 3),
                      "Import video link should be visible in guide sheet")
    }

    func test_guideImportButton_opensImportView() {
        openGuideSheet()

        let importLink = app.buttons["recording.guide.import.button"]
        XCTAssertTrue(importLink.waitForExistence(timeout: 3))
        importLink.tap()

        XCTAssertTrue(app.buttons["import.fixture.button"].waitForExistence(timeout: 3),
                      "Guide import entry should open the unified ImportView")
    }

    func test_simulatedBroadcast_processesAndAppearsInLibrary() {
        openGuideSheet()

        let simulateButton = app.buttons["recording.guide.simulate.button"]
        XCTAssertTrue(simulateButton.waitForExistence(timeout: 3),
                      "Simulated broadcast button should be visible under UI tests")
        simulateButton.tap()

        let backButton = app.buttons["preview.back.button"]
        let exportButton = app.buttons["preview.export.button"]
        let processingRing = element(matching: "processing.progress.ring")
        XCTAssertTrue(
            processingRing.waitForExistence(timeout: 5)
                || backButton.waitForExistence(timeout: 10)
                || exportButton.waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 10) || exportButton.waitForExistence(timeout: 2),
            "Simulated broadcast should complete and present preview"
        )
        backButton.tap()

        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Library"].tap()

        let libraryCard = app.buttons["library.item.card"].firstMatch
        XCTAssertTrue(libraryCard.waitForExistence(timeout: 5),
                      "Broadcast result should be persisted into Library immediately")
    }

    // MARK: - Helper

    private func openGuideSheet() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Capture"].tap()

        let recordButton = app.buttons["capture.record.button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 3))
        recordButton.tap()

        // Wait for sheet to appear
        _ = app.staticTexts["录屏拼接"].waitForExistence(timeout: 3)
    }

    private func configureLaunchEnvironment() {
        let sessionRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PicelfGuideUITests-\(UUID().uuidString)", isDirectory: true)
        app.launchEnvironment["UITEST_IMPORT_FIXTURE"] = "ui-import"
        app.launchEnvironment["UITEST_SIMULATE_BROADCAST_FIXTURE"] = "ui-broadcast"
        app.launchEnvironment["UITEST_RESULT_STORE_ROOT"] = sessionRoot.appendingPathComponent("results").path
        app.launchEnvironment["UITEST_BROADCAST_ROOT"] = sessionRoot.appendingPathComponent("broadcast").path
    }

    private func element(matching identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
