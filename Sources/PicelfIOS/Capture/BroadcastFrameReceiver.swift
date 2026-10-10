// BroadcastFrameReceiver.swift
// PicelfIOS — Receives frame files from the Broadcast Upload Extension
//
// Watches the shared App Group directory for new frame files written by
// PicelfBroadcastUpload/SampleHandler. Reads frames and feeds them to
// the StitchingCoordinator for incremental stitching.
//
// Target: iOS 16+, Swift 5.9+

import UIKit
import os

private let log = Logger(subsystem: "com.picelf.ios", category: "BroadcastFrameReceiver")

@MainActor
final class BroadcastFrameReceiver: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isReceiving = false
    @Published private(set) var receivedFrameCount = 0

    // MARK: - Private

    /// Frame callback for each loaded CGImage.
    private var onFrame: ((CGImage) -> Void)?

    /// Tracks the latest consumed frame filename so deleted files do not skew future reads.
    private var lastProcessedFrameName: String?

    /// Timer for polling the shared directory.
    private var pollTimer: Timer?

    /// Darwin notification token for new-frame signals.
    private var darwinNotifyToken: Int32 = 0

    /// Whether the broadcast extension signaled it has stopped.
    private var extensionStopped = false

    // MARK: - Public API

    /// Start receiving frames from the broadcast extension.
    ///
    /// - Parameter onFrame: Called on the main thread for each new CGImage frame.
    func startReceiving(onFrame: @escaping (CGImage) -> Void) {
        guard !isReceiving else { return }

        self.onFrame = onFrame
        self.lastProcessedFrameName = nil
        self.receivedFrameCount = 0
        self.extensionStopped = false

        // Clean any leftover frames from previous sessions
        BroadcastFrameRelay.cleanFramesDirectory()

        // Register for Darwin notification when extension writes a new frame
        registerDarwinNotification()

        // Also poll periodically as a fallback (Darwin notifications can be missed)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollForNewFrames()
            }
        }

        isReceiving = true
        log.notice("BroadcastFrameReceiver started")
    }

    /// Stop receiving frames.
    func stopReceiving() {
        guard isReceiving else { return }

        pollTimer?.invalidate()
        pollTimer = nil
        unregisterDarwinNotification()

        // Process any remaining frames
        pollForNewFrames()

        isReceiving = false
        onFrame = nil
        log.notice("BroadcastFrameReceiver stopped, total received: \(self.receivedFrameCount)")
    }

    /// Whether the broadcast extension has signaled that it stopped recording.
    var didExtensionStop: Bool {
        extensionStopped
    }

    // MARK: - Frame Polling

    private func pollForNewFrames() {
        let frameURLs = BroadcastFrameRelay.sortedFrameFileURLs()

        let newFrames = frameURLs.filter { url in
            guard let lastProcessedFrameName else { return true }
            return url.lastPathComponent > lastProcessedFrameName
        }
        guard !newFrames.isEmpty else { return }

        for url in newFrames {
            autoreleasepool {
                guard let data = try? Data(contentsOf: url),
                      let uiImage = UIImage(data: data),
                      let cgImage = uiImage.cgImage else {
                    log.warning("Failed to load frame: \(url.lastPathComponent)")
                    return
                }

                onFrame?(cgImage)
                receivedFrameCount += 1

                // Delete the frame file after reading to stay under memory limits
                try? FileManager.default.removeItem(at: url)
            }
        }

        lastProcessedFrameName = newFrames.last?.lastPathComponent
    }

    // MARK: - Darwin Notifications

    private func registerDarwinNotification() {
        // New frame notification
        let newFrameName = BroadcastFrameRelay.newFrameNotificationName as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let receiver = Unmanaged<BroadcastFrameReceiver>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    receiver.pollForNewFrames()
                }
            },
            newFrameName,
            nil,
            .deliverImmediately
        )

        // Recording stopped notification
        let stoppedName = BroadcastFrameRelay.recordingStoppedNotificationName as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let receiver = Unmanaged<BroadcastFrameReceiver>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    receiver.extensionStopped = true
                    receiver.pollForNewFrames()
                }
            },
            stoppedName,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterDarwinNotification() {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    deinit {
        pollTimer?.invalidate()
    }
}
