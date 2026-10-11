import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Combine
import os
import Darwin

private let workbenchLog = Logger(subsystem: "com.picelf", category: "Workbench")

private final class SnapPersistImageBox: @unchecked Sendable {
    let cgImage: CGImage?
    let image: NSImage
    init(_ image: NSImage) {
        self.image = image
        self.cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

private struct ImportedVideoMetadata: Sendable {
    let size: CGSize?
    let durationSeconds: Double?
}

struct ManagedFileOperations {
    let move: (URL, URL) throws -> Void
    let copy: (URL, URL) throws -> Void
    let remove: (URL) throws -> Void

    static let live = ManagedFileOperations(
        move: { try FileManager.default.moveItem(at: $0, to: $1) },
        copy: { try FileManager.default.copyItem(at: $0, to: $1) },
        remove: { try FileManager.default.removeItem(at: $0) }
    )
}

private struct ManagedOutputPersistenceError: LocalizedError {
    let sourceURL: URL
    let destinationURL: URL
    let moveError: Error
    let copyError: Error?

    var errorDescription: String? {
        if let copyError {
            return "Failed to persist recording to Workbench. Move: \(moveError.localizedDescription). Copy: \(copyError.localizedDescription)."
        }
        return "Failed to persist recording to Workbench: \(moveError.localizedDescription)."
    }
}

@MainActor
final class WorkbenchStore: ObservableObject {
    @Published private(set) var transferCount = 0
    @Published private(set) var jobs: [WorkbenchJob] = []
    @Published private(set) var lastEnqueuedJobID: UUID?

    let maxConcurrentJobs: Int
    var onOpenImage: ((NSImage, URL?) -> Void)?
    var onOpenCanvas: (([NSImage]) -> Void)?
    var onAddToCanvas: ((NSImage) -> Void)?
    var onPinImage: ((NSImage, UUID) -> Void)?

    private struct JobRuntime {
        let runner: any WorkbenchStitchJobRuntime
        var task: Task<Void, Never>?
    }

    private var runtimes: [UUID: JobRuntime] = [:]
    private var queue: [UUID] = []
    private var running: Set<UUID> = []
    private var userCancelled: Set<UUID> = []
    private let downloadPublisher: @Sendable (URL, URL) throws -> Bool
    private let clipboard: NSPasteboard
    private let downloadsDirectory: URL?
    private let outputDirectory: URL
    private let jobsFileURL: URL
    private let preferences: AppPreferences
    private let nowProvider: () -> Date
    private let managedFileOperations: ManagedFileOperations
    private var preferenceCancellables: Set<AnyCancellable> = []
    private var expiryTimer: Timer?

    private static let defaultOutputDirectory: URL = AppDataPaths.workbenchResultsDirectory

    private static let defaultJobsFileURL: URL = AppDataPaths.workbenchJobsFileURL

    init(
        maxConcurrentJobs: Int = 2,
        outputDirectory: URL? = nil,
        jobsFileURL: URL? = nil,
        preferences: AppPreferences = .shared,
        now: @escaping () -> Date = Date.init,
        managedFileOperations: ManagedFileOperations = .live,
        downloadsDirectory: URL? = nil,
        clipboard: NSPasteboard = .general,
        downloadPublisher: @escaping @Sendable (URL, URL) throws -> Bool = { try WorkbenchStore.publishDownload($0, $1) }
    ) {
        self.downloadPublisher = downloadPublisher
        self.clipboard = clipboard
        self.downloadsDirectory = downloadsDirectory
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
        let root = outputDirectory ?? Self.defaultOutputDirectory
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.outputDirectory = root
        self.jobsFileURL = jobsFileURL ?? Self.defaultJobsFileURL
        self.preferences = preferences
        self.nowProvider = now
        self.managedFileOperations = managedFileOperations
        loadPersistedJobs()
        observeRetentionPreferences()
        purgeExpiredJobs(reason: "startup")
        scheduleNextExpiryCheck()
    }

    var hasActiveWork: Bool {
        runningCount + queuedCount + transferCount > 0 || jobs.contains { $0.status == .processing }
    }

    func beginTransfer() { transferCount += 1 }
    func endTransfer() { transferCount -= 1 }

    var runningCount: Int { running.count }
    var queuedCount: Int { queue.count }
    var completedCount: Int { jobs.reduce(0) { $1.status == .completed ? $0 + 1 : $0 } }
    var failedCount: Int {
        jobs.reduce(0) {
            ($1.status == .failed || $1.status == .cancelled) ? $0 + 1 : $0
        }
    }
    var activeProgress: Double {
        let activeJobs = jobs.filter { $0.status == .queued || $0.status == .processing }
        guard !activeJobs.isEmpty else { return 0 }
        let total = activeJobs.reduce(0.0) { $0 + min(1, max(0, $1.progress)) }
        return total / Double(activeJobs.count)
    }

    // MARK: - Persistence

    private func loadPersistedJobs() {
        guard FileManager.default.fileExists(atPath: jobsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: jobsFileURL)
            let decoded = try JSONDecoder().decode([WorkbenchJob].self, from: data)
            var droppedNonCompleted = 0
            var droppedMissingOutput = 0
            var droppedUnmanagedOutput = 0
            let valid = decoded.compactMap { job -> WorkbenchJob? in
                guard job.status == .completed else {
                    droppedNonCompleted += 1
                    return nil
                }
                guard let url = job.outputURL else {
                    droppedMissingOutput += 1
                    return nil
                }
                guard isManagedOutputURL(url) else {
                    droppedUnmanagedOutput += 1
                    return nil
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    droppedMissingOutput += 1
                    return nil
                }
                return job
            }
            jobs = valid
            let droppedTotal = droppedNonCompleted + droppedMissingOutput + droppedUnmanagedOutput
            workbenchLog.notice(
                "Loaded \(valid.count) persisted jobs (dropped \(droppedTotal): nonCompleted=\(droppedNonCompleted), missingOutput=\(droppedMissingOutput), unmanagedOutput=\(droppedUnmanagedOutput))"
            )
            if droppedTotal > 0 {
                persistJobs()
            }
        } catch {
            workbenchLog.error("Failed to load persisted jobs: \(error.localizedDescription)")
        }
    }

    private func persistJobs() {
        let completed = jobs.filter { job in
            guard job.status == .completed, let url = job.outputURL else { return false }
            guard isManagedOutputURL(url) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(completed)
            let directory = jobsFileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: jobsFileURL, options: .atomic)
        } catch {
            workbenchLog.error("Failed to persist jobs: \(error.localizedDescription)")
        }
    }

    private func observeRetentionPreferences() {
        preferences.$captureRetentionValue
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.purgeExpiredJobs(reason: "retention-value-changed")
                self.scheduleNextExpiryCheck()
            }
            .store(in: &preferenceCancellables)

        preferences.$captureRetentionUnit
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.purgeExpiredJobs(reason: "retention-unit-changed")
                self.scheduleNextExpiryCheck()
            }
            .store(in: &preferenceCancellables)
    }

    private func now() -> Date {
        nowProvider()
    }

    private func expirationAnchor(for job: WorkbenchJob) -> Date {
        job.endedAt ?? job.createdAt
    }

    private func expirationDate(for job: WorkbenchJob) -> Date? {
        guard job.status.isTerminal, !job.isPinned else { return nil }
        return expirationAnchor(for: job).addingTimeInterval(preferences.captureRetentionInterval)
    }

    private func purgeExpiredJobs(reason: String) {
        let current = now()
        let expiredIDs = jobs.compactMap { job -> UUID? in
            guard let expiresAt = expirationDate(for: job) else { return nil }
            return expiresAt <= current ? job.id : nil
        }
        guard !expiredIDs.isEmpty else { return }

        for jobID in expiredIDs {
            removeJobFromStore(jobID: jobID, deleteOutput: true)
        }
        persistJobs()
        scheduleNextExpiryCheck()
        processQueue()
        workbenchLog.notice("Expired \(expiredIDs.count) capture(s) via \(reason, privacy: .public)")
    }

    private func scheduleNextExpiryCheck() {
        expiryTimer?.invalidate()
        expiryTimer = nil

        let current = now()
        let nextExpiration = jobs.compactMap { expirationDate(for: $0) }.min()
        guard let nextExpiration else { return }

        let delay = max(nextExpiration.timeIntervalSince(current), 0.1)
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.purgeExpiredJobs(reason: "timer")
                self.scheduleNextExpiryCheck()
            }
        }
        timer.tolerance = min(max(delay * 0.1, 0.1), 5)
        expiryTimer = timer
    }

    // MARK: - Job Management

    @discardableResult
    func enqueue(submission: CaptureSubmission) -> UUID {
        let id = UUID()
        let appName = submission.windowInfo?.appName ?? "(unknown app)"
        let title = submission.windowInfo?.title ?? "(untitled window)"
        let job = WorkbenchJob(
            id: id,
            createdAt: submission.submittedAt,
            sourceAppName: appName,
            sourceWindowTitle: title,
            captureFrameCount: submission.acceptedFrameCount,
            captureRect: submission.captureRect,
            captureType: submission.captureType,
            startedAt: nil,
            endedAt: nil,
            status: .queued,
            progress: 0,
            phase: L10n.phaseQueued,
            outputSize: nil,
            outputURL: nil,
            errorDescription: nil
        )

        jobs.insert(job, at: 0)
        runtimes[id] = JobRuntime(runner: submission.runner)
        queue.append(id)
        lastEnqueuedJobID = id

        workbenchLog.notice("Enqueued job \(id.uuidString, privacy: .public) frames=\(submission.acceptedFrameCount)")
        processQueue()
        return id
    }

    func cancel(jobID: UUID) {
        if let idx = queue.firstIndex(of: jobID) {
            queue.remove(at: idx)
            updateJob(jobID) { job in
                job.status = .cancelled
                job.phase = L10n.phaseCancelled
                job.progress = 0
                job.endedAt = now()
            }
            persistJobs()
            scheduleNextExpiryCheck()
            if var runtime = runtimes[jobID] {
                runtime.task = nil
                runtimes[jobID] = runtime
            }
            workbenchLog.notice("Cancelled queued job \(jobID.uuidString, privacy: .public)")
            return
        }

        userCancelled.insert(jobID)
        if let runtime = runtimes[jobID] {
            runtime.runner.cancel()
            runtime.task?.cancel()
            workbenchLog.notice("Cancellation requested for running job \(jobID.uuidString, privacy: .public)")
        }
    }

    func retry(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        guard job.status == .failed || job.status == .cancelled else { return }
        guard var runtime = runtimes[jobID] else {
            workbenchLog.warning("Retry ignored for \(jobID.uuidString, privacy: .public): runtime unavailable")
            return
        }

        userCancelled.remove(jobID)
        runtime.task?.cancel()
        runtime.task = nil
        runtimes[jobID] = runtime
        running.remove(jobID)
        queue.removeAll { $0 == jobID }
        updateJob(jobID) { updated in
            updated.startedAt = nil
            updated.endedAt = nil
            updated.status = .queued
            updated.progress = 0
            updated.phase = L10n.phaseQueued
            updated.outputSize = nil
            updated.outputURL = nil
            updated.errorDescription = nil
        }

        if !queue.contains(jobID) {
            queue.append(jobID)
        }
        persistJobs()
        scheduleNextExpiryCheck()
        workbenchLog.notice("Retry queued for job \(jobID.uuidString, privacy: .public)")
        processQueue()
    }

    func remove(jobID: UUID) {
        cancel(jobID: jobID)
        removeJobFromStore(jobID: jobID, deleteOutput: true)
        persistJobs()
        scheduleNextExpiryCheck()
        processQueue()
    }

    func open(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }

        // Video → system player
        if job.isVideoOutput, let url = job.outputURL {
            guard isManagedOutputURL(url), FileManager.default.fileExists(atPath: url.path) else {
                workbenchLog.warning("Skipping open for unmanaged or missing recording output: \(url.path, privacy: .public)")
                return
            }
            NSWorkspace.shared.open(url)
            return
        }

        // Image → editor (load from disk on demand, no in-memory caching)
        guard let url = job.outputURL, isManagedOutputURL(url), FileManager.default.fileExists(atPath: url.path) else {
            if let url = job.outputURL {
                workbenchLog.warning("Skipping open for unmanaged or missing image output: \(url.path, privacy: .public)")
            }
            return
        }
        guard let image = NSImage(contentsOf: url) else { return }
        onOpenImage?(image, url)
    }

    func image(for jobID: UUID) -> NSImage? {
        guard let job = jobs.first(where: { $0.id == jobID }),
              job.canAddToCanvas,
              let url = job.outputURL,
              isManagedOutputURL(url),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    @discardableResult
    func copyResultToClipboard(jobID: UUID, pasteboard: NSPasteboard? = nil) -> Bool {
        let pasteboard = pasteboard ?? clipboard
        guard let image = image(for: jobID),
              let cg = WatermarkRenderer.apply(to: image, config: preferences.watermarkConfig).cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    func saveResultToDownloads(jobID: UUID) async throws -> URL {
        beginTransfer()
        defer { endTransfer() }
        guard let image = image(for: jobID) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let box = SnapPersistImageBox(WatermarkRenderer.apply(to: image, config: preferences.watermarkConfig))
        let format: ImageExporter.Format = preferences.defaultFormat == .png
            ? .png : .jpeg(quality: CGFloat(preferences.jpegQuality))
        let directory = try downloadsDirectory ?? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Picelf-\(formatter.string(from: now()))"
        let publish = downloadPublisher
        return try await Task.detached(priority: .userInitiated) {
            let temporary = directory.appendingPathComponent(".Picelf-\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            if let cg = box.cgImage {
                try ImageExporter.export(cg, to: temporary, format: format)
            } else {
                try ImageExporter.export(box.image, to: temporary, format: format)
            }
            // A same-volume hard link publishes the completed file atomically and
            // fails with EEXIST rather than overwriting a concurrent export.
            var number = 1
            while true {
                let suffix = number == 1 ? "" : " (\(number))"
                let destination = directory.appendingPathComponent("\(name)\(suffix).\(format.fileExtension)")
                if try publish(temporary, destination) { return destination }
                number += 1
            }
        }.value
    }

    nonisolated static func publishDownload(_ temporary: URL, _ destination: URL) throws -> Bool {
        if link(temporary.path, destination.path) == 0 { return true }
        let code = errno
        if code == EEXIST { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    func markPinned(jobID: UUID) {
        updateJob(jobID) { job in
            job.isPinned = true
        }
        persistJobs()
        scheduleNextExpiryCheck()
    }

    func unmarkPinned(jobID: UUID) {
        updateJob(jobID) { job in
            job.isPinned = false
        }
        persistJobs()
        purgeExpiredJobs(reason: "manual-unpin")
        scheduleNextExpiryCheck()
    }

    func revealInFinder(jobID: UUID) {
        guard let url = jobs.first(where: { $0.id == jobID })?.outputURL else { return }
        guard isManagedOutputURL(url), FileManager.default.fileExists(atPath: url.path) else {
            workbenchLog.warning("Skipping reveal for unmanaged or missing output: \(url.path, privacy: .public)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func importFromPasteboard(_ pasteboard: NSPasteboard? = nil) async -> [UUID] {
        await importSnapshot(WorkbenchPasteboardSnapshot(pasteboard ?? clipboard))
    }

    func importSnapshot(_ snapshot: WorkbenchPasteboardSnapshot) async -> [UUID] {
        if !snapshot.fileURLs.isEmpty { return await importFiles(snapshot.fileURLs) }
        for data in snapshot.imageData {
            if let image = NSImage(data: data), let id = await importImage(image, sourceName: L10n.clipboard) {
                return [id]
            }
        }
        return []
    }

    func importFiles(_ urls: [URL]) async -> [UUID] {
        beginTransfer()
        defer { endTransfer() }
        var importedIDs: [UUID] = []
        var seenPaths = Set<String>()

        for originalURL in urls {
            let url = originalURL.resolvingSymlinksInPath().standardizedFileURL
            guard url.isFileURL else { continue }
            guard seenPaths.insert(url.path).inserted else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else {
                workbenchLog.debug("Ignoring missing import source: \(url.path, privacy: .public)")
                continue
            }

            if Self.isVideoFile(url) {
                if let importedID = await importVideo(from: url, sourceName: url.lastPathComponent) {
                    importedIDs.append(importedID)
                }
                continue
            }

            if Self.isImageFile(url), let image = NSImage(contentsOf: url) {
                if let importedID = await importImage(image, sourceName: url.lastPathComponent) {
                    importedIDs.append(importedID)
                }
                continue
            }

            workbenchLog.debug("Ignoring unsupported import source: \(url.path, privacy: .public)")
        }

        return importedIDs
    }

    func importImage(_ image: NSImage, sourceName: String) async -> UUID? {
        beginTransfer()
        defer { endTransfer() }
        let id = UUID()
        let outputURL = makeOutputURL(jobID: id)
        let imageBox = SnapPersistImageBox(image)
        let outputSize = CGSize(width: image.size.width, height: image.size.height)

        do {
            try await Self.persistImageBox(imageBox, to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            workbenchLog.error("Failed to import image '\(sourceName, privacy: .public)': \(error.localizedDescription)")
            return nil
        }

        let timestamp = now()
        let job = WorkbenchJob(
            id: id,
            createdAt: timestamp,
            sourceAppName: sourceName,
            sourceWindowTitle: L10n.custom,
            captureFrameCount: 1,
            captureRect: CGRect(origin: .zero, size: outputSize),
            captureType: .custom,
            outputKind: .image,
            startedAt: timestamp,
            endedAt: timestamp,
            status: .completed,
            progress: 1.0,
            phase: L10n.phaseDone,
            outputSize: outputSize,
            outputURL: outputURL,
            errorDescription: nil
        )
        jobs.insert(job, at: 0)
        lastEnqueuedJobID = id
        persistJobs()
        scheduleNextExpiryCheck()
        return id
    }

    func importVideo(from sourceURL: URL, sourceName: String) async -> UUID? {
        beginTransfer()
        defer { endTransfer() }
        let id = UUID()
        let outputURL = makeOutputURL(jobID: id, extension: sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)

        do {
            try await Self.copyManagedFile(from: sourceURL, to: outputURL)
            let metadata = await Self.loadVideoMetadata(from: outputURL)
            let outputSize = metadata.size
            let timestamp = now()
            let job = WorkbenchJob(
                id: id,
                createdAt: timestamp,
                sourceAppName: sourceName,
                sourceWindowTitle: L10n.custom,
                captureFrameCount: 1,
                captureRect: CGRect(origin: .zero, size: outputSize ?? .zero),
                captureType: .custom,
                outputKind: .video,
                startedAt: timestamp,
                endedAt: timestamp,
                status: .completed,
                progress: 1.0,
                phase: L10n.phaseDone,
                outputSize: outputSize,
                outputURL: outputURL,
                errorDescription: nil,
                videoDurationSeconds: metadata.durationSeconds
            )
            jobs.insert(job, at: 0)
            lastEnqueuedJobID = id
            persistJobs()
            scheduleNextExpiryCheck()
            return id
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            workbenchLog.error("Failed to import video '\(sourceName, privacy: .public)': \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func addCompletedSnap(image: NSImage, windowInfo: WindowInfo?, captureRect: CGRect) -> UUID {
        let id = UUID()
        let outputURL = makeOutputURL(jobID: id)
        let timestamp = now()
        let enqueueStart = CFAbsoluteTimeGetCurrent()
        let job = WorkbenchJob(
            id: id,
            createdAt: timestamp,
            sourceAppName: windowInfo?.appName ?? "(unknown)",
            sourceWindowTitle: windowInfo?.title ?? "(untitled)",
            captureFrameCount: 1,
            captureRect: captureRect,
            captureType: .snap,
            outputKind: .image,
            startedAt: timestamp,
            endedAt: nil,
            status: .processing,
            progress: 0.0,
            phase: L10n.phaseSaving,
            outputSize: nil,
            outputURL: nil,
            errorDescription: nil
        )
        jobs.insert(job, at: 0)
        lastEnqueuedJobID = id
        persistJobs()
        let enqueueMs = Int((CFAbsoluteTimeGetCurrent() - enqueueStart) * 1000.0)
        workbenchLog.notice("Queued snap persist job \(id.uuidString.prefix(8), privacy: .public) enqueue=\(enqueueMs)ms")

        let imageBox = SnapPersistImageBox(image)
        let outputWidth = Double(image.size.width)
        let outputHeight = Double(image.size.height)
        Task.detached(priority: .utility) { [weak self, id, outputURL] in
            let exportStart = CFAbsoluteTimeGetCurrent()
            do {
                if let cgImage = imageBox.cgImage {
                    try ImageExporter.export(cgImage, to: outputURL, format: .png)
                } else {
                    try ImageExporter.export(imageBox.image, to: outputURL, format: .png)
                }
                let exportMs = Int((CFAbsoluteTimeGetCurrent() - exportStart) * 1000.0)
                await MainActor.run { [weak self] in
                    self?.completeSnapPersist(
                        jobID: id,
                        outputURL: outputURL,
                        outputSize: CGSize(width: CGFloat(outputWidth), height: CGFloat(outputHeight)),
                        exportMilliseconds: exportMs
                    )
                }
            } catch {
                let exportMs = Int((CFAbsoluteTimeGetCurrent() - exportStart) * 1000.0)
                await MainActor.run { [weak self] in
                    self?.failSnapPersist(
                        jobID: id,
                        outputURL: outputURL,
                        error: error,
                        exportMilliseconds: exportMs
                    )
                }
            }
        }

        return id
    }

    private func completeSnapPersist(
        jobID: UUID,
        outputURL: URL,
        outputSize: CGSize,
        exportMilliseconds: Int
    ) {
        guard jobs.contains(where: { $0.id == jobID }) else {
            try? FileManager.default.removeItem(at: outputURL)
            workbenchLog.debug("Snap persist finished after job removal \(jobID.uuidString.prefix(8), privacy: .public)")
            return
        }

        updateJob(jobID) { job in
            job.status = .completed
            job.progress = 1.0
            job.phase = L10n.phaseDone
            job.endedAt = now()
            job.outputSize = outputSize
            job.outputURL = outputURL
            job.errorDescription = nil
        }

        persistJobs()
        scheduleNextExpiryCheck()
        if exportMilliseconds > 120 {
            workbenchLog.warning("Snap persist slow \(jobID.uuidString.prefix(8), privacy: .public) export=\(exportMilliseconds)ms")
        } else {
            workbenchLog.notice("Snap persisted \(jobID.uuidString.prefix(8), privacy: .public) export=\(exportMilliseconds)ms")
        }
    }

    private func failSnapPersist(
        jobID: UUID,
        outputURL: URL,
        error: Error,
        exportMilliseconds: Int
    ) {
        try? FileManager.default.removeItem(at: outputURL)
        guard jobs.contains(where: { $0.id == jobID }) else { return }

        updateJob(jobID) { job in
            job.status = .failed
            job.progress = 0.0
            job.phase = L10n.phaseFailed
            job.endedAt = now()
            job.outputSize = nil
            job.outputURL = nil
            job.errorDescription = error.localizedDescription
        }

        persistJobs()
        scheduleNextExpiryCheck()
        workbenchLog.error(
            "Snap persist failed \(jobID.uuidString.prefix(8), privacy: .public) export=\(exportMilliseconds)ms: \(error.localizedDescription)"
        )
    }

    func clearCompleted() {
        let removable = jobs.filter { $0.status == .completed || $0.status == .cancelled || $0.status == .failed }
        for job in removable {
            remove(jobID: job.id)
        }
    }

#if DEBUG
    struct RuntimeDebugStats {
        let runtimeCount: Int
        let activeTaskCount: Int
        let queuedCount: Int
        let runningCount: Int
        let terminalRuntimeCount: Int
        let stitchRuntimeCount: Int
        let retainedStitchFrameCount: Int
    }

    func debugRuntimeStats() -> RuntimeDebugStats {
        let terminalIDs = Set(
            jobs.filter { $0.status == .failed || $0.status == .cancelled }
                .map(\.id)
        )
        let runtimeValues = Array(runtimes.values)
        let stitchFrameCounts = runtimeValues.compactMap { runtime -> Int? in
            guard let coordinator = runtime.runner as? StitchingCoordinator else { return nil }
            return coordinator.totalFrameCount
        }
        let terminalRuntimeCount = runtimes.keys.reduce(into: 0) { partialResult, id in
            if terminalIDs.contains(id) {
                partialResult += 1
            }
        }

        return RuntimeDebugStats(
            runtimeCount: runtimeValues.count,
            activeTaskCount: runtimeValues.reduce(into: 0) { partialResult, runtime in
                if runtime.task != nil {
                    partialResult += 1
                }
            },
            queuedCount: queue.count,
            runningCount: running.count,
            terminalRuntimeCount: terminalRuntimeCount,
            stitchRuntimeCount: stitchFrameCounts.count,
            retainedStitchFrameCount: stitchFrameCounts.reduce(0, +)
        )
    }

    func shutdownForTesting() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        preferenceCancellables.removeAll()
    }
#endif

    // MARK: - Processing

    private func processQueue() {
        while running.count < maxConcurrentJobs, !queue.isEmpty {
            let next = queue.removeFirst()
            start(jobID: next)
        }
    }

    private func start(jobID: UUID) {
        guard runtimes[jobID] != nil else { return }
        running.insert(jobID)

        updateJob(jobID) { job in
            job.status = .processing
            job.startedAt = now()
            job.phase = L10n.phasePreparing
            job.progress = 0
            job.errorDescription = nil
            job.outputURL = nil
            job.outputSize = nil
        }

        var runtime = runtimes[jobID]
        runtime?.task = Task { [weak self] in
            await self?.execute(jobID: jobID)
        }
        if let runtime {
            runtimes[jobID] = runtime
        }
    }

    private func execute(jobID: UUID) async {
        guard let runtime = runtimes[jobID] else { return }
        do {
            let image = try await runtime.runner.stitch { [weak self] progress in
                guard let self else { return }
                self.updateJob(jobID) { job in
                    job.progress = progress.fraction
                    job.phase = progress.phase
                }
            }
            await finish(jobID: jobID, image: image, runner: runtime.runner)
        } catch {
            fail(jobID: jobID, error: error, runner: runtime.runner)
        }
    }

    private func finish(jobID: UUID, image: NSImage, runner: any WorkbenchStitchJobRuntime) async {
        let persistedURL: URL?
        let outputSize: CGSize?
        let videoDurationSeconds: Double?

        if let sourceURL = runner.outputFileURL {
            switch persistManagedOutput(from: sourceURL, jobID: jobID) {
            case .success(let managedURL):
                persistedURL = managedURL
                let metadata = await Self.loadVideoMetadata(from: managedURL)
                if let recordingRunner = runner as? ScreenRecordingRunner {
                    outputSize = metadata.size ?? recordingRunner.videoSize
                    videoDurationSeconds = recordingRunner.videoDuration
                } else {
                    outputSize = metadata.size
                    videoDurationSeconds = metadata.durationSeconds
                }
            case .failure(let error):
                fail(jobID: jobID, error: error, runner: runner)
                return
            }
        } else {
            // Image export (existing path)
            let outputURL = makeOutputURL(jobID: jobID)
            do {
                try ImageExporter.export(image, to: outputURL, format: .png)
                persistedURL = outputURL
            } catch {
                workbenchLog.error("Failed to persist result for job \(jobID.uuidString, privacy: .public): \(error.localizedDescription)")
                fail(jobID: jobID, error: error, runner: runner)
                return
            }
            outputSize = image.size
            videoDurationSeconds = nil

            // Cache raw frames to disk — only for image outputs
            // Uses incremental export to avoid copying the entire frame array into memory.
            if preferences.cacheFramesToDisk,
               let coordinator = runner as? StitchingCoordinator {
                let framesDir = outputURL.deletingPathExtension().appendingPathExtension("frames")
                try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
                let written = coordinator.exportFramesToDisk(directory: framesDir)
                if written > 0 {
                    workbenchLog.notice("Cached \(written) frames to \(framesDir.path, privacy: .public)")
                }
            }
        }

        // Reset runner to free captured frames/buffers, then remove runtime
        // (completed jobs don't need a runtime — images are loaded from disk on demand)
        if let runtime = runtimes.removeValue(forKey: jobID) {
            runtime.runner.reset()
        }

        updateJob(jobID) { job in
            job.status = .completed
            job.progress = 1
            job.phase = L10n.phaseDone
            job.endedAt = now()
            job.outputSize = outputSize
            job.outputURL = persistedURL
            job.videoDurationSeconds = videoDurationSeconds
        }

        running.remove(jobID)
        persistJobs()
        scheduleNextExpiryCheck()
        if let outputSize {
            workbenchLog.notice("Completed job \(jobID.uuidString, privacy: .public) output=\(Int(outputSize.width))x\(Int(outputSize.height))")
        } else {
            workbenchLog.notice("Completed job \(jobID.uuidString, privacy: .public) output=unknown")
        }

        // Auto-open only for image captures (not video)
        if runner.outputFileURL == nil {
            copyResultToClipboard(jobID: jobID)
            onOpenImage?(image, persistedURL)
        }

        processQueue()
    }

    private func persistManagedOutput(from sourceURL: URL, jobID: UUID) -> Result<URL, Error> {
        let destinationURL = makeOutputURL(jobID: jobID, extension: sourceURL.pathExtension)

        do {
            try managedFileOperations.move(sourceURL, destinationURL)
            return .success(destinationURL)
        } catch {
            let moveError = error
            workbenchLog.warning("Move into managed output failed for \(sourceURL.lastPathComponent, privacy: .public): \(moveError.localizedDescription)")
            do {
                try managedFileOperations.copy(sourceURL, destinationURL)
                try? managedFileOperations.remove(sourceURL)
                return .success(destinationURL)
            } catch {
                let copyError = error
                workbenchLog.error("Copy into managed output failed for \(sourceURL.lastPathComponent, privacy: .public): \(copyError.localizedDescription)")
                return .failure(
                    ManagedOutputPersistenceError(
                        sourceURL: sourceURL,
                        destinationURL: destinationURL,
                        moveError: moveError,
                        copyError: copyError
                    )
                )
            }
        }
    }

    private func fail(jobID: UUID, error: Error, runner: any WorkbenchStitchJobRuntime) {
        let cancelled = userCancelled.contains(jobID) || error is CancellationError
        if cancelled {
            userCancelled.remove(jobID)
        }

        var failureDescription = cancelled ? "Cancelled by user." : error.localizedDescription
        if !cancelled,
           case .frameSizeMismatch = (error as? StitchingError),
           let coordinator = runner as? StitchingCoordinator,
           coordinator.sizeMismatchDroppedFrames > 0 {
            let dropped = coordinator.sizeMismatchDroppedFrames
            failureDescription += " Dropped \(dropped) mismatched frame\(dropped == 1 ? "" : "s") during capture."
        }

        updateJob(jobID) { job in
            job.status = cancelled ? .cancelled : .failed
            job.phase = cancelled ? L10n.phaseCancelled : L10n.phaseFailed
            job.endedAt = now()
            job.errorDescription = failureDescription
        }

        if let job = jobs.first(where: { $0.id == jobID }), !job.canRetry {
            if let runtime = runtimes.removeValue(forKey: jobID) {
                runtime.runner.reset()
            }
        } else if var runtime = runtimes[jobID] {
            runtime.task = nil
            runtimes[jobID] = runtime
        }
        running.remove(jobID)
        persistJobs()
        scheduleNextExpiryCheck()
        workbenchLog.error("Job \(jobID.uuidString, privacy: .public) ended with status \(cancelled ? "cancelled" : "failed", privacy: .public): \(error.localizedDescription)")
        processQueue()
    }

    private func removeJobFromStore(jobID: UUID, deleteOutput: Bool) {
        queue.removeAll { $0 == jobID }
        running.remove(jobID)
        userCancelled.remove(jobID)

        if let runtime = runtimes.removeValue(forKey: jobID) {
            runtime.runner.reset()
        }

        if let idx = jobs.firstIndex(where: { $0.id == jobID }) {
            let removedJob = jobs[idx]
            jobs.remove(at: idx)
            if deleteOutput {
                deletePersistedArtifacts(for: removedJob)
            }
        }
    }

    private func deletePersistedArtifacts(for job: WorkbenchJob) {
        if let outputURL = job.outputURL, isManagedOutputURL(outputURL) {
            try? FileManager.default.removeItem(at: outputURL)
        } else if let outputURL = job.outputURL {
            workbenchLog.warning("Skipping delete for unmanaged output: \(outputURL.path, privacy: .public)")
        }
        if let framesDirectory = cachedFramesDirectory(for: job) {
            try? FileManager.default.removeItem(at: framesDirectory)
        }
    }

    private func cachedFramesDirectory(for job: WorkbenchJob) -> URL? {
        guard job.hasManagedFrameCache, let outputURL = job.outputURL else {
            return nil
        }
        guard isManagedOutputURL(outputURL) else { return nil }
        return outputURL.deletingPathExtension().appendingPathExtension("frames")
    }

    func isManagedOutputURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let managedRoot = outputDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        if candidate == managedRoot { return true }
        return candidate.hasPrefix(managedRoot + "/")
    }

    private func updateJob(_ id: UUID, mutate: (inout WorkbenchJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        var job = jobs[index]
        mutate(&job)
        jobs[index] = job
    }

    private func humanizedPhase(_ phase: String) -> String {
        switch phase {
        case "deduplicate": return L10n.phaseDedup
        case "overlap": return L10n.phaseOverlap
        case "outlier": return L10n.phaseOutlier
        case "audit": return L10n.phaseAudit
        case "progress-guard": return L10n.phaseProgressGuard
        case "composite": return L10n.phaseComposite
        case "web-truncation": return L10n.phaseWebTrunc
        default:
            if phase.isEmpty { return L10n.phaseProcessing }
            return phase.prefix(1).uppercased() + phase.dropFirst()
        }
    }

    private func makeOutputURL(jobID: UUID, extension ext: String = "png") -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: now())
        return outputDirectory.appendingPathComponent("picelf-\(timestamp)-\(jobID.uuidString.prefix(8)).\(ext)")
    }

    private static func persistImageBox(_ imageBox: SnapPersistImageBox, to outputURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            if let cgImage = imageBox.cgImage {
                try ImageExporter.export(cgImage, to: outputURL, format: .png)
            } else {
                try ImageExporter.export(imageBox.image, to: outputURL, format: .png)
            }
        }.value
    }

    private static func copyManagedFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }.value
    }

    private static func loadVideoMetadata(from url: URL) async -> ImportedVideoMetadata {
        let asset = AVURLAsset(url: url)
        var durationSeconds: Double?
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite {
                durationSeconds = seconds
            }
        }

        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return ImportedVideoMetadata(size: nil, durationSeconds: durationSeconds)
        }

        let naturalSize = try? await track.load(.naturalSize)
        let preferredTransform = try? await track.load(.preferredTransform)
        let resolvedSize: CGSize?
        if let naturalSize {
            if let preferredTransform {
                let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
                resolvedSize = CGSize(width: abs(rect.width), height: abs(rect.height))
            } else {
                resolvedSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
            }
        } else {
            resolvedSize = nil
        }

        return ImportedVideoMetadata(size: resolvedSize, durationSeconds: durationSeconds)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return type.conforms(to: .image)
        }
        return NSImage(contentsOf: url) != nil
    }

    private static func isVideoFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
        }
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v":
            return true
        default:
            return false
        }
    }
}
