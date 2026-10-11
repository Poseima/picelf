import AppKit
import ScreenCaptureKit
import XCTest
@testable import Picelf

@MainActor
final class DesktopCaptureTests: XCTestCase {
    private func screenAndID() throws -> (NSScreen, CGDirectDisplayID) {
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        return (screen, number.uint32Value)
    }

    private func candidate(id: CGWindowID = 9, frame: CGRect = CGRect(x: 0, y: 0, width: 300, height: 300),
                           layer: Int = 0) -> WindowEnumerator.Candidate {
        .init(info: WindowInfo(id: id, title: "Fixture", appName: "Fixture", appBundleID: "fixture",
                              frame: frame, isOnScreen: true), layer: layer)
    }

    private func frozenImage(on screen: NSScreen) throws -> CGImage {
        let width = Int(screen.frame.width * 2)
        let height = Int(screen.frame.height * 2)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = x < width / 2 ? 255 : 0
                pixels[offset + 1] = x >= width / 2 ? 255 : 0
                pixels[offset + 2] = y >= height / 2 ? 255 : 0
                pixels[offset + 3] = 255
            }
        }
        let context = try XCTUnwrap(CGContext(data: pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bitmap.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    func testEmptyAndFilteredWindowListsStillCaptureDesktopPixels() async throws {
        let (screen, displayID) = try screenAndID()
        let source = try frozenImage(on: screen)
        let excluded = [candidate(frame: CGRect(x: 0, y: 0, width: 40, height: 40)), candidate(id: 10, layer: 1)]
        // Also cover a window on another display: it must not become desktop metadata.
        let offscreen = [candidate(frame: CGRect(x: screen.frame.maxX + 500, y: screen.frame.minY,
                                                width: 300, height: 300))]
        let cases: [([WindowEnumerator.Candidate], CGWindowID?)] = [
            ([], nil), (excluded, nil), (offscreen, nil), ([candidate(frame: screen.frame)], 9)
        ]
        for (candidates, expectedWindowID) in cases {
            let enumerator = WindowEnumerator { .init(windows: candidates, displayIDs: [displayID]) }
            let orchestrator = CaptureOrchestrator(windowEnumerator: enumerator,
                frozenImageProvider: { _ in source }, clipboardWriter: { _ in })
            defer { orchestrator.cancelSnapEdit() }
            orchestrator.suppressAlerts = true
            let completed = expectation(description: "Desktop image confirmed")
            var output: NSImage?
            orchestrator.onSnapEditConfirmed = { image, window, _ in
                output = image
                XCTAssertEqual(window?.id, expectedWindowID)
                completed.fulfill()
            }
            await orchestrator.activate()
            XCTAssertNil(orchestrator.lastActivationFailure)
            XCTAssertTrue(orchestrator.framePanel?.isVisible == true)
            XCTAssertTrue(orchestrator.dimmingWindow?.isVisible == true)
            XCTAssertNil(orchestrator.captureState.selectedWindowID)
            XCTAssertNotNil(orchestrator.captureState.frozenBackgroundImage)
            let frame = CGRect(x: screen.frame.midX - 32, y: screen.frame.maxY - 64 - 48, width: 64, height: 48)
            orchestrator.captureState.frameRect = frame
            orchestrator.captureState.mode = .dragSelecting
            orchestrator.manualSelectionCommitted()
            orchestrator.captureState.mode = .selectionReady
            for _ in 0..<100 where !orchestrator.captureState.isSnapEditing {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(orchestrator.captureState.isSnapEditing)
            orchestrator.confirmSnapEdit()
            await fulfillment(of: [completed], timeout: 2)
            let result = try XCTUnwrap(output)
            let cg = try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil))
            // Verify the encoded export as well as the in-memory result.
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            let decoded = try XCTUnwrap(NSBitmapImageRep(data: png))
            let original = NSBitmapImageRep(cgImage: source)
            XCTAssertEqual(decoded.pixelsWide, 128)
            XCTAssertEqual(decoded.pixelsHigh, 96)
            for x in [16, 112] {
                let color = try XCTUnwrap(decoded.colorAt(x: x, y: 20)?.usingColorSpace(.sRGB))
                let expected = try XCTUnwrap(original.colorAt(x: source.width / 2 - 64 + x, y: 128 + 20)?.usingColorSpace(.sRGB))
                XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.01)
                XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.01)
                XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.01)
                XCTAssertEqual(color.alphaComponent, expected.alphaComponent, accuracy: 0.01)
            }
            XCTAssertNil(orchestrator.framePanel)
            XCTAssertNil(orchestrator.captureState.frozenBackgroundImage)
        }
    }

    func testFailedRefreshClearsCachesAndSuccessfulRefreshClearsError() async throws {
        let (_, displayID) = try screenAndID()
        var fail = false
        let window = candidate()
        let expectedError = NSError(domain: "Fixture", code: 7)
        let enumerator = WindowEnumerator {
            if fail { throw expectedError }
            return .init(windows: [window], displayIDs: [displayID])
        }
        await enumerator.refreshAvailableContent()
        XCTAssertEqual(enumerator.windows.map(\.id), [window.info.id])
        XCTAssertEqual(enumerator.displayIDs, [displayID])
        fail = true
        await enumerator.refreshAvailableContent()
        XCTAssertTrue(enumerator.windows.isEmpty)
        XCTAssertTrue(enumerator.displayIDs.isEmpty)
        XCTAssertEqual(enumerator.error as NSError?, expectedError)
        fail = false
        await enumerator.refreshAvailableContent()
        XCTAssertNil(enumerator.error)
        XCTAssertEqual(enumerator.displayIDs, [displayID])
    }

    func testActivationFailuresRestorePresentationAndAllowRetry() async throws {
        let (screen, displayID) = try screenAndID()
        let source = try frozenImage(on: screen)
        let denied = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let generic = NSError(domain: "Fixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "Fixture enumeration failed"])
        let cases: [(Error?, [CGDirectDisplayID], Bool, CaptureActivationFailure)] = [
            (denied, [displayID], true, .permissionDenied),
            (generic, [displayID], true, .contentEnumerationFailed(generic.localizedDescription)),
            (nil, [], true, .noCapturableDisplay),
            (nil, [UInt32.max], true, .noCapturableDisplay),
            (nil, [displayID], false, .snapshotFailed)
        ]
        for (error, ids, imageAvailable, expected) in cases {
            var recovering = false
            var imageRequests = 0
            let enumerator = WindowEnumerator {
                if !recovering, let error { throw error }
                return .init(windows: [], displayIDs: recovering ? [displayID] : ids)
            }
            let orchestrator = CaptureOrchestrator(windowEnumerator: enumerator, frozenImageProvider: { _ in
                imageRequests += 1
                return recovering || imageAvailable ? source : nil
            }, clipboardWriter: { _ in })
            orchestrator.suppressAlerts = true
            var presentation: [String] = []
            orchestrator.onWillActivate = { presentation.append("lower") }
            orchestrator.onDidDeactivate = { presentation.append("restore") }
            await orchestrator.activate()
            XCTAssertEqual(orchestrator.lastActivationFailure, expected)
            XCTAssertEqual(presentation, ["lower", "restore"])
            XCTAssertNil(orchestrator.framePanel)
            XCTAssertNil(orchestrator.toolbarPanel)
            XCTAssertNil(orchestrator.dimmingWindow)
            XCTAssertNil(orchestrator.captureState.frozenBackgroundImage)
            XCTAssertNil(orchestrator.captureState.selectedWindowID)
            XCTAssertTrue(orchestrator.captureState.frameRect.isEmpty)
            XCTAssertEqual(imageRequests, expected == .snapshotFailed ? 1 : 0)
            recovering = true
            await orchestrator.activate()
            XCTAssertNil(orchestrator.lastActivationFailure)
            XCTAssertTrue(orchestrator.framePanel?.isVisible == true)
            orchestrator.deactivate()
            XCTAssertEqual(presentation, ["lower", "restore", "lower", "restore"])
        }
    }
}
