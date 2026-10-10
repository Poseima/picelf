import XCTest
import AppKit
import SwiftUI
@testable import Picelf

@MainActor
final class EditorDirectManipulationTests: XCTestCase {
    func test_defaultToolIsNilAndPanToolRemoved() {
        let document = makeDocument()

        XCTAssertNil(document.selectedTool)
        XCTAssertFalse(EditorTool.allCases.map(\.rawValue).contains("Hand"))
    }

    func test_toggleToolUsesSharedSelectionLogic() {
        let document = makeDocument()

        document.toggleTool(.rectangle)
        XCTAssertEqual(document.selectedTool, .rectangle)

        document.toggleTool(.rectangle)
        XCTAssertNil(document.selectedTool)

        document.toggleTool(.ellipse)
        XCTAssertEqual(document.selectedTool, .ellipse)

        document.toggleTool(.ellipse)
        XCTAssertNil(document.selectedTool)
    }

    func test_editToolbarSymbolsRemainStable() {
        XCTAssertEqual(EditToolbarSymbol.undo, "arrow.uturn.backward")
        XCTAssertEqual(EditToolbarSymbol.redo, "arrow.uturn.forward")
        XCTAssertEqual(EditToolbarSymbol.delete, "trash")
        XCTAssertEqual(EditToolbarSymbol.fit, "arrow.up.left.and.down.right.magnifyingglass")
        XCTAssertEqual(EditToolbarSymbol.zoomOut, "minus.magnifyingglass")
        XCTAssertEqual(EditToolbarSymbol.zoomIn, "plus.magnifyingglass")
        XCTAssertEqual(EditToolbarSymbol.pin, "pin.fill")
        XCTAssertEqual(EditToolbarSymbol.scrollCapture, "scroll")
        XCTAssertEqual(EditToolbarSymbol.record, "record.circle")
        XCTAssertEqual(EditToolbarSymbol.ocr, "doc.viewfinder")
        XCTAssertEqual(EditToolbarSymbol.extractSubject, "person.and.background.dotted")
        XCTAssertEqual(EditToolbarSymbol.watermarkOff, "drop")
        XCTAssertEqual(EditToolbarSymbol.watermarkOn, "drop.fill")
        XCTAssertEqual(EditToolbarSymbol.cancel, "xmark")
        XCTAssertEqual(EditToolbarSymbol.confirm, "checkmark")
    }

    func test_interactionUpdateGateAcceptsFirstPoint() {
        var gate = EditorInteractionUpdateGate(minInterval: 0.02, minDistance: 2)
        XCTAssertTrue(gate.shouldAccept(point: CGPoint(x: 10, y: 10), now: 1.0))
    }

    func test_interactionUpdateGateRejectsPointInsideInterval() {
        var gate = EditorInteractionUpdateGate(minInterval: 0.02, minDistance: 2)
        XCTAssertTrue(gate.shouldAccept(point: CGPoint(x: 10, y: 10), now: 1.0))
        XCTAssertFalse(gate.shouldAccept(point: CGPoint(x: 20, y: 20), now: 1.01))
    }

    func test_interactionUpdateGateRejectsTinyMovement() {
        var gate = EditorInteractionUpdateGate(minInterval: 0.02, minDistance: 2)
        XCTAssertTrue(gate.shouldAccept(point: CGPoint(x: 10, y: 10), now: 1.0))
        XCTAssertFalse(gate.shouldAccept(point: CGPoint(x: 11, y: 10.5), now: 1.03))
    }

    func test_interactionUpdateGateAcceptsAfterIntervalAndDistance() {
        var gate = EditorInteractionUpdateGate(minInterval: 0.02, minDistance: 2)
        XCTAssertTrue(gate.shouldAccept(point: CGPoint(x: 10, y: 10), now: 1.0))
        XCTAssertTrue(gate.shouldAccept(point: CGPoint(x: 13, y: 13), now: 1.03))
    }

    func test_hitTestSelectsTopMostAndMoveWorksWithoutPanTool() throws {
        let document = makeDocument()

        document.selectedTool = .rectangle
        document.beginAnnotation(at: CGPoint(x: 20, y: 20))
        document.updateAnnotation(at: CGPoint(x: 120, y: 100))
        document.commitAnnotation()

        document.selectedTool = .ellipse
        document.beginAnnotation(at: CGPoint(x: 60, y: 50))
        document.updateAnnotation(at: CGPoint(x: 160, y: 130))
        document.commitAnnotation()

        // Overlap area should hit the most recently added (top-most) annotation.
        document.selectAnnotation(at: CGPoint(x: 80, y: 70))
        let selectedID = try XCTUnwrap(document.selectedAnnotationIDs.first)
        let selectedBeforeMove = try XCTUnwrap(document.annotations.first(where: { $0.id == selectedID }))
        XCTAssertEqual(selectedBeforeMove.kind, .ellipse)
        XCTAssertEqual(document.selectedTool, .ellipse)

        document.moveSelection(by: CGSize(width: 24, height: -12))
        document.finalizeInteractionChange()

        let selectedAfterMove = try XCTUnwrap(document.annotations.first(where: { $0.id == selectedID }))
        XCTAssertEqual(selectedAfterMove.start.x, selectedBeforeMove.start.x + 24, accuracy: 0.001)
        XCTAssertEqual(selectedAfterMove.start.y, selectedBeforeMove.start.y - 12, accuracy: 0.001)
        XCTAssertEqual(selectedAfterMove.end.x, selectedBeforeMove.end.x + 24, accuracy: 0.001)
        XCTAssertEqual(selectedAfterMove.end.y, selectedBeforeMove.end.y - 12, accuracy: 0.001)
    }

    func test_shapeToolDragLifecycleCreatesAnnotation() throws {
        let document = makeDocument()
        document.selectedTool = .highlight

        document.beginAnnotation(at: CGPoint(x: 10, y: 15))
        document.updateAnnotation(at: CGPoint(x: 80, y: 45))
        document.commitAnnotation()

        XCTAssertEqual(document.annotations.count, 1)
        let annotation = try XCTUnwrap(document.annotations.first)
        XCTAssertEqual(annotation.kind, .highlight)
        XCTAssertEqual(annotation.bounds.width, 70, accuracy: 0.001)
        XCTAssertEqual(annotation.bounds.height, 30, accuracy: 0.001)
    }

    func test_tinyShapeDraftIsDiscardedOnCommit() {
        let document = makeDocument()
        document.selectedTool = .rectangle

        document.beginAnnotation(at: CGPoint(x: 20, y: 20))
        document.updateAnnotation(at: CGPoint(x: 21, y: 21))
        document.commitAnnotation()

        XCTAssertTrue(document.annotations.isEmpty)
    }

    func test_pointToolCreatesImmediateAnnotation() throws {
        let document = makeDocument()  // 300x200 image
        document.selectedTool = .text

        document.beginAnnotation(at: CGPoint(x: 40, y: 60))

        XCTAssertEqual(document.annotations.count, 1)
        let annotation = try XCTUnwrap(document.annotations.first)
        XCTAssertEqual(annotation.kind, .text)
        XCTAssertEqual(annotation.text, "")
        // textBoxWidth clamped to available space: min(320, 300 - 40 - 8) = 252
        XCTAssertEqual(annotation.textBoxWidth, 252, accuracy: 0.001)
        XCTAssertEqual(document.editingTextID, annotation.id)
        // Text tool stays active for consecutive placement
        XCTAssertEqual(document.selectedTool, .text)
    }

    func test_stepAndStickerToolsAreOneShotAfterPlacement() throws {
        let document = makeDocument()

        document.selectedTool = .step
        document.beginAnnotation(at: CGPoint(x: 60, y: 80))
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.annotations[0].kind, .step)
        XCTAssertNil(document.selectedTool)

        document.selectedTool = .sticker
        document.beginAnnotation(at: CGPoint(x: 90, y: 120))
        XCTAssertEqual(document.annotations.count, 2)
        XCTAssertEqual(document.annotations[1].kind, .sticker)
        XCTAssertNil(document.selectedTool)
    }

    func test_emptyTextCommitRemovesTemporaryTextAnnotation() {
        let document = makeDocument()
        document.selectedTool = .text

        document.beginAnnotation(at: CGPoint(x: 40, y: 60))
        XCTAssertEqual(document.annotations.count, 1)

        document.commitTextEditing("   ")

        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertNil(document.editingTextID)
        XCTAssertTrue(document.selectedAnnotationIDs.isEmpty)
    }

    func test_multilineTextCommitPreservesNewline() throws {
        let document = makeDocument()
        document.selectedTool = .text
        document.beginAnnotation(at: CGPoint(x: 40, y: 60))

        document.commitTextEditing("line 1\nline 2")

        let annotation = try XCTUnwrap(document.annotations.first)
        XCTAssertEqual(annotation.text, "line 1\nline 2")
    }

    func test_deleteEditingTextIfEmptyRemovesEditingAnnotation() {
        let document = makeDocument()
        document.selectedTool = .text
        document.beginAnnotation(at: CGPoint(x: 40, y: 60))

        XCTAssertTrue(document.deleteEditingTextIfEmpty())
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertNil(document.editingTextID)
        XCTAssertTrue(document.selectedAnnotationIDs.isEmpty)
    }

    func test_deleteEditingTextIfEmptyReturnsFalseForNonEmptyText() throws {
        let document = makeDocument()
        document.selectedTool = .text
        document.beginAnnotation(at: CGPoint(x: 40, y: 60))
        let id = try XCTUnwrap(document.annotations.first?.id)
        document.updateText(for: id, text: "hello")

        XCTAssertFalse(document.deleteEditingTextIfEmpty())
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.editingTextID, id)
    }

    func test_commitActiveTextEditingReturnsFalseWhenNoEditingSession() {
        let document = makeDocument()

        XCTAssertFalse(document.commitActiveTextEditing())
        XCTAssertNil(document.editingTextID)
    }

    func test_commitActiveTextEditingRemovesWhitespaceOnlyText() throws {
        let document = makeDocument()
        document.selectedTool = .text
        document.beginAnnotation(at: CGPoint(x: 40, y: 60))
        let id = try XCTUnwrap(document.annotations.first?.id)
        document.updateText(for: id, text: "   ")

        XCTAssertTrue(document.commitActiveTextEditing())
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertNil(document.editingTextID)
        XCTAssertTrue(document.selectedAnnotationIDs.isEmpty)
    }

    func test_commitActiveTextEditingCommitsAndTrimsText() throws {
        let document = makeDocument()
        document.selectedTool = .text
        document.beginAnnotation(at: CGPoint(x: 40, y: 60))
        let id = try XCTUnwrap(document.annotations.first?.id)
        document.updateText(for: id, text: "  hello  ")

        XCTAssertTrue(document.commitActiveTextEditing())
        let annotation = try XCTUnwrap(document.annotations.first(where: { $0.id == id }))
        XCTAssertEqual(annotation.text, "hello")
        XCTAssertNil(document.editingTextID)
        XCTAssertEqual(document.selectedAnnotationIDs, Set([id]))
    }

    func test_activateToolForAnnotationIfSelectionModeActivatesMatchingTool() throws {
        let document = makeDocument()
        document.selectedTool = .rectangle
        document.beginAnnotation(at: CGPoint(x: 20, y: 20))
        document.updateAnnotation(at: CGPoint(x: 120, y: 100))
        document.commitAnnotation()
        let id = try XCTUnwrap(document.annotations.first?.id)
        document.selectedTool = nil

        document.activateToolForAnnotationIfSelectionMode(id)

        XCTAssertEqual(document.selectedTool, .rectangle)
    }

    func test_activateToolForAnnotationIfSelectionModeDoesNotOverrideActiveTool() throws {
        let document = makeDocument()
        document.selectedTool = .rectangle
        document.beginAnnotation(at: CGPoint(x: 20, y: 20))
        document.updateAnnotation(at: CGPoint(x: 120, y: 100))
        document.commitAnnotation()
        let id = try XCTUnwrap(document.annotations.first?.id)
        document.selectedTool = .text

        document.activateToolForAnnotationIfSelectionMode(id)

        XCTAssertEqual(document.selectedTool, .text)
    }

    func test_updateSelectedTextBoxWidthClampsAndAppliesToText() throws {
        let document = makeDocument()
        document.selectedTool = .text
        document.beginAnnotation(at: CGPoint(x: 40, y: 60))
        document.commitTextEditing("hello world")
        let id = try XCTUnwrap(document.annotations.first?.id)
        document.selectedAnnotationIDs = [id]

        document.updateSelectedTextBoxWidth(4_000)

        let annotation = try XCTUnwrap(document.annotations.first)
        XCTAssertEqual(annotation.textBoxWidth, 1_200, accuracy: 0.001)
        XCTAssertEqual(document.preferredTextBoxWidth, 1_200, accuracy: 0.001)
    }

    func test_tooltipsAreSingleLineForToolbarButtons() {
        for tool in EditorTool.allCases {
            let tooltip = EditorTooltipProvider.text(for: .tool(tool))
            XCTAssertFalse(tooltip.contains("\n"), "Tool tooltip should be single-line: \(tool.rawValue)")
        }

        let toolbarKeys: [EditorTooltipKey] = [
            .undo, .redo, .delete, .fit, .zoomOut, .zoomIn, .actualSize,
            .zoomPercent, .save, .copy, .share
        ]
        for key in toolbarKeys {
            let tooltip = EditorTooltipProvider.text(for: key)
            XCTAssertFalse(tooltip.contains("\n"), "Toolbar tooltip should be single-line: \(key)")
        }
    }

    func test_compositorPreservesTopLeftAnnotationCoordinates() throws {
        let base = makeSolidImage(width: 120, height: 100, color: .white)
        let annotation = EditorAnnotation(
            kind: .rectangle,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 50, y: 40),
            color: .red,
            lineWidth: 2,
            fillColor: .red
        )

        let output = try XCTUnwrap(
            EditorCompositor.compose(
                baseImage: base,
                imageSize: CGSize(width: 120, height: 100),
                annotations: [annotation],
                draft: nil
            )
        )

        let topSample = try XCTUnwrap(sampleRGBAAtPoint(output, pointTopLeft: CGPoint(x: 25, y: 25)))
        XCTAssertLessThan(topSample.g, 245, "Top area should contain red fill")
        XCTAssertLessThan(topSample.b, 245, "Top area should contain red fill")

        let bottomSample = try XCTUnwrap(sampleRGBAAtPoint(output, pointTopLeft: CGPoint(x: 25, y: 75)))
        XCTAssertGreaterThan(bottomSample.g, 245, "Bottom area should remain white")
        XCTAssertGreaterThan(bottomSample.b, 245, "Bottom area should remain white")
    }

    private func makeDocument(width: Int = 300, height: Int = 200) -> EditorDocument {
        let suiteName = "com.picelf.tests.editordoc.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = AppPreferences(defaults: defaults)
        return EditorDocument(
            baseImage: makeUniqueRowImage(width: width, height: height),
            prefs: prefs
        )
    }

    private func makeSolidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        makeStripedImage(
            width: width,
            height: height,
            stripeHeight: max(1, height),
            colors: [color]
        )
    }

    private func sampleRGBAAtPoint(_ image: NSImage, pointTopLeft: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width
        let height = cg.height
        let scaleX = CGFloat(width) / max(1, image.size.width)
        let scaleY = CGFloat(height) / max(1, image.size.height)
        let x = Int((pointTopLeft.x * scaleX).rounded())
        let yTop = Int((pointTopLeft.y * scaleY).rounded())
        guard x >= 0, x < width, yTop >= 0, yTop < height else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let index = yTop * bytesPerRow + x * 4
        return (
            r: pixels[index],
            g: pixels[index + 1],
            b: pixels[index + 2],
            a: pixels[index + 3]
        )
    }
}
