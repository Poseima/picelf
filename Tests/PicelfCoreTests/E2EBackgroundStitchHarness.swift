import XCTest
import AppKit
import ImageIO
@testable import Picelf

enum E2EBackgroundStitchError: LocalizedError {
    case failed(reason: String)
    case timedOut(timeoutSeconds: Double)
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .failed(let reason):
            return "Background stitch failed: \(reason)"
        case .timedOut(let timeoutSeconds):
            return "Background stitch timed out after \(Int(timeoutSeconds))s"
        case .outputUnavailable:
            return "Background stitch completed but no output image was available"
        }
    }
}

@MainActor
enum E2EBackgroundStitchHarness {
    static func configure(
        orchestrator: CaptureOrchestrator,
        label: String,
        maxConcurrentJobs: Int = 1,
        showWorkbenchWindow: Bool = true,
        activateWorkbenchWindow: Bool = true
    ) -> WorkbenchStore {
        let runID = UUID().uuidString
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-e2e-workbench-\(runID)", isDirectory: true)
        let jobsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-e2e-workbench-\(runID).json")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let store = WorkbenchStore(
            maxConcurrentJobs: maxConcurrentJobs,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL
        )
        let workbenchWindowController = showWorkbenchWindow
            ? WorkbenchWindowController(store: store)
            : nil

        orchestrator.onCaptureSubmitted = { submission in
            print("[\(label)] Submitted to Workbench background queue: frames=\(submission.acceptedFrameCount)")
            let jobID = store.enqueue(submission: submission)
            print("[\(label)] Tracked Workbench job id: \(jobID.uuidString)")
            if let workbenchWindowController {
                workbenchWindowController.show(activate: activateWorkbenchWindow)
                print("[\(label)] Workbench window shown (activate=\(activateWorkbenchWindow))")
            }
        }
        return store
    }

    @MainActor
    static func assertWorkbenchVisible(
        label: String,
        timeoutSeconds: Double = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let visible = NSApp.windows.contains { window in
                guard window.title == "Picelf Workbench", window.isVisible else {
                    return false
                }
                return true
            }
            if visible { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        XCTFail(
            "[\(label)] Workbench window did not become visible within \(Int(timeoutSeconds))s",
            file: file,
            line: line
        )
    }

    static func awaitResult(
        from store: WorkbenchStore,
        label: String,
        timeoutSeconds: Double = 180,
        targetJobID: UUID? = nil
    ) async throws -> NSImage {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var openedImage: NSImage?
        var trackedJobID = targetJobID
        let previousOnOpen = store.onOpenImage
        store.onOpenImage = { image, url in
            openedImage = image
            previousOnOpen?(image, url)
        }
        defer {
            store.onOpenImage = previousOnOpen
        }

        var lastStatusSecond = -1
        while Date() < deadline {
            if trackedJobID == nil {
                trackedJobID = store.lastEnqueuedJobID
            }

            guard let trackedJobID else {
                try await Task.sleep(for: .milliseconds(200))
                continue
            }

            guard let tracked = store.jobs.first(where: { $0.id == trackedJobID }) else {
                try await Task.sleep(for: .milliseconds(200))
                continue
            }

            if tracked.status == .failed || tracked.status == .cancelled {
                throw E2EBackgroundStitchError.failed(reason: tracked.errorDescription ?? tracked.phase)
            }

            if tracked.status == .completed {
                store.open(jobID: tracked.id)
                if let openedImage {
                    return openedImage
                }

                if let outputURL = tracked.outputURL,
                   let image = NSImage(contentsOf: outputURL) {
                    return image
                }

                throw E2EBackgroundStitchError.outputUnavailable
            }

            let elapsed = Int(Date().timeIntervalSince(deadline.addingTimeInterval(-timeoutSeconds)))
            if elapsed != lastStatusSecond, elapsed % 3 == 0 {
                lastStatusSecond = elapsed
                let running = store.runningCount
                let queued = store.queuedCount
                let progress = Int((store.activeProgress * 100).rounded())
                print("[\(label)] Background stitching... running=\(running) queued=\(queued) progress=\(progress)%")
            }

            try await Task.sleep(for: .milliseconds(200))
        }

        throw E2EBackgroundStitchError.timedOut(timeoutSeconds: timeoutSeconds)
    }
}
