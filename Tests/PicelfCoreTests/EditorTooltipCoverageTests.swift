import XCTest
@testable import Picelf

final class EditorTooltipCoverageTests: XCTestCase {
    func test_allEditorToolsHaveTooltipText() {
        for tool in EditorTool.allCases {
            let text = EditorTooltipProvider.text(for: .tool(tool)).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(text.isEmpty, "Missing tooltip for tool: \(tool.rawValue)")
        }
    }

    func test_coreToolbarTooltipsAreNonEmpty() {
        let keys: [EditorTooltipKey] = [
            .stickerPicker,
            .undo,
            .redo,
            .delete,
            .fit,
            .zoomOut,
            .zoomIn,
            .actualSize,
            .zoomPercent,
            .save,
            .copy,
            .share,
            .translate,
            .watermark
        ]

        for key in keys {
            let text = EditorTooltipProvider.text(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(text.isEmpty, "Missing tooltip for key: \(key)")
        }
    }

    func test_keyInspectorAndStatusTooltipsAreNonEmpty() {
        let keys: [EditorTooltipKey] = [
            .inspector,
            .summaryTool,
            .summaryAnnotations,
            .summaryImage,
            .strokeColor,
            .fillColor,
            .lineWidth,
            .textSize,
            .textWidth,
            .replaceSticker,
            .mosaicBlock,
            .exportFormat,
            .jpegQuality,
            .translationTarget,
            .translationOverlay,
            .translationCopy,
            .translationExport,
            .statusZoom,
            .statusCanvas,
            .statusSelected
        ]

        for key in keys {
            let text = EditorTooltipProvider.text(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(text.isEmpty, "Missing tooltip for key: \(key)")
        }
    }
}
