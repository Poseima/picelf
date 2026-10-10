import XCTest
@testable import Picelf

final class MagnifierTests: XCTestCase {

    // MARK: - MagnifierPanel properties

    @MainActor
    func test_panelInitProperties() {
        let panel = MagnifierPanel()
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(
            panel.level,
            NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        )
        panel.orderOut(nil)
    }

    // MARK: - Repositioning / edge flipping

    @MainActor
    func test_repositionNormalPlacement() {
        let panel = MagnifierPanel()
        let screen = NSScreen.main!
        let cursor = CGPoint(x: screen.frame.midX, y: screen.frame.midY)

        panel.reposition(near: cursor, on: screen)

        // Should be offset 20pt right and 20pt below (AppKit y-up: below = lower y)
        XCTAssertEqual(panel.frame.origin.x, cursor.x + 20, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, cursor.y - panel.frame.height - 20, accuracy: 1)
        panel.orderOut(nil)
    }

    @MainActor
    func test_repositionFlipsNearRightEdge() {
        let panel = MagnifierPanel()
        let screen = NSScreen.main!
        // Place cursor near the right edge
        let cursor = CGPoint(x: screen.visibleFrame.maxX - 10, y: screen.frame.midY)

        panel.reposition(near: cursor, on: screen)

        // Should flip to the left of the cursor
        XCTAssertLessThan(panel.frame.origin.x, cursor.x)
        panel.orderOut(nil)
    }

    @MainActor
    func test_repositionFlipsNearBottomEdge() {
        let panel = MagnifierPanel()
        let screen = NSScreen.main!
        // Place cursor near the bottom edge (low y in AppKit)
        let cursor = CGPoint(x: screen.frame.midX, y: screen.visibleFrame.minY + 5)

        panel.reposition(near: cursor, on: screen)

        // Should flip above the cursor
        XCTAssertGreaterThan(panel.frame.origin.y, cursor.y)
        panel.orderOut(nil)
    }

    // MARK: - hexColor extraction

    @MainActor
    func test_hexColorFromKnownImage() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        // Create a 3x3 solid red image in sRGB
        let ctx = CGContext(
            data: nil, width: 3, height: 3,
            bitsPerComponent: 8, bytesPerRow: 3 * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        // Fill with raw pixel values (255,0,0) via direct buffer write
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(3 * 3) {
            buf[i * 4 + 0] = 0    // B
            buf[i * 4 + 1] = 0    // G
            buf[i * 4 + 2] = 255  // R
            buf[i * 4 + 3] = 255  // A
        }
        let cgImage = ctx.makeImage()!

        // Extract center pixel using the same algorithm as CaptureOrchestrator.hexColor
        let hexCtx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        let centerX = cgImage.width / 2
        let centerY = cgImage.height / 2
        hexCtx.draw(cgImage, in: CGRect(x: -centerX, y: -centerY, width: cgImage.width, height: cgImage.height))
        let pixel = hexCtx.data!.assumingMemoryBound(to: UInt8.self)
        let b = pixel[0], g = pixel[1], r = pixel[2]
        let hex = String(format: "#%02X%02X%02X", r, g, b)

        XCTAssertEqual(hex, "#FF0000")
    }

    @MainActor
    func test_hexColorGreen() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 3, height: 3,
            bitsPerComponent: 8, bytesPerRow: 3 * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(3 * 3) {
            buf[i * 4 + 0] = 0    // B
            buf[i * 4 + 1] = 255  // G
            buf[i * 4 + 2] = 0    // R
            buf[i * 4 + 3] = 255  // A
        }
        let cgImage = ctx.makeImage()!

        let hexCtx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        let cx = cgImage.width / 2, cy = cgImage.height / 2
        hexCtx.draw(cgImage, in: CGRect(x: -cx, y: -cy, width: cgImage.width, height: cgImage.height))
        let pixel = hexCtx.data!.assumingMemoryBound(to: UInt8.self)
        let hex = String(format: "#%02X%02X%02X", pixel[2], pixel[1], pixel[0])

        XCTAssertEqual(hex, "#00FF00")
    }

    // MARK: - CaptureState defaults

    @MainActor
    func test_captureStateDefaults() {
        let state = CaptureState()
        XCTAssertEqual(state.mode, .idleSelecting)
        XCTAssertEqual(state.frameRect, .zero)
        XCTAssertNil(state.selectedWindowID)
        XCTAssertFalse(state.isCapturing)
        XCTAssertFalse(state.isStitching)
    }

}

/// Exercises the current frozen-screen overlay, using a signed test host and a real desktop.
final class CaptureOverlayLiveTests: XCTestCase {
    @MainActor
    private func activateOverlay() async throws -> CaptureOrchestrator {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1",
            "Live overlay tests require PICELF_RUN_LIVE_TESTS=1 and Screen Recording permission")
        let orchestrator = CaptureOrchestrator()
        orchestrator.suppressAlerts = true
        await orchestrator.activate()
        guard orchestrator.framePanel != nil else {
            orchestrator.deactivate()
            throw XCTSkip("No capturable windows or Screen Recording permission")
        }
        return orchestrator
    }

    @MainActor
    func test_activateCreatesFrozenOverlay() async throws {
        let orchestrator = try await activateOverlay()
        defer { orchestrator.deactivate() }
        XCTAssertNotNil(orchestrator.dimmingWindow)
        XCTAssertNotNil(orchestrator.captureState.frozenBackgroundImage)
        XCTAssertGreaterThan(orchestrator.captureState.frozenScreenFrame.width, 0)
    }

    @MainActor
    func test_deactivateClearsOverlayAndFrozenImage() async throws {
        let orchestrator = try await activateOverlay()
        orchestrator.deactivate()
        XCTAssertNil(orchestrator.framePanel)
        XCTAssertNil(orchestrator.dimmingWindow)
        XCTAssertNil(orchestrator.captureState.frozenBackgroundImage)
        XCTAssertEqual(orchestrator.captureState.frozenScreenFrame, .zero)
    }

    @MainActor
    func test_selectionReadyPreservesFrozenScreen() async throws {
        let orchestrator = try await activateOverlay()
        defer { orchestrator.deactivate() }
        let image = try XCTUnwrap(orchestrator.captureState.frozenBackgroundImage)
        orchestrator.captureState.mode = .selectionReady
        await Task.yield()
        XCTAssertTrue(orchestrator.captureState.frozenBackgroundImage === image)
        XCTAssertNotNil(orchestrator.framePanel)
    }

    @MainActor
    func test_returnToSelectingPreservesOverlay() async throws {
        let orchestrator = try await activateOverlay()
        defer { orchestrator.deactivate() }
        let panel = try XCTUnwrap(orchestrator.framePanel)
        orchestrator.captureState.mode = .selectionReady
        await Task.yield()
        orchestrator.captureState.mode = .idleSelecting
        await Task.yield()
        XCTAssertTrue(orchestrator.framePanel === panel)
        XCTAssertNotNil(orchestrator.captureState.frozenBackgroundImage)
    }
}
