import XCTest
import ScreenCaptureKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import Picelf

/// E2E test that exercises the REAL user flow through CaptureOrchestrator.
///
/// Simulates: menu bar click → activate() → frame overlay shows →
/// select Preview window → Start → scroll → Done → stitch → save result.
///
/// This test uses the same code path the real app uses, so if the overlay
/// doesn't show or stitching fails, this test catches it.
///
/// **Frame caching:** On first run, captured frames are saved to
/// `Tests/PicelfCoreTests/Fixtures/e2e-frames/`. Subsequent runs load
/// cached frames and skip the ~60s capture phase. Delete the directory
/// to force re-capture.
final class RealCaptureE2ETests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1",
            "Live desktop tests require PICELF_RUN_LIVE_TESTS=1 and capture permissions")
    }

    private var pdfPath: String {
        ProcessInfo.processInfo.environment["PICELF_TEST_PDF_PATH"]
            ?? projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures/scroll-test.pdf").path
    }

    /// Project root derived from this test file's location.
    private var projectRootURL: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Tests/PicelfCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    /// Fixtures directory path for external cache regression tests.
    private var fixturesPath: String {
        projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures").path
    }

    /// Directory where cached frames are stored.
    private var cachedFramesDirURL: URL {
        projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures/e2e-frames")
    }

    /// Separate cache for resized-frame captures.
    private var resizedFramesCacheDirURL: URL {
        projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures/e2e-frames-resized")
    }

    /// Directory where test output images are saved.
    private var outputDirURL: URL {
        projectRootURL.appendingPathComponent("Tests/PicelfCoreTests/Fixtures/e2e-output")
    }

    /// Base output path for stitched result images.
    private var outputPath: String {
        let dir = outputDirURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("picelf-e2e-result.png").path
    }

    // Stored as instance property so it survives through tearDown,
    // preventing use-after-free in XCTMemoryChecker.
    @MainActor private var orchestrator: CaptureOrchestrator?

    override func tearDown() {
        guard ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1" else { return }
        // Close Preview
        let script = NSAppleScript(source: """
            tell application "Preview" to quit
        """)
        script?.executeAndReturnError(nil)
        super.tearDown()
    }

    /// THE anchor test: full user flow via CaptureOrchestrator.
    ///
    /// Uses cached frames if available (skip capture, ~5s).
    /// Falls back to full capture on first run (~60s) and caches frames.
    @MainActor
    func test_captureAndStitchRealPDF() async throws {

        // ── Fast path: stitch from cached frames ──────────────
        if let frames = loadCachedFrames() {
            print("[E2E] Using \(frames.count) cached frames from \(cachedFramesDirURL.path)")
            let coordinator = StitchingCoordinator()
            for frame in frames {
                coordinator.appendFrame(frame)
            }
            print("[E2E] Fed \(coordinator.frameCount) frames to coordinator, stitching...")
            let result = try await coordinator.stitch()
            print("[E2E] Stitched from cache: \(result.width)x\(result.height)")

            let outputURL = URL(fileURLWithPath: outputPath)
            try ImageExporter.export(result, to: outputURL, format: .png)
            NSWorkspace.shared.open(outputURL)
            print("[E2E] Saved to: \(outputPath)")
            print("[E2E] CACHED STITCH PASSED — delete \(cachedFramesDirURL.lastPathComponent)/ to re-capture")
            return
        }
        print("[E2E] No cached frames found, running full capture...")

        // ── Step 1: Open PDF in Preview ──────────────────────
        let pdfURL = URL(fileURLWithPath: pdfPath)
        try XCTSkipIf(!FileManager.default.fileExists(atPath: pdfPath),
                       "Test PDF not present at: \(pdfPath)")
        try XCTSkipIf(NSScreen.main == nil,
                       "Requires a display — cannot run headless")

        NSWorkspace.shared.open(pdfURL)
        print("[E2E] Opened PDF in Preview, waiting for window...")
        try await Task.sleep(for: .seconds(3))

        // Bring Preview to front and resize to a known good size.
        // Previous runs may have left the window tiny or off-screen.
        let activateScript = NSAppleScript(source: """
            tell application "Preview"
                activate
                if (count of windows) > 0 then
                    set bounds of front window to {100, 100, 1200, 900}
                end if
            end tell
        """)
        activateScript?.executeAndReturnError(nil)
        try await Task.sleep(for: .seconds(1))

        // Reset scroll position to the top of the PDF.
        // (Previous test runs may have scrolled it down.)
        scrollToTop()
        try await Task.sleep(for: .milliseconds(500))

        // ── Step 2: Create orchestrator and call activate() ──
        //           (simulates user clicking menu bar icon)
        let orch = CaptureOrchestrator()
        orch.suppressAlerts = true
        self.orchestrator = orch

        let workbench = E2EBackgroundStitchHarness.configure(
            orchestrator: orch,
            label: "E2E"
        )

        await orch.activate()

        // ── Step 3: Verify overlay panels are showing ────────
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

        print("[E2E] Overlays are showing. Windows found: \(orch.windowEnumerator.windows.count)")

        // ── Step 4: Select the Preview window ────────────────
        //           (simulates user picking from dropdown)
        // Pick the LARGEST Preview window (in case multiple exist)
        let previewWindow = orch.windowEnumerator.windows
            .filter {
                $0.appBundleID == "com.apple.Preview"
                    && $0.frame.width > 200
                    && $0.frame.height > 200
            }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })

        guard let previewWindow else {
            for (i, w) in orch.windowEnumerator.windows.enumerated() {
                print("[E2E] window[\(i)]: '\(w.appName): \(w.title)' bundle=\(w.appBundleID)")
            }
            XCTFail("Preview window not found in windowEnumerator.windows")
            return
        }

        print("[E2E] Selected Preview: id=\(previewWindow.id) '\(previewWindow.title)' " +
              "\(Int(previewWindow.frame.width))x\(Int(previewWindow.frame.height))")

        orch.captureState.selectedWindowID = previewWindow.id
        orch.captureState.frameRect = previewWindow.frame

        // ── Step 5: Click Start ──────────────────────────────
        await orch.startCapture()

        // Batch mode is now always used for final stitch; no override needed

        XCTAssertTrue(orch.captureState.isCapturing,
            "isCapturing should be true after startCapture()")
        XCTAssertTrue(orch.captureStream.isCapturing,
            "captureStream.isCapturing should be true")

        print("[E2E] Capture started. Scrolling PDF...")

        // ── Step 5b: Bring Preview to front ─────────────────
        // The overlays float above Preview. For scroll events to reach
        // Preview, it must be the frontmost app — just like when the
        // real user switches to their target app to scroll.
        activateScript?.executeAndReturnError(nil)
        try await Task.sleep(for: .milliseconds(500))

        // ── Step 6: Scroll the PDF ──────────────────────────
        let windowCenter = CGPoint(
            x: previewWindow.frame.midX,
            y: previewWindow.frame.midY
        )

        try await Task.sleep(for: .milliseconds(500))

        let scrollSteps = 60
        for i in 1...scrollSteps {
            scrollDown(at: windowCenter, lines: 5)
            try await Task.sleep(for: .milliseconds(350))
            if i % 10 == 0 {
                let accepted = orch.stitchingCoordinator.frameCount
                let raw = orch.captureStream.capturedFrameCount
                print("[E2E] Scroll step \(i)/\(scrollSteps) — raw: \(raw), accepted: \(accepted)")
            }
        }

        // Extra pause to capture final position
        try await Task.sleep(for: .seconds(1))

        // ── Step 7: Verify frames before stopping ────────────
        let acceptedBeforeStop = orch.stitchingCoordinator.frameCount
        print("[E2E] Before stop: \(acceptedBeforeStop) accepted frames")
        XCTAssertGreaterThan(acceptedBeforeStop, 1,
            "Should have >1 accepted frame before stopping. Got \(acceptedBeforeStop). " +
            "Scrolling likely didn't work or dedup is too aggressive.")

        // ── Step 7b: Cache frames for future stitch-only runs ─
        do {
            let capturedFrames = try orch.stitchingCoordinator.loadAllFrames()
            saveCachedFrames(capturedFrames)
        } catch {
            print("[E2E] Warning: could not cache frames: \(error)")
        }

        // ── Step 8: Click Done ───────────────────────────────
        await orch.stopCapture()

        XCTAssertFalse(orch.captureState.isCapturing,
            "isCapturing should be false after stopCapture()")
        XCTAssertGreaterThanOrEqual(workbench.jobs.count, 1,
            "Expected capture to be submitted to Workbench background queue")
        await E2EBackgroundStitchHarness.assertWorkbenchVisible(label: "E2E")

        // ── Step 9: Wait for background stitch result ────────
        let result: NSImage
        do {
            result = try await E2EBackgroundStitchHarness.awaitResult(
                from: workbench,
                label: "E2E",
                timeoutSeconds: 240
            )
        } catch {
            XCTFail("Background stitching failed: \(error.localizedDescription)")
            return
        }
        print("[E2E] Background stitched result: \(Int(result.size.width))x\(Int(result.size.height))")

        // Verify overlays were cleaned up by deactivate()
        XCTAssertNil(orch.framePanel,
            "Frame panel should be nil after deactivate()")
        XCTAssertNil(orch.toolbarPanel,
            "Toolbar panel should be nil after deactivate()")
        XCTAssertNil(orch.dimmingWindow,
            "Dimming window should be nil after deactivate()")

        // ── Step 10: Verify dimensions, quality, and save ────
        print("[E2E] Stitched result: \(Int(result.size.width))x\(Int(result.size.height))")
        let rawOutputPath = outputPath.replacingOccurrences(of: ".png", with: "-raw.png")
        let rawOutputURL = URL(fileURLWithPath: rawOutputPath)
        if (try? ImageExporter.export(result, to: rawOutputURL, format: .png)) != nil {
            print("[E2E] Saved raw stitched image to: \(rawOutputPath)")
        }

        // Shared validator: dimensions, contrast, overlap-removal, duplication, seams.
        let windowPixelWidth = Int(previewWindow.frame.width) * 2
        let windowPixelHeight = Int(previewWindow.frame.height) * 2
        let contrastSample = CGRect(
            x: 50,
            y: 400,
            width: min(800, max(1, Int(result.size.width) - 100)),
            height: 200
        )
        let validationContext = E2EValidationContext(
            acceptedFrameCount: acceptedBeforeStop,
            windowPixelWidth: windowPixelWidth,
            windowPixelHeight: windowPixelHeight,
            contrastSampleRect: contrastSample
        )
        // Note: E2EStitchValidator expects CGImage, get it from NSImage
        guard let resultCG = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Could not convert NSImage to CGImage for validation")
            return
        }
        let report = E2EStitchValidator.validateStitchedImage(
            resultCG,
            context: validationContext,
            profile: .highRecall,
            policy: .criticalOnly
        )
        print(report.formattedSummary(prefix: "[E2E]"))
        guard report.passed else {
            XCTFail(report.failureSummary(prefix: "[E2E]"))
            return
        }

        // Save and open for visual inspection
        let outputURL = URL(fileURLWithPath: outputPath)
        try ImageExporter.export(result, to: outputURL, format: .png)
        NSWorkspace.shared.open(outputURL)
        print("[E2E] Saved to: \(outputPath)")
        print("[E2E] ALL CHECKS PASSED — full CaptureOrchestrator flow works!")

        // Explicit cleanup: break all references before the test exits
        // to prevent XCTMemoryChecker from crashing on stale ObjC objects.
        orch.onCaptureSubmitted = nil
        orch.onStitchingComplete = nil
        orch.onStitchingFailed = nil
        self.orchestrator = nil

        // Let the RunLoop drain any remaining autorelease objects
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
    }

    /// E2E for resized capture frame:
    /// verifies stitching respects the user-resized frame width instead of full window width.
    @MainActor
    func test_captureAndStitchRealPDF_withResizedFrame() async throws {

        // ── Fast path: stitch from cached resized frames ──────
        if let frames = loadCachedFrames(from: resizedFramesCacheDirURL) {
            print("[E2E-Resized] Using \(frames.count) cached frames")
            let coordinator = StitchingCoordinator()
            for frame in frames { coordinator.appendFrame(frame) }
            let result = try await coordinator.stitch()
            print("[E2E-Resized] Stitched from cache: \(result.width)x\(result.height)")
            let resizedOutputPath = outputPath.replacingOccurrences(of: ".png", with: "-resized-frame.png")
            try ImageExporter.export(result, to: URL(fileURLWithPath: resizedOutputPath), format: .png)
            print("[E2E-Resized] CACHED STITCH PASSED — delete e2e-frames-resized/ to re-capture")
            return
        }
        print("[E2E-Resized] No cached frames, running full capture...")

        let pdfURL = URL(fileURLWithPath: pdfPath)
        try XCTSkipIf(!FileManager.default.fileExists(atPath: pdfPath),
                       "Test PDF not present at: \(pdfPath)")
        try XCTSkipIf(NSScreen.main == nil,
                       "Requires a display — cannot run headless")

        NSWorkspace.shared.open(pdfURL)
        print("[E2E-Resized] Opened PDF in Preview, waiting for window...")
        try await Task.sleep(for: .seconds(3))

        let activateScript = NSAppleScript(source: """
            tell application "Preview"
                activate
                if (count of windows) > 0 then
                    set bounds of front window to {100, 100, 1200, 900}
                end if
            end tell
        """)
        activateScript?.executeAndReturnError(nil)
        try await Task.sleep(for: .seconds(1))

        scrollToTop()
        try await Task.sleep(for: .milliseconds(500))

        let orch = CaptureOrchestrator()
        orch.suppressAlerts = true
        self.orchestrator = orch

        let workbench = E2EBackgroundStitchHarness.configure(
            orchestrator: orch,
            label: "E2E-Resized"
        )

        await orch.activate()

        let previewWindow = orch.windowEnumerator.windows
            .filter {
                $0.appBundleID == "com.apple.Preview"
                    && $0.frame.width > 200
                    && $0.frame.height > 200
            }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })

        guard let previewWindow else {
            XCTFail("Preview window not found in windowEnumerator.windows")
            return
        }

        orch.captureState.selectedWindowID = previewWindow.id

        // Simulate user resizing frame inward from all sides.
        let resizedFrame = previewWindow.frame.insetBy(dx: 120, dy: 100)
        XCTAssertGreaterThan(resizedFrame.width, 400, "Resized frame width should remain usable")
        XCTAssertGreaterThan(resizedFrame.height, 300, "Resized frame height should remain usable")
        orch.captureState.frameRect = resizedFrame
        print("[E2E-Resized] Using resized frame: \(resizedFrame)")

        await orch.startCapture()
        XCTAssertTrue(orch.captureState.isCapturing, "isCapturing should be true after startCapture()")
        XCTAssertTrue(orch.captureStream.isCapturing, "captureStream.isCapturing should be true")

        activateScript?.executeAndReturnError(nil)
        try await Task.sleep(for: .milliseconds(500))

        let windowCenter = CGPoint(
            x: previewWindow.frame.midX,
            y: previewWindow.frame.midY
        )

        let scrollSteps = 40
        for i in 1...scrollSteps {
            scrollDown(at: windowCenter, lines: 5)
            try await Task.sleep(for: .milliseconds(350))
            if i % 10 == 0 {
                let accepted = orch.stitchingCoordinator.frameCount
                let raw = orch.captureStream.capturedFrameCount
                print("[E2E-Resized] Scroll step \(i)/\(scrollSteps) — raw: \(raw), accepted: \(accepted)")
            }
        }
        try await Task.sleep(for: .seconds(1))

        let acceptedBeforeStop = orch.stitchingCoordinator.frameCount
        XCTAssertGreaterThan(acceptedBeforeStop, 1,
            "Should have >1 accepted frame before stopping. Got \(acceptedBeforeStop).")

        // Cache resized frames for future stitch-only runs
        do {
            let capturedFrames = try orch.stitchingCoordinator.loadAllFrames()
            saveCachedFrames(capturedFrames, to: resizedFramesCacheDirURL)
        } catch {
            print("[E2E-Resized] Warning: could not cache frames: \(error)")
        }

        await orch.stopCapture()

        XCTAssertFalse(orch.captureState.isCapturing, "isCapturing should be false after stopCapture()")
        XCTAssertGreaterThanOrEqual(workbench.jobs.count, 1,
            "Expected capture to be submitted to Workbench background queue")
        await E2EBackgroundStitchHarness.assertWorkbenchVisible(label: "E2E-Resized")

        let result: NSImage
        do {
            result = try await E2EBackgroundStitchHarness.awaitResult(
                from: workbench,
                label: "E2E-Resized",
                timeoutSeconds: 240
            )
        } catch {
            XCTFail("Background stitching failed: \(error.localizedDescription)")
            return
        }

        // Width should reflect resized frame (allowing limited edge cropping).
        let resultWidth = Int(result.size.width)
        let resizedFramePixelWidth = Int(resizedFrame.width) * 2
        let fullWindowPixelWidth = Int(previewWindow.frame.width) * 2
        XCTAssertLessThan(resultWidth, fullWindowPixelWidth - 100,
            "Result width should be narrower than full-window capture width")
        XCTAssertGreaterThanOrEqual(resultWidth, resizedFramePixelWidth - 200,
            "Result width should be close to resized frame width")
        XCTAssertLessThanOrEqual(resultWidth, resizedFramePixelWidth + 10,
            "Result width should not exceed resized frame width significantly")

        let resizedOutputPath = outputPath.replacingOccurrences(of: ".png", with: "-resized-frame.png")
        let resizedOutputURL = URL(fileURLWithPath: resizedOutputPath)
        try ImageExporter.export(result, to: resizedOutputURL, format: .png)
        print("[E2E-Resized] Saved to: \(resizedOutputPath)")

        orch.onCaptureSubmitted = nil
        orch.onStitchingComplete = nil
        orch.onStitchingFailed = nil
        self.orchestrator = nil
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
    }

    // MARK: - Helpers

    /// Send Cmd+Home to scroll document to top.
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
            print("[E2E] Failed to create CGEvent scroll event")
            return
        }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Frame Cache (save once, stitch many times)

    private func saveCachedFrames(_ frames: [CGImage], to dir: URL? = nil) {
        let dir = dir ?? cachedFramesDirURL
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
        print("[E2E] Saved \(frames.count) frames to cache: \(dir.path)")
    }

    private func loadCachedFrames(from dir: URL? = nil) -> [CGImage]? {
        let dir = dir ?? cachedFramesDirURL
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        let basePath = dir.path

        var frames: [CGImage] = []
        var index = 0
        while true {
            let filename = String(format: "frame-%05d.png", index)
            let path = basePath + "/" + filename
            guard fileExistsPOSIX(atPath: path) else { break }
            guard let image = loadPNGFramePOSIX(atPath: path) else {
                print("[E2E] Failed to load cached frame: \(filename)")
                return nil
            }
            frames.append(image)
            index += 1
        }
        guard !frames.isEmpty else { return nil }
        print("[E2E] Loaded \(frames.count) cached frames from: \(dir.path)")
        return frames
    }

    private func fileExistsPOSIX(atPath path: String) -> Bool {
        path.withCString { access($0, F_OK) == 0 }
    }

    private func loadPNGFramePOSIX(atPath path: String) -> CGImage? {
        let fd = path.withCString { open($0, O_RDONLY) }
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { return nil }

        let byteCount = Int(info.st_size)
        var data = Data(count: byteCount)
        let readSucceeded = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }

            var totalRead = 0
            while totalRead < byteCount {
                let bytesRead = read(fd, baseAddress.advanced(by: totalRead), byteCount - totalRead)
                guard bytesRead > 0 else { return false }
                totalRead += bytesRead
            }
            return true
        }

        guard readSucceeded,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    // MARK: - Stitch-Only Tests (from cached frames)

    /// Fast stitch-only test: loads cached frames, stitches with batch pipeline.
    /// Run `test_captureAndStitchRealPDF` once first to create the cache.
    @MainActor
    func test_stitchFromCachedFrames_batch() async throws {
        guard let frames = loadCachedFrames() else {
            throw XCTSkip("No cached frames. Run test_captureAndStitchRealPDF first to create the cache.")
        }
        try XCTSkipIf(frames.count < 2, "Need at least 2 cached frames")

        let coordinator = StitchingCoordinator()
        coordinator.useDiskBackedStorage = false  // keep in memory for speed
        // Replay frames through the same incremental coordinator used during capture.

        for frame in frames {
            coordinator.appendFrame(frame)
        }
        print("[Stitch-Batch] Fed \(coordinator.frameCount) frames to coordinator")

        let stitchStart = CFAbsoluteTimeGetCurrent()
        let result = try await coordinator.stitch { progress in
            if Int(progress.fraction * 100) % 20 == 0 {
                print("[Stitch-Batch] \(Int(progress.fraction * 100))% — \(progress.phase)")
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - stitchStart
        print("[Stitch-Batch] Completed in \(String(format: "%.2f", elapsed))s — \(result.width)x\(result.height)")

        XCTAssertGreaterThan(result.height, result.width, "Stitched result should be taller than wide")
        XCTAssertGreaterThan(result.height, frames[0].height, "Stitched result should be taller than a single frame")

        let outputURL = URL(fileURLWithPath: outputPath.replacingOccurrences(of: ".png", with: "-batch-cached.png"))
        try ImageExporter.export(result, to: outputURL, format: .png)
        print("[Stitch-Batch] Saved to: \(outputURL.path)")
    }

    /// Regression replay for an external cached frame directory.
    /// Usage:
    /// PICELF_CACHE_FRAMES_DIR="/path/to/capture.frames" xcodebuild test ...
    @MainActor
    func test_stitchFromExternalCachedFrames_regression() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR",
            label: "ExternalCache",
            outputSuffix: "-external-cache.png"
        )
    }

    /// Regression replay for the fixed-panels duplication case.
    /// Usage:
    /// PICELF_CACHE_FRAMES_DIR_FIXED="/path/to/capture.frames" xcodebuild test ...
    @MainActor
    func test_stitchFromExternalCachedFrames_fixedPanels_regression() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_FIXED",
            label: "ExternalCacheFixedPanels",
            outputSuffix: "-external-cache-fixed-panels.png"
        )
    }

    /// Stable selector wrapper for fixed-panels cache regression.
    @MainActor
    func test_externalCache_223120_fixedPanels() async throws {
        var profile = E2EValidationProfile.highRecall
        profile.minContrast = 80  // Low-contrast UI panels
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_FIXED",
            label: "ExternalCacheFixedPanels223120",
            outputSuffix: "-external-cache-fixed-panels-223120.png",
            profile: profile
        )
    }

    /// Stable selector wrapper for additional fixed-element cache regression.
    @MainActor
    func test_externalCache_232054_fixedElements() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_232054",
            label: "ExternalCacheFixedElements232054",
            outputSuffix: "-external-cache-fixed-elements-232054.png"
        )
    }

    /// Stable selector wrapper for 013723 cache regression (50 frames).
    @MainActor
    func test_externalCache_013723() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_013723",
            label: "ExternalCache013723",
            outputSuffix: "-external-cache-013723.png"
        )
    }

    /// Regression test for ClawHub (F0EAC26A): 86 frames, large sticky header (349px).
    /// Validates that detectTopStaticRows handles headers > 200px.
    @MainActor
    func test_externalCache_clawhub() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_CLAWHUB",
            label: "ExternalCacheClawHub",
            outputSuffix: "-external-cache-clawhub.png"
        )
    }

    /// Regression test for Pinard blog (C19578F3): 62 frames, Vision returns ty=0.
    /// Validates MAD fallback offset detection for small scrolls (46-60px).
    @MainActor
    func test_externalCache_pinard() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_PINARD",
            label: "ExternalCachePinard",
            outputSuffix: "-external-cache-pinard.png"
        )
    }

    /// Regression test for ClawHub (DEC4EFCD): 87 frames, tiny ~8px avg scroll, 349px header.
    /// Validates MAD offset detection for very small scrolls (offset < 10px).
    @MainActor
    func test_externalCache_clawhub_DEC4EFCD() async throws {
        var profile = E2EValidationProfile.highRecall
        profile.requireTallerThanWide = false  // short page: output is wider than tall
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_CLAWHUB2",
            label: "ExternalCacheClawHubDEC4",
            outputSuffix: "-external-cache-clawhub-dec4.png",
            profile: profile,
            expectedHeight: 2700
        )
    }

    /// Regression test for Pinard blog (0F106ADA): 67 frames, Vision=0 for all, ~50px scroll with animation.
    /// Validates trimmed mean MAD fallback for animated content.
    @MainActor
    func test_externalCache_pinard_0F106ADA() async throws {
        var profile = E2EValidationProfile.highRecall
        profile.requireTallerThanWide = false  // may be wider than tall depending on frame acceptance
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_PINARD2",
            label: "ExternalCachePinard0F10",
            outputSuffix: "-external-cache-pinard-0f10.png",
            profile: profile,
            expectedHeight: 4700,
            heightTolerance: 0.15  // wider tolerance — new template matching algorithm + animated sidebar
        )
    }

    /// Stable selector wrapper for 214802 cache regression.
    @MainActor
    func test_externalCache_214802() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_214802",
            label: "ExternalCache214802",
            outputSuffix: "-external-cache-214802.png"
        )
    }

    /// Stable selector wrapper for 221009 cache (terminal with bottom-fixed tab bar).
    /// Uses relaxed profile: dark terminal has low contrast and visually repetitive prompt lines.
    @MainActor
    func test_externalCache_221009() async throws {
        var terminalProfile = E2EValidationProfile.highRecall
        terminalProfile.minContrast = 80
        terminalProfile.repeatedSectionRules.criticalMinConsecutiveWindows = 20
        terminalProfile.duplicationRules.criticalAreaRatio = 0.25
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/external.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_221009",
            label: "ExternalCache221009",
            outputSuffix: "-external-cache-221009.png",
            profile: terminalProfile
        )
    }

    /// CSDN tutorial article with animated sidebar widgets (D9B044D8).
    /// No ground truth available — validate structure only, no height assertion.
    /// Uses relaxed duplication profile: tutorial articles contain multiple similar-looking
    /// screenshots (Apple Developer portal at different steps) that trigger false positives.
    @MainActor
    func test_externalCache_D9B044D8_animated() async throws {
        var articleProfile = E2EValidationProfile.highRecall
        articleProfile.duplicationRules.criticalAreaRatio = 0.40
        articleProfile.duplicationRules.warningMedianMAD = 3.0
        articleProfile.seamRules.criticalMaxBandMAD = 0.5  // Whitespace bands register ~0.9 MAD; only flag truly identical seams
        articleProfile.repeatedSectionRules.criticalMinConsecutiveWindows = 6  // Tutorial screenshots look similar; need longer run for critical
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/picelf-20260306-144243-D9B044D8.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_D9B044D8",
            label: "ExternalCacheD9B044D8",
            outputSuffix: "-external-cache-D9B044D8.png",
            profile: articleProfile
        )
    }

    /// Web page with large fixed header (28E4C37D).
    /// Tests SSD matching with 333px static header region.
    /// Uses relaxed edge-overlay rules — Bilibili's consistent sidebar triggers false positives.
    @MainActor
    func test_externalCache_28E4C37D_fixedHeader() async throws {
        var webProfile = E2EValidationProfile.highRecall
        webProfile.edgeOverlayRules.maxStripMAD = 5.0  // Tighter: only flag near-identical edge strips
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/picelf-20260306-144036-28E4C37D.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_28E4C37D",
            label: "ExternalCache28E4C37D",
            outputSuffix: "-external-cache-28E4C37D.png",
            profile: webProfile,
            expectedHeight: 4948,
            heightTolerance: 0.15
        )
    }

    /// Apple Developer documentation page with fixed header + sidebar (442E95DD).
    /// Ground truth: 1920x3378. Adjusted for our width (1880): ~3378.
    @MainActor
    func test_externalCache_A2186CF4_zhihuArticle() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/picelf-20260306-163122-A2186CF4.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_A2186CF4",
            label: "ExternalCacheA2186CF4",
            outputSuffix: "-external-cache-A2186CF4.png",
            ocrBenchmark: OCRBenchmarkSpec(
                benchmarkImageURL: URL(fileURLWithPath: fixturesPath + "/picelf-20260306-163122-A2186CF4_benchmark.png")
            ),
            expectedHeight: 2824,
            heightTolerance: 0.15
        )
    }

    func test_externalCache_442E95DD_appleDevDoc() async throws {
        try await runExternalCacheRegression(
            defaultExternalCacheDir: fixturesPath + "/picelf-20260306-155117-442E95DD.frames",
            envKey: "PICELF_CACHE_FRAMES_DIR_442E95DD",
            label: "ExternalCache442E95DD",
            outputSuffix: "-external-cache-442E95DD.png",
            expectedHeight: 3378,
            heightTolerance: 0.15
        )
    }

    @MainActor
    private func runExternalCacheRegression(
        defaultExternalCacheDir: String,
        envKey: String,
        label: String,
        outputSuffix: String,
        profile: E2EValidationProfile = .highRecall,
        ocrBenchmark: OCRBenchmarkSpec? = nil,
        expectedHeight: Int? = nil,
        heightTolerance: Double = 0.05
    ) async throws {
        let cacheDir = resolvedExternalCacheDir(
            defaultExternalCacheDir: defaultExternalCacheDir,
            envKey: envKey
        )
        guard FileManager.default.fileExists(atPath: cacheDir) else {
            throw XCTSkip("External cache dir not found: \(cacheDir)")
        }
        let cacheURL = URL(fileURLWithPath: cacheDir, isDirectory: true)
        guard let frames = loadCachedFrames(from: cacheURL) else {
            XCTFail("Failed to load cached frames from: \(cacheDir)")
            return
        }
        try XCTSkipIf(frames.count < 2, "Need at least 2 cached frames")

        let coordinator = StitchingCoordinator()
        coordinator.useDiskBackedStorage = false

        for frame in frames {
            coordinator.appendFrame(frame)
        }
        print("[\(label)] Fed \(coordinator.frameCount) frames")

        let start = CFAbsoluteTimeGetCurrent()
        let result = try await coordinator.stitch(onProgress: nil)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        guard let resultCG = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Could not convert NSImage to CGImage")
            return
        }

        XCTAssertLessThan(elapsed, 20.0,
            "[\(label)] Stitch took \(String(format: "%.1f", elapsed))s — must complete in <20s")
        print("[\(label)] Stitch finished in \(String(format: "%.2f", elapsed))s size=\(resultCG.width)x\(resultCG.height)")
        if let metrics = coordinator.lastRunMetrics {
            print(
                "[\(label)] Metrics frames=\(metrics.totalFrames) skipped=\(metrics.skippedFrames) down=\(metrics.downScrollFrames) up=\(metrics.upScrollFrames) duplicateRejects=\(metrics.duplicateRejects) noMoveRejects=\(metrics.noMovementRejects) elapsedMs=\(metrics.elapsedMilliseconds)"
            )
        }

        XCTAssertGreaterThan(resultCG.height, frames[0].height, "Stitched image should be taller than one frame")
        XCTAssertGreaterThan(resultCG.height, frames[0].height / 2, "Regression guard: must not collapse close to empty")

        // Expected height validation (±tolerance)
        if let expectedHeight = expectedHeight {
            let tolerance = Int(Double(expectedHeight) * heightTolerance)
            XCTAssertGreaterThan(resultCG.height, expectedHeight - tolerance,
                "[\(label)] Output height \(resultCG.height) is too short (expected ~\(expectedHeight) ±\(tolerance))")
            XCTAssertLessThan(resultCG.height, expectedHeight + tolerance,
                "[\(label)] Output height \(resultCG.height) is too tall (expected ~\(expectedHeight) ±\(tolerance))")
        }

        let contrastSample = CGRect(
            x: 50,
            y: min(400, max(0, resultCG.height / 4)),
            width: max(1, min(800, resultCG.width - 100)),
            height: max(1, min(220, resultCG.height / 6))
        )
        let context = E2EValidationContext(
            acceptedFrameCount: frames.count,
            windowPixelWidth: frames[0].width,
            windowPixelHeight: frames[0].height,
            contrastSampleRect: contrastSample
        )
        let report = E2EStitchValidator.validateStitchedImage(
            resultCG,
            context: context,
            profile: profile,
            policy: .criticalOnly
        )
        print(report.formattedSummary(prefix: "[\(label)]"))
        XCTAssertTrue(report.passed, report.failureSummary(prefix: "[\(label)]"))

        let fixtureOutputURL = URL(fileURLWithPath: outputPath.replacingOccurrences(of: ".png", with: outputSuffix))
        let outputURL = regressionMirrorOutputURL(for: fixtureOutputURL)
        try exportRegressionPNG(resultCG, to: outputURL)
        print("[\(label)] Saved to: \(outputURL.path)")
        print("[\(label)] Fixture mirror target: \(fixtureOutputURL.path)")

        if let ocrBenchmark {
            let ocrReport = try await E2EOCRBenchmarkValidator.validate(
                outputImage: resultCG,
                outputImageURL: outputURL,
                benchmarkImageURL: ocrBenchmark.benchmarkImageURL,
                thresholds: ocrBenchmark.thresholds
            )
            print(ocrReport.formattedSummary(prefix: "[\(label)]"))
            XCTAssertTrue(ocrReport.passed, ocrReport.failureSummary(prefix: "[\(label)]"))
        }
    }

    private func resolvedExternalCacheDir(defaultExternalCacheDir: String, envKey: String) -> String {
        let envPath = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath = (envPath?.isEmpty == false) ? envPath! : defaultExternalCacheDir

        // Some archived fixture sets reliably wedge the XCTest app host when opened
        // from their original Desktop-backed location. Prefer clean mirrors when present.
        let mirrorMappings: [(suffix: String, mirror: String)] = [
            ("/picelf-20260306-163122-A2186CF4.frames", "/private/tmp/picelf-clean-a218-rewrite.frames"),
            ("/picelf-20260306-144036-28E4C37D.frames", "/private/tmp/picelf-clean-28-rewrite.frames"),
            ("/picelf-20260306-144243-D9B044D8.frames", "/private/tmp/picelf-clean-d9-rewrite.frames"),
        ]

        for mapping in mirrorMappings where basePath.hasSuffix(mapping.suffix) {
            if FileManager.default.fileExists(atPath: mapping.mirror) {
                print("[E2E] Remapped cache dir to stable mirror: \(mapping.mirror)")
                return mapping.mirror
            }
        }

        return basePath
    }

    private func exportRegressionPNG(_ image: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw StitchingError.exportFailed(
                format: "PNG",
                reason: "Could not encode bitmap representation for regression export."
            )
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) == false {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: data)
    }

    private func regressionMirrorOutputURL(for fixtureURL: URL) -> URL {
        let mirrorDir = URL(fileURLWithPath: "/private/tmp/picelf-regression-output", isDirectory: true)
        try? FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)
        return mirrorDir.appendingPathComponent(fixtureURL.lastPathComponent)
    }

}
