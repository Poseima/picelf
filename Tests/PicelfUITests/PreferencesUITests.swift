import XCTest

/// Run only with PICELF_RUN_LIVE_TESTS=1 in a signed Debug test scheme.
final class PreferencesUITests: XCTestCase {
    private var app: XCUIApplication!
    private var preferencesSuite: String!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1",
                         "Settings UI tests require an explicitly enabled, signed desktop test run.")
        continueAfterFailure = false
        preferencesSuite = "com.picelf.preferences.uitests.\(UUID().uuidString)"
        app = XCUIApplication()
        app.launchArguments = ["--uitest-open-preferences", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PICELF_UI_TEST_PREFERENCES_SUITE"] = preferencesSuite
        app.launchEnvironment["PICELF_UI_TEST_PREFERENCES_FIXTURES"] = "1"
        app.launch()
        XCTAssertTrue(categoryTitle("general").waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground || app?.state == .runningBackground { app.terminate() }
        if let preferencesSuite {
            UserDefaults(suiteName: preferencesSuite)?.removePersistentDomain(forName: preferencesSuite)
        }
        app = nil
    }

    func test_categoryClicksChangeContentAndKeepWindowFrame() throws {
        let window = app.windows["preferences.window"]
        let frame = window.frame
        let categories = ["capture", "translation", "shortcuts", "general"]
        for category in categories + categories.reversed() {
            app.buttons["preferences.tab.\(category)"].click()
            XCTAssertTrue(categoryTitle(category).waitForExistence(timeout: 2))
            for other in categories where other != category {
                XCTAssertFalse(categoryTitle(other).exists)
            }
            XCTAssertEqual(window.frame, frame)
            attachPreview(window, name: "settings-en-\(category)")
        }

        app.buttons["preferences.tab.translation"].click()
        XCTAssertTrue(app.popUpButtons["preferences.translationTarget"].exists)
        window.buttons[XCUIIdentifierCloseWindow].click()
        app.typeKey(",", modifierFlags: [.command])
        // The system command reopens the same window and preserves category.
        XCTAssertTrue(categoryTitle("translation").waitForExistence(timeout: 3))
        XCTAssertEqual(window.frame, frame)
        XCTAssertTrue(app.buttons["preferences.tab.capture"].waitForExistence(timeout: 3))
        app.buttons["preferences.tab.capture"].click()
        XCTAssertTrue(categoryTitle("capture").waitForExistence(timeout: 2))
    }

    func test_languageSwitchKeepsNavigationWorking() throws {
        let picker = app.popUpButtons["preferences.language"]
        picker.click()
        app.menuItems["中文"].click()
        XCTAssertTrue(textValue(of: categoryTitle("general")).hasPrefix("通用"))

        for category in ["translation", "shortcuts", "capture", "general"] {
            app.buttons["preferences.tab.\(category)"].click()
            XCTAssertTrue(categoryTitle(category).waitForExistence(timeout: 2))
            attachPreview(app.windows["preferences.window"],
                          name: "settings-zh-\(category)")
        }
        picker.click()
        app.menuItems["English"].click()
        XCTAssertTrue(textValue(of: categoryTitle("general")).hasPrefix("General"))
        app.buttons["preferences.tab.translation"].click()
        XCTAssertTrue(categoryTitle("translation").waitForExistence(timeout: 2))
    }

    func test_minimumWindowHandlesExpandedSettingsAndLongPresetList() throws {
        let window = app.windows["preferences.window"]
        let originalFrame = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -3, dy: -3))
        corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -160, dy: -160)))
        XCTAssertGreaterThanOrEqual(window.frame.width, 820)
        XCTAssertLessThan(window.frame.width, originalFrame.width)
        XCTAssertTrue(app.sliders["preferences.jpegQuality"].exists)
        attachPreview(window, name: "settings-minimum-general")

        let resizedFrame = window.frame
        for category in ["translation", "shortcuts", "capture"] {
            app.buttons["preferences.tab.\(category)"].click()
            XCTAssertTrue(categoryTitle(category).waitForExistence(timeout: 2))
            XCTAssertEqual(window.frame, resizedFrame)
            attachPreview(window, name: "settings-minimum-\(category)")
        }
        let lastPreset = app.buttons["Remove Research capture region 20"]
        for _ in 0..<6 where !lastPreset.isHittable {
            window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        }
        XCTAssertTrue(lastPreset.isHittable)
        XCTAssertEqual(window.frame, resizedFrame)
        attachPreview(window, name: "settings-minimum-presets-scrolled")
    }

    func test_keyboardFocusActivatesCategories() throws {
        app.buttons["preferences.tab.general"].click()
        app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(categoryTitle("shortcuts").waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(categoryTitle("capture").waitForExistence(timeout: 2))
    }

    func test_softwareUpdateCardDoesNotStartUpdaterInTestHost() throws {
        let card = app.descendants(matching: .any)["preferences.softwareUpdates"]
        XCTAssertTrue(card.exists)
        let check = app.buttons["preferences.checkForUpdates"]
        let window = app.windows["preferences.window"]
        let version = app.descendants(matching: .any)["preferences.updateVersion"]
        XCTAssertTrue(version.exists)
        XCTAssertTrue(version.isHittable)
        XCTAssertGreaterThan(version.frame.width, 50)
        XCTAssertFalse(check.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["preferences.updateDownloads"].exists)
        attachPreview(window, name: "settings-software-update-card")
    }

    private func attachPreview(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func categoryTitle(_ category: String) -> XCUIElement {
        app.descendants(matching: .any)["preferences.title.\(category)"]
    }

    private func textValue(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }
}
