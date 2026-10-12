import Foundation

enum RecordingError: Error, LocalizedError {
    case writerCreationFailed(String)
    case finalizationFailed(String)
    case noFramesCaptured
    case cancelled
    case durationLimitReached
    case microphoneAccessDenied
    case streamStopped(Error)
    case displayConfigurationChanged
    case invalidCaptureRegion
    case unsupportedVideoSize

    var errorDescription: String? {
        switch self {
        case .displayConfigurationChanged:
            return L10n.recordingDisplayChangedStart
        case .invalidCaptureRegion:
            return L10n.recordingInvalidRegion
        case .unsupportedVideoSize:
            return L10n.recordingUnsupportedSize
        case .writerCreationFailed(let reason):
            return "Failed to create video writer: \(reason)"
        case .finalizationFailed(let reason):
            return "Failed to finalize recording: \(reason)"
        case .noFramesCaptured:
            return "No video frames were captured."
        case .cancelled:
            return "Recording was cancelled."
        case .durationLimitReached:
            return "Duration limit reached."
        case .microphoneAccessDenied:
            return "Microphone access was denied."
        case .streamStopped(let error):
            return "Recording stream stopped unexpectedly: \(error.localizedDescription)"
        }
    }
}
