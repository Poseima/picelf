import Foundation
import CoreGraphics

enum CaptureType: String, Codable {
    case scroll
    case snap
    case recording
    case custom
}

enum WorkbenchOutputKind: String, Codable {
    case image
    case video
}

enum WorkbenchJobStatus: String, Codable {
    case queued
    case processing
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .processing:
            return false
        }
    }
}

struct WorkbenchJob: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let sourceAppName: String
    let sourceWindowTitle: String
    let captureFrameCount: Int
    let captureRect: CGRect
    let captureType: CaptureType
    let outputKind: WorkbenchOutputKind

    var startedAt: Date?
    var endedAt: Date?
    var status: WorkbenchJobStatus
    var progress: Double
    var phase: String
    var outputSize: CGSize?
    var outputURL: URL?
    var errorDescription: String?
    var videoDurationSeconds: Double?
    var isPinned: Bool

    // MARK: - Codable (CGRect/CGSize aren't Codable by default)

    enum CodingKeys: String, CodingKey {
        case id, createdAt, sourceAppName, sourceWindowTitle, captureFrameCount
        case captureRectX, captureRectY, captureRectW, captureRectH
        case captureType, outputKind
        case startedAt, endedAt, status, progress, phase
        case outputSizeW, outputSizeH
        case outputURL, errorDescription, videoDurationSeconds
        case isPinned
    }

    init(id: UUID, createdAt: Date, sourceAppName: String, sourceWindowTitle: String,
         captureFrameCount: Int, captureRect: CGRect, captureType: CaptureType = .scroll,
         outputKind: WorkbenchOutputKind? = nil,
         startedAt: Date?, endedAt: Date?,
         status: WorkbenchJobStatus, progress: Double, phase: String, outputSize: CGSize?,
         outputURL: URL?, errorDescription: String?, videoDurationSeconds: Double? = nil,
         isPinned: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceWindowTitle = sourceWindowTitle
        self.captureFrameCount = captureFrameCount
        self.captureRect = captureRect
        self.captureType = captureType
        self.outputKind = outputKind ?? Self.inferredOutputKind(captureType: captureType, outputURL: outputURL)
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.progress = progress
        self.phase = phase
        self.outputSize = outputSize
        self.outputURL = outputURL
        self.errorDescription = errorDescription
        self.videoDurationSeconds = videoDurationSeconds
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sourceAppName = try c.decode(String.self, forKey: .sourceAppName)
        sourceWindowTitle = try c.decode(String.self, forKey: .sourceWindowTitle)
        captureFrameCount = try c.decode(Int.self, forKey: .captureFrameCount)
        let rx = try c.decode(CGFloat.self, forKey: .captureRectX)
        let ry = try c.decode(CGFloat.self, forKey: .captureRectY)
        let rw = try c.decode(CGFloat.self, forKey: .captureRectW)
        let rh = try c.decode(CGFloat.self, forKey: .captureRectH)
        captureRect = CGRect(x: rx, y: ry, width: rw, height: rh)
        captureType = try c.decodeIfPresent(CaptureType.self, forKey: .captureType) ?? .scroll
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        status = try c.decode(WorkbenchJobStatus.self, forKey: .status)
        progress = try c.decode(Double.self, forKey: .progress)
        phase = try c.decode(String.self, forKey: .phase)
        if let sw = try c.decodeIfPresent(CGFloat.self, forKey: .outputSizeW),
           let sh = try c.decodeIfPresent(CGFloat.self, forKey: .outputSizeH) {
            outputSize = CGSize(width: sw, height: sh)
        } else {
            outputSize = nil
        }
        outputURL = try c.decodeIfPresent(URL.self, forKey: .outputURL)
        outputKind = try c.decodeIfPresent(WorkbenchOutputKind.self, forKey: .outputKind)
            ?? Self.inferredOutputKind(captureType: captureType, outputURL: outputURL)
        errorDescription = try c.decodeIfPresent(String.self, forKey: .errorDescription)
        videoDurationSeconds = try c.decodeIfPresent(Double.self, forKey: .videoDurationSeconds)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(sourceAppName, forKey: .sourceAppName)
        try c.encode(sourceWindowTitle, forKey: .sourceWindowTitle)
        try c.encode(captureFrameCount, forKey: .captureFrameCount)
        try c.encode(captureRect.origin.x, forKey: .captureRectX)
        try c.encode(captureRect.origin.y, forKey: .captureRectY)
        try c.encode(captureRect.size.width, forKey: .captureRectW)
        try c.encode(captureRect.size.height, forKey: .captureRectH)
        try c.encode(captureType, forKey: .captureType)
        try c.encode(outputKind, forKey: .outputKind)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encode(status, forKey: .status)
        try c.encode(progress, forKey: .progress)
        try c.encode(phase, forKey: .phase)
        try c.encodeIfPresent(outputSize?.width, forKey: .outputSizeW)
        try c.encodeIfPresent(outputSize?.height, forKey: .outputSizeH)
        try c.encodeIfPresent(outputURL, forKey: .outputURL)
        try c.encodeIfPresent(errorDescription, forKey: .errorDescription)
        try c.encodeIfPresent(videoDurationSeconds, forKey: .videoDurationSeconds)
        try c.encode(isPinned, forKey: .isPinned)
    }

    var isImageOutput: Bool {
        outputKind == .image
    }

    var isVideoOutput: Bool {
        outputKind == .video
    }

    var isCustomImport: Bool {
        captureType == .custom
    }

    var canCopyToClipboard: Bool {
        status == .completed && isImageOutput
    }

    var canOpenResult: Bool {
        status == .completed
    }

    var canPinToDesktop: Bool {
        status == .completed && isImageOutput
    }

    var canAddToCanvas: Bool {
        status == .completed && isImageOutput
    }

    var canRetry: Bool {
        (status == .failed || status == .cancelled) && !isCustomImport && isImageOutput
    }

    var hasManagedFrameCache: Bool {
        !isCustomImport && isImageOutput
    }

    private static func inferredOutputKind(captureType: CaptureType, outputURL: URL?) -> WorkbenchOutputKind {
        if let url = outputURL {
            switch url.pathExtension.lowercased() {
            case "mov", "mp4", "m4v":
                return .video
            default:
                break
            }
        }
        return captureType == .recording ? .video : .image
    }
}
