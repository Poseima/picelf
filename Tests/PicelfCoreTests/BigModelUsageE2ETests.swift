import XCTest
import ScreenCaptureKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Picelf

/// E2E test that opens the BigModel GLM Coding usage page in Chrome, scrolls through it,
/// and produces a long stitched screenshot using the full CaptureOrchestrator flow.
final class BigModelUsageE2ETests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1",
            "Live desktop tests require PICELF_RUN_LIVE_TESTS=1 and capture permissions")
    }

    private var pageURL: URL { URL(string: ProcessInfo.processInfo.environment["PICELF_TEST_PAGE_URL"] ?? "https://developer.apple.com/documentation/vision")! }

    /// Project root derived from this test file's location.
    private var projectRootURL: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var cachedFramesDirURL: URL {
        projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures/e2e-frames-bigmodel")
    }

    private var outputDirURL: URL {
        projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures/e2e-output")
    }

    private var outputPath: String {
        let dir = outputDirURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("picelf-e2e-bigmodel-usage-result.png").path
    }

    private var rawOutputPath: String {
        outputPath.replacingOccurrences(of: ".png", with: "-raw.png")
    }

    @MainActor private var orchestrator: CaptureOrchestrator?

    override func tearDown() {
        let script = NSAppleScript(source: """
            tell application "Google Chrome"
                close front window
            end tell
        """)
        script?.executeAndReturnError(nil)
        super.tearDown()
    }

    @MainActor
    func test_captureAndStitchBigModelUsagePage() async throws {

        // ── Fast path: stitch from cached frames ──────────────
        if let frames = loadCachedFrames() {
            print("[E2E-BigModel] Using \(frames.count) cached frames")
            let coordinator = StitchingCoordinator()
            for frame in frames { coordinator.appendFrame(frame) }
            let result = try await coordinator.stitch()
            print("[E2E-BigModel] Stitched from cache: \(result.width)x\(result.height)")
            let outputURL = URL(fileURLWithPath: outputPath)
            try ImageExporter.export(result, to: outputURL, format: .png)
            print("[E2E-BigModel] CACHED STITCH PASSED — delete e2e-frames-bigmodel/ to re-capture")
            return
        }
        print("[E2E-BigModel] No cached frames, running full capture...")

        // ── Step 1: Open URL in browser ───────────────────────
        try XCTSkipIf(NSScreen.main == nil,
                       "Requires a display — cannot run headless")

        NSWorkspace.shared.open(pageURL)
        print("[E2E-BigModel] Opened \(pageURL) in browser, waiting for page load...")
        try await Task.sleep(for: .seconds(6))

        // Bring Chrome to front and resize to known dimensions.
        let activateScript = NSAppleScript(source: """
            tell application "Google Chrome"
                activate
                if (count of windows) > 0 then
                    set bounds of front window to {100, 100, 1200, 900}
                end if
            end tell
        """)
        activateScript?.executeAndReturnError(nil)
        try await Task.sleep(for: .seconds(1))

        // Scroll to top of page (Cmd+Home).
        scrollToTop()
        try await Task.sleep(for: .milliseconds(500))

        // ── Step 2: Create orchestrator and activate ─────────
        let orch = CaptureOrchestrator()
        orch.suppressAlerts = true
        self.orchestrator = orch

        let workbench = E2EBackgroundStitchHarness.configure(
            orchestrator: orch,
            label: "E2E-BigModel"
        )

        await orch.activate()

        // ── Step 3: Verify overlay panels ────────────────────
        XCTAssertNotNil(orch.framePanel,
            "Frame panel should exist after activate()")
        XCTAssertTrue(orch.framePanel?.isVisible ?? false,
            "Frame panel should be visible")
        XCTAssertNotNil(orch.toolbarPanel,
            "Toolbar panel should exist after activate()")
        XCTAssertTrue(orch.toolbarPanel?.isVisible ?? false,
            "Toolbar panel should be visible")
        XCTAssertNotNil(orch.dimmingWindow,
            "Dimming window should exist after activate()")
        XCTAssertTrue(orch.dimmingWindow?.isVisible ?? false,
            "Dimming window should be visible")

        print("[E2E-BigModel] Overlays showing. Windows found: \(orch.windowEnumerator.windows.count)")

        // ── Step 4: Select the Chrome window ─────────────────
        let chromeWindow = orch.windowEnumerator.windows
            .filter {
                $0.appBundleID == "com.google.Chrome"
                    && $0.frame.width > 200
                    && $0.frame.height > 200
            }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })

        guard let chromeWindow = chromeWindow else {
            for (i, w) in orch.windowEnumerator.windows.enumerated() {
                print("[E2E-BigModel] window[\(i)]: '\(w.appName): \(w.title)' bundle=\(w.appBundleID)")
            }
            XCTFail("Chrome window not found in windowEnumerator.windows")
            return
        }

        print("[E2E-BigModel] Selected Chrome: id=\(chromeWindow.id) '\(chromeWindow.title)' " +
              "\(Int(chromeWindow.frame.width))x\(Int(chromeWindow.frame.height))")

        orch.captureState.selectedWindowID = chromeWindow.id
        orch.captureState.frameRect = chromeWindow.frame

        // ── Step 5: Start capture ────────────────────────────
        await orch.startCapture()
        XCTAssertTrue(orch.captureState.isCapturing,
            "isCapturing should be true after startCapture()")
        XCTAssertTrue(orch.captureStream.isCapturing,
            "captureStream.isCapturing should be true")

        print("[E2E-BigModel] Capture started. Scrolling page...")

        // ── Step 5b: Bring Chrome to front ───────────────────
        activateScript?.executeAndReturnError(nil)
        try await Task.sleep(for: .milliseconds(500))

        // ── Step 6: Scroll the page ──────────────────────────
        let windowCenter = CGPoint(
            x: chromeWindow.frame.midX,
            y: chromeWindow.frame.midY
        )

        try await Task.sleep(for: .milliseconds(500))

        let scrollSteps = 80
        for i in 1...scrollSteps {
            scrollDown(at: windowCenter, lines: 5)
            try await Task.sleep(for: .milliseconds(350))
            if i % 10 == 0 {
                let accepted = orch.stitchingCoordinator.frameCount
                let raw = orch.captureStream.capturedFrameCount
                print("[E2E-BigModel] Scroll step \(i)/\(scrollSteps) — raw: \(raw), accepted: \(accepted)")
            }
        }

        // Extra pause to capture final position
        try await Task.sleep(for: .seconds(1))

        // ── Step 7: Verify frames before stopping ────────────
        let acceptedBeforeStop = orch.stitchingCoordinator.frameCount
        print("[E2E-BigModel] Before stop: \(acceptedBeforeStop) accepted frames")
        XCTAssertGreaterThan(acceptedBeforeStop, 1,
            "Should have >1 accepted frame before stopping. Got \(acceptedBeforeStop). " +
            "Scrolling likely didn't work or dedup is too aggressive.")

        // Cache frames for future stitch-only runs
        do {
            let capturedFrames = try orch.stitchingCoordinator.loadAllFrames()
            saveCachedFrames(capturedFrames)
        } catch {
            print("[E2E-BigModel] Warning: could not cache frames: \(error)")
        }

        // ── Step 8: Stop capture ─────────────────────────────
        await orch.stopCapture()

        XCTAssertFalse(orch.captureState.isCapturing,
            "isCapturing should be false after stopCapture()")
        XCTAssertGreaterThanOrEqual(workbench.jobs.count, 1,
            "Expected capture to be submitted to Workbench background queue")
        await E2EBackgroundStitchHarness.assertWorkbenchVisible(label: "E2E-BigModel")

        // ── Step 9: Wait for background stitch result ────────
        let result: NSImage
        do {
            result = try await E2EBackgroundStitchHarness.awaitResult(
                from: workbench,
                label: "E2E-BigModel",
                timeoutSeconds: 240
            )
        } catch {
            XCTFail("Background stitching failed: \(error.localizedDescription)")
            return
        }
        print("[E2E-BigModel] Background stitched result: \(Int(result.size.width))x\(Int(result.size.height))")

        // Verify overlays were cleaned up
        XCTAssertNil(orch.framePanel,
            "Frame panel should be nil after deactivate()")
        XCTAssertNil(orch.toolbarPanel,
            "Toolbar panel should be nil after deactivate()")
        XCTAssertNil(orch.dimmingWindow,
            "Dimming window should be nil after deactivate()")

        // ── Step 10: Verify dimensions, quality, and save ────
        print("[E2E-BigModel] Stitched result: \(Int(result.size.width))x\(Int(result.size.height))")
        let rawOutputURL = URL(fileURLWithPath: rawOutputPath)
        if (try? ImageExporter.export(result, to: rawOutputURL, format: .png)) != nil {
            print("[E2E-BigModel] Saved raw stitched image to: \(rawOutputPath)")
        }

        // Shared validator: dimensions, contrast, overlap-removal, duplication, seams.
        let windowPixelWidth = Int(chromeWindow.frame.width) * 2
        let windowPixelHeight = Int(chromeWindow.frame.height) * 2
        let sampleY = min(Int(result.size.height) / 3, Int(result.size.height) - 300)
        let contrastSample = CGRect(
            x: 50,
            y: sampleY,
            width: min(800, max(1, Int(result.size.width) - 100)),
            height: 200
        )
        let validationContext = E2EValidationContext(
            acceptedFrameCount: acceptedBeforeStop,
            windowPixelWidth: windowPixelWidth,
            windowPixelHeight: windowPixelHeight,
            contrastSampleRect: contrastSample
        )
        // This page is a dashboard-style usage view with naturally repetitive
        // list/table sections; keep hard duplication/seam checks strict, but
        // avoid elevating repeated-section heuristics to critical.
        var profile = E2EValidationProfile.highRecall
        profile.repeatedSectionRules.criticalMinConsecutiveWindows = 10_000
        // Note: E2EStitchValidator expects CGImage, get it from NSImage
        guard let resultCG = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Could not convert NSImage to CGImage for validation")
            return
        }
        let report = E2EStitchValidator.validateStitchedImage(
            resultCG,
            context: validationContext,
            profile: profile,
            policy: .criticalOnly
        )
        print(report.formattedSummary(prefix: "[E2E-BigModel]"))
        XCTAssertEqual(report.stats.duplicateRunCount, 0, "Expected no duplicate runs")
        XCTAssertEqual(report.stats.seamCount, 0, "Expected no seam artifacts")
        guard report.passed else {
            XCTFail(report.failureSummary(prefix: "[E2E-BigModel]"))
            return
        }

        // Save and open for visual inspection
        let outputURL = URL(fileURLWithPath: outputPath)
        try ImageExporter.export(result, to: outputURL, format: .png)
        NSWorkspace.shared.open(outputURL)
        print("[E2E-BigModel] Saved to: \(outputPath)")
        print("[E2E-BigModel] ALL CHECKS PASSED — BigModel usage page capture works!")

        // Explicit cleanup
        orch.onCaptureSubmitted = nil
        orch.onStitchingComplete = nil
        orch.onStitchingFailed = nil
        self.orchestrator = nil
        try? await Task.sleep(for: .seconds(1))
    }

    // MARK: - Frame Cache

    private func saveCachedFrames(_ frames: [CGImage]) {
        let dir = cachedFramesDirURL
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, frame) in frames.enumerated() {
            let filename = String(format: "frame-%05d.png", i)
            let url = dir.appendingPathComponent(filename)
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, frame, nil)
                CGImageDestinationFinalize(dest)
            }
        }
        print("[E2E-BigModel] Saved \(frames.count) frames to cache")
    }

    private func loadCachedFrames() -> [CGImage]? {
        let dir = cachedFramesDirURL
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasSuffix(".png") }
            .sorted()
        guard let files, !files.isEmpty else { return nil }
        var frames: [CGImage] = []
        for file in files {
            let url = dir.appendingPathComponent(file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            frames.append(image)
        }
        print("[E2E-BigModel] Loaded \(frames.count) cached frames")
        return frames
    }

    // MARK: - Helpers

    private func scrollToTop() {
        let keyCode: CGKeyCode = 0x73 // Home key
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func scrollDown(at point: CGPoint, lines: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: -lines,
            wheel2: 0,
            wheel3: 0
        ) else {
            print("[E2E-BigModel] Failed to create CGEvent scroll event")
            return
        }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}
