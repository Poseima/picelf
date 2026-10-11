import XCTest
import AppKit

/// Explicit opt-in only. Run against a signed Debug build and isolated fixtures.
final class WorkbenchUITests: XCTestCase {
    private var app: XCUIApplication!
    private var suite: String!
    private var window: XCUIElement { app.windows["workbench.window"] }
    private var tiles: XCUIElementQuery { window.descendants(matching: .group).matching(NSPredicate(format: "identifier BEGINSWITH 'workbench.image.'")) }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1",
                          "Workbench UI tests require explicit opt-in and a signed Debug build.")
        continueAfterFailure = false
        suite = "com.picelf.workbench.uitest.\(UUID())"
        app = XCUIApplication()
        app.launchArguments = ["--uitest-open-workbench", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PICELF_RUN_LIVE_TESTS"] = "1"
        app.launchEnvironment["PICELF_UI_TEST_PREFERENCES_SUITE"] = suite
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws {
        app?.terminate()
        if let suite { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    private func click(_ tile: XCUIElement, right: Bool = false) {
        let point = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        if right { point.rightClick() } else { point.click() }
    }
    private func waitForCount(_ count: Int) {
        let predicate = NSPredicate { [self] _, _ in tiles.count == count }
        expectation(for: predicate, evaluatedWith: app)
        waitForExpectations(timeout: 5)
    }
    private func clipboardBitmap() throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(NSPasteboard.general.data(forType: .png))))
    }

    private func pixels(_ data: Data) throws -> Data {
        let image = try XCTUnwrap(NSBitmapImageRep(data: data)?.cgImage)
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }

    func testRealCopyPasteAndSearchFieldPrecedence() throws {
        click(tiles.firstMatch)
        app.typeKey("c", modifierFlags: .command)
        let original = try XCTUnwrap(NSPasteboard.general.data(forType: .png))
        let bitmap = try clipboardBitmap()
        XCTAssertGreaterThan(bitmap.pixelsHigh, 1000) // Full result, not gallery thumbnail.
        app.typeKey("v", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        waitForCount(3)
        click(tiles.firstMatch)
        app.typeKey("c", modifierFlags: .command)
        XCTAssertEqual(try XCTUnwrap(NSPasteboard.general.data(forType: .png)), original)

        let search = app.textFields["workbench.search"]
        search.click()
        search.typeText("Native text")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Native text")
        app.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(search.value as? String, "Native text")
        XCTAssertEqual(tiles.count, 0)
    }

    func testExternalImagePasteClearsFiltersAndSaveUsesContextTarget() throws {
        let board = NSPasteboard.general
        click(tiles.firstMatch)
        app.typeKey("c", modifierFlags: .command)
        let originalData = try XCTUnwrap(board.data(forType: .png))
        let external = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 127, pixelsHigh: 3001,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 508, bitsPerPixel: 32)!
        memset(external.bitmapData!, 0, external.bytesPerRow * external.pixelsHigh)
        board.clearContents()
        board.setData(external.representation(using: .png, properties: [:])!, forType: .png)
        app.buttons["Pin Library"].click()
        window.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7)).click()
        app.typeKey("v", modifierFlags: .command)
        waitForCount(2)
        click(tiles.firstMatch)
        app.typeKey("c", modifierFlags: .command)
        XCTAssertEqual(try clipboardBitmap().pixelsWide, 127)
        XCTAssertEqual(try clipboardBitmap().pixelsHigh, 3001)
        XCTAssertEqual(try clipboardBitmap().colorAt(x: 20, y: 20)?.alphaComponent, 0)

        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let before = Set(try FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil))
        click(tiles.element(boundBy: 1), right: true) // Save older fixture while external image remains selected.
        app.menuItems["Save to Downloads"].click()
        XCTAssertTrue(app.buttons["workbench.showSavedInFinder"].waitForExistence(timeout: 3))
        let after = Set(try FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil))
        let file = try XCTUnwrap(after.subtracting(before).first { $0.lastPathComponent.hasPrefix("Picelf-") })
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try pixels(Data(contentsOf: file)), try pixels(originalData))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "workbench-download-feedback"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.typeKey(",", modifierFlags: .command)
        app.popUpButtons["preferences.language"].click()
        app.menuItems["中文"].click()
        app.windows["preferences.window"].buttons[XCUIIdentifierCloseWindow].click()
        click(tiles.firstMatch, right: true)
        XCTAssertTrue(app.menuItems["保存到下载"].waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }
}
