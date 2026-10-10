// VideoFrameExtractor.swift
// PicelfIOS — Extract CGImage frames from video via AVFoundation
//
// Uses AVAssetReader + AVAssetReaderTrackOutput with BGRA pixel format.
// Samples at configurable fps, skips near-duplicate frames (MAD < 2.0),
// and downsamples to a max width to manage memory on iOS.
//
// Target: iOS 16+, Swift 5.9+

import AVFoundation
import CoreGraphics
import Accelerate
import os

private let log = Logger(subsystem: "com.picelf.ios", category: "VideoFrameExtractor")

/// Extracts CGImage frames from a video file at a configurable sample rate.
final class VideoFrameExtractor: @unchecked Sendable {

    // MARK: - Configuration

    struct Configuration {
        /// Target frames per second to sample from the video.
        var sampleFPS: Double = 5.0
        /// Maximum output width in pixels. Frames wider than this are downsampled.
        var maxWidth: Int = 1080
        /// MAD threshold below which consecutive frames are considered duplicates.
        var duplicateMADThreshold: Float = 2.0
    }

    // MARK: - Progress

    struct Progress {
        let framesExtracted: Int
        let framesSkipped: Int
        let totalSamples: Int
        let fraction: Double
    }

    // MARK: - Properties

    let configuration: Configuration
    private let _isCancelled = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        get { _isCancelled.withLock { $0 } }
        set { _isCancelled.withLock { $0 = newValue } }
    }

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Extract frames from a video file at the configured sample rate.
    ///
    /// - Parameters:
    ///   - url: File URL of the video.
    ///   - progress: Called after each sample with extraction progress.
    ///   - onFrame: Called for each accepted frame after deduplication. Frames are emitted
    ///     incrementally and only a small trailing window is retained to support end trimming.
    /// - Returns: Number of frames emitted.
    /// - Throws: On read failure, cancellation, or callback failure.
    @discardableResult
    func enumerateFrames(
        from url: URL,
        progress: ((Progress) -> Void)? = nil,
        onFrame: (CGImage) throws -> Void
    ) async throws -> Int {
        isCancelled = false

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Load duration and tracks
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoFrameExtractorError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else {
            throw VideoFrameExtractorError.invalidDuration
        }

        let totalSamples = max(1, Int(durationSeconds * configuration.sampleFPS))
        let sampleInterval = durationSeconds / Double(totalSamples)

        log.notice("Extracting frames: duration=\(String(format: "%.1f", durationSeconds))s, fps=\(self.configuration.sampleFPS), totalSamples=\(totalSamples), naturalSize=\(Int(naturalSize.width))x\(Int(naturalSize.height))")

        // Configure asset reader
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)

        // Set time range to start from the beginning
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)

        guard reader.startReading() else {
            throw VideoFrameExtractorError.readerStartFailed(reader.error)
        }

        var previousGray: [Float]?
        var previousWidth = 0
        var previousHeight = 0
        var extracted = 0
        var skipped = 0
        var emitted = 0
        var consecutiveSkips = 0
        let maxConsecutiveSkips = 5
        let minimumAcceptedFramesForEarlyStop = 4
        let minimumProgressForEarlyStop = 0.35
        let trailingWindowSize = 20
        var trailingFrames: [CGImage] = []
        var nextSampleTime: Double = 0
        var sampleIndex = 0

        func emitFrame(_ frame: CGImage) throws {
            try onFrame(frame)
            emitted += 1
        }

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard !isCancelled else {
                reader.cancelReading()
                throw VideoFrameExtractorError.cancelled
            }

            let presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

            // Skip frames before the next target sample time
            guard presentationTime >= nextSampleTime else { continue }
            nextSampleTime = presentationTime + sampleInterval
            sampleIndex += 1

            // Convert to CGImage
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            guard let cgImage = cgImageFromPixelBuffer(pixelBuffer) else { continue }

            // Downsample if needed
            let frame: CGImage
            if cgImage.width > configuration.maxWidth {
                frame = FrameDownsampler.downsample(cgImage, maxWidth: configuration.maxWidth) ?? cgImage
            } else {
                frame = cgImage
            }

            // Duplicate detection via sampled MAD
            let currentGray = grayscaleBuffer(from: frame)
            let w = frame.width
            let h = frame.height

            if let prevGray = previousGray, previousWidth == w, previousHeight == h {
                let mad = computeMotionMAD(prevGray, currentGray, width: w, height: h)
                if mad < configuration.duplicateMADThreshold {
                    skipped += 1
                    consecutiveSkips += 1
                    progress?(Progress(
                        framesExtracted: extracted,
                        framesSkipped: skipped,
                        totalSamples: totalSamples,
                        fraction: Double(sampleIndex) / Double(totalSamples)
                    ))
                    // Treat a duplicate run as "scroll ended" only after we have already
                    // seen meaningful motion deep enough into the clip. Some recordings
                    // stay static for the first second and would otherwise terminate before
                    // the real scroll starts.
                    let progressFraction = Double(sampleIndex) / Double(max(1, totalSamples))
                    if consecutiveSkips >= maxConsecutiveSkips &&
                        extracted >= minimumAcceptedFramesForEarlyStop &&
                        progressFraction >= minimumProgressForEarlyStop {
                        log.notice("Detected scroll stop: \(consecutiveSkips) consecutive duplicate frames. Ending extraction early.")
                        break
                    }
                    continue
                }
            }

            consecutiveSkips = 0
            previousGray = currentGray
            previousWidth = w
            previousHeight = h
            extracted += 1
            trailingFrames.append(frame)

            if trailingFrames.count > trailingWindowSize {
                let nextFrame = trailingFrames.removeFirst()
                try emitFrame(nextFrame)
            }

            progress?(Progress(
                framesExtracted: extracted,
                framesSkipped: skipped,
                totalSamples: totalSamples,
                fraction: Double(sampleIndex) / Double(totalSamples)
            ))
        }

        if reader.status == .failed {
            throw VideoFrameExtractorError.readingFailed(reader.error)
        }

        log.notice("Extraction complete: \(extracted) frames extracted, \(skipped) duplicates skipped from \(totalSamples) samples")

        // Post-extraction: trim trailing near-static frames while keeping memory bounded.
        let trimmedTrailingStaticFrames = trimTrailingStaticFrames(trailingFrames)
        if trimmedTrailingStaticFrames.count < trailingFrames.count {
            log.notice("Trimmed \(trailingFrames.count - trimmedTrailingStaticFrames.count) trailing static frames")
        }
        let trimmedTrailingFrames = trimTrailingOverlayFrames(trimmedTrailingStaticFrames)
        if trimmedTrailingFrames.count < trimmedTrailingStaticFrames.count {
            log.notice("Trimmed \(trimmedTrailingStaticFrames.count - trimmedTrailingFrames.count) trailing overlay frames")
        }

        for frame in trimmedTrailingFrames {
            try emitFrame(frame)
        }

        return emitted
    }

    /// Extract frames from a video file at the configured sample rate.
    ///
    /// - Parameters:
    ///   - url: File URL of the video.
    ///   - progress: Called after each sample with extraction progress.
    /// - Returns: Array of CGImage frames (deduplicated, downsampled).
    /// - Throws: On read failure or cancellation.
    func extractFrames(
        from url: URL,
        progress: ((Progress) -> Void)? = nil
    ) async throws -> [CGImage] {
        var frames: [CGImage] = []
        _ = try await enumerateFrames(from: url, progress: progress) { frame in
            frames.append(frame)
        }
        return frames
    }

    /// Cancel an in-progress extraction.
    func cancel() {
        isCancelled = true
    }

    // MARK: - Trailing Frame Trim

    /// Remove trailing frames where the page is no longer scrolling.
    /// Compares each trailing frame's center region against a reference frame.
    /// The center crop excludes status bar (top) and home indicator (bottom) which have system animations.
    private func trimTrailingStaticFrames(_ frames: [CGImage]) -> [CGImage] {
        guard frames.count > 3 else { return frames }

        let w = frames[0].width
        let h = frames[0].height

        // Center crop: exclude top 15% and bottom 15% (status bar + home indicator)
        let cropTop = Int(Double(h) * 0.15)
        let cropBottom = Int(Double(h) * 0.15)
        let cropH = h - cropTop - cropBottom
        guard cropH > 0 else { return frames }
        let cropRect = CGRect(x: 0, y: cropTop, width: w, height: cropH)

        // Use the last frame as reference — compare backwards
        guard let refCrop = frames.last?.cropping(to: cropRect) else { return frames }
        let refGray = grayscaleBuffer(from: refCrop)
        let relaxedThreshold: Float = 3.0
        var trimCount = 0

        // Walk backwards from second-to-last
        for i in stride(from: frames.count - 2, through: max(0, frames.count - 20), by: -1) {
            guard let crop = frames[i].cropping(to: cropRect) else { break }
            guard crop.width == refCrop.width, crop.height == refCrop.height else { break }

            let gray = grayscaleBuffer(from: crop)
            let mad = computeSampledMAD(refGray, gray, width: crop.width, height: crop.height)

            if mad < relaxedThreshold {
                trimCount += 1
            } else {
                break
            }
        }

        if trimCount > 0 {
            return Array(frames.dropLast(trimCount))
        }
        return frames
    }

    /// Remove trailing frames where system UI overlays slide in at the end of recording.
    /// This catches stop-recording/control-center tails that are not near-duplicates of the
    /// page but also are not valid scroll content and should not be stitched into the result.
    private func trimTrailingOverlayFrames(_ frames: [CGImage]) -> [CGImage] {
        guard frames.count > 3 else { return frames }

        let height = frames[0].height
        let topRows = min(max(24, height / 12), max(24, height / 8))
        let bottomRows = min(max(48, height / 8), max(48, height / 5))
        if let abruptOverlayStart = abruptTrailingOverlayStartIndex(
            in: frames,
            topRows: topRows,
            bottomRows: bottomRows
        ) {
            return Array(frames[..<abruptOverlayStart])
        }

        var trimCount = 0
        for index in stride(from: frames.count - 1, through: max(1, frames.count - 6), by: -1) {
            let current = frames[index]
            let previous = frames[index - 1]
            guard current.width == previous.width, current.height == previous.height else { break }

            let bottomMAD = bandMADBetween(previous, current, rows: bottomRows, edge: .bottom)
            let topMAD = bandMADBetween(previous, current, rows: topRows, edge: .top)
            let centerMAD = centerCropMADBetween(previous, current)

            let looksLikeOverlay =
                (bottomMAD > 14.0 && centerMAD > 7.0) ||
                (bottomMAD > 10.0 && topMAD > 8.0 && centerMAD > 5.0)

            if looksLikeOverlay {
                trimCount += 1
            } else {
                break
            }
        }

        if trimCount > 0 {
            return Array(frames.dropLast(trimCount))
        }
        return frames
    }

    private func abruptTrailingOverlayStartIndex(
        in frames: [CGImage],
        topRows: Int,
        bottomRows: Int
    ) -> Int? {
        guard frames.count > 3 else { return nil }

        let lookbackStart = max(1, frames.count - 8)
        for index in stride(from: frames.count - 1, through: lookbackStart, by: -1) {
            let current = frames[index]
            let previous = frames[index - 1]
            guard current.width == previous.width, current.height == previous.height else { continue }

            let topMAD = bandMADBetween(previous, current, rows: topRows, edge: .top)
            let bottomMAD = bandMADBetween(previous, current, rows: bottomRows, edge: .bottom)
            let centerMAD = centerCropMADBetween(previous, current)
            let abruptOverlayTransition =
                (topMAD > 42.0 && bottomMAD > 42.0 && centerMAD > 40.0) ||
                ((topMAD > 90.0 || bottomMAD > 90.0) && centerMAD > 65.0)

            if abruptOverlayTransition {
                return index
            }
        }

        return nil
    }

    private enum BandEdge {
        case top
        case bottom
    }

    private func bandMADBetween(_ lhs: CGImage, _ rhs: CGImage, rows: Int, edge: BandEdge) -> Float {
        guard rows >= 8,
              let lhsBand = cropBand(lhs, rows: rows, edge: edge),
              let rhsBand = cropBand(rhs, rows: rows, edge: edge),
              lhsBand.width == rhsBand.width,
              lhsBand.height == rhsBand.height else {
            return 0
        }

        let lhsGray = grayscaleBuffer(from: lhsBand)
        let rhsGray = grayscaleBuffer(from: rhsBand)
        return computeSampledMAD(lhsGray, rhsGray, width: lhsBand.width, height: lhsBand.height)
    }

    private func centerCropMADBetween(_ lhs: CGImage, _ rhs: CGImage) -> Float {
        let width = lhs.width
        let height = lhs.height
        let insetX = width / 5
        let insetTop = height / 6
        let insetBottom = height / 6
        let cropHeight = height - insetTop - insetBottom
        guard cropHeight > 16 else { return 0 }

        let rect = CGRect(x: insetX, y: insetTop, width: width - insetX * 2, height: cropHeight)
        guard let lhsCrop = lhs.cropping(to: rect),
              let rhsCrop = rhs.cropping(to: rect) else {
            return 0
        }

        let lhsGray = grayscaleBuffer(from: lhsCrop)
        let rhsGray = grayscaleBuffer(from: rhsCrop)
        return computeSampledMAD(lhsGray, rhsGray, width: lhsCrop.width, height: lhsCrop.height)
    }

    private func cropBand(_ image: CGImage, rows: Int, edge: BandEdge) -> CGImage? {
        let safeRows = min(max(0, rows), image.height)
        guard safeRows > 0 else { return nil }

        let rect: CGRect
        switch edge {
        case .top:
            rect = CGRect(x: 0, y: image.height - safeRows, width: image.width, height: safeRows)
        case .bottom:
            rect = CGRect(x: 0, y: 0, width: image.width, height: safeRows)
        }
        return image.cropping(to: rect)
    }

    // MARK: - Private Helpers

    /// Create a CGImage from a CVPixelBuffer.
    private func cgImageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        // BGRA pixel format: use premultipliedFirst + byteOrder32Little
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        return context.makeImage()
    }

    /// Convert a CGImage to a grayscale float buffer for MAD comparison.
    private func grayscaleBuffer(from image: CGImage) -> [Float] {
        let w = image.width
        let h = image.height
        guard let data = image.dataProvider?.data else {
            return [Float](repeating: 0, count: w * h)
        }
        let ptr = CFDataGetBytePtr(data)!
        let bpr = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8

        var gray = [Float](repeating: 0, count: w * h)
        for row in 0..<h {
            let rowStart = row * bpr
            for col in 0..<w {
                let offset = rowStart + col * bpp
                // BGRA order: B=0, G=1, R=2, A=3
                let b = Float(ptr[offset])
                let g = Float(ptr[offset + 1])
                let r = Float(ptr[offset + 2])
                gray[row * w + col] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }
        return gray
    }

    /// Compute sampled MAD between two grayscale buffers (sample every 10th row).
    private func computeSampledMAD(
        _ a: [Float], _ b: [Float],
        width w: Int, height h: Int
    ) -> Float {
        var totalAbsDiff: Float = 0
        var sampledRows: Float = 0
        var rowDiff = [Float](repeating: 0, count: w)

        a.withUnsafeBufferPointer { aBuf in
            b.withUnsafeBufferPointer { bBuf in
                for row in stride(from: 0, to: h, by: 10) {
                    let start = row * w
                    vDSP_vsub(bBuf.baseAddress! + start, 1,
                              aBuf.baseAddress! + start, 1,
                              &rowDiff, 1, vDSP_Length(w))
                    var rowMAD: Float = 0
                    vDSP_svemg(rowDiff, 1, &rowMAD, vDSP_Length(w))
                    totalAbsDiff += rowMAD / Float(w)
                    sampledRows += 1
                }
            }
        }
        return totalAbsDiff / max(1, sampledRows)
    }

    /// Motion-oriented MAD for video deduplication.
    /// Excludes the most static chrome bands so imported feeds do not get
    /// misclassified as duplicates while only the content area is moving.
    private func computeMotionMAD(
        _ a: [Float], _ b: [Float],
        width w: Int, height h: Int
    ) -> Float {
        guard w > 32, h > 64 else {
            return computeSampledMAD(a, b, width: w, height: h)
        }

        let topInset = max(12, Int(Double(h) * 0.12))
        let bottomInset = max(18, Int(Double(h) * 0.18))
        let leftInset = max(8, Int(Double(w) * 0.12))
        let rightInset = leftInset
        let startRow = min(h - 1, topInset)
        let endRow = max(startRow + 1, h - bottomInset)
        let startCol = min(w - 1, leftInset)
        let endCol = max(startCol + 1, w - rightInset)

        var totalAbsDiff: Float = 0
        var sampleCount: Float = 0
        for row in stride(from: startRow, to: endRow, by: 8) {
            let rowStart = row * w
            for col in stride(from: startCol, to: endCol, by: 3) {
                totalAbsDiff += abs(a[rowStart + col] - b[rowStart + col])
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return computeSampledMAD(a, b, width: w, height: h)
        }
        return totalAbsDiff / sampleCount
    }
}

// MARK: - Errors

enum VideoFrameExtractorError: LocalizedError {
    case noVideoTrack
    case invalidDuration
    case readerStartFailed(Error?)
    case readingFailed(Error?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The video file does not contain a video track."
        case .invalidDuration:
            return "The video has zero or invalid duration."
        case .readerStartFailed(let error):
            return "Failed to start reading video: \(error?.localizedDescription ?? "unknown error")"
        case .readingFailed(let error):
            return "Video reading failed: \(error?.localizedDescription ?? "unknown error")"
        case .cancelled:
            return "Frame extraction was cancelled."
        }
    }
}
