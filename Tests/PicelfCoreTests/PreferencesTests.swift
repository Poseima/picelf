import XCTest
import AppKit
@testable import Picelf

final class PreferencesTests: XCTestCase {
    private var prefs: AppPreferences!
    private let suiteName = "com.picelf.tests.\(UUID().uuidString)"

    override func setUp() {
        let defaults = UserDefaults(suiteName: suiteName)!
        prefs = AppPreferences(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func test_settingsWindowResizesWithoutMovingItsTopEdge() throws {
        let existingWindows = Set(NSApplication.shared.windows.map(\.windowNumber))
        let controller = PreferencesWindowController()
        controller.show(tab: .general)
        let window = try XCTUnwrap(NSApplication.shared.windows.first {
            !existingWindows.contains($0.windowNumber)
        })
        defer { window.orderOut(nil) }
        let top = window.frame.maxY
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 760, accuracy: 1)
        for tab in [PreferencesTab.capture, .translation, .shortcuts, .general] {
            controller.show(tab: tab)
            XCTAssertEqual(window.frame.maxY, top, accuracy: 1)
            XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 760, accuracy: 1)
            XCTAssertGreaterThan(window.contentRect(forFrameRect: window.frame).height, 300)
        }
        window.orderOut(nil)
        controller.show()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 1)
    }

    func test_defaultValues() {
        XCTAssertEqual(prefs.defaultFormat, .png)
        XCTAssertEqual(prefs.jpegQuality, 0.9)
        XCTAssertEqual(prefs.editorToolState.exportFormat, .png)
        XCTAssertEqual(prefs.editorToolState.jpegQuality, 0.9, accuracy: 0.001)
        XCTAssertEqual(prefs.editorToolState.textBoxWidth, 320, accuracy: 0.001)
        XCTAssertNil(prefs.editorToolState.selectedToolRaw)
        XCTAssertTrue(prefs.autoSnapToWindows)
        XCTAssertFalse(prefs.cacheFramesToDisk)
        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.captureRetentionUnit, .days)
        XCTAssertEqual(prefs.captureRetentionValue, 10)
        XCTAssertEqual(prefs.captureRetentionInterval, 10 * 24 * 3600, accuracy: 0.001)
        XCTAssertEqual(prefs.translationTargetPreference, .followAppLanguage)
        XCTAssertEqual(prefs.translationLastUsedTargetLanguage, .english)
        XCTAssertEqual(prefs.translationOverlayMode, .hover)
        XCTAssertTrue(prefs.translationAutoRunFromSnapEdit)
        XCTAssertEqual(prefs.translationExportFormatPreference, .matchSource)
        XCTAssertTrue(prefs.presets.isEmpty)
    }

    func test_persistenceRoundTrip() {
        prefs.defaultFormat = .jpeg
        prefs.jpegQuality = 0.75
        prefs.autoSnapToWindows = false
        prefs.translationTargetPreference = .lastUsed
        prefs.translationLastUsedTargetLanguage = .japanese
        prefs.translationOverlayMode = .replace
        prefs.translationAutoRunFromSnapEdit = false
        prefs.translationExportFormatPreference = .png
        prefs.updateEditorToolState { state in
            state.recordToolSelection(rawValue: "Mosaic")
            state.lineWidth = 9
            state.textBoxWidth = 420
            state.mosaicBlockSize = 22
        }

        let prefs2 = AppPreferences(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(prefs2.defaultFormat, .jpeg)
        XCTAssertEqual(prefs2.jpegQuality, 0.75)
        XCTAssertFalse(prefs2.autoSnapToWindows)
        XCTAssertEqual(prefs2.translationTargetPreference, .lastUsed)
        XCTAssertEqual(prefs2.translationLastUsedTargetLanguage, .japanese)
        XCTAssertEqual(prefs2.translationOverlayMode, .replace)
        XCTAssertFalse(prefs2.translationAutoRunFromSnapEdit)
        XCTAssertEqual(prefs2.translationExportFormatPreference, .png)
        XCTAssertEqual(prefs2.editorToolState.selectedToolRaw, "Mosaic")
        XCTAssertEqual(prefs2.editorToolState.lineWidth, 9, accuracy: 0.001)
        XCTAssertEqual(prefs2.editorToolState.textBoxWidth, 420, accuracy: 0.001)
        XCTAssertEqual(prefs2.editorToolState.mosaicBlockSize, 22, accuracy: 0.001)
    }

    func test_legacyExportSettingsMigrateToEditorToolState() {
        let migrationSuite = "com.picelf.tests.migrate.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: migrationSuite) }

        let defaults = UserDefaults(suiteName: migrationSuite)!
        defaults.set(ImageFormat.jpeg.rawValue, forKey: "defaultFormat")
        defaults.set(0.42, forKey: "jpegQuality")

        let migrated = AppPreferences(defaults: defaults)
        XCTAssertEqual(migrated.editorToolState.exportFormat, .jpeg)
        XCTAssertEqual(migrated.editorToolState.jpegQuality, 0.42, accuracy: 0.001)

        migrated.updateEditorToolState { state in
            state.exportFormat = .png
            state.jpegQuality = 0.88
        }
        XCTAssertEqual(migrated.defaultFormat, .png)
        XCTAssertEqual(migrated.jpegQuality, 0.88, accuracy: 0.001)
    }

    func test_presetCRUD() {
        let preset = RegionPreset(name: "Full Width", width: 1920, height: 1080)
        prefs.addPreset(preset)
        XCTAssertEqual(prefs.presets.count, 1)
        XCTAssertEqual(prefs.presets.first?.name, "Full Width")

        var updated = preset
        updated.name = "HD"
        prefs.updatePreset(updated)
        XCTAssertEqual(prefs.presets.first?.name, "HD")

        prefs.removePreset(id: preset.id)
        XCTAssertTrue(prefs.presets.isEmpty)
    }

    func test_captureRetentionRoundTripAndClamp() {
        prefs.captureRetentionUnit = .seconds
        prefs.captureRetentionValue = 999_999

        let reloaded = AppPreferences(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(reloaded.captureRetentionUnit, .seconds)
        XCTAssertEqual(reloaded.captureRetentionValue, 86_400)
        XCTAssertEqual(reloaded.captureRetentionInterval, 86_400, accuracy: 0.001)
    }

    func test_captureRetentionIntervalConvertsByUnit() {
        prefs.captureRetentionUnit = .seconds
        prefs.captureRetentionValue = 3
        XCTAssertEqual(prefs.captureRetentionInterval, 3, accuracy: 0.001)

        prefs.captureRetentionUnit = .hours
        prefs.captureRetentionValue = 2
        XCTAssertEqual(prefs.captureRetentionInterval, 7_200, accuracy: 0.001)

        prefs.captureRetentionUnit = .days
        prefs.captureRetentionValue = 4
        XCTAssertEqual(prefs.captureRetentionInterval, 345_600, accuracy: 0.001)
    }
}
