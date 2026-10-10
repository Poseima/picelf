// NavigationUITests.swift
// PicelfIOSUITests — UI tests for tab navigation

import XCTest

final class NavigationUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-appLanguage", "en", "--relay-ui-isolated", "--relay-ui-no-network"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_languageSwitchRefreshesTabsAndVisitedPages() {
        XCTAssertTrue(tabButton("Capture").waitForExistence(timeout: 5))
        tabButton("Library").tap()
        XCTAssertTrue(app.navigationBars["Library"].exists)
        tabButton("Settings").tap()
        chooseLanguage("中文")
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(tabButton("捕获").exists)
        XCTAssertTrue(tabButton("资料库").exists)
        saveScreenshot("Settings Chinese")

        tabButton("资料库").tap()
        XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有拼接结果"].exists)
        saveScreenshot("Library Chinese")
        tabButton("捕获").tap()
        XCTAssertTrue(app.buttons["capture.import.button"].label.contains("导入视频"))
        saveScreenshot("Capture Chinese")

        tabButton("设置").tap()
        chooseLanguage("English")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        tabButton("Library").tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No stitched results yet"].exists)
        saveScreenshot("Library English")
        tabButton("Capture").tap()
        XCTAssertTrue(app.buttons["capture.import.button"].label.contains("Import Video"))
        saveScreenshot("Capture English")
    }

    func test_largeTextLanguagePickerAndImportStayUsable() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(tabButton("Capture").waitForExistence(timeout: 5))
        tabButton("Settings").tap()
        let picker = app.buttons["settings.language.picker"]
        for _ in 0..<5 {
            if picker.isHittable { break }
            app.swipeUp()
        }
        chooseLanguage("中文")
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        saveScreenshot("Settings Chinese Large Text")
        chooseLanguage("English")
        tabButton("Capture").tap()
        let importButton = app.buttons["capture.import.button"]
        XCTAssertTrue(importButton.isHittable)
        importButton.tap()
        XCTAssertTrue(app.navigationBars["Import Video"].waitForExistence(timeout: 3))
        let cancel = app.buttons["import.cancel.button"]
        XCTAssertTrue(cancel.isHittable)
        saveScreenshot("Import English Large Text")
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Picelf"].waitForExistence(timeout: 3))
    }

    func test_iPadRelayLanguageAndTextControls() throws {
        guard tabButton("Relay Canvas").waitForExistence(timeout: 3) else {
            throw XCTSkip("Relay Canvas is available on iPad only")
        }
        tabButton("Relay Canvas").tap()
        XCTAssertTrue(app.navigationBars["Relay Canvas"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["relay.connection"].label, "Waiting to Connect")
        saveScreenshot("Relay English")
        tabButton("Settings").tap()
        chooseLanguage("中文")
        tabButton("接力画板").tap()
        XCTAssertTrue(app.navigationBars["接力画板"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["relay.connection"].label, "等待连接")
        app.buttons["relay.connection"].tap()
        XCTAssertTrue(app.staticTexts["设备连接"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["未连接，打开两端接力画板即可重连"].exists)
        saveScreenshot("Relay Chinese Connection")
        app.tap()
        saveScreenshot("Relay Chinese")
        tabButton("设置").tap()
        chooseLanguage("English")
        tabButton("Relay Canvas").tap()
        app.buttons["relay.newPaper"].tap()
        app.buttons["Landscape Canvas"].tap()
        XCTAssertTrue(app.buttons["relay.textTool"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["relay.textTool"].label, "Add Text")
        app.buttons["relay.textTool"].tap()
        app.otherElements["relay.canvas"].coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
        let input = app.textViews["relay.textInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("Review notes")
        let finish = app.buttons["relay.finishText"]
        XCTAssertTrue(finish.isHittable)
        XCTAssertEqual(finish.label, "Finish Typing")
        saveScreenshot("Relay English Text Editing")
        finish.tap()
        app.buttons["relay.back"].tap()
        XCTAssertTrue(app.buttons["relay.history"].waitForExistence(timeout: 5))
    }

    private func tabButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func chooseLanguage(_ name: String) {
        let picker = app.buttons["settings.language.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let choice = app.buttons[name].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
    }

    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Launch

    func test_appLaunchesSuccessfully() {
        // The app should launch and display the tab view
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5),
                      "Tab bar should be visible after launch")
    }

    // MARK: - Tab visibility

    func test_allThreeTabs_areVisible() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        XCTAssertTrue(tabBar.buttons["Capture"].exists, "Capture tab should exist")
        XCTAssertTrue(tabBar.buttons["Library"].exists, "Library tab should exist")
        XCTAssertTrue(tabBar.buttons["Settings"].exists, "Settings tab should exist")
    }

    // MARK: - Tab navigation

    func test_tappingCaptureTab_showsCaptureView() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Capture"].tap()

        // CaptureView shows the "Picelf" navigation title
        XCTAssertTrue(app.navigationBars["Picelf"].waitForExistence(timeout: 3),
                      "Capture view should show Picelf navigation title")
    }

    func test_tappingLibraryTab_showsLibraryView() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Library"].tap()

        // LibraryView has the navigation title "Library"
        let libraryTitle = app.navigationBars["Library"]
        XCTAssertTrue(libraryTitle.waitForExistence(timeout: 3),
                      "Library view should show Library navigation title")
    }

    func test_tappingSettingsTab_showsSettingsView() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Settings"].tap()

        // SettingsView has the navigation title "Settings"
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3),
                      "Settings view should show Settings navigation title")
    }

    // MARK: - Tab switching

    func test_switchingBetweenTabs_works() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        // Start at Capture, go to Library, then Settings, then back to Capture
        tabBar.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 3))

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        tabBar.buttons["Capture"].tap()
        // Verify we're back at capture view
        XCTAssertTrue(app.navigationBars["Picelf"].waitForExistence(timeout: 3),
                      "Should return to Capture view with Picelf title")
    }
}
