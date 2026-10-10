// ImportFlowUITests.swift
// PicelfIOSUITests — UI tests for the import flow

import XCTest

final class ImportFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        configureLaunchEnvironment()
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Button existence

    func test_importButton_exists() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Capture"].tap()

        let importButton = app.buttons["capture.import.button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3),
                      "Import button should exist on Capture tab as the primary entry")
        XCTAssertFalse(app.buttons["capture.record.button"].exists,
                       "Public iOS Capture tab should no longer expose the old recording entry")
    }

    // MARK: - Recent results section

    func test_recentResultsSection_hasTitle() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Capture"].tap()

        // The recent results section displays a title text
        let recentTitle = app.staticTexts["最近结果"]
        XCTAssertTrue(recentTitle.waitForExistence(timeout: 3),
                      "Recent results section title should be visible on Capture tab")
    }

    func test_importFixture_processesAndShowsPreview() {
        runImportFixtureFlow()
    }

    func test_importFixture_persistsIntoRecentResults() {
        runImportFixtureFlow()

        let backButton = app.buttons["preview.back.button"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()

        let recentCard = app.buttons["capture.recent.card"].firstMatch
        XCTAssertTrue(recentCard.waitForExistence(timeout: 5),
                      "Successful import should appear in Recent immediately")
    }

    // MARK: - Helpers

    private func configureLaunchEnvironment() {
        let sessionRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PicelfIOSUITests-\(UUID().uuidString)", isDirectory: true)
        app.launchEnvironment["UITEST_IMPORT_FIXTURE"] = "ui-import"
        app.launchEnvironment["UITEST_RESULT_STORE_ROOT"] = sessionRoot.appendingPathComponent("results").path
        app.launchEnvironment["UITEST_BROADCAST_ROOT"] = sessionRoot.appendingPathComponent("broadcast").path
    }

    private func openCaptureTab() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Capture"].tap()
    }

    private func runImportFixtureFlow() {
        openCaptureTab()

        let importButton = app.buttons["capture.import.button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()

        let fixtureButton = app.buttons["import.fixture.button"]
        XCTAssertTrue(fixtureButton.waitForExistence(timeout: 3),
                      "Debug import fixture button should be visible under UI tests")
        fixtureButton.tap()

        let processingRing = element(matching: "processing.progress.ring")
        let previewBackButton = app.buttons["preview.back.button"]
        let previewExportButton = app.buttons["preview.export.button"]
        XCTAssertTrue(
            processingRing.waitForExistence(timeout: 5)
                || previewBackButton.waitForExistence(timeout: 10)
                || previewExportButton.waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            previewBackButton.waitForExistence(timeout: 10)
                || previewExportButton.waitForExistence(timeout: 2),
            "Import fixture should complete and present preview"
        )
    }

    private func element(matching identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
