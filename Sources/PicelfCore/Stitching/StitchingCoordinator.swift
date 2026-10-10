// StitchingCoordinator.swift
// Picelf — High-Level Stitching Coordinator
//
// Incremental stitching: frames are stitched as they arrive using
// 2D template matching on horizontal slices (SSD-based).
//
// Target: macOS 14+, Swift 5.9+

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Accelerate
import ImageIO
import UniformTypeIdentifiers
import os

#if canImport(AppKit)
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
typealias PlatformImage = UIImage
#endif

private func makePlatformImage(cgImage: CGImage) -> PlatformImage {
    #if canImport(AppKit)
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    #elseif canImport(UIKit)
    return UIImage(cgImage: cgImage)
    #endif
}

private let log = Logger(subsystem: "com.picelf", category: "StitchingCoordinator")

// MARK: - Progress Reporting

/// Reports stitching progress back to the caller.
struct StitchingProgress {
    /// 0.0 ... 1.0
    let fraction: Double
    /// Human-readable description of the current phase.
    let phase: String
    /// Index of the frame currently being processed.
    let currentFrame: Int
    /// Total number of frames.
    let totalFrames: Int

    var percentage: Int { Int((fraction * 100).rounded()) }
}

// MARK: - StitchingCoordinator

/// High-level coordinator that manages the full stitching lifecycle.
///
/// Uses incremental template matching: frames are stitched as they arrive
/// via coarse+fine SSD matching with trimmed aggregation.
@MainActor
final class StitchingCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var frameCount: Int = 0
    @Published private(set) var isStitching: Bool = false
    @Published private(set) var progress: StitchingProgress?
    @Published private(set) var result: PlatformImage?
    @Published private(set) var error: StitchingError?
    @Published private(set) var sizeMismatchDroppedFrames: Int = 0

    // MARK: - Configuration (simplified - no longer used but kept for API compatibility)

    var configuration: StitchingConfiguration = .default
    var useDiskBackedStorage: Bool = false
    var runtimePolicy: StitchRuntimePolicy = .defaultBalanced
    var onRuntimeEvent: ((StitchRuntimeEvent) -> Void)?
    private(set) var lastRunMetrics: StitchRunMetrics?

    /// Callback fired on the main queue whenever a new frame is composited.
    /// Used for live preview during capture.
    nonisolated(unsafe) var onPreviewUpdate: ((PlatformImage) -> Void)?

    // MARK: - Private State

    /// Lock for thread-safe access to stitching state from background queue
    private let stateLock = NSLock()
    nonisolated(unsafe) private var _canvas: PixelCanvas?
    nonisolated(unsafe) private var _previousCG: CGImage?
    nonisolated(unsafe) private var _internalFrameCount: Int = 0
    nonisolated(unsafe) private var _capturedFrames: [CGImage] = []
    nonisolated(unsafe) private var _cachedStaticRows: (top: Int, bottom: Int)?
    nonisolated(unsafe) private var _processedFrameIndex: Int = 0
    nonisolated(unsafe) private var _lastPreviewTime: CFAbsoluteTime = 0

    // Grayscale Float buffers for template matching (Step 1: proper luminance)
    nonisolated(unsafe) private var _previousGray: [Float]?       // w × h full-res grayscale
    nonisolated(unsafe) private var _previousGrayCoarse: [Float]?  // (w/4) × (h/4) downsampled
    // _previousGray16 removed: 2-level SSD (4× → 1×) replaces 3-level (16× → 4× → 1×)
    nonisolated(unsafe) private var _grayWidth: Int = 0
    nonisolated(unsafe) private var _grayHeight: Int = 0
    nonisolated(unsafe) private var _lastDeltaY: Int?  // Previous scroll offset for ROI clipping

    // Pipeline parallelism: preprocess (grayscale conversion) and match (SSD + composite)
    // run on separate serial queues. While matchQueue processes frame N, preprocessQueue
    // prepares frame N+1's grayscale buffers in parallel — WeChat-style 2-stage pipeline.
    private let preprocessQueue = DispatchQueue(label: "com.picelf.preprocess", qos: .userInitiated)
    private let matchQueue = DispatchQueue(label: "com.picelf.match", qos: .userInitiated)
    private var acceptedFrameSize: CGSize?
    private let rightEdgeCropPixels: Int = 40

    // MARK: - Init

    init() {}

    #if DEBUG
    deinit {
        let retainedFrames = stateLock.withLock { _capturedFrames.count }
        log.debug("StitchingCoordinator deinit: retainedFrames=\(retainedFrames, privacy: .public)")
    }
    #endif

    // MARK: - Frame Collection

    /// Append a captured frame. Thread-safe — call from the ScreenCaptureKit callback.
    ///
    /// Frames are stitched incrementally using template matching (SSD).
    @discardableResult
    func appendFrame(_ frame: CGImage) -> Bool {
        let frame = normalizePixelData(cropRightEdgeIfNeeded(frame))

        // Check for size mismatch
        if let expectedSize = acceptedFrameSize {
            if Int(expectedSize.width) != frame.width || Int(expectedSize.height) != frame.height {
                sizeMismatchDroppedFrames += 1
                log.warning("Dropped mismatched frame: expected \(Int(expectedSize.width))x\(Int(expectedSize.height)), got \(frame.width)x\(frame.height)")
                return false
            }
        } else {
            acceptedFrameSize = CGSize(width: frame.width, height: frame.height)
        }

        // First frame initializes the stitch
        let isFirst = stateLock.withLock {
            _capturedFrames.append(frame)

            if _canvas == nil {
                let canvas = PixelCanvas()
                if let data = frame.dataProvider?.data {
                    let ptr = CFDataGetBytePtr(data)!
                    canvas.setFirstFrame(
                        rgbaPtr: ptr, bpr: frame.bytesPerRow,
                        w: frame.width, h: frame.height
                    )
                    // Pre-convert first frame to grayscale for next comparison
                    let bpp = frame.bitsPerPixel / 8
                    let gray = convertToGrayscaleFloat(ptr: ptr, bpr: frame.bytesPerRow, w: frame.width, h: frame.height, bpp: bpp)
                    _previousGray = gray
                    let coarse4 = downsampleGray4x(gray, w: frame.width, h: frame.height)
                    _previousGrayCoarse = coarse4
                    _grayWidth = frame.width
                    _grayHeight = frame.height
                }
                _canvas = canvas
                _previousCG = frame
                _internalFrameCount = 1
                _processedFrameIndex = 1
                log.notice("Frame accepted: \(frame.width)x\(frame.height), accepted=1 received=1")
                return true
            }
            return false
        }

        // Update frameCount on MainActor to show total captured frames in UI
        frameCount = stateLock.withLock { _capturedFrames.count }

        if !isFirst {
            // Pipeline stage 1: preprocess (grayscale + downsample) — can overlap with
            // previous frame's match stage running on matchQueue
            preprocessQueue.async { [weak self] in
                guard let self else { return }
                let preprocessed = self.preprocess(frame: frame)
                // Pipeline stage 2: match + composite (serial queue ensures frame ordering)
                self.matchQueue.async { [weak self] in
                    guard let self else { return }
                    if let preprocessed {
                        self.matchAndComposite(preprocessed: preprocessed)
                    }
                    self.stateLock.withLock { self._processedFrameIndex += 1 }
                }
            }
        }

        return true
    }

    // MARK: - Pipeline Stage 1: Preprocess

    /// Data produced by the preprocess stage, consumed by match stage.
    private struct PreprocessedFrame {
        let cgImage: CGImage
        let rgbaData: CFData  // keep reference alive so curPtr remains valid
        let curGray: [Float]
        let curGrayCoarse: [Float]
        let w: Int
        let h: Int
        let bpr: Int
        let bpp: Int
        let preprocessTimeMs: Int
    }

    /// Extract pixel data, convert to grayscale, downsample — runs on preprocessQueue.
    nonisolated private func preprocess(frame: CGImage) -> PreprocessedFrame? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let data = frame.dataProvider?.data else { return nil }
        let ptr = CFDataGetBytePtr(data)!
        let w = frame.width
        let h = frame.height
        let bpr = frame.bytesPerRow
        let bpp = frame.bitsPerPixel / 8

        let curGray = convertToGrayscaleFloat(ptr: ptr, bpr: bpr, w: w, h: h, bpp: bpp)
        let curGrayCoarse = downsampleGray4x(curGray, w: w, h: h)

        let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        return PreprocessedFrame(
            cgImage: frame, rgbaData: data,
            curGray: curGray, curGrayCoarse: curGrayCoarse,
            w: w, h: h, bpr: bpr, bpp: bpp, preprocessTimeMs: ms
        )
    }

    // MARK: - Pipeline Stage 2: Match + Composite

    /// SSD matching and canvas composite — runs on matchQueue (serial, one frame at a time).
    nonisolated private func matchAndComposite(preprocessed pp: PreprocessedFrame) {
        let tStart = CFAbsoluteTimeGetCurrent()
        let frame = pp.cgImage
        let w = pp.w
        let h = pp.h

        stateLock.lock()
        let prevCG = _previousCG
        let canvas = _canvas
        let cachedStatic = _cachedStaticRows
        let prevGray = _previousGray
        let prevGrayCoarse = _previousGrayCoarse
        let grayW = _grayWidth
        let grayH = _grayHeight
        stateLock.unlock()

        guard let prevCG, canvas != nil else { return }

        // Size mismatch — update anchor and skip
        guard prevCG.width == w, prevCG.height == h else {
            stateLock.withLock {
                _previousCG = frame
                _previousGray = pp.curGray
                _previousGrayCoarse = pp.curGrayCoarse
                _grayWidth = w
                _grayHeight = h
            }
            log.warning("Frame skipped: size mismatch")
            return
        }

        let curPtr = CFDataGetBytePtr(pp.rgbaData)!

        // Use cached previous gray, or convert now (fallback)
        let effPrevGray: [Float]
        let effPrevGrayCoarse: [Float]
        if let prevGray, let prevGrayCoarse, grayW == w, grayH == h {
            effPrevGray = prevGray
            effPrevGrayCoarse = prevGrayCoarse
        } else {
            // Fallback: extract prev pixel data and convert
            guard let prevData = prevCG.dataProvider?.data else {
                stateLock.withLock {
                    _previousCG = frame
                    _previousGray = pp.curGray
                    _previousGrayCoarse = pp.curGrayCoarse
                    _grayWidth = w
                    _grayHeight = h
                }
                return
            }
            let prevPtr = CFDataGetBytePtr(prevData)!
            let prevBPR = prevCG.bytesPerRow
            let bpp = prevCG.bitsPerPixel / 8
            effPrevGray = convertToGrayscaleFloat(ptr: prevPtr, bpr: prevBPR, w: w, h: h, bpp: bpp)
            effPrevGrayCoarse = downsampleGray4x(effPrevGray, w: w, h: h)
        }

        func updateAnchor() {
            stateLock.withLock {
                _previousCG = frame
                _previousGray = pp.curGray
                _previousGrayCoarse = pp.curGrayCoarse
                _grayWidth = w
                _grayHeight = h
            }
        }

        // Phase 0: Quick near-duplicate rejection via sampled MAD.
        // Frames with no meaningful scroll have very low MAD (<2.0).
        // This prevents false dy=1 matches on smooth content regions.
        var rowDiff = [Float](repeating: 0, count: w)
        var totalAbsDiff: Float = 0
        var sampledRowCount: Float = 0
        effPrevGray.withUnsafeBufferPointer { pBuf in
            pp.curGray.withUnsafeBufferPointer { cBuf in
                for row in stride(from: 0, to: h, by: 10) {
                    let start = row * w
                    vDSP_vsub(cBuf.baseAddress! + start, 1, pBuf.baseAddress! + start, 1, &rowDiff, 1, vDSP_Length(w))
                    var rowMAD: Float = 0
                    vDSP_svemg(rowDiff, 1, &rowMAD, vDSP_Length(w))
                    totalAbsDiff += rowMAD / Float(w)
                    sampledRowCount += 1
                }
            }
        }
        let frameMAD = totalAbsDiff / max(1, sampledRowCount)
        guard frameMAD >= 2.0 else { updateAnchor(); return }

        // Phase 1: Detect static rows (top header, bottom footer)
        // Cache is only set after a successful stitch to avoid locking in wrong
        // values from near-duplicate pairs where no real scroll has occurred.
        let staticRows: (top: Int, bottom: Int)
        if let cached = cachedStatic {
            staticRows = cached
        } else {
            staticRows = detectStaticRowsGray(
                prevGray: effPrevGray, curGray: pp.curGray, w: w, h: h
            )
        }
        let roiH = h - staticRows.top - staticRows.bottom
        guard roiH > 80 else { updateAnchor(); return }

        // Phase 2: Column SSD matching — find vertical scroll offset
        let t1 = CFAbsoluteTimeGetCurrent()
        let roiTop = staticRows.top + 2
        let roiBottom = h - staticRows.bottom - 2
        let roiH2 = roiBottom - roiTop
        guard roiH2 > 40 else { updateAnchor(); return }

        let matchResult = findOffsetViaColumnSSD(
            prevGray: effPrevGray, curGray: pp.curGray,
            prevGrayCoarse: effPrevGrayCoarse, curGrayCoarse: pp.curGrayCoarse,
            w: w, h: h,
            roiTop: roiTop, roiBottom: roiBottom
        )

        let t2 = CFAbsoluteTimeGetCurrent()
        let deltaY = matchResult.deltaY
        let matchSSD = matchResult.ssdPerPixel
        let matchConf = matchResult.confidence

        // Accept if SSD is low with sufficient confidence, OR highly confident
        // even with elevated SSD. Confidence guards against false matches in
        // uniform/whitespace regions where SSD ≈ 0 at any offset.
        // passedLowSSD: near-perfect pixel match (< 2.0) is always safe for small scrolls
        // Large jumps (deltaY > 150) need higher confidence to prevent wrong
        // offsets that would create duplicated content bands.
        let passedSSD = matchSSD < 10.0 && matchConf >= 0.15
        let passedLowSSD = matchSSD < 2.0 && deltaY <= 100
        let passedHighConf = matchConf > 0.9 && matchSSD < 50.0
        let largeJumpSafe = deltaY <= 150 || matchConf >= 0.4
        let accepted = deltaY > 0 && (passedSSD || passedLowSSD || passedHighConf) && largeJumpSafe
        guard accepted else {
            updateAnchor()
            log.notice("Frame dropped: deltaY=\(deltaY) ssd=\(String(format: "%.1f", matchSSD)) conf=\(String(format: "%.3f", matchConf))")
            return
        }

        // Phase 3: PixelCanvas composite
        let appendHeight = min(deltaY, h - staticRows.bottom)
        guard appendHeight > 0 else { updateAnchor(); return }

        let sourceStart = h - staticRows.bottom - appendHeight

        stateLock.lock()
        // Cache static rows on first successful stitch — this guarantees the
        // detection was from a pair with real scrolling, not near-duplicates.
        if _cachedStaticRows == nil {
            let roiForCache = h - staticRows.top - staticRows.bottom
            if (staticRows.top >= 10 || staticRows.bottom >= 10) && roiForCache >= h * 3 / 10 {
                _cachedStaticRows = staticRows
                if staticRows.bottom > 0 {
                    _canvas?.trimBottom(staticRows.bottom)
                }
            }
        }
        _canvas?.appendRows(
            from: curPtr, bpr: pp.bpr,
            sourceStartRow: sourceStart,
            sourceRowCount: appendHeight
        )
        let canvasH = _canvas?.currentHeight ?? 0
        let canvasW = _canvas?.width ?? 0
        _previousCG = frame
        _previousGray = pp.curGray
        _previousGrayCoarse = pp.curGrayCoarse
        _grayWidth = w
        _grayHeight = h
        _lastDeltaY = deltaY
        _internalFrameCount += 1
        let count = _internalFrameCount
        let callback = onPreviewUpdate
        let lastPreview = _lastPreviewTime
        stateLock.unlock()

        // Throttled preview — only create CGImage every 200ms
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPreview > 0.2, let callback {
            stateLock.withLock { _lastPreviewTime = now }
            if let cg = stateLock.withLock({ _canvas?.makeCGImage() }) {
                let previewImage = makePlatformImage(cgImage: cg)
                DispatchQueue.main.async { callback(previewImage) }
            }
        }
        Task { @MainActor in self.frameCount = count }
        let t4 = CFAbsoluteTimeGetCurrent()
        log.notice("Frame stitched: deltaY=\(deltaY)px ssd=\(String(format: "%.1f", matchSSD)) conf=\(String(format: "%.3f", matchConf)) topStatic=\(staticRows.top)px bottomStatic=\(staticRows.bottom)px canvas=\(canvasW)x\(canvasH) timing=prep:\(pp.preprocessTimeMs)ms match:\(Int((t2-t1)*1000))ms total:\(Int((t4-tStart)*1000))ms")
    }

    // MARK: - Stitching

    /// Finalize and return the stitched image.
    func stitch(onProgress: ((StitchingProgress) -> Void)?) async throws -> PlatformImage {
        isStitching = true
        let runStartTime = CFAbsoluteTimeGetCurrent()
        onRuntimeEvent?(.phaseStarted(name: "stitch", mode: StitchExecutionMode.balanced.rawValue))

        // Drain both pipeline queues: preprocessQueue first (ensures all preprocessed
        // frames are dispatched to matchQueue), then matchQueue (processes them in order).
        let frames = stateLock.withLock { Array(_capturedFrames) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            preprocessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { continuation.resume(); return }
                self.matchQueue.async(flags: .barrier) { [weak self] in
                    guard let self else { continuation.resume(); return }
                    // Process any remaining frames not yet dispatched
                    let startIdx = self.stateLock.withLock { self._processedFrameIndex }
                    for i in startIdx..<frames.count {
                        if let pp = self.preprocess(frame: frames[i]) {
                            self.matchAndComposite(preprocessed: pp)
                        }
                    }
                    continuation.resume()
                }
            }
        }
        let (finalCG, totalFrames, acceptedFrames): (CGImage?, Int, Int) = stateLock.withLock {
            // Re-add bottom static footer from the last captured frame
            if let bottomStatic = _cachedStaticRows?.bottom, bottomStatic > 0,
               let lastFrame = _capturedFrames.last,
               let data = lastFrame.dataProvider?.data {
                _canvas?.appendRows(
                    from: CFDataGetBytePtr(data)!, bpr: lastFrame.bytesPerRow,
                    sourceStartRow: lastFrame.height - bottomStatic,
                    sourceRowCount: bottomStatic
                )
            }
            return (_canvas?.makeCGImage(), _capturedFrames.count, _internalFrameCount)
        }

        guard let finalCG else {
            isStitching = false
            throw StitchingError.noFrames
        }

        let image = makePlatformImage(cgImage: finalCG)
        result = image
        isStitching = false

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - runStartTime) * 1000.0)
        lastRunMetrics = StitchRunMetrics(
            totalFrames: totalFrames,
            skippedFrames: max(0, totalFrames - acceptedFrames),
            downScrollFrames: max(0, acceptedFrames - 1),
            upScrollFrames: 0,
            duplicateRejects: max(0, totalFrames - acceptedFrames),
            noMovementRejects: max(0, totalFrames - acceptedFrames),
            finalPixelWidth: finalCG.width,
            finalPixelHeight: finalCG.height,
            elapsedMilliseconds: elapsedMs
        )

        log.notice("Stitch complete: \(finalCG.width)x\(finalCG.height), frames=\(totalFrames), accepted=\(acceptedFrames), elapsed=\(elapsedMs)ms")

        return image
    }

    /// API compatibility overload used by existing tests/callers.
    func stitch() async throws -> PlatformImage {
        try await stitch(onProgress: nil)
    }

    // MARK: - Control

    /// Reset the coordinator for a new capture session.
    func reset() {
        stateLock.withLock {
            _canvas = nil
            _previousCG = nil
            _internalFrameCount = 0
            _capturedFrames.removeAll(keepingCapacity: false)
            _cachedStaticRows = nil
            _processedFrameIndex = 0
            _lastPreviewTime = 0
            _previousGray = nil
            _previousGrayCoarse = nil
            _grayWidth = 0
            _grayHeight = 0
            _lastDeltaY = nil
        }

        frameCount = 0
        isStitching = false
        progress = nil
        result = nil
        error = nil
        acceptedFrameSize = nil
        onPreviewUpdate = nil
        onRuntimeEvent = nil
        lastRunMetrics = nil
        log.info("StitchingCoordinator reset")
    }

    /// Cancel stitching (no-op for incremental approach).
    func cancel() {
        log.info("Cancel called (no-op for incremental stitching)")
    }

    /// Total frame count (for API compatibility).
    var totalFrameCount: Int {
        frameCount
    }

    /// Returns all captured frames in acceptance order (post size validation).
    func loadAllFrames() throws -> [CGImage] {
        stateLock.withLock { _capturedFrames }
    }

    /// Write all captured frames to disk as PNGs, one at a time to avoid
    /// duplicating the entire frame array in memory.
    /// Returns the number of frames written.
    func exportFramesToDisk(directory: URL) -> Int {
        let count = stateLock.withLock { _capturedFrames.count }
        guard count > 0 else { return 0 }

        for i in 0..<count {
            let frame = stateLock.withLock { _capturedFrames[i] }
            let filename = String(format: "frame-%05d.png", i)
            let url = directory.appendingPathComponent(filename)
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, frame, nil)
                CGImageDestinationFinalize(dest)
            }
        }
        return count
    }

    nonisolated private func currentStitchImage() -> PlatformImage? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let cg = _canvas?.makeCGImage() else { return nil }
        return makePlatformImage(cgImage: cg)
    }

    // MARK: - Private: Static Row Detection

    /// Detect static rows from raw pixel pointers (avoids redundant CGImage decompression).
    nonisolated private func detectStaticRowsFromPtr(
        prevPtr: UnsafePointer<UInt8>, curPtr: UnsafePointer<UInt8>,
        w: Int, h: Int, prevBPR: Int, curBPR: Int, bpp: Int
    ) -> (top: Int, bottom: Int) {
        let threshold: Float = 5.0
        let baseGapTolerance = 15
        let maxPerSide = Int(Float(h) * 0.4)
        let pixelsPerRow = w * bpp

        // Top scan
        var topStatic = 0
        var consecutiveNonStatic = 0
        let topMax = min(h, maxPerSide)
        for row in 0..<topMax {
            var sum: Float = 0
            let prevRow = prevPtr + row * prevBPR
            let curRow = curPtr + row * curBPR
            for col in 0..<pixelsPerRow {
                sum += abs(Float(prevRow[col]) - Float(curRow[col]))
            }
            if sum / Float(pixelsPerRow) <= threshold {
                topStatic = row + 1
                consecutiveNonStatic = 0
            } else {
                consecutiveNonStatic += 1
                let effectiveGap = topStatic > 200 ? 3 : baseGapTolerance
                if consecutiveNonStatic > effectiveGap { break }
            }
        }
        if topStatic < 10 { topStatic = 0 }

        // Bottom scan (from last row upward)
        var bottomStatic = 0
        consecutiveNonStatic = 0
        let bottomMax = min(h, maxPerSide)
        for offset in 0..<bottomMax {
            let row = h - 1 - offset
            guard row >= topStatic else { break }
            var sum: Float = 0
            let prevRow = prevPtr + row * prevBPR
            let curRow = curPtr + row * curBPR
            for col in 0..<pixelsPerRow {
                sum += abs(Float(prevRow[col]) - Float(curRow[col]))
            }
            if sum / Float(pixelsPerRow) <= threshold {
                bottomStatic = offset + 1
                consecutiveNonStatic = 0
            } else {
                consecutiveNonStatic += 1
                let effectiveGap = bottomStatic > 200 ? 3 : baseGapTolerance
                if consecutiveNonStatic > effectiveGap { break }
            }
        }
        if bottomStatic < 10 { bottomStatic = 0 }

        return (top: topStatic, bottom: bottomStatic)
    }

    /// Convenience: detect static rows from CGImage pair (used for external API).
    nonisolated private func detectStaticRows(previous: CGImage, current: CGImage) -> (top: Int, bottom: Int) {
        guard previous.width == current.width, previous.height == current.height,
              let prevData = previous.dataProvider?.data,
              let curData = current.dataProvider?.data else { return (0, 0) }
        return detectStaticRowsFromPtr(
            prevPtr: CFDataGetBytePtr(prevData)!, curPtr: CFDataGetBytePtr(curData)!,
            w: previous.width, h: previous.height,
            prevBPR: previous.bytesPerRow, curBPR: current.bytesPerRow,
            bpp: previous.bitsPerPixel / 8
        )
    }

    // MARK: - Private: Template Matching (SSD)

    /// Compute SSD between a template and a search area at each slide position.
    // MARK: - Private: Fast Coarse SSD (early termination, center-half, no trimming)

    /// Fast coarse SSD search with early termination.
    /// Returns best position (in pixel units) and confidence.
    /// Uses center-half columns and no per-row trimming for maximum speed.
    nonisolated private func coarseMatchSSD(
        templatePtr: UnsafePointer<UInt8>, templateBPR: Int, templateStartRow: Int,
        searchPtr: UnsafePointer<UInt8>, searchBPR: Int, searchStartRow: Int,
        width: Int, bpp: Int,
        templateH: Int, searchH: Int,
        downsample: Int
    ) -> (bestPosition: Int?, confidence: Float) {
        let dsTemplateH = templateH / downsample
        guard dsTemplateH >= 2 else { return (nil, 0) }

        let maxPos = searchH - templateH
        guard maxPos >= 0 else { return (nil, 0) }

        // Full width for coarse quality, but stride by downsample×bpp for speed
        let colStart = 0
        let colEnd = width * bpp
        let colStride = bpp * downsample

        var bestSSD: Float = .greatestFiniteMagnitude
        var bestPos: Int = 0
        var secondBestSSD: Float = .greatestFiniteMagnitude

        // Reverse scan: scroll-down content matches near the END of the search range.
        // Scanning end→start finds bestSSD first, enabling early termination on all
        // subsequent positions (especially duplicates that match at the very end).
        let startPos = maxPos - (maxPos % downsample)  // align to downsample grid
        for pos in stride(from: startPos, through: 0, by: -downsample) {
            var totalSSD: Float = 0
            var earlyTerminated = false

            for tRow in stride(from: 0, to: templateH, by: downsample) {
                let tRowPtr = templatePtr + (templateStartRow + tRow) * templateBPR
                let sRowPtr = searchPtr + (searchStartRow + pos + tRow) * searchBPR

                var rowSSD: Float = 0
                var col = colStart
                while col < colEnd {
                    let diff = Float(tRowPtr[col]) - Float(sRowPtr[col])
                    rowSSD += diff * diff
                    col += colStride
                }
                totalSSD += rowSSD

                // Early termination: if running mean already exceeds 3× best, skip
                if totalSSD > bestSSD * 3.0 {
                    earlyTerminated = true
                    break
                }
            }

            if earlyTerminated { continue }

            let meanSSD = totalSSD / Float(dsTemplateH)
            if meanSSD < bestSSD {
                if abs(pos - bestPos) > downsample * 5 { secondBestSSD = bestSSD }
                bestSSD = meanSSD
                bestPos = pos
            } else if meanSSD < secondBestSSD && abs(pos - bestPos) > downsample * 5 {
                secondBestSSD = meanSSD
            }
        }

        guard bestSSD < .greatestFiniteMagnitude else { return (nil, 0) }

        let confidence: Float
        if secondBestSSD > 0, secondBestSSD < .greatestFiniteMagnitude, bestSSD < secondBestSSD {
            confidence = 1.0 - (bestSSD / secondBestSSD)
        } else {
            confidence = 0
        }

        return (bestPosition: bestPos, confidence: confidence)
    }

    // MARK: - Private: Fine Template Matching (SSD with trimming)

    /// Compute SSD between a template and a search area at each slide position.
    /// Uses per-row trimmed SSD (discard top 15% of row SSDs) for animation robustness.
    nonisolated private func templateMatchSSD(
        templatePtr: UnsafePointer<UInt8>, templateBPR: Int, templateStartRow: Int,
        searchPtr: UnsafePointer<UInt8>, searchBPR: Int, searchStartRow: Int,
        width: Int, bpp: Int,
        templateH: Int, searchH: Int,
        downsample: Int = 1,
        searchStart: Int = 0, searchEnd: Int? = nil
    ) -> [(position: Int, ssd: Float)] {
        let dsTemplateH = templateH / downsample
        guard dsTemplateH >= 2 else { return [] }

        let maxPos = searchH - templateH
        let effectiveEnd = min(searchEnd ?? (maxPos + 1), maxPos + 1)
        guard searchStart < effectiveEnd else { return [] }

        var results: [(position: Int, ssd: Float)] = []
        results.reserveCapacity((effectiveEnd - searchStart) / max(downsample, 1))

        let trimFraction: Float = 0.15  // discard top 15% of per-row SSDs

        for pos in stride(from: searchStart, to: effectiveEnd, by: downsample) {
            var rowSSDs: [Float] = []
            rowSSDs.reserveCapacity(dsTemplateH)

            for tRow in stride(from: 0, to: templateH, by: downsample) {
                let templateRowIdx = templateStartRow + tRow
                let searchRowIdx = searchStartRow + pos + tRow

                let tRowPtr = templatePtr + templateRowIdx * templateBPR
                let sRowPtr = searchPtr + searchRowIdx * searchBPR

                var rowSSD: Float = 0
                var col = 0
                let colEnd = width * bpp
                while col < colEnd {
                    let diff = Float(tRowPtr[col]) - Float(sRowPtr[col])
                    rowSSD += diff * diff
                    col += bpp * downsample
                }
                rowSSDs.append(rowSSD)
            }

            guard !rowSSDs.isEmpty else { continue }

            // Trimmed aggregation: sort, discard top 15%
            rowSSDs.sort()
            let trimCount = max(1, Int(Float(rowSSDs.count) * trimFraction))
            let keepCount = rowSSDs.count - trimCount
            guard keepCount > 0 else { continue }

            var totalSSD: Float = 0
            for i in 0..<keepCount {
                totalSSD += rowSSDs[i]
            }

            results.append((position: pos / downsample, ssd: totalSSD / Float(keepCount)))
        }

        return results
    }

    /// Compute confidence (sharpness) of the SSD minimum.
    /// Finds second-best SSD at least `neighborRadius` positions away from best.
    /// Confidence = 1.0 - (bestSSD / secondBestSSD). Returns 0..1.
    nonisolated private func computeConfidence(
        ssdResults: [(position: Int, ssd: Float)],
        bestIdx: Int,
        neighborRadius: Int = 20
    ) -> Float {
        guard bestIdx < ssdResults.count else { return 0 }
        let bestSSD = ssdResults[bestIdx].ssd
        let bestPos = ssdResults[bestIdx].position

        var secondBestSSD: Float = Float.greatestFiniteMagnitude
        for (i, result) in ssdResults.enumerated() {
            if i == bestIdx { continue }
            if abs(result.position - bestPos) < neighborRadius { continue }
            if result.ssd < secondBestSSD {
                secondBestSSD = result.ssd
            }
        }

        guard secondBestSSD > 0, secondBestSSD < Float.greatestFiniteMagnitude,
              bestSSD < secondBestSSD else { return 0 }

        return 1.0 - (bestSSD / secondBestSSD)
    }

    /// Compute pixel variance of a region (for template quality check).
    nonisolated private func computeRegionVariance(
        ptr: UnsafePointer<UInt8>, bpr: Int,
        w: Int, bpp: Int,
        startRow: Int, rowCount: Int
    ) -> Float {
        var sum: Float = 0
        var sumSq: Float = 0
        var count: Float = 0

        // Sample every 4th row, every 4th pixel for speed
        for row in stride(from: startRow, to: startRow + rowCount, by: 4) {
            let rowPtr = ptr + row * bpr
            var col = 0
            let colEnd = w * bpp
            while col < colEnd {
                let val = Float(rowPtr[col])
                sum += val
                sumSq += val * val
                count += 1
                col += bpp * 4
            }
        }

        guard count > 1 else { return 0 }
        let mean = sum / count
        return (sumSq / count) - (mean * mean)
    }

    // MARK: - Private: Column SSD Matching

    private struct ColumnSSDResult {
        let deltaY: Int
        let ssdPerPixel: Float   // SSD per pixel in the overlap zone (lower = better match)
        let confidence: Float    // 0..1 — how much better best SSD is vs second-best at a different offset
    }

    /// Find scroll offset via 2-level hierarchical SSD template matching.
    ///
    /// Algorithm (coarse-to-fine):
    /// 1. Level 0 (4× downsample) — scan ALL dy positions at 4× resolution
    /// 2. Level 1 (1× full res) — refine top 3 L0 candidates ±3px
    ///
    /// Previous 3-level (16× → 4× → 1×) was too coarse at L0: the 16× scan
    /// often missed the correct offset for pages with uniform content or small
    /// scrolls, producing low confidence that caused valid frames to be dropped.
    /// The 4× scan is ~4× more expensive but still fast (~2-3ms) and far more
    /// accurate, eliminating a whole class of false rejections.
    nonisolated private func findOffsetViaColumnSSD(
        prevGray: [Float], curGray: [Float],
        prevGrayCoarse: [Float], curGrayCoarse: [Float],
        w: Int, h: Int,
        roiTop: Int, roiBottom: Int
    ) -> ColumnSSDResult {
        let roiH = roiBottom - roiTop
        let noMatch = ColumnSSDResult(deltaY: 0, ssdPerPixel: Float.greatestFiniteMagnitude, confidence: 0)

        guard roiH > 40, w > 10 else { return noMatch }

        // Center-column margins: exclude outer 20% on each side to handle
        // sticky sidebars, scrollbars, and fixed edge decorations.
        // Only the center 60% of columns are compared at each SSD level.
        let marginFrac = 5  // 1/5 = 20% margin on each side

        // Downsample factors
        let ds4 = 4
        let ds4W = w / ds4
        let ds4H = h / ds4
        let ds4RoiTop = roiTop / ds4
        let ds4RoiH = roiH / ds4
        guard ds4W > 0, ds4RoiH > 10, ds4H > 0 else { return noMatch }

        // --- Level 0: Full scan at 4× downsample ---
        struct Candidate { let dy: Int; let ssd: Float }
        var l0Candidates: [Candidate] = []

        let margin4 = ds4W / marginFrac
        let center4Start = margin4
        let colStride4 = vDSP_Stride(2)
        let center4Span = max(1, ds4W - 2 * margin4)
        let colCount4 = vDSP_Length((center4Span + 1) / 2)
        let minOverlap4 = max(3, ds4RoiH * 3 / 10)
        let maxDy4 = ds4RoiH - minOverlap4

        l0Candidates.reserveCapacity(maxDy4)
        var rowBuf4 = [Float](repeating: 0, count: ds4RoiH)

        prevGrayCoarse.withUnsafeBufferPointer { pBuf in
            curGrayCoarse.withUnsafeBufferPointer { cBuf in
                let pBase = pBuf.baseAddress!
                let cBase = cBuf.baseAddress!

                for dy4 in 1...maxDy4 {
                    let overlap4 = ds4RoiH - dy4
                    guard overlap4 >= minOverlap4 else { continue }
                    guard ds4RoiTop + overlap4 <= ds4H,
                          ds4RoiTop + dy4 + overlap4 <= ds4H else { continue }

                    var idx = 0
                    for r in stride(from: 0, to: overlap4, by: 2) {
                        let prevRow = (ds4RoiTop + dy4 + r) * ds4W + center4Start
                        let curRow = (ds4RoiTop + r) * ds4W + center4Start
                        vDSP_distancesq(pBase + prevRow, colStride4,
                                        cBase + curRow, colStride4,
                                        &rowBuf4[idx], colCount4)
                        idx += 1
                    }
                    // Trim top 30% — tolerates animated content (GIFs, ads, timestamps)
                    rowBuf4[0..<idx].sort()
                    let keep = max(1, idx - Int(Float(idx) * 0.30))
                    var total: Float = 0
                    for i in 0..<keep { total += rowBuf4[i] }
                    l0Candidates.append(Candidate(dy: dy4, ssd: total / Float(keep) / Float(colCount4)))
                }
            }
        }

        guard !l0Candidates.isEmpty else { return noMatch }
        l0Candidates.sort { $0.ssd < $1.ssd }

        // Compute confidence from L0 (4×) landscape: best vs second-best at a different offset.
        let l0Confidence: Float = {
            let best = l0Candidates[0]
            if let secondBest = l0Candidates.first(where: { abs($0.dy - best.dy) > 5 }) {
                return best.ssd < secondBest.ssd ? 1.0 - (best.ssd / secondBest.ssd) : 0
            }
            return 0
        }()

        // --- Level 1: Fine refinement at full resolution ±3px ---
        // Skip if L0 winner already has very low SSD (< 5.0 at 4× is accurate enough).
        let l0Best = l0Candidates[0]
        if l0Best.ssd < 5.0 {
            let dy = l0Best.dy * ds4
            if dy > 0 {
                let topL0 = l0Candidates.prefix(3).map { "dy\($0.dy * ds4)=\(String(format: "%.1f", $0.ssd))" }.joined(separator: ",")
                log.notice("ColumnSSD: L0=[\(topL0)] winner=dy\(dy) ssd=\(String(format: "%.1f", l0Best.ssd)) conf=\(String(format: "%.3f", l0Confidence)) (L0-fast)")
                return ColumnSSDResult(deltaY: dy, ssdPerPixel: l0Best.ssd, confidence: l0Confidence)
            }
        }

        // Refine top 3 L0 candidates at full resolution for ±3px precision
        var bestResult = noMatch
        let marginFine = w / marginFrac
        let centerFineStart = marginFine
        let centerFineSpan = max(1, w - 2 * marginFine)
        let fineColStride = vDSP_Stride(4)
        let fineColCount = vDSP_Length((centerFineSpan + 3) / 4)
        var fineRowSSDs = [Float](repeating: 0, count: (roiH + 3) / 4)

        prevGray.withUnsafeBufferPointer { pBuf in
            curGray.withUnsafeBufferPointer { cBuf in
                let pBase = pBuf.baseAddress!
                let cBase = cBuf.baseAddress!

                for l0c in l0Candidates.prefix(3) {
                    let centerDy = l0c.dy * ds4
                    let fineStart = max(1, centerDy - 3)
                    let fineEnd = min(roiH - 20, centerDy + 3)
                    guard fineStart <= fineEnd else { continue }

                    for dy in fineStart...fineEnd {
                        let overlapH = roiH - dy
                        guard overlapH > 20 else { continue }
                        guard roiTop + overlapH <= h,
                              roiTop + dy + overlapH <= h else { continue }

                        var idx = 0
                        for r in stride(from: 0, to: overlapH, by: 4) {
                            let prevRowStart = (roiTop + dy + r) * w + centerFineStart
                            let curRowStart = (roiTop + r) * w + centerFineStart
                            vDSP_distancesq(pBase + prevRowStart, fineColStride,
                                            cBase + curRowStart, fineColStride,
                                            &fineRowSSDs[idx], fineColCount)
                            idx += 1
                        }
                        let actualSamples = idx

                        fineRowSSDs[0..<actualSamples].sort()
                        let keepCount = max(1, actualSamples - Int(Float(actualSamples) * 0.30))
                        var totalSSD: Float = 0
                        for i in 0..<keepCount { totalSSD += fineRowSSDs[i] }
                        let ssdPerPixel = totalSSD / Float(keepCount) / Float(fineColCount)

                        if ssdPerPixel < bestResult.ssdPerPixel {
                            bestResult = ColumnSSDResult(deltaY: dy, ssdPerPixel: ssdPerPixel, confidence: l0Confidence)
                        }
                    }
                }
            }
        }

        if bestResult.deltaY > 0 {
            let topL0 = l0Candidates.prefix(3).map { "dy\($0.dy * ds4)=\(String(format: "%.1f", $0.ssd))" }.joined(separator: ",")
            log.notice("ColumnSSD: L0=[\(topL0)] winner=dy\(bestResult.deltaY) ssd=\(String(format: "%.1f", bestResult.ssdPerPixel)) conf=\(String(format: "%.3f", l0Confidence))")
        }

        return bestResult
    }

    // MARK: - Private: Grayscale Static Row Detection

    /// Detect static rows from grayscale Float buffers using vDSP.
    nonisolated private func detectStaticRowsGray(
        prevGray: [Float], curGray: [Float], w: Int, h: Int
    ) -> (top: Int, bottom: Int) {
        let threshold: Float = 5.0
        let baseGapTolerance = 15
        let maxPerSide = Int(Float(h) * 0.4)
        var diffRow = [Float](repeating: 0, count: w)

        // Top scan
        var topStatic = 0
        var consecutiveNonStatic = 0
        let topMax = min(h, maxPerSide)
        for row in 0..<topMax {
            let rowStart = row * w
            // diffRow = prevGray[row] - curGray[row]
            prevGray.withUnsafeBufferPointer { pBuf in
                curGray.withUnsafeBufferPointer { cBuf in
                    vDSP_vsub(cBuf.baseAddress! + rowStart, 1,
                              pBuf.baseAddress! + rowStart, 1,
                              &diffRow, 1, vDSP_Length(w))
                }
            }
            // MAD = mean(abs(diff))
            var absSum: Float = 0
            vDSP_svemg(diffRow, 1, &absSum, vDSP_Length(w))
            let mad = absSum / Float(w)

            if mad <= threshold {
                topStatic = row + 1
                consecutiveNonStatic = 0
            } else {
                consecutiveNonStatic += 1
                let effectiveGap = topStatic > 200 ? 3 : baseGapTolerance
                if consecutiveNonStatic > effectiveGap { break }
            }
        }
        if topStatic < 10 { topStatic = 0 }

        // Bottom scan (from last row upward)
        var bottomStatic = 0
        consecutiveNonStatic = 0
        let bottomMax = min(h, maxPerSide)
        for offset in 0..<bottomMax {
            let row = h - 1 - offset
            guard row >= topStatic else { break }
            let rowStart = row * w
            prevGray.withUnsafeBufferPointer { pBuf in
                curGray.withUnsafeBufferPointer { cBuf in
                    vDSP_vsub(cBuf.baseAddress! + rowStart, 1,
                              pBuf.baseAddress! + rowStart, 1,
                              &diffRow, 1, vDSP_Length(w))
                }
            }
            var absSum: Float = 0
            vDSP_svemg(diffRow, 1, &absSum, vDSP_Length(w))
            let mad = absSum / Float(w)

            if mad <= threshold {
                bottomStatic = offset + 1
                consecutiveNonStatic = 0
            } else {
                consecutiveNonStatic += 1
                let effectiveGap = bottomStatic > 200 ? 3 : baseGapTolerance
                if consecutiveNonStatic > effectiveGap { break }
            }
        }
        if bottomStatic < 10 { bottomStatic = 0 }

        return (top: topStatic, bottom: bottomStatic)
    }

    // MARK: - Private: Grayscale Coarse SSD

    // MARK: - Private: Grayscale Conversion

    /// Convert RGBA UInt8 pixel data to proper grayscale Float buffer.
    /// Uses ITU-R BT.601 luminance: gray = 0.299*R + 0.587*G + 0.114*B
    /// vDSP_vfltu8 for SIMD UInt8→Float, vDSP_vsma for weighted accumulation.
    nonisolated private func convertToGrayscaleFloat(
        ptr: UnsafePointer<UInt8>, bpr: Int, w: Int, h: Int, bpp: Int
    ) -> [Float] {
        let count = w * h
        var gray = [Float](repeating: 0, count: count)
        // Row-level scratch buffers (reused across rows)
        var rFloat = [Float](repeating: 0, count: w)
        var gFloat = [Float](repeating: 0, count: w)
        var bFloat = [Float](repeating: 0, count: w)
        var rWeight: Float = 0.299
        var gWeight: Float = 0.587
        var bWeight: Float = 0.114
        let n = vDSP_Length(w)

        for row in 0..<h {
            let rowPtr = ptr + row * bpr
            let grayRowStart = row * w
            // SIMD UInt8→Float with stride=bpp (picks every bpp-th byte = one channel)
            vDSP_vfltu8(rowPtr, vDSP_Stride(bpp), &rFloat, 1, n)          // R
            vDSP_vfltu8(rowPtr + 1, vDSP_Stride(bpp), &gFloat, 1, n)      // G
            vDSP_vfltu8(rowPtr + 2, vDSP_Stride(bpp), &bFloat, 1, n)      // B
            // gray[row] = 0.299*R + 0.587*G + 0.114*B
            gray.withUnsafeMutableBufferPointer { gBuf in
                let dst = gBuf.baseAddress! + grayRowStart
                vDSP_vsmul(rFloat, 1, &rWeight, dst, 1, n)
                vDSP_vsma(gFloat, 1, &gWeight, dst, 1, dst, 1, n)
                vDSP_vsma(bFloat, 1, &bWeight, dst, 1, dst, 1, n)
            }
        }
        return gray
    }

    /// Downsample a grayscale Float buffer by 4× (box filter via simple subsampling).
    nonisolated private func downsampleGray4x(
        _ gray: [Float], w: Int, h: Int
    ) -> [Float] {
        let dw = w / 4
        let dh = h / 4
        guard dw > 0, dh > 0 else { return [] }
        var coarse = [Float](repeating: 0, count: dw * dh)
        for row in 0..<dh {
            let srcRow = row * 4
            let srcRowStart = srcRow * w
            let dstRowStart = row * dw
            for col in 0..<dw {
                coarse[dstRowStart + col] = gray[srcRowStart + col * 4]
            }
        }
        return coarse
    }

    // MARK: - Private: Utilities

    nonisolated private func cropRightEdgeIfNeeded(_ image: CGImage) -> CGImage {
        guard rightEdgeCropPixels > 0 else { return image }
        let crop = min(rightEdgeCropPixels, max(0, image.width - 2))
        guard crop > 0 else { return image }

        let rect = CGRect(x: 0, y: 0, width: image.width - crop, height: image.height)
        return image.cropping(to: rect) ?? image
    }

    /// Ensure a CGImage has standalone pixel data accessible via dataProvider.
    /// CGImage.cropping(to:) shares the parent's backing buffer — CFDataGetBytePtr
    /// returns the parent's (0,0) offset, and bytesPerRow reflects the parent's width.
    /// This re-renders such sub-images into a fresh bitmap with correct layout.
    nonisolated private func normalizePixelData(_ image: CGImage) -> CGImage {
        let bpp = image.bitsPerPixel / 8
        guard bpp > 0 else { return image }
        // Fast path: standalone image with correct row stride and accessible data
        if image.bytesPerRow == image.width * bpp, image.dataProvider?.data != nil {
            return image
        }
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * bpp,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

}

// MARK: - Convenience: Save / Copy / Share

extension StitchingCoordinator {

    /// Save the stitched result to a file.
    func save(
        to url: URL,
        format: ImageExporter.Format,
        trimTop: Int = 0,
        trimBottom: Int = 0
    ) throws {
        guard let image = result else {
            throw StitchingError.exportFailed(format: "save", reason: "No stitched result available.")
        }

        let finalImage: PlatformImage
        if trimTop > 0 || trimBottom > 0 {
            #if canImport(AppKit)
            guard let trimmed = image.trimmed(top: trimTop, bottom: trimBottom) else {
                throw StitchingError.exportFailed(format: "save", reason: "Invalid trim parameters.")
            }
            finalImage = trimmed
            #elseif canImport(UIKit)
            finalImage = image.trimmed(top: CGFloat(trimTop), bottom: CGFloat(trimBottom))
            #endif
        } else {
            finalImage = image
        }

        try ImageExporter.export(finalImage, to: url, format: format)
    }

    /// Copy the stitched result to the clipboard.
    func copyToClipboard(trimTop: Int = 0, trimBottom: Int = 0) throws {
        guard let image = result else {
            throw StitchingError.exportFailed(format: "clipboard", reason: "No stitched result available.")
        }

        let finalImage: PlatformImage
        if trimTop > 0 || trimBottom > 0 {
            #if canImport(AppKit)
            guard let trimmed = image.trimmed(top: trimTop, bottom: trimBottom) else {
                throw StitchingError.exportFailed(format: "clipboard", reason: "Invalid trim parameters.")
            }
            finalImage = trimmed
            #elseif canImport(UIKit)
            finalImage = image.trimmed(top: CGFloat(trimTop), bottom: CGFloat(trimBottom))
            #endif
        } else {
            finalImage = image
        }

        #if canImport(AppKit)
        try finalImage.copyToClipboard()
        #elseif canImport(UIKit)
        finalImage.copyToClipboard()
        #endif
    }
}
