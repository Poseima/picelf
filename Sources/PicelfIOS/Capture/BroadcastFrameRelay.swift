// BroadcastFrameRelay.swift
// PicelfIOS — Shared constants for Broadcast Extension <-> Main App communication
//
// Both the PicelfBroadcastUpload extension and the main PicelfIOS app use these
// constants to coordinate frame transfer via the shared App Group container.
//
// Target: iOS 16+, Swift 5.9+

import Foundation
import CoreGraphics

/// Shared constants for broadcast extension frame relay.
enum BroadcastFrameRelay {

    /// App Group identifier shared between the main app and the broadcast extension.
    static let appGroupID = "group.com.picelf.open.shared"

    /// Directory name within the App Group container where captured frames are written.
    static let framesDirectoryName = "broadcast-frames"

    /// Darwin notification name posted by the broadcast extension when a new frame is written.
    static let newFrameNotificationName = "com.picelf.broadcast.newFrame"

    /// Darwin notification name posted by the broadcast extension when recording stops.
    static let recordingStoppedNotificationName = "com.picelf.broadcast.stopped"

    /// File prefix for frame files (e.g., "frame_000042.jpg").
    static let frameFilePrefix = "frame_"

    /// Marker file written when the broadcast extension finishes recording.
    static let stopMarkerFileName = "recording-stopped.marker"

    /// JPEG compression quality for frame files (0.0 - 1.0).
    /// Balance between quality and disk/memory usage within the 50MB extension limit.
    static let jpegQuality: CGFloat = 0.7

    /// Optional override root used by tests so they do not depend on the real App Group container.
    static let rootOverrideEnvironmentKey = "UITEST_BROADCAST_ROOT"

    // MARK: - Helpers

    static func containerRootURL(rootURL: URL? = nil) -> URL? {
        if let rootURL {
            return rootURL
        }

        if let overridePath = ProcessInfo.processInfo.environment[rootOverrideEnvironmentKey],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }

        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
    }

    /// Returns the shared frames directory URL, creating it if necessary.
    static func framesDirectoryURL(rootURL: URL? = nil) -> URL? {
        guard let containerURL = containerRootURL(rootURL: rootURL) else { return nil }

        let framesDir = containerURL.appendingPathComponent(framesDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        return framesDir
    }

    /// Generate a frame filename with zero-padded index.
    static func frameFileName(index: Int) -> String {
        String(format: "%@%06d.jpg", frameFilePrefix, index)
    }

    /// Clean up all frame files from the shared directory.
    static func stopMarkerURL(rootURL: URL? = nil) -> URL? {
        framesDirectoryURL(rootURL: rootURL)?.appendingPathComponent(stopMarkerFileName)
    }

    static func writeStopMarker(rootURL: URL? = nil) {
        guard let markerURL = stopMarkerURL(rootURL: rootURL) else { return }
        try? Data().write(to: markerURL, options: .atomic)
    }

    static func hasStopMarker(rootURL: URL? = nil) -> Bool {
        guard let markerURL = stopMarkerURL(rootURL: rootURL) else { return false }
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Clean up all frame files and stop markers from the shared directory.
    static func cleanFramesDirectory(rootURL: URL? = nil) {
        guard let dir = framesDirectoryURL(rootURL: rootURL) else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Returns sorted frame file URLs from the shared directory.
    static func sortedFrameFileURLs(rootURL: URL? = nil) -> [URL] {
        guard let dir = framesDirectoryURL(rootURL: rootURL) else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix(frameFilePrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
