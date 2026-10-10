// ReplayKitCaptureStream.swift
// PicelfIOS — In-app ReplayKit screen capture stream
//
// Uses RPScreenRecorder.shared().startCapture to record the screen.
// Filters for .screen sample buffers only, converts CMSampleBuffer → CGImage
// via CVPixelBuffer → CIContext.createCGImage.
//
// Target: iOS 16+, Swift 5.9+

import ReplayKit
import CoreImage
import UIKit
import os

private let log = Logger(subsystem: "com.picelf.ios", category: "ReplayKitCaptureStream")

@MainActor
final class ReplayKitCaptureStream: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isCapturing = false
    @Published private(set) var frameCount = 0

    // MARK: - Private

    /// Reuse a single CIContext for CVPixelBuffer → CGImage conversion (avoid per-frame allocation).
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Frame callback provided by the caller.
    private var onFrame: ((CGImage) -> Void)?

    // MARK: - Public API

    /// Start capturing screen content via ReplayKit in-app capture.
    ///
    /// - Parameter onFrame: Called on a background thread for each captured screen frame (CGImage).
    /// - Throws: If ReplayKit fails to start capture or the recorder is unavailable.
    func startCapture(onFrame: @escaping (CGImage) -> Void) async throws {
        guard !isCapturing else {
            log.warning("startCapture called while already capturing")
            return
        }

        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            throw ReplayKitCaptureError.recorderUnavailable
        }

        self.onFrame = onFrame
        self.frameCount = 0

        // RPScreenRecorder.startCapture is callback-based; bridge to async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture { [weak self] sampleBuffer, sampleBufferType, error in
                // This handler is called on a background thread
                if let error {
                    log.error("ReplayKit capture error: \(error.localizedDescription)")
                    return
                }

                // Only process video frames (ignore audio/mic)
                guard sampleBufferType == .video else { return }
                guard let self else { return }

                if let cgImage = self.cgImageFromSampleBuffer(sampleBuffer) {
                    self.onFrame?(cgImage)
                    Task { @MainActor [weak self] in
                        self?.frameCount += 1
                    }
                }
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        isCapturing = true
        log.notice("ReplayKit capture started")
    }

    /// Stop capturing.
    func stopCapture() async throws {
        guard isCapturing else {
            log.warning("stopCapture called while not capturing")
            return
        }

        let recorder = RPScreenRecorder.shared()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        isCapturing = false
        onFrame = nil
        log.notice("ReplayKit capture stopped, total frames: \(self.frameCount)")
    }

    // MARK: - Private Helpers

    /// Convert a CMSampleBuffer (from ReplayKit .screen) to CGImage.
    private func cgImageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        return ciContext.createCGImage(ciImage, from: rect)
    }
}

// MARK: - Errors

enum ReplayKitCaptureError: LocalizedError {
    case recorderUnavailable

    var errorDescription: String? {
        switch self {
        case .recorderUnavailable:
            return "Screen recording is not available on this device."
        }
    }
}
