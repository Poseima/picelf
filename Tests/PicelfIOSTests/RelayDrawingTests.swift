import XCTest
import UIKit
import PencilKit
@testable import Picelf

@MainActor
final class RelayDrawingTests: XCTestCase {
    func testPencilKitInkSurvivesSaveAndOriginalResolutionExport() throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let cg = try XCTUnwrap(TestHelpers.makeSolidColorImage(width: 120, height: 80, color: UIColor.white.cgColor))
        let png = try RelayImage.png(cg)
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "Pencil test", origin: .mac, width: 120, height: 80)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png))
        hub.beginEditing(task.id)
        let model = try RelayDrawingModel(task: task, hub: hub)
        let points = [CGPoint(x: 15, y: 40), CGPoint(x: 105, y: 40)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: TimeInterval(index) * 0.1,
                          size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        model.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: path)])
        model.changed(); model.flush(); model.pause()
        let restoredTask = try XCTUnwrap(hub.task(task.id))
        let restored = try RelayDrawingModel(task: restoredTask, hub: hub)
        XCTAssertEqual(restored.canvas.drawing.strokes.count, 1)
        XCTAssertGreaterThan(restored.canvas.drawing.bounds.width, 80)
        let result = try XCTUnwrap(restored.render().cgImage)
        XCTAssertEqual(result.width, 120); XCTAssertEqual(result.height, 80)
        let bytes = pixel(result, x: 60, y: 40)
        XCTAssertGreaterThan(bytes.0, 200)
        XCTAssertLessThan(bytes.1, 100, "Middle of red stroke should not be white")
        let corner = pixel(result, x: 2, y: 2)
        XCTAssertGreaterThan(corner.1, 200, "Base image must still be visible")
        XCTAssertEqual(restored.canvas.overrideUserInterfaceStyle, .light)
    }
    func testPreviewScalesDownWithoutChangingCanvasOrFinalSize() throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let cg = try XCTUnwrap(TestHelpers.makeSolidColorImage(width: 2400, height: 800))
        let png = try RelayImage.png(cg)
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "Wide image", origin: .mac, width: 2400, height: 800)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png))
        let model = try RelayDrawingModel(task: task, hub: hub)
        let preview = model.render(scale: 0.5)
        XCTAssertEqual(preview.cgImage?.width, 1200)
        XCTAssertEqual(model.render().cgImage?.width, 2400)
        XCTAssertEqual(model.pixelSize.width, 2400)
    }
    func testBackgroundExportMatchesLegacyPixelsAndReportsPreviewTiming() async throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let cg = try XCTUnwrap(TestHelpers.makeSolidColorImage(width: 2400, height: 1600, color: UIColor.white.cgColor))
        let png = try RelayImage.png(cg)
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "Timing", origin: .mac, width: 2400, height: 1600)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png))
        let model = try RelayDrawingModel(task: task, hub: hub)
        let points = [CGPoint(x: 200, y: 300), CGPoint(x: 2100, y: 700)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 20, height: 20), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        model.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        var legacyMS = 0.0, snapshotMS = 0.0, pipelineMS = 0.0
        let scale = 2048.0 / 2400.0
        for _ in 0..<5 {
            let start = CACurrentMediaTime()
            _ = try XCTUnwrap(model.render(scale: scale).pngData())
            legacyMS += (CACurrentMediaTime() - start) * 1000
            let nextStart = CACurrentMediaTime()
            _ = try await model.encoded(drawing: model.canvas.drawing, scale: scale)
            pipelineMS += (CACurrentMediaTime() - nextStart) * 1000
            snapshotMS += model.snapshotMilliseconds
        }
        print("RELAY_PREVIEW_TIMING legacy_main_ms=\(legacyMS / 5) snapshot_main_ms=\(snapshotMS / 5) new_total_ms=\(pipelineMS / 5)")
        model.texts = RelayTextDocument(boxes: (0..<5).map { index in
            RelayTextBox(text: "PPT review 中文标注与多行说明\nEditable notes", x: 120, y: Double(100 + index * 220), width: 900, fontSize: 48)
        })
        snapshotMS = 0; pipelineMS = 0
        for _ in 0..<5 {
            let start = CACurrentMediaTime()
            _ = try await model.encoded(drawing: model.canvas.drawing, scale: scale)
            pipelineMS += (CACurrentMediaTime() - start) * 1000; snapshotMS += model.snapshotMilliseconds
        }
        print("RELAY_TEXT_PREVIEW_TIMING boxes=5 snapshot_main_ms=\(snapshotMS / 5) total_ms=\(pipelineMS / 5)")
        let exported = try await model.encoded(drawing: model.canvas.drawing)
        let actual = try XCTUnwrap(UIImage(data: exported)?.cgImage)
        let expected = try XCTUnwrap(model.render().cgImage)
        XCTAssertEqual(actual.width, 2400); XCTAssertEqual(actual.height, 1600)
        for (x, y) in [(2, 2), (1150, 500), (1150, 1100)] {
            let a = pixel(actual, x: x, y: y), b = pixel(expected, x: x, y: y)
            XCTAssertLessThanOrEqual(abs(Int(a.0) - Int(b.0)), 2); XCTAssertLessThanOrEqual(abs(Int(a.1) - Int(b.1)), 2)
        }
    }
    func testSaveFailureKeepsInkAndCanRetry() throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let png = try RelayImage.png(XCTUnwrap(TestHelpers.makeSolidColorImage(width: 120, height: 80)))
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "Draft", origin: .mac, width: 120, height: 80)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png)); hub.beginEditing(task.id)
        let model = try RelayDrawingModel(task: task, hub: hub)
        let folder = directory.appendingPathComponent(task.id.uuidString)
        try FileManager.default.removeItem(at: folder)
        try Data().write(to: folder) // Simulate an unwritable task directory without changing system permissions.
        XCTAssertFalse(model.flush())
        XCTAssertEqual(hub.task(task.id)?.state, .editing)
        try FileManager.default.removeItem(at: folder)
        XCTAssertTrue(model.flush())
    }
    func testViewportCentersAndPreservesZoomOnResize() throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let png = try RelayImage.png(XCTUnwrap(TestHelpers.makeSolidColorImage(width: 1200, height: 800)))
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "Viewport", origin: .mac, width: 1200, height: 800)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png))
        let model = try RelayDrawingModel(task: task, hub: hub)
        let host = RelayCanvasHost(model: model)
        let delegate = RelayDrawingCanvas.Coordinator(model: model)
        delegate.content = host.content; host.scroll.delegate = delegate
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 600); host.layoutIfNeeded()
        XCTAssertEqual(host.scroll.contentInset.top, 100, accuracy: 1)
        host.scroll.setZoomScale(1.5, animated: false)
        host.frame.size = CGSize(width: 800, height: 500); host.layoutIfNeeded()
        XCTAssertEqual(host.scroll.zoomScale, 1.5, accuracy: 0.01)
    }
    func testEditableTextRestoresAndExportMatchesScreenLayout() async throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let png = try RelayImage.png(XCTUnwrap(TestHelpers.makeSolidColorImage(width: 640, height: 480, color: UIColor.white.cgColor)))
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "Text", origin: .mac, width: 640, height: 480)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png)); hub.beginEditing(task.id)
        let model = try RelayDrawingModel(task: task, hub: hub)
        defer { model.pause() }
        let box = RelayTextBox(text: "中文 PPT\nReview 2026", x: 70, y: 60, width: 240, fontSize: 32, bold: true, color: .emerald, background: true)
        model.replaceTexts(.init(boxes: [box]))
        XCTAssertTrue(model.flush())
        let restored = try RelayDrawingModel(task: XCTUnwrap(hub.task(task.id)), hub: hub)
        defer { restored.pause() }
        XCTAssertEqual(restored.texts.boxes, [box])
        XCTAssertTrue(restored.canvas.drawing.strokes.isEmpty)
        let expected = try XCTUnwrap(restored.render().cgImage)
        let exported = try await restored.encoded(drawing: restored.canvas.drawing)
        let actual = try XCTUnwrap(UIImage(data: exported)?.cgImage)
        XCTAssertEqual(actual.width, 640); XCTAssertEqual(actual.height, 480)
        var inkPixels = 0
        for y in stride(from: 60, to: 180, by: 3) {
            for x in stride(from: 70, to: 310, by: 3) {
                let a = pixel(actual, x: x, y: y), b = pixel(expected, x: x, y: y)
                XCTAssertLessThanOrEqual(abs(Int(a.0) - Int(b.0)), 2)
                if a.0 < 100 && a.1 > 80 { inkPixels += 1 }
            }
        }
        XCTAssertGreaterThan(inkPixels, 20, "Export must actually contain the text")
        var narrow = box; narrow.width = 100
        XCTAssertGreaterThan(RelayTextLayout.frame(narrow).height, RelayTextLayout.frame(box).height)
    }
    func testMarkedInputIsNotSavedUntilCommitted() throws {
        let directory = TestHelpers.makeTemporaryDirectory()
        defer { TestHelpers.removeTemporaryDirectory(directory) }
        let png = try RelayImage.png(XCTUnwrap(TestHelpers.makeSolidColorImage(width: 640, height: 480)))
        let hub = RelayCoordinator(role: .iPad, directory: directory, startTransport: { _ in })
        let task = RelayTask(title: "IME", origin: .mac, width: 640, height: 480)
        hub.receive(.init(kind: .task, taskID: task.id, task: task, image: png)); hub.beginEditing(task.id)
        let model = try RelayDrawingModel(task: task, hub: hub)
        let host = RelayCanvasHost(model: model)
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 480); host.layoutIfNeeded()
        model.chooseText(); model.addText(at: CGPoint(x: 60, y: 60), zoom: 1); host.textOverlay.refresh()
        let input = try XCTUnwrap(host.textOverlay.subviews.compactMap { $0 as? RelayTextItemView }.first?.textView)
        input.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
        host.textOverlay.textViewDidChange(input)
        XCTAssertTrue(model.hasMarkedText)
        XCTAssertEqual(model.texts.boxes.first?.text, "")
        XCTAssertTrue(model.flush())
        XCTAssertEqual(try RelayTextDocument.decode(hub.data(task.id, RelayTextDocument.filename)).boxes.first?.text, "")
        input.unmarkText(); input.text = "中文"; host.textOverlay.textViewDidChange(input)
        XCTAssertFalse(model.hasMarkedText); XCTAssertEqual(model.texts.boxes.first?.text, "中文")
        host.textOverlay.finishEditing(); model.pause()
    }
    func testTextValidationAndOldPacketCompatibility() throws {
        let legacy = RelayPacket(kind: .accepted, taskID: UUID(), liveVersion: 1)
        let decoded = try JSONDecoder().decode(RelayPacket.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.padText); XCTAssertNil(decoded.textVersion)
        var document = RelayTextDocument(boxes: [.init(text: "听写", x: 0, y: 0, width: 120, fontSize: 24)])
        XCTAssertEqual(try RelayTextDocument.decode(document.encoded()), document)
        document.boxes.append(document.boxes[0])
        XCTAssertThrowsError(try document.encoded())
        document.boxes.removeLast(); document.boxes[0].width = -1
        XCTAssertThrowsError(try document.encoded())
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { pointer in
            let ctx = CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let index = (y * image.width + x) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }
}
