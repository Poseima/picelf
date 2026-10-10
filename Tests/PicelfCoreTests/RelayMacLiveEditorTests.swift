import XCTest
import AppKit
@testable import Picelf

@MainActor
final class RelayMacLiveEditorTests: XCTestCase {
    func testAnnotationArchiveRestoresEditableStylesAndSourcePixelExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacLiveEditor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let c = try XCTUnwrap(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let png = try RelayImage.png(XCTUnwrap(c.makeImage()))
        let task = RelayTask(title: "Editor", origin: .mac, width: 120, height: 80)
        try RelayStore(directory: root).save(task, base: png)
        let hub = RelayCoordinator(role: .mac, directory: root, startTransport: { _ in })
        hub.collaboration.sendOverride = { _ in }
        hub.collaboration.discoveredPeer(); try hub.collaboration.start(task.id)
        let bridge = try RelayMacLiveEditor(id: task.id, hub: hub)
        bridge.document.selectedTool = .arrow
        bridge.document.beginAnnotation(at: CGPoint(x: 10, y: 20))
        bridge.document.updateAnnotation(at: CGPoint(x: 100, y: 60))
        bridge.document.commitAnnotation()
        try await bridge.flush()
        let output = try XCTUnwrap(hub.collaboration.layerData(task.id, role: .mac))
        XCTAssertEqual(try RelayImage.pngDimensions(output).0, 120, "Retina screen scale must not double output pixels")
        XCTAssertEqual(try RelayImage.pngDimensions(output).1, 80)
        let doc = try XCTUnwrap(hub.collaboration.layerData(task.id, role: .mac, document: true))
        let restored = try JSONDecoder().decode(RelayMacDocument.self, from: doc)
        XCTAssertEqual(restored.annotations.count, 1)
        XCTAssertEqual(restored.annotations.first?.annotation.kind, .arrow)
        let annotations = bridge.document.annotations.count
        bridge.document.relayInkOverlay = NSImage(data: png)
        XCTAssertEqual(bridge.document.annotations.count, annotations)
        bridge.document.undo()
        XCTAssertTrue(bridge.document.annotations.isEmpty)
        XCTAssertNotNil(bridge.document.relayInkOverlay, "Local undo must preserve iPad ink")
    }
}
