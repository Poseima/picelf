// SampleHandler.swift
// PicelfBroadcastUpload — Broadcast Upload Extension for cross-app screen recording
//
// RPBroadcastSampleHandler subclass that receives screen frames from the system
// when the user starts a broadcast from any app. Frames are written as JPEG files
// to the shared App Group directory for the main PicelfIOS app to consume.
//
// CRITICAL: Broadcast extensions have a 50MB memory limit. All frames must be
// written to disk immediately — do NOT accumulate frames in memory.
//
// Target: iOS 16+, Swift 5.9+

import ReplayKit
import UIKit
import os

private let log = Logger(subsystem: "com.picelf.broadcast", category: "SampleHandler")

/// Shared constants duplicated here because the extension cannot import the main app target.
/// These MUST match the values in BroadcastFrameRelay.swift.
private enum Constants {
    static let appGroupID = "group.com.picelf.open.shared"
    static let framesDirectoryName = "broadcast-frames"
    static let newFrameNotificationName = "com.picelf.broadcast.newFrame"
    static let recordingStoppedNotificationName = "com.picelf.broadcast.stopped"
    static let frameFilePrefix = "frame_"
    static let stopMarkerFileName = "recording-stopped.marker"
    static let jpegQuality: CGFloat = 0.7
}

class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Properties

    /// URL of the shared frames directory.
    private var framesDirectoryURL: URL?

    /// Monotonically increasing frame index for filename ordering.
    private var frameIndex: Int = 0

    /// Reuse CIContext for efficient pixel buffer → CGImage conversion.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Frame sampling: skip frames to reduce disk I/O and stay under memory limits.
    /// At ~30fps capture, sampling every 6th frame gives ~5fps effective rate.
    private var sampleBufferCount: Int = 0
    private let sampleInterval: Int = 6

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        log.notice("Broadcast started")

        // Create the shared frames directory
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupID
        ) else {
            log.error("Failed to get App Group container URL")
            finishBroadcastWithError(NSError(
                domain: "com.picelf.broadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared container"]
            ))
            return
        }

        let dir = containerURL.appendingPathComponent(Constants.framesDirectoryName, isDirectory: true)
        do {
            // Clean up any leftover frames from previous sessions
            if FileManager.default.fileExists(atPath: dir.path) {
                let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                for file in files {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error("Failed to create frames directory: \(error.localizedDescription)")
        }

        framesDirectoryURL = dir
        frameIndex = 0
        sampleBufferCount = 0
    }

    override func broadcastPaused() {
        log.notice("Broadcast paused")
    }

    override func broadcastResumed() {
        log.notice("Broadcast resumed")
    }

    override func broadcastFinished() {
        log.notice("Broadcast finished, total frames written: \(self.frameIndex)")

        if let framesDirectoryURL {
            let markerURL = framesDirectoryURL.appendingPathComponent(Constants.stopMarkerFileName)
            try? Data().write(to: markerURL, options: .atomic)
        }

        // Notify the main app that recording has stopped
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: Constants.recordingStoppedNotificationName as CFString),
            nil,
            nil,
            true
        )
    }

    // MARK: - Sample Buffer Processing

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Only process screen frames (ignore audio/mic)
        guard sampleBufferType == .video else { return }

        // Frame sampling to reduce disk writes
        sampleBufferCount += 1
        guard sampleBufferCount % sampleInterval == 0 else { return }

        guard let framesDir = framesDirectoryURL else { return }

        // Convert CMSampleBuffer → JPEG data and write to disk immediately
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        autoreleasepool {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            guard let cgImage = ciContext.createCGImage(
                ciImage,
                from: CGRect(x: 0, y: 0, width: width, height: height)
            ) else {
                return
            }

            // Convert to JPEG data
            let uiImage = UIImage(cgImage: cgImage)
            guard let jpegData = uiImage.jpegData(compressionQuality: Constants.jpegQuality) else {
                return
            }

            // Write to shared directory
            let fileName = String(format: "%@%06d.jpg", Constants.frameFilePrefix, frameIndex)
            let fileURL = framesDir.appendingPathComponent(fileName)

            do {
                try jpegData.write(to: fileURL, options: .atomic)
                frameIndex += 1

                // Notify main app that a new frame is available
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName(rawValue: Constants.newFrameNotificationName as CFString),
                    nil,
                    nil,
                    true
                )
            } catch {
                log.error("Failed to write frame \(self.frameIndex): \(error.localizedDescription)")
            }
        }
    }
}
