import AVFoundation

enum RecordingFormat: String, Codable, CaseIterable {
    case mp4, mov

    var avFileType: AVFileType { self == .mp4 ? .mp4 : .mov }
    var fileExtension: String { rawValue }
}

enum RecordingResolution: String, Codable, CaseIterable {
    case hd, fhd, original
}

struct RecordingConfiguration {
    var format: RecordingFormat = .mp4
    var resolution: RecordingResolution = .original
    var frameRate: Int = 30
    var captureSystemAudio: Bool = true
    var microphoneDeviceID: String? = nil
    var showsCursor: Bool = true
    var durationLimitSeconds: Int = 0
    var countdownSeconds: Int = 0
    var scaleFactor: Int = 2
}
