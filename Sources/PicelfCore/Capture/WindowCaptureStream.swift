import Foundation
import ScreenCaptureKit
import CoreMedia
import os

private let log = Logger(subsystem: "com.picelf", category: "CaptureStream")

struct WindowCaptureRegion: Equatable {
    let xPoints: CGFloat
    let yPointsFromTop: CGFloat
    let widthPoints: CGFloat
    let heightPoints: CGFloat
}

enum WindowCaptureStreamError: Error, LocalizedError {
    case invalidCaptureRegion
    case stopTimedOut(seconds: Double)

    var errorDescription: String? {
        switch self {
        case .invalidCaptureRegion:
            return "The selected capture region is invalid."
        case .stopTimedOut(let seconds):
            return "Stopping capture timed out after \(Int(seconds)) seconds."
        }
    }
}

@MainActor
final class WindowCaptureStream: NSObject, ObservableObject {
    private enum StreamLifecycleState {
        case idle
        case capturing
        case stopping
    }

    private struct OutputGateState {
        var lifecycle: StreamLifecycleState = .idle
        var acceptsFrames = false
        var cropRectPixels: CGRect?
    }

    @Published private(set) var isCapturing = false
    @Published private(set) var capturedFrameCount = 0
    @Published private(set) var error: Error?

    private var stream: SCStream?
    private var onFrame: ((CGImage) -> Void)?
    private let ciContext = CIContext()
    private let outputGate = OSAllocatedUnfairLock(initialState: OutputGateState())

    var framesPerSecond: Int = 10
    var showsCursor: Bool = false
    var scaleFactor: Int = 1

    func startCapture(
        window: SCWindow,
        region: WindowCaptureRegion? = nil,
        onFrame: @escaping (CGImage) -> Void
    ) async throws {
        self.onFrame = onFrame
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * scaleFactor
        config.height = Int(window.frame.height) * scaleFactor
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        config.showsCursor = showsCursor
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let configuredCropRect: CGRect?
        if let region {
            guard let pixelRect = Self.pixelCropRect(
                for: region,
                scaleFactor: scaleFactor,
                imageWidth: config.width,
                imageHeight: config.height
            ) else {
                throw WindowCaptureStreamError.invalidCaptureRegion
            }
            configuredCropRect = pixelRect
            log.info(
                "Capture region points x=\(region.xPoints, privacy: .public) yTop=\(region.yPointsFromTop, privacy: .public) w=\(region.widthPoints, privacy: .public) h=\(region.heightPoints, privacy: .public); pixels=\(pixelRect.debugDescription, privacy: .public)"
            )
        } else {
            configuredCropRect = nil
        }

        outputGate.withLock { state in
            state.lifecycle = .idle
            state.acceptsFrames = false
            state.cropRectPixels = configuredCropRect
        }

        log.info("Starting capture: window='\(window.title ?? "untitled")' configSize=\(config.width)x\(config.height) scaleFactor=\(self.scaleFactor) fps=\(self.framesPerSecond)")

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let queue = DispatchQueue(label: "com.picelf.capture", qos: .userInteractive)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        self.isCapturing = true
        self.capturedFrameCount = 0
        self.error = nil
        outputGate.withLock { state in
            state.lifecycle = .capturing
            state.acceptsFrames = true
            state.cropRectPixels = configuredCropRect
        }
        log.info("Capture stream started successfully")
    }

    func stopCapture(timeoutSeconds: Double = 3) async {
        guard let activeStream = stream else {
            log.warning("stopCapture() called but no active stream")
            outputGate.withLock { state in
                state.lifecycle = .idle
                state.acceptsFrames = false
                state.cropRectPixels = nil
            }
            return
        }
        log.info("Stopping capture stream. Total raw frames delivered: \(self.capturedFrameCount)")

        outputGate.withLock { state in
            state.lifecycle = .stopping
            state.acceptsFrames = false
        }

        isCapturing = false

        do {
            try activeStream.removeStreamOutput(self, type: .screen)
        } catch {
            log.warning("removeStreamOutput failed: \(error.localizedDescription)")
        }

        let stopTask = Task {
            try await activeStream.stopCapture()
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try await stopTask.value
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    throw WindowCaptureStreamError.stopTimedOut(seconds: timeoutSeconds)
                }

                _ = try await group.next()
                group.cancelAll()
            }
        } catch WindowCaptureStreamError.stopTimedOut {
            stopTask.cancel()
            log.error("stopCapture() timed out after \(Int(timeoutSeconds))s; continuing cleanup in background")
        } catch is CancellationError {
            stopTask.cancel()
            log.error("stopCapture() task cancelled; proceeding with teardown")
        } catch {
            log.error("Error stopping stream: \(error.localizedDescription)")
            self.error = error
        }

        stream = nil
        onFrame = nil
        outputGate.withLock { state in
            state.lifecycle = .idle
            state.acceptsFrames = false
            state.cropRectPixels = nil
        }
    }

    /// Both rects must be in CG screen coordinates (y-down, origin at top-left).
    nonisolated static func makeCaptureRegion(
        selectedFrameInScreen: CGRect,
        windowFrameInScreen: CGRect
    ) -> WindowCaptureRegion? {
        let intersection = selectedFrameInScreen.intersection(windowFrameInScreen)
        guard !intersection.isNull, !intersection.isEmpty else { return nil }
        guard intersection.width > 0, intersection.height > 0 else { return nil }

        let xPoints = intersection.minX - windowFrameInScreen.minX
        let yPointsFromTop = intersection.minY - windowFrameInScreen.minY
        let widthPoints = intersection.width
        let heightPoints = intersection.height

        guard xPoints >= 0,
              yPointsFromTop >= 0,
              widthPoints > 0,
              heightPoints > 0 else {
            return nil
        }

        return WindowCaptureRegion(
            xPoints: xPoints,
            yPointsFromTop: yPointsFromTop,
            widthPoints: widthPoints,
            heightPoints: heightPoints
        )
    }

    nonisolated static func pixelCropRect(
        for region: WindowCaptureRegion,
        scaleFactor: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect? {
        let scale = max(1, scaleFactor)
        let scaledXMin = Int(floor(region.xPoints * CGFloat(scale)))
        let scaledYMin = Int(floor(region.yPointsFromTop * CGFloat(scale)))
        let scaledXMax = Int(ceil((region.xPoints + region.widthPoints) * CGFloat(scale)))
        let scaledYMax = Int(ceil((region.yPointsFromTop + region.heightPoints) * CGFloat(scale)))

        let clampedXMin = max(0, min(imageWidth, scaledXMin))
        let clampedYMin = max(0, min(imageHeight, scaledYMin))
        let clampedXMax = max(clampedXMin, min(imageWidth, scaledXMax))
        let clampedYMax = max(clampedYMin, min(imageHeight, scaledYMax))

        let cropWidth = clampedXMax - clampedXMin
        let cropHeight = clampedYMax - clampedYMin
        guard cropWidth > 0, cropHeight > 0 else { return nil }

        return CGRect(x: clampedXMin, y: clampedYMin, width: cropWidth, height: cropHeight)
    }
}

extension WindowCaptureStream: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("SCStream stopped with error: \(error.localizedDescription)")
        Task { @MainActor in
            self.error = error
            self.isCapturing = false
            self.stream = nil
            self.outputGate.withLock { state in
                state.lifecycle = .idle
                state.acceptsFrames = false
                state.cropRectPixels = nil
            }
        }
    }
}

extension WindowCaptureStream: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        let gateSnapshot = outputGate.withLock { state in
            (state.acceptsFrames, state.cropRectPixels)
        }
        guard gateSnapshot.0 else { return }

        guard let imageBuffer = sampleBuffer.imageBuffer else {
            log.warning("Sample buffer has no imageBuffer — skipping frame")
            return
        }

        // Render to a CPU-backed bitmap so that dataProvider?.data is accessible
        // (CIContext.createCGImage can return GPU-backed images where raw pixel
        // access returns nil, which breaks frame deduplication.)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let gpuImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            log.warning("CIContext.createCGImage failed — skipping frame")
            return
        }

        // Draw into a CPU bitmap context to ensure dataProvider?.data works
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            log.warning("CGContext creation failed — skipping frame")
            return
        }
        ctx.draw(gpuImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let cpuImage = ctx.makeImage() else {
            log.warning("CGContext.makeImage failed — skipping frame")
            return
        }

        let outputImage: CGImage
        if let cropRectPixels = gateSnapshot.1 {
            let frameWidth = cpuImage.width
            let frameHeight = cpuImage.height
            let clampedCrop = CGRect(
                x: max(0, min(frameWidth, Int(cropRectPixels.origin.x))),
                y: max(0, min(frameHeight, Int(cropRectPixels.origin.y))),
                width: max(0, min(frameWidth, Int(cropRectPixels.maxX)) - max(0, min(frameWidth, Int(cropRectPixels.origin.x)))),
                height: max(0, min(frameHeight, Int(cropRectPixels.maxY)) - max(0, min(frameHeight, Int(cropRectPixels.origin.y))))
            )

            guard clampedCrop.width > 0,
                  clampedCrop.height > 0,
                  let cropped = cpuImage.cropping(to: clampedCrop) else {
                log.warning("Invalid crop rect during frame output: \(cropRectPixels.debugDescription, privacy: .public)")
                return
            }

            // Re-render to a fresh bitmap. CGImage.cropping(to:) shares the
            // parent's backing buffer — CFDataGetBytePtr returns the parent's
            // (0,0) offset, not the crop's. Downstream template matching reads
            // raw pixel data via dataProvider, so we need data aligned to (0,0).
            let freshImage: CGImage? = {
                guard let ctx = CGContext(
                    data: nil,
                    width: cropped.width, height: cropped.height,
                    bitsPerComponent: 8, bytesPerRow: cropped.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
                return ctx.makeImage()
            }()
            outputImage = freshImage ?? cropped
        } else {
            outputImage = cpuImage
        }

        Task { @MainActor in
            self.capturedFrameCount += 1
            self.onFrame?(outputImage)
        }
    }
}
