import Foundation

enum RecordingError: Error, LocalizedError {
    case writerCreationFailed(String)
    case finalizationFailed(String)
    case noFramesCaptured
    case cancelled
    case durationLimitReached
    case microphoneAccessDenied
    case streamStopped(Error)

    var errorDescription: String? {
        switch self {
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
