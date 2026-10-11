import AppKit
import XCTest
@testable import Picelf

/// Explicitly opted-in tests hide and restore applications, move the pointer,
/// and briefly display capture overlays. They never request TCC access.
@MainActor
final class DesktopCaptureLiveTests: XCTestCase {
    private func requireLiveAccess() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PICELF_RUN_LIVE_TESTS"] == "1" && env["PICELF_RUN_DESKTOP_CAPTURE_TESTS"] == "1",
                          "Desktop capture requires both explicit live-test opt-ins")
        let signature = MicrophonePermissionRuntimeDiagnostics.current()
        try XCTSkipUnless(signature.isSigned && signature.teamIdentifier != nil,
                          "Desktop capture requires a developer-signed Debug test host")
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "Grant Screen Recording to the signed test host first")
    }

    private func hideApplications() async -> [NSRunningApplication] {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isHidden && $0.activationPolicy == .regular }
        for app in apps { _ = app.hide() }
        try? await Task.sleep(for: .milliseconds(300))
        return apps
    }

    private func fixtureWindow() -> NSWindow {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let window = NSWindow(contentRect: CGRect(x: screen.frame.midX - 160, y: screen.frame.midY - 120,
                                                  width: 320, height: 240),
                              styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Picelf Desktop Capture Fixture"
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGreen.cgColor
        window.contentView = view
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func captureAndVerify(expectsWindow: Bool) async throws {
        let orchestrator = CaptureOrchestrator(clipboardWriter: { _ in })
        orchestrator.suppressAlerts = true
        defer { orchestrator.cancelSnapEdit() }
        await orchestrator.activate()
        XCTAssertNil(orchestrator.lastActivationFailure)
        XCTAssertTrue(orchestrator.framePanel?.isVisible == true)
        if !expectsWindow { XCTAssertTrue(orchestrator.windowEnumerator.windows.isEmpty) }
        let state = orchestrator.captureState
        let screen = state.frozenScreenFrame
        let frozen = try XCTUnwrap(state.frozenBackgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rect = CGRect(x: screen.midX - 60, y: screen.midY - 40, width: 120, height: 80)
        let scaleX = state.frozenPixelScaleX
        let scaleY = state.frozenPixelScaleY
        let expected = try XCTUnwrap(frozen.cropping(to: CGRect(
            x: (rect.minX - screen.minX) * scaleX, y: (screen.maxY - rect.maxY) * scaleY,
            width: rect.width * scaleX, height: rect.height * scaleY)))
        let completed = expectation(description: "Real desktop image confirmed")
        var output: NSImage?
        orchestrator.onSnapEditConfirmed = { image, window, _ in
            output = image
            XCTAssertEqual(window != nil, expectsWindow)
            completed.fulfill()
        }
        state.frameRect = rect
        state.mode = .dragSelecting
        orchestrator.manualSelectionCommitted()
        state.mode = .selectionReady
        for _ in 0..<100 where !state.isSnapEditing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(state.isSnapEditing)
        orchestrator.confirmSnapEdit()
        await fulfillment(of: [completed], timeout: 3)
        let image = try XCTUnwrap(output?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let actual = try XCTUnwrap(NSBitmapImageRep(data: png))
        let source = NSBitmapImageRep(cgImage: expected)
        XCTAssertEqual(actual.pixelsWide, expected.width)
        XCTAssertEqual(actual.pixelsHigh, expected.height)
        for (x, y) in [(10, 10), (expected.width / 2, expected.height / 2), (expected.width - 10, expected.height - 10)] {
            let a = try XCTUnwrap(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let e = try XCTUnwrap(source.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            XCTAssertEqual(a.redComponent, e.redComponent, accuracy: 0.02)
            XCTAssertEqual(a.greenComponent, e.greenComponent, accuracy: 0.02)
            XCTAssertEqual(a.blueComponent, e.blueComponent, accuracy: 0.02)
        }
    }

    func testLiveBareDesktopAndMinimizedWindow() async throws {
        try requireLiveAccess()
        let apps = await hideApplications()
        defer { for app in apps { _ = app.unhide() } }
        try await captureAndVerify(expectsWindow: false)
        let window = fixtureWindow()
        defer { window.orderOut(nil) }
        window.miniaturize(nil)
        try await Task.sleep(for: .milliseconds(300))
        try await captureAndVerify(expectsWindow: false)
    }

    func testLiveNormalWindow() async throws {
        try requireLiveAccess()
        let apps = await hideApplications()
        defer { for app in apps { _ = app.unhide() } }
        let window = fixtureWindow()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        try await captureAndVerify(expectsWindow: true)
    }

    func testLiveMultipleDisplays() async throws {
        try requireLiveAccess()
        try XCTSkipUnless(NSScreen.screens.count > 1, "Connect a second display for live multi-display validation")
        let apps = await hideApplications()
        let originalPointer = NSEvent.mouseLocation
        defer {
            CGWarpMouseCursorPosition(ScreenCoordinateSpace.appKitPointToCG(originalPointer))
            for app in apps { _ = app.unhide() }
        }
        for screen in NSScreen.screens {
            CGWarpMouseCursorPosition(ScreenCoordinateSpace.appKitPointToCG(CGPoint(x: screen.frame.midX, y: screen.frame.midY)))
            try await Task.sleep(for: .milliseconds(100))
            try await captureAndVerify(expectsWindow: false)
        }
    }
}
