import XCTest
import CoreGraphics
import AppKit
@testable import Picelf

@MainActor
final class WorkbenchStoreTests: XCTestCase {
    func test_enqueueCompletesAndPersistsResult() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let resultImage = makeStripedImage(width: 200, height: 120)
        let runner = FakeWorkbenchRunner(plans: [.success(resultImage, delayMS: 20)])
        let submission = makeSubmission(title: "Complete Case", runner: runner, frameCount: 6)

        store.enqueue(submission: submission)
        let completed = await waitForJob(in: store, titled: "Complete Case", status: .completed)
        XCTAssertNotNil(completed, "Expected completed workbench job")
        XCTAssertEqual(completed?.outputSize?.width, 200)
        XCTAssertEqual(completed?.outputSize?.height, 120)
        XCTAssertNotNil(completed?.outputURL, "Completed jobs should persist output image")
        if let url = completed?.outputURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func test_cancelQueuedJobMarksCancelled() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let firstRunner = FakeWorkbenchRunner(plans: [.success(makeStripedImage(width: 240, height: 130), delayMS: 240)])
        let secondRunner = FakeWorkbenchRunner(plans: [.success(makeStripedImage(width: 220, height: 140), delayMS: 10)])

        store.enqueue(submission: makeSubmission(title: "Running Job", runner: firstRunner, frameCount: 7))
        store.enqueue(submission: makeSubmission(title: "Queued Job", runner: secondRunner, frameCount: 5))

        try await Task.sleep(nanoseconds: 60_000_000)
        guard let queuedID = store.jobs.first(where: { $0.sourceWindowTitle == "Queued Job" })?.id else {
            XCTFail("Queued job not found")
            return
        }

        store.cancel(jobID: queuedID)

        let cancelled = await waitForJob(in: store, titled: "Queued Job", status: .cancelled)
        XCTAssertNotNil(cancelled, "Queued job should transition to cancelled")
        let runningCompleted = await waitForJob(in: store, titled: "Running Job", status: .completed)
        XCTAssertNotNil(runningCompleted, "Running job should still complete")
        XCTAssertEqual(secondRunner.stitchCallCount, 0, "Cancelled queued job should never start stitching")
    }

    func test_retryFailedJobCompletesOnSecondAttempt() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let runner = FakeWorkbenchRunner(plans: [
            .failure(FakeWorkbenchRunner.FakeError.syntheticFailure, delayMS: 20),
            .success(makeStripedImage(width: 210, height: 110), delayMS: 20)
        ])

        store.enqueue(submission: makeSubmission(title: "Retry Case", runner: runner, frameCount: 8))
        let failed = await waitForJob(in: store, titled: "Retry Case", status: .failed)
        XCTAssertNotNil(failed)

        guard let retryID = failed?.id else {
            XCTFail("Failed job id missing")
            return
        }
        store.retry(jobID: retryID)

        let completed = await waitForJob(in: store, titled: "Retry Case", status: .completed)
        XCTAssertNotNil(completed, "Retry should complete successfully")
        XCTAssertEqual(runner.stitchCallCount, 2)
    }

    func test_snapRunnerCompletesImmediately() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let image = makeStripedImage(width: 300, height: 200)
        let submission = CaptureSubmission(
            runner: SnapRunner(image: image),
            windowInfo: nil,
            acceptedFrameCount: 1,
            captureRect: .zero,
            captureType: .snap,
            submittedAt: Date()
        )
        store.enqueue(submission: submission)
        let job = try await waitForJob(in: store, titled: "(untitled window)", status: .completed)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.captureType, .snap)
        XCTAssertEqual(job?.captureFrameCount, 1)
        XCTAssertNotNil(job?.outputURL)
    }

    func test_oldJSONWithoutCaptureTypeDecodesAsScroll() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","createdAt":0,"sourceAppName":"Test","sourceWindowTitle":"Test","captureFrameCount":5,"captureRectX":0,"captureRectY":0,"captureRectW":100,"captureRectH":100,"status":"completed","progress":1,"phase":"Done"}]
        """
        let jobs = try JSONDecoder().decode([WorkbenchJob].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(jobs.first?.captureType, .scroll)
        XCTAssertEqual(jobs.first?.outputKind, .image)
    }

    func test_oldJSONWithoutOutputKindInfersVideoForRecording() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","createdAt":0,"sourceAppName":"Test","sourceWindowTitle":"Record","captureFrameCount":1,"captureRectX":0,"captureRectY":0,"captureRectW":100,"captureRectH":100,"captureType":"recording","status":"completed","progress":1,"phase":"Done","outputURL":"file:///tmp/test.mov"}]
        """
        let jobs = try JSONDecoder().decode([WorkbenchJob].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(jobs.first?.captureType, .recording)
        XCTAssertEqual(jobs.first?.outputKind, .video)
    }

    func test_importImageCreatesCustomCompletedJob() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }

        let importedID = await store.importImage(
            makeStripedImage(width: 210, height: 140),
            sourceName: "diagram.png"
        )

        guard let importedID,
              let job = store.jobs.first(where: { $0.id == importedID }) else {
            XCTFail("Expected imported image job")
            return
        }

        XCTAssertEqual(job.captureType, .custom)
        XCTAssertEqual(job.outputKind, .image)
        XCTAssertEqual(job.sourceWindowTitle, L10n.custom)
        XCTAssertEqual(job.sourceAppName, "diagram.png")
        XCTAssertEqual(job.status, .completed)
        XCTAssertNotNil(job.outputURL)
        if let outputURL = job.outputURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func test_importVideoFileCreatesCustomCompletedJob() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-import-\(UUID().uuidString).mov")
        try Data("fake-video".utf8).write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let importedIDs = await store.importFiles([sourceURL])
        guard let importedID = importedIDs.first,
              let job = store.jobs.first(where: { $0.id == importedID }) else {
            XCTFail("Expected imported video job")
            return
        }

        XCTAssertEqual(job.captureType, .custom)
        XCTAssertEqual(job.outputKind, .video)
        XCTAssertEqual(job.sourceWindowTitle, L10n.custom)
        XCTAssertEqual(job.sourceAppName, sourceURL.lastPathComponent)
        XCTAssertEqual(job.status, .completed)
        XCTAssertNotNil(job.outputURL)
        if let outputURL = job.outputURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            XCTAssertTrue(store.isManagedOutputURL(outputURL))
        }
    }

    func test_recordingRunnerCompletesAndPersistsManagedVideoWithoutPreviewFrame() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }

        let sourceURL = try makeTempVideoFile(contents: Data("not-a-real-video".utf8))
        let submission = CaptureSubmission(
            runner: ScreenRecordingRunner(videoURL: sourceURL, duration: 3.25),
            windowInfo: makeWindowInfo(title: "Recorded Clip"),
            acceptedFrameCount: 0,
            captureRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            captureType: .recording,
            submittedAt: Date()
        )

        store.enqueue(submission: submission)

        let job = await waitForJob(in: store, titled: "Recorded Clip", status: .completed)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.captureType, .recording)
        XCTAssertEqual(job?.outputKind, .video)
        XCTAssertEqual(job?.videoDurationSeconds ?? 0, 3.25, accuracy: 0.001)
        XCTAssertNil(job?.outputSize, "Invalid video metadata should not block completion")
        if let outputURL = job?.outputURL {
            XCTAssertTrue(store.isManagedOutputURL(outputURL))
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        } else {
            XCTFail("Expected managed recording output URL")
        }
    }

    func test_recordingRunnerCompletedJobReloadsFromPersistence() async throws {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        let store = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL
        )
        defer { store.shutdownForTesting() }

        let sourceURL = try makeTempVideoFile(contents: Data("persisted-recording".utf8))
        let submission = CaptureSubmission(
            runner: ScreenRecordingRunner(videoURL: sourceURL, duration: 1.5),
            windowInfo: makeWindowInfo(title: "Persisted Recording"),
            acceptedFrameCount: 0,
            captureRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            captureType: .recording,
            submittedAt: Date()
        )

        store.enqueue(submission: submission)
        let completed = await waitForJob(in: store, titled: "Persisted Recording", status: .completed)
        XCTAssertNotNil(completed)

        let reloaded = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL
        )
        defer { reloaded.shutdownForTesting() }

        XCTAssertEqual(reloaded.jobs.count, 1)
        XCTAssertEqual(reloaded.jobs.first?.sourceWindowTitle, "Persisted Recording")
        XCTAssertEqual(reloaded.jobs.first?.captureType, .recording)
        XCTAssertEqual(reloaded.jobs.first?.outputKind, .video)
        XCTAssertNotNil(reloaded.jobs.first?.outputURL)
    }

    func test_recordingPersistenceFallsBackToCopyWhenMoveFails() async throws {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        let store = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL,
            managedFileOperations: ManagedFileOperations(
                move: { _, _ in throw CocoaError(.fileWriteUnknown) },
                copy: { try FileManager.default.copyItem(at: $0, to: $1) },
                remove: { try FileManager.default.removeItem(at: $0) }
            )
        )
        defer { store.shutdownForTesting() }

        let sourceURL = try makeTempVideoFile(contents: Data("copy-fallback".utf8))
        let submission = CaptureSubmission(
            runner: ScreenRecordingRunner(videoURL: sourceURL, duration: 2.0),
            windowInfo: makeWindowInfo(title: "Copy Fallback Recording"),
            acceptedFrameCount: 0,
            captureRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            captureType: .recording,
            submittedAt: Date()
        )

        store.enqueue(submission: submission)

        let completed = await waitForJob(in: store, titled: "Copy Fallback Recording", status: .completed)
        XCTAssertNotNil(completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path), "Source temp file should be removed after copy fallback")
        if let outputURL = completed?.outputURL {
            XCTAssertTrue(store.isManagedOutputURL(outputURL))
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        } else {
            XCTFail("Expected managed output after copy fallback")
        }
    }

    func test_recordingPersistenceFailureMarksJobFailedInsteadOfCompletingWithTempURL() async throws {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        let store = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL,
            managedFileOperations: ManagedFileOperations(
                move: { _, _ in throw CocoaError(.fileWriteUnknown) },
                copy: { _, _ in throw CocoaError(.fileWriteOutOfSpace) },
                remove: { _ in }
            )
        )
        defer { store.shutdownForTesting() }

        let sourceURL = try makeTempVideoFile(contents: Data("broken-persist".utf8))
        let submission = CaptureSubmission(
            runner: ScreenRecordingRunner(videoURL: sourceURL, duration: 0.8),
            windowInfo: makeWindowInfo(title: "Broken Recording"),
            acceptedFrameCount: 0,
            captureRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            captureType: .recording,
            submittedAt: Date()
        )

        store.enqueue(submission: submission)

        let failed = await waitForJob(in: store, titled: "Broken Recording", status: .failed)
        XCTAssertNotNil(failed)
        XCTAssertNil(failed?.outputURL, "Failed recording persistence must not keep temp URLs as output")
        XCTAssertEqual(failed?.outputKind, .video)
        XCTAssertTrue(failed?.errorDescription?.contains("Failed to persist recording to Workbench") == true)
    }

    func test_importFromPasteboardCreatesCustomClipboardImageJob() async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let clipboardImage = makeStripedImage(width: 160, height: 96)
        try clipboardImage.copyToClipboard()

        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }

        let importedIDs = await store.importFromPasteboard()
        guard let importedID = importedIDs.first,
              let job = store.jobs.first(where: { $0.id == importedID }) else {
            XCTFail("Expected imported clipboard image job")
            return
        }

        XCTAssertEqual(job.captureType, .custom)
        XCTAssertEqual(job.outputKind, .image)
        XCTAssertEqual(job.sourceWindowTitle, L10n.custom)
        XCTAssertEqual(job.sourceAppName, L10n.clipboard)
    }

    func test_copyResultToClipboardCopiesCompletedImportedImage() async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let importedID = await store.importImage(
            makeStripedImage(width: 180, height: 110),
            sourceName: "copy-me.png"
        )

        guard let importedID else {
            XCTFail("Expected imported image id")
            return
        }
        XCTAssertTrue(store.copyResultToClipboard(jobID: importedID))
        XCTAssertNotNil(pasteboard.data(forType: .png))
    }

    func test_persistJobs_keepsCompletedOnly() async throws {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        let store = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL
        )
        defer { store.shutdownForTesting() }

        let failedRunner = FakeWorkbenchRunner(plans: [
            .failure(FakeWorkbenchRunner.FakeError.syntheticFailure, delayMS: 20),
        ])
        let completedRunner = FakeWorkbenchRunner(plans: [
            .success(makeStripedImage(width: 128, height: 88), delayMS: 20),
        ])

        store.enqueue(submission: makeSubmission(title: "Persisted Fail", runner: failedRunner, frameCount: 2))
        store.enqueue(submission: makeSubmission(title: "Persisted Complete", runner: completedRunner, frameCount: 3))

        let failed = await waitForJob(in: store, titled: "Persisted Fail", status: .failed)
        XCTAssertNotNil(failed)
        let completed = await waitForJob(in: store, titled: "Persisted Complete", status: .completed)
        XCTAssertNotNil(completed)

        let data = try Data(contentsOf: jobsFileURL)
        let persisted = try JSONDecoder().decode([WorkbenchJob].self, from: data)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.status, .completed)
        XCTAssertEqual(persisted.first?.sourceWindowTitle, "Persisted Complete")
    }

    func test_loadPersistedJobs_dropsUnmanagedAndNonCompletedRecords() throws {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        let unmanagedDirectory = makeTempOutputDirectory()
        let now = Date()

        let managedOutputURL = outputDirectory.appendingPathComponent("managed.png")
        try ImageExporter.export(makeStripedImage(width: 100, height: 60), to: managedOutputURL, format: .png)
        let unmanagedOutputURL = unmanagedDirectory.appendingPathComponent("unmanaged.png")
        try ImageExporter.export(makeStripedImage(width: 100, height: 60), to: unmanagedOutputURL, format: .png)

        let managedJob = WorkbenchJob(
            id: UUID(),
            createdAt: now,
            sourceAppName: "Managed App",
            sourceWindowTitle: "Managed Job",
            captureFrameCount: 1,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 60),
            captureType: .snap,
            startedAt: now,
            endedAt: now,
            status: .completed,
            progress: 1,
            phase: L10n.phaseDone,
            outputSize: CGSize(width: 100, height: 60),
            outputURL: managedOutputURL,
            errorDescription: nil
        )

        let unmanagedJob = WorkbenchJob(
            id: UUID(),
            createdAt: now,
            sourceAppName: "Unmanaged App",
            sourceWindowTitle: "Unmanaged Job",
            captureFrameCount: 1,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 60),
            captureType: .snap,
            startedAt: now,
            endedAt: now,
            status: .completed,
            progress: 1,
            phase: L10n.phaseDone,
            outputSize: CGSize(width: 100, height: 60),
            outputURL: unmanagedOutputURL,
            errorDescription: nil
        )

        let failedJob = WorkbenchJob(
            id: UUID(),
            createdAt: now,
            sourceAppName: "Failed App",
            sourceWindowTitle: "Failed Job",
            captureFrameCount: 2,
            captureRect: CGRect(x: 0, y: 0, width: 120, height: 80),
            captureType: .scroll,
            startedAt: now,
            endedAt: now,
            status: .failed,
            progress: 0.5,
            phase: L10n.phaseFailed,
            outputSize: nil,
            outputURL: nil,
            errorDescription: "synthetic"
        )

        let seedData = try JSONEncoder().encode([managedJob, unmanagedJob, failedJob])
        try seedData.write(to: jobsFileURL, options: .atomic)

        let store = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL
        )
        defer { store.shutdownForTesting() }

        XCTAssertEqual(store.jobs.count, 1)
        XCTAssertEqual(store.jobs.first?.sourceWindowTitle, "Managed Job")

        let rewrittenData = try Data(contentsOf: jobsFileURL)
        let rewritten = try JSONDecoder().decode([WorkbenchJob].self, from: rewrittenData)
        XCTAssertEqual(rewritten.count, 1)
        XCTAssertEqual(rewritten.first?.sourceWindowTitle, "Managed Job")
    }

    func test_isManagedOutputURL_acceptsOnlyInsideOutputDirectory() {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        let store = WorkbenchStore(
            maxConcurrentJobs: 1,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL
        )
        defer { store.shutdownForTesting() }

        let inside = outputDirectory.appendingPathComponent("inside.png")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).png")

        XCTAssertTrue(store.isManagedOutputURL(inside))
        XCTAssertFalse(store.isManagedOutputURL(outside))
    }

    func test_scrollAutoClipboard_appliesWatermarkWhenEnabled() async throws {
        let prefs = AppPreferences.shared
        let originalConfig = prefs.watermarkConfig
        defer { prefs.watermarkConfig = originalConfig }

        var config = WatermarkConfig()
        config.isEnabled = true
        config.text = "PICELF-WM"
        config.tiledEnabled = false
        config.position = .middleCenter
        config.opacity = 1
        config.fontSize = 26
        prefs.watermarkConfig = config

        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let baseImage = makeStripedImage(width: 240, height: 150)
        let runner = FakeWorkbenchRunner(plans: [.success(baseImage, delayMS: 20)])
        store.enqueue(submission: makeSubmission(title: "Clipboard Watermark", runner: runner, frameCount: 5))

        let completed = await waitForJob(in: store, titled: "Clipboard Watermark", status: .completed)
        XCTAssertNotNil(completed)

        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .png), let clipboardImage = NSImage(data: data) else {
            XCTFail("Expected PNG data on pasteboard")
            return
        }
        let expected = CaptureOutputWatermarking.render(baseImage)
        let clipboardData = normalizedRGBAData(of: clipboardImage)
        let expectedData = normalizedRGBAData(of: expected)
        let baseData = normalizedRGBAData(of: baseImage)

        let diffToExpected = meanAbsoluteByteDifference(lhs: clipboardData, rhs: expectedData)
        let diffToBase = meanAbsoluteByteDifference(lhs: clipboardData, rhs: baseData)

        XCTAssertLessThanOrEqual(diffToExpected, 1.5, "Clipboard watermark output diverged too much from expected render")
        XCTAssertGreaterThan(diffToBase, 0.5, "Watermark-enabled output should differ from base image")
    }

    func test_completedCaptureExpiresAndDeletesOutputFile() async throws {
        let suite = "com.picelf.tests.retention.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        prefs.captureRetentionUnit = .seconds
        prefs.captureRetentionValue = 1

        let store = makeIsolatedStore(maxConcurrentJobs: 1, preferences: prefs)
        defer { store.shutdownForTesting() }
        let jobID = store.addCompletedSnap(
            image: makeStripedImage(width: 180, height: 120),
            windowInfo: makeWindowInfo(title: "Expires Soon"),
            captureRect: CGRect(x: 0, y: 0, width: 180, height: 120)
        )
        let completed = await waitForJob(in: store, titled: "Expires Soon", status: .completed)
        let outputURL = completed?.outputURL
        XCTAssertNotNil(outputURL)
        let frameCacheDir = outputURL.map { createDummyFrameCache(for: $0) }

        let removed = await waitForJobAbsence(in: store, id: jobID, timeoutSeconds: 4)
        XCTAssertTrue(removed, "Expected completed job to expire")
        if let outputURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), "Expired output file should be deleted")
        }
        if let frameCacheDir {
            XCTAssertFalse(FileManager.default.fileExists(atPath: frameCacheDir.path), "Expired frame cache should be deleted")
        }
    }

    func test_removeDeletesOutputAndFrameCache() async throws {
        let store = makeIsolatedStore(maxConcurrentJobs: 1)
        defer { store.shutdownForTesting() }
        let jobID = store.addCompletedSnap(
            image: makeStripedImage(width: 200, height: 140),
            windowInfo: makeWindowInfo(title: "Manual Delete"),
            captureRect: CGRect(x: 0, y: 0, width: 200, height: 140)
        )

        guard let outputURL = await waitForJob(in: store, titled: "Manual Delete", status: .completed)?.outputURL else {
            XCTFail("Expected outputURL for completed capture")
            return
        }
        let frameCacheDir = createDummyFrameCache(for: outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: frameCacheDir.path))

        store.remove(jobID: jobID)

        XCTAssertNil(store.jobs.first(where: { $0.id == jobID }), "Expected job to be removed from store")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), "Deleted capture should remove output file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: frameCacheDir.path), "Deleted capture should remove frame cache")
    }

    func test_pinnedCaptureDoesNotExpire() async throws {
        let suite = "com.picelf.tests.retention.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        prefs.captureRetentionUnit = .seconds
        prefs.captureRetentionValue = 1

        let store = makeIsolatedStore(maxConcurrentJobs: 1, preferences: prefs)
        defer { store.shutdownForTesting() }
        let jobID = store.addCompletedSnap(
            image: makeStripedImage(width: 160, height: 100),
            windowInfo: makeWindowInfo(title: "Pinned Keep"),
            captureRect: CGRect(x: 0, y: 0, width: 160, height: 100)
        )
        store.markPinned(jobID: jobID)

        try await Task.sleep(nanoseconds: 2_200_000_000)
        let job = store.jobs.first(where: { $0.id == jobID })
        XCTAssertNotNil(job)
        XCTAssertTrue(job?.isPinned == true)
    }

    func test_shorteningRetentionPurgesExistingCapturesImmediately() async throws {
        let suite = "com.picelf.tests.retention.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        prefs.captureRetentionUnit = .hours
        prefs.captureRetentionValue = 1

        let store = makeIsolatedStore(maxConcurrentJobs: 1, preferences: prefs)
        defer { store.shutdownForTesting() }
        let jobID = store.addCompletedSnap(
            image: makeStripedImage(width: 140, height: 90),
            windowInfo: makeWindowInfo(title: "Immediate Purge"),
            captureRect: CGRect(x: 0, y: 0, width: 140, height: 90)
        )

        try await Task.sleep(nanoseconds: 1_200_000_000)
        prefs.captureRetentionUnit = .seconds
        prefs.captureRetentionValue = 1

        let removed = await waitForJobAbsence(in: store, id: jobID, timeoutSeconds: 2)
        XCTAssertTrue(removed, "Expected retention policy change to purge old captures immediately")
    }

    private func makeSubmission(
        title: String,
        runner: any WorkbenchStitchJobRuntime,
        frameCount: Int
    ) -> CaptureSubmission {
        let windowInfo = WindowInfo(
            id: 42,
            title: title,
            appName: "Test Browser",
            appBundleID: "com.picelf.tests",
            frame: CGRect(x: 0, y: 0, width: 1024, height: 720),
            isOnScreen: true
        )

        return CaptureSubmission(
            runner: runner,
            windowInfo: windowInfo,
            acceptedFrameCount: frameCount,
            captureRect: CGRect(x: 100, y: 120, width: 900, height: 640),
            captureType: .scroll,
            submittedAt: Date()
        )
    }

    private func waitForJob(
        in store: WorkbenchStore,
        titled title: String,
        status: WorkbenchJobStatus,
        timeoutSeconds: Double = 4
    ) async -> WorkbenchJob? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let job = store.jobs.first(where: { $0.sourceWindowTitle == title && $0.status == status }) {
                return job
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return nil
    }

    private func waitForJobAbsence(
        in store: WorkbenchStore,
        id: UUID,
        timeoutSeconds: Double = 4
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if store.jobs.first(where: { $0.id == id }) == nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return false
    }

    private func makeWindowInfo(title: String) -> WindowInfo {
        WindowInfo(
            id: CGWindowID(Int.random(in: 1_000...9_999)),
            title: title,
            appName: "Retention App",
            appBundleID: "com.picelf.tests.retention",
            frame: CGRect(x: 0, y: 0, width: 900, height: 600),
            isOnScreen: true
        )
    }

    private func makeTempOutputDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-workbench-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempJobsFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-workbench-jobs-\(UUID().uuidString).json")
    }

    private func makeTempVideoFile(contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("picelf-recording-\(UUID().uuidString).mov")
        try contents.write(to: url, options: .atomic)
        return url
    }

    private func createDummyFrameCache(for outputURL: URL) -> URL {
        let framesDir = outputURL.deletingPathExtension().appendingPathExtension("frames")
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        let markerFile = framesDir.appendingPathComponent("frame-00000.dat")
        FileManager.default.createFile(atPath: markerFile.path, contents: Data("marker".utf8))
        return framesDir
    }

    private func normalizedRGBAData(of image: NSImage) -> Data {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: cg.width,
                height: cg.height,
                bitsPerComponent: 8,
                bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            XCTFail("Missing image data")
            return Data()
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let data = context.data else {
            XCTFail("Missing normalized image data")
            return Data()
        }
        return Data(bytes: data, count: cg.width * cg.height * 4)
    }

    private func meanAbsoluteByteDifference(lhs: Data, rhs: Data) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        let total = zip(lhs, rhs).reduce(into: UInt64(0)) { partial, pair in
            partial += UInt64(abs(Int(pair.0) - Int(pair.1)))
        }
        return Double(total) / Double(lhs.count)
    }

    private func makeIsolatedStore(
        maxConcurrentJobs: Int,
        preferences: AppPreferences = AppPreferences.shared
    ) -> WorkbenchStore {
        let outputDirectory = makeTempOutputDirectory()
        let jobsFileURL = makeTempJobsFileURL()
        return WorkbenchStore(
            maxConcurrentJobs: maxConcurrentJobs,
            outputDirectory: outputDirectory,
            jobsFileURL: jobsFileURL,
            preferences: preferences
        )
    }
}

@MainActor
private final class FakeWorkbenchRunner: WorkbenchStitchJobRuntime {
    enum FakeError: LocalizedError {
        case syntheticFailure
        case missingPlan

        var errorDescription: String? {
            switch self {
            case .syntheticFailure:
                return "Synthetic failure"
            case .missingPlan:
                return "Runner plan missing"
            }
        }
    }

    enum Plan {
        case success(NSImage, delayMS: UInt64)
        case failure(Error, delayMS: UInt64)
    }

    private(set) var stitchCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var resetCallCount = 0
    private var plans: [Plan]

    init(plans: [Plan]) {
        self.plans = plans
    }

    func stitch(onProgress: ((StitchingProgress) -> Void)?) async throws -> NSImage {
        stitchCallCount += 1
        guard !plans.isEmpty else {
            throw FakeError.missingPlan
        }

        let plan = plans.removeFirst()
        onProgress?(StitchingProgress(fraction: 0.2, phase: "Preparing", currentFrame: 0, totalFrames: 1))

        switch plan {
        case let .success(image, delayMS):
            if delayMS > 0 {
                try await Task.sleep(nanoseconds: delayMS * 1_000_000)
            }
            onProgress?(StitchingProgress(fraction: 1.0, phase: "Done", currentFrame: 1, totalFrames: 1))
            return image

        case let .failure(error, delayMS):
            if delayMS > 0 {
                try await Task.sleep(nanoseconds: delayMS * 1_000_000)
            }
            throw error
        }
    }

    func cancel() {
        cancelCallCount += 1
    }

    func reset() {
        resetCallCount += 1
    }
}
