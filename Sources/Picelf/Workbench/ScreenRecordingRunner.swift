import AppKit
import AVFoundation

@MainActor
final class ScreenRecordingRunner: WorkbenchStitchJobRuntime {
    private let videoURL: URL
    let videoDuration: TimeInterval
    private(set) var videoSize: CGSize?
    private static let placeholderSize = NSSize(width: 2, height: 2)

    var outputFileURL: URL? { videoURL }

    init(videoURL: URL, duration: TimeInterval) {
        self.videoURL = videoURL
        self.videoDuration = duration
    }

    func stitch(onProgress: ((StitchingProgress) -> Void)?) async throws -> NSImage {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        onProgress?(StitchingProgress(
            fraction: 0.3,
            phase: L10n.phaseFinalizingVideo,
            currentFrame: 1,
            totalFrames: 1
        ))

        let asset = AVURLAsset(url: videoURL)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try? await track.load(.naturalSize)
            let preferredTransform = try? await track.load(.preferredTransform)
            if let naturalSize {
                if let preferredTransform {
                    let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
                    videoSize = CGSize(width: abs(rect.width), height: abs(rect.height))
                } else {
                    videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
                }
            }
        }

        onProgress?(StitchingProgress(
            fraction: 1.0,
            phase: L10n.phaseDone,
            currentFrame: 1,
            totalFrames: 1
        ))
        return NSImage(size: Self.placeholderSize)
    }

    func cancel() {}

    func reset() {
        try? FileManager.default.removeItem(at: videoURL)
    }
}
