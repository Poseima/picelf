import XCTest

final class PicelfUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitest-open-editor", "-ApplePersistenceIgnoreState", "YES"]
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground || app?.state == .runningBackground {
            app.terminate()
        }
        app = nil
    }

    func testAppLaunches() throws {
        throw XCTSkip("Redundant with other UI tests; launch lifecycle can be flaky in shared local runners.")
    }

    func testEditorToolbarElementsExistAndPanToolIsRemoved() throws {
        app.launch()

        let window = app.windows["Picelf — Editor"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let selectedTool = app.staticTexts["uitest.tool.selected"]
        XCTAssertTrue(selectedTool.waitForExistence(timeout: 2))
        XCTAssertTrue(textValue(of: selectedTool).lowercased().contains("none"))

        let panAvailability = app.staticTexts["uitest.tool.pan.available"]
        XCTAssertTrue(panAvailability.waitForExistence(timeout: 2))
        XCTAssertTrue(textValue(of: panAvailability).lowercased().contains("false"))

        XCTAssertTrue(app.buttons["toolbar.save"].exists)
        XCTAssertTrue(app.buttons["toolbar.copy"].exists)
        XCTAssertTrue(app.buttons["toolbar.share"].exists)
    }

    func testZoomButtonsChangeStatusText() throws {
        app.launch()

        let window = app.windows["Picelf — Editor"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let zoomDiagnostic = app.staticTexts["uitest.zoom.value"]
        XCTAssertTrue(zoomDiagnostic.waitForExistence(timeout: 2))

        let initialPercent = try XCTUnwrap(percent(from: textValue(of: zoomDiagnostic)))

        app.typeKey("=", modifierFlags: [.command])
        XCTAssertTrue(waitForDifferentPercent(in: zoomDiagnostic, from: initialPercent, timeout: 2))

        let updated = try XCTUnwrap(percent(from: textValue(of: zoomDiagnostic)))
        app.typeKey("-", modifierFlags: [.command])
        XCTAssertTrue(waitForDifferentPercent(in: zoomDiagnostic, from: updated, timeout: 2))
    }

    private func textValue(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    private func percent(from label: String) -> Int? {
        guard let value = label.split(separator: "=").last else { return nil }
        return Int(value)
    }

    private func waitForDifferentPercent(in element: XCUIElement, from old: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let current = percent(from: textValue(of: element)), current != old {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }
}
