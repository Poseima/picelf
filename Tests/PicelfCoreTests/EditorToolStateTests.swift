import XCTest
@testable import Picelf

final class EditorToolStateTests: XCTestCase {
    func test_defaultStateUsesExpectedDefaults() {
        let state = EditorToolState.defaultState()

        XCTAssertEqual(state.schemaVersion, EditorToolState.currentSchemaVersion)
        XCTAssertNil(state.selectedToolRaw)
        XCTAssertTrue(state.toolRecencyRaw.isEmpty)
        XCTAssertEqual(state.lineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(state.textFontSize, 18, accuracy: 0.001)
        XCTAssertEqual(state.textBoxWidth, 320, accuracy: 0.001)
        XCTAssertEqual(state.mosaicBlockSize, 14, accuracy: 0.001)
        XCTAssertEqual(state.selectedSticker, "★")
        XCTAssertEqual(state.exportFormat, .png)
        XCTAssertEqual(state.jpegQuality, 0.9, accuracy: 0.001)
        XCTAssertTrue(state.strokeColor.approximatelyEquals(EditorToolState.defaultStrokeColor))
        XCTAssertTrue(state.fillColor.approximatelyEquals(EditorToolState.defaultFillColor))
    }

    func test_recordToolSelectionMovesToolToFrontWithoutDuplication() {
        var state = EditorToolState.defaultState()

        state.recordToolSelection(rawValue: "Rect")
        state.recordToolSelection(rawValue: "Mosaic")
        state.recordToolSelection(rawValue: "Rect")

        XCTAssertEqual(state.selectedToolRaw, "Rect")
        XCTAssertEqual(state.toolRecencyRaw.prefix(2), ["Rect", "Mosaic"])
    }

    func test_snapEditDoesNotAutoResolveTool() {
        var state = EditorToolState.defaultState()
        state.recordToolSelection(rawValue: "Mosaic")
        state.recordToolSelection(rawValue: "Sticker")

        let resolved = state.resolvedSelectedToolRaw(for: .snapEdit)
        XCTAssertNil(resolved)
    }

    func test_fullEditorDoesNotAutoResolveTool() {
        var state = EditorToolState.defaultState()
        state.recordToolSelection(rawValue: "Rect")
        state.recordToolSelection(rawValue: "Mosaic")

        XCTAssertNil(state.resolvedSelectedToolRaw(for: .fullEditor))
    }

    func test_canvasContextHasNoResolvedTool() {
        var state = EditorToolState.defaultState()
        state.recordToolSelection(rawValue: "Rect")

        XCTAssertNil(state.resolvedSelectedToolRaw(for: .canvasExportOnly))
    }

    func test_sanitizedClampsAndDropsUnknownTools() {
        let state = EditorToolState(
            schemaVersion: 999,
            selectedToolRaw: "Unknown",
            toolRecencyRaw: ["Unknown", "Rect", "Rect", "Mosaic"],
            strokeColor: EditorToolState.defaultStrokeColor,
            fillColor: CodableColor(color: .clear),
            lineWidth: 100,
            textFontSize: -2,
            textBoxWidth: 3_000,
            mosaicBlockSize: 100,
            selectedSticker: "  ",
            exportFormat: .jpeg,
            jpegQuality: 3
        ).sanitized()

        XCTAssertEqual(state.schemaVersion, EditorToolState.currentSchemaVersion)
        XCTAssertNil(state.selectedToolRaw)
        XCTAssertEqual(state.toolRecencyRaw, ["Rect", "Mosaic"])
        XCTAssertEqual(state.lineWidth, 24, accuracy: 0.001)
        XCTAssertEqual(state.textFontSize, 12, accuracy: 0.001)
        XCTAssertEqual(state.textBoxWidth, 1_200, accuracy: 0.001)
        XCTAssertEqual(state.mosaicBlockSize, 40, accuracy: 0.001)
        XCTAssertEqual(state.jpegQuality, 1.0, accuracy: 0.001)
        XCTAssertEqual(state.selectedSticker, "★")
    }

    func test_sanitizedMigratesLegacyDefaultStrokeColorToEmerald() {
        let migrated = EditorToolState(
            schemaVersion: 1,
            selectedToolRaw: nil,
            toolRecencyRaw: [],
            strokeColor: CodableColor(color: .cyan),
            fillColor: CodableColor(color: .clear),
            lineWidth: EditorToolState.defaultLineWidth,
            textFontSize: EditorToolState.defaultTextFontSize,
            textBoxWidth: EditorToolState.defaultTextBoxWidth,
            mosaicBlockSize: EditorToolState.defaultMosaicBlockSize,
            selectedSticker: EditorToolState.defaultSticker,
            exportFormat: .png,
            jpegQuality: 0.9
        ).sanitized()

        XCTAssertEqual(migrated.schemaVersion, EditorToolState.currentSchemaVersion)
        XCTAssertTrue(migrated.strokeColor.approximatelyEquals(EditorToolState.defaultStrokeColor))
    }

    func test_sanitizedPreservesCustomizedStrokeColorDuringMigration() {
        let custom = CodableColor(color: .red)
        let migrated = EditorToolState(
            schemaVersion: 1,
            selectedToolRaw: nil,
            toolRecencyRaw: [],
            strokeColor: custom,
            fillColor: CodableColor(color: .clear),
            lineWidth: EditorToolState.defaultLineWidth,
            textFontSize: EditorToolState.defaultTextFontSize,
            textBoxWidth: EditorToolState.defaultTextBoxWidth,
            mosaicBlockSize: EditorToolState.defaultMosaicBlockSize,
            selectedSticker: EditorToolState.defaultSticker,
            exportFormat: .png,
            jpegQuality: 0.9
        ).sanitized()

        XCTAssertEqual(migrated.schemaVersion, EditorToolState.currentSchemaVersion)
        XCTAssertTrue(migrated.strokeColor.approximatelyEquals(custom))
    }
}
