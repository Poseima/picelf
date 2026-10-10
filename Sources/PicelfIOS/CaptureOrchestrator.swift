// CaptureOrchestrator.swift
// PicelfIOS — Orchestrates video import, broadcast recovery, and stitching
//
// @MainActor ObservableObject that drives the pipeline:
// video import -> frame extraction -> StitchingCoordinator.appendFrame() -> stitch() -> UIImage result
// broadcast return -> frame file import -> StitchingCoordinator.appendFrame() -> stitch() -> UIImage result
// Also retains an internal ReplayKit path for non-public debugging use.
//
// Target: iOS 16+, Swift 5.9+

import Foundation
import UIKit
import os
#if DEBUG
import AVFoundation
#endif

private let log = Logger(subsystem: "com.picelf.ios", category: "CaptureOrchestrator")

@MainActor
final class IOSCaptureOrchestrator: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case idle
        case extracting(progress: Double, framesExtracted: Int, totalSamples: Int)
        case recording(frameCount: Int)
        case stitching(progress: Double)
        case completed
        case failed(message: String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.extracting(let lp, let lf, let lt), .extracting(let rp, let rf, let rt)):
                return lp == rp && lf == rf && lt == rt
            case (.recording(let l), .recording(let r)): return l == r
            case (.stitching(let l), .stitching(let r)): return l == r
            case (.completed, .completed): return true
            case (.failed(let l), .failed(let r)): return l == r
            default: return false
            }
        }
    }

    // MARK: - Published Properties

    @Published private(set) var state: State = .idle
    @Published private(set) var resultImage: UIImage?
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var extractedFrameCount: Int = 0
    @Published private(set) var stitchedFrameCount: Int = 0
    @Published private(set) var lastSavedResult: StitchResult?

    // MARK: - Private Properties

    private static let sampleFPSDefaultsKey = "ios_sampleFPS"
    #if DEBUG
    static let uiTestImportFixtureEnvKey = "UITEST_IMPORT_FIXTURE"
    static let uiTestBroadcastFixtureEnvKey = "UITEST_SIMULATE_BROADCAST_FIXTURE"
    #endif

    private weak var resultStore: ResultStore?
    private var extractor: VideoFrameExtractor?
    private let coordinator = StitchingCoordinator()
    private let captureStream = ReplayKitCaptureStream()

    // MARK: - Init

    init(resultStore: ResultStore? = nil) {
        self.resultStore = resultStore
    }

    func attach(resultStore: ResultStore) {
        self.resultStore = resultStore
    }

    // MARK: - Public API

    /// Process a video file: extract frames, stitch them, produce a UIImage result.
    ///
    /// - Parameters:
    ///   - videoURL: Local file URL of the video to process.
    ///   - sampleFPS: Optional override for frames per second to sample. When nil, uses settings.
    ///   - maxWidth: Maximum frame width in pixels (default 720).
    func processVideo(
        from videoURL: URL,
        sampleFPS: Double? = nil,
        maxWidth: Int = 720
    ) async {
        prepareProcessingState()
        state = .extracting(progress: 0, framesExtracted: 0, totalSamples: 0)

        let resolvedSampleFPS = sampleFPS ?? storedSampleFPS()
        let config = VideoFrameExtractor.Configuration(
            sampleFPS: resolvedSampleFPS,
            maxWidth: maxWidth
        )
        let videoExtractor = VideoFrameExtractor(configuration: config)
        self.extractor = videoExtractor

        do {
            let emittedFrames = try await videoExtractor.enumerateFrames(from: videoURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state = .extracting(
                        progress: progress.fraction,
                        framesExtracted: progress.framesExtracted,
                        totalSamples: progress.totalSamples
                    )
                    self?.extractedFrameCount = progress.framesExtracted
                }
            } onFrame: { [weak self] frame in
                guard let self else { return }
                _ = autoreleasepool {
                    self.coordinator.appendFrame(frame)
                }
                self.stitchedFrameCount = self.coordinator.frameCount
            }

            guard emittedFrames > 0 else {
                state = .failed(message: "No frames were extracted from the video.")
                return
            }

            log.notice("Imported video emitted \(emittedFrames) frames into the coordinator")
            state = .stitching(progress: 0)

            let stitchedImage = try await stitchCurrentFrames()
            complete(with: stitchedImage, logMessage: "Video stitch complete")
        } catch {
            log.error("Frame extraction failed: \(error.localizedDescription)")
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Remove stale broadcast artifacts before the user starts a new Control Center broadcast.
    func prepareBroadcastCapture(rootURL: URL? = nil) {
        BroadcastFrameRelay.cleanFramesDirectory(rootURL: rootURL)
    }

    /// Process a stopped Control Center broadcast if one exists in the shared relay directory.
    ///
    /// - Returns: `true` when a pending broadcast session was found and consumed.
    @discardableResult
    func processPendingBroadcastIfNeeded(rootURL: URL? = nil) async -> Bool {
        guard BroadcastFrameRelay.hasStopMarker(rootURL: rootURL) else { return false }

        let frameURLs = BroadcastFrameRelay.sortedFrameFileURLs(rootURL: rootURL)
        guard !frameURLs.isEmpty else {
            BroadcastFrameRelay.cleanFramesDirectory(rootURL: rootURL)
            return false
        }

        prepareProcessingState()
        state = .extracting(progress: 0, framesExtracted: 0, totalSamples: frameURLs.count)

        defer {
            BroadcastFrameRelay.cleanFramesDirectory(rootURL: rootURL)
        }

        var loadedFrameCount = 0
        for (index, url) in frameURLs.enumerated() {
            guard !Task.isCancelled else { return true }

            autoreleasepool {
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data),
                      let cgImage = image.cgImage else {
                    log.warning("Skipping unreadable broadcast frame: \(url.lastPathComponent, privacy: .public)")
                    return
                }

                coordinator.appendFrame(cgImage)
                loadedFrameCount += 1
                stitchedFrameCount = coordinator.frameCount
            }

            state = .extracting(
                progress: Double(index + 1) / Double(frameURLs.count),
                framesExtracted: loadedFrameCount,
                totalSamples: frameURLs.count
            )
            extractedFrameCount = loadedFrameCount
        }

        guard loadedFrameCount > 0 else {
            state = .failed(message: "No valid broadcast frames were found.")
            return true
        }

        do {
            state = .stitching(progress: 0)
            let stitchedImage = try await stitchCurrentFrames()
            complete(with: stitchedImage, logMessage: "Broadcast stitch complete")
        } catch {
            log.error("Broadcast stitching failed: \(error.localizedDescription)")
            state = .failed(message: error.localizedDescription)
        }

        return true
    }

    // MARK: - Live Recording API (internal / non-primary)

    /// Start live screen capture via ReplayKit.
    ///
    /// This path is kept for internal debugging only. The public UX uses Control Center broadcast.
    func startLiveCapture() async throws {
        prepareProcessingState()
        state = .recording(frameCount: 0)

        try await captureStream.startCapture { [weak self] cgImage in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.coordinator.appendFrame(cgImage)
                let count = self.coordinator.frameCount
                self.stitchedFrameCount = count
                self.state = .recording(frameCount: count)
            }
        }
    }

    /// Stop live screen capture and stitch all captured frames.
    @discardableResult
    func stopLiveCapture() async throws -> UIImage {
        try await captureStream.stopCapture()
        state = .stitching(progress: 0)

        let stitchedImage = try await stitchCurrentFrames()
        complete(with: stitchedImage, logMessage: "Live capture stitch complete")
        return stitchedImage
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Cancel the current operation.
    func cancel() {
        extractor?.cancel()
        coordinator.cancel()
        if captureStream.isCapturing {
            Task {
                try? await captureStream.stopCapture()
            }
        }
        reset()
    }

    /// Reset to idle state.
    func reset() {
        state = .idle
        resultImage = nil
        previewImage = nil
        extractedFrameCount = 0
        stitchedFrameCount = 0
        lastSavedResult = nil
        coordinator.reset()
        extractor = nil
    }

    // MARK: - Private Helpers

    private func prepareProcessingState() {
        reset()
        coordinator.onPreviewUpdate = { [weak self] platformImage in
            Task { @MainActor [weak self] in
                self?.previewImage = platformImage
            }
        }
    }

    private func stitchCurrentFrames() async throws -> UIImage {
        try await coordinator.stitch(onProgress: { [weak self] stitchProgress in
            Task { @MainActor [weak self] in
                self?.state = .stitching(progress: stitchProgress.fraction)
            }
        })
    }

    private func complete(with stitchedImage: UIImage, logMessage: String) {
        resultImage = stitchedImage
        previewImage = stitchedImage
        lastSavedResult = resultStore?.save(image: stitchedImage)
        state = .completed
        log.notice("\(logMessage, privacy: .public): \(stitchedImage.size.width)x\(stitchedImage.size.height)")
    }

    private func storedSampleFPS() -> Double {
        let defaults = UserDefaults.standard
        guard let storedValue = defaults.object(forKey: Self.sampleFPSDefaultsKey) as? Double,
              storedValue > 0 else {
            return 5.0
        }
        return storedValue
    }
}

#if DEBUG
extension IOSCaptureOrchestrator {

    var uiTestImportFixtureName: String? {
        Self.fixtureName(for: Self.uiTestImportFixtureEnvKey)
    }

    var uiTestBroadcastFixtureName: String? {
        Self.fixtureName(for: Self.uiTestBroadcastFixtureEnvKey)
    }

    @discardableResult
    func processUITestImportFixture(named fixtureName: String) async -> Bool {
        do {
            let videoURL = try await Self.makeUITestImportVideo(named: fixtureName)
            await processVideo(from: videoURL)
            if case .completed = state {
                return true
            }
            return false
        } catch {
            state = .failed(message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func simulatePendingBroadcastFixture(named fixtureName: String, rootURL: URL? = nil) async -> Bool {
        do {
            prepareBroadcastCapture(rootURL: rootURL)
            try Self.writeUITestBroadcastFixture(named: fixtureName, rootURL: rootURL)
            return await processPendingBroadcastIfNeeded(rootURL: rootURL)
        } catch {
            state = .failed(message: error.localizedDescription)
            return false
        }
    }

    static func fixtureName(for environmentKey: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private struct UITestFixtureSpec {
        let name: String
        let width: Int
        let height: Int
        let sectionHeight: Int
        let viewportHeight: Int
        let scrollStep: Int
        let fps: Int
    }

    private static func fixtureSpec(named fixtureName: String) -> UITestFixtureSpec {
        let normalized = fixtureName.lowercased()
        switch normalized {
        case "broadcast", "ui-broadcast", "broadcast-basic":
            return UITestFixtureSpec(name: normalized, width: 430, height: 4200, sectionHeight: 220, viewportHeight: 932, scrollStep: 320, fps: 15)
        case "import", "ui-import", "import-basic":
            return UITestFixtureSpec(name: normalized, width: 430, height: 3600, sectionHeight: 200, viewportHeight: 932, scrollStep: 300, fps: 15)
        default:
            return UITestFixtureSpec(name: normalized, width: 430, height: 3900, sectionHeight: 210, viewportHeight: 932, scrollStep: 310, fps: 15)
        }
    }

    private static func fixtureScrollPositions(for spec: UITestFixtureSpec) -> [Int] {
        guard spec.height > spec.viewportHeight else { return [0] }

        var positions: [Int] = []
        var current = 0
        let lastOrigin = max(0, spec.height - spec.viewportHeight)
        while current < lastOrigin {
            positions.append(current)
            current += spec.scrollStep
        }
        positions.append(lastOrigin)
        return Array(NSOrderedSet(array: positions)) as? [Int] ?? positions
    }

    private static func makeUITestImportVideo(named fixtureName: String) async throws -> URL {
        let spec = fixtureSpec(named: fixtureName)
        let image = try makeTallFixtureImage(spec: spec)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PicelfUITestFixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let videoURL = tempDir.appendingPathComponent("\(spec.name)-import.mp4")
        try await writeScrollingVideo(from: image, spec: spec, to: videoURL)
        return videoURL
    }

    private static func writeUITestBroadcastFixture(named fixtureName: String, rootURL: URL? = nil) throws {
        let spec = fixtureSpec(named: fixtureName)
        let image = try makeTallFixtureImage(spec: spec)
        let positions = fixtureScrollPositions(for: spec)
        guard let framesDirectoryURL = BroadcastFrameRelay.framesDirectoryURL(rootURL: rootURL) else {
            throw UITestFixtureError.cannotAccessBroadcastDirectory
        }

        for (index, originY) in positions.enumerated() {
            let cropRect = CGRect(x: 0, y: originY, width: spec.width, height: spec.viewportHeight)
            guard let frame = image.cropping(to: cropRect) else { continue }
            let frameURL = framesDirectoryURL.appendingPathComponent(BroadcastFrameRelay.frameFileName(index: index))
            guard let jpegData = UIImage(cgImage: frame).jpegData(compressionQuality: BroadcastFrameRelay.jpegQuality) else {
                continue
            }
            try jpegData.write(to: frameURL, options: .atomic)
        }

        BroadcastFrameRelay.writeStopMarker(rootURL: rootURL)
    }

    private static func makeTallFixtureImage(spec: UITestFixtureSpec) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: spec.width,
            height: spec.height,
            bitsPerComponent: 8,
            bytesPerRow: spec.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw UITestFixtureError.cannotCreateContext
        }

        let sectionColors: [UIColor] = [
            UIColor(red: 0.95, green: 0.95, blue: 0.98, alpha: 1.0),
            UIColor(red: 0.92, green: 0.97, blue: 0.93, alpha: 1.0),
            UIColor(red: 0.98, green: 0.95, blue: 0.90, alpha: 1.0),
            UIColor(red: 0.93, green: 0.93, blue: 0.98, alpha: 1.0),
            UIColor(red: 0.97, green: 0.93, blue: 0.93, alpha: 1.0),
            UIColor(red: 0.93, green: 0.97, blue: 0.97, alpha: 1.0)
        ]

        var y = 0
        var sectionIndex = 0
        while y < spec.height {
            let sectionHeight = min(spec.sectionHeight, spec.height - y)
            let color = sectionColors[sectionIndex % sectionColors.count]
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: spec.height - y - sectionHeight, width: spec.width, height: sectionHeight))

            context.setStrokeColor(UIColor(white: 0.75, alpha: 1.0).cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: 0, y: CGFloat(spec.height - y)))
            context.addLine(to: CGPoint(x: CGFloat(spec.width), y: CGFloat(spec.height - y)))
            context.strokePath()

            UIGraphicsPushContext(context)
            let title = "Picelf Fixture \(sectionIndex + 1)" as NSString
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.darkGray
            ]
            let titleY = CGFloat(spec.height - y - sectionHeight / 2 - 18)
            title.draw(at: CGPoint(x: 24, y: titleY), withAttributes: titleAttributes)

            let lineAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.gray
            ]
            for line in 0..<5 {
                let text = "Fixture \(spec.name) line \(line + 1) section \(sectionIndex + 1)" as NSString
                text.draw(
                    at: CGPoint(x: 32, y: titleY + 34 + CGFloat(line * 20)),
                    withAttributes: lineAttributes
                )
            }
            UIGraphicsPopContext()

            y += spec.sectionHeight
            sectionIndex += 1
        }

        guard let image = context.makeImage() else {
            throw UITestFixtureError.cannotCreateImage
        }
        return image
    }

    private static func writeScrollingVideo(from image: CGImage, spec: UITestFixtureSpec, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)

        let positions = fixtureScrollPositions(for: spec)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: spec.width,
            AVVideoHeightKey: spec.viewportHeight
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: spec.width,
                kCVPixelBufferHeightKey as String: spec.viewportHeight
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw UITestFixtureError.cannotCreateVideo
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? UITestFixtureError.cannotCreateVideo
        }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for (frameIndex, originY) in positions.enumerated() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            guard let frame = image.cropping(to: CGRect(x: 0, y: originY, width: spec.width, height: spec.viewportHeight)) else {
                continue
            }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                spec.width,
                spec.viewportHeight,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            )
            guard let pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: spec.width,
                height: spec.viewportHeight,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                context.draw(frame, in: CGRect(x: 0, y: 0, width: spec.width, height: spec.viewportHeight))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let presentationTime = CMTime(value: Int64(frameIndex), timescale: Int32(spec.fps))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? UITestFixtureError.cannotCreateVideo
        }
    }

    private enum UITestFixtureError: LocalizedError {
        case cannotCreateContext
        case cannotCreateImage
        case cannotCreateVideo
        case cannotAccessBroadcastDirectory

        var errorDescription: String? {
            switch self {
            case .cannotCreateContext:
                return "Failed to create the fixture drawing context."
            case .cannotCreateImage:
                return "Failed to create the fixture image."
            case .cannotCreateVideo:
                return "Failed to create the fixture video."
            case .cannotAccessBroadcastDirectory:
                return "Failed to access the broadcast relay directory."
            }
        }
    }
}
#endif
