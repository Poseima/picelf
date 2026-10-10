import CoreGraphics
import Foundation

struct E2EValidationContext {
    var acceptedFrameCount: Int?
    var windowPixelWidth: Int?
    var windowPixelHeight: Int?
    var contrastSampleRect: CGRect

    init(
        acceptedFrameCount: Int? = nil,
        windowPixelWidth: Int? = nil,
        windowPixelHeight: Int? = nil,
        contrastSampleRect: CGRect
    ) {
        self.acceptedFrameCount = acceptedFrameCount
        self.windowPixelWidth = windowPixelWidth
        self.windowPixelHeight = windowPixelHeight
        self.contrastSampleRect = contrastSampleRect
    }
}

enum E2EValidationSeverity: String {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
}

struct E2EValidationPolicy {
    var failOnWarnings: Bool

    static let criticalOnly = E2EValidationPolicy(failOnWarnings: false)
    static let strictWarnings = E2EValidationPolicy(failOnWarnings: true)

    func blocks(_ severity: E2EValidationSeverity) -> Bool {
        switch severity {
        case .critical:
            return true
        case .warning:
            return failOnWarnings
        case .info:
            return false
        }
    }
}

struct E2EValidationIssue {
    let category: String
    let severity: E2EValidationSeverity
    let message: String
    let yStart: Int?
    let yEnd: Int?
    let offsetPx: Int?
}

struct E2EValidationCheck {
    let name: String
    let passed: Bool
    let detail: String
}

struct E2EValidationStats {
    var contrast: Int?
    var overlapRatio: Double?
    var duplicateRunCount: Int
    var seamCount: Int
    var repeatedSectionCount: Int
    var edgeOverlayRepeatCount: Int
    var duplicatedAreaRatio: Double

    init(
        contrast: Int? = nil,
        overlapRatio: Double? = nil,
        duplicateRunCount: Int = 0,
        seamCount: Int = 0,
        repeatedSectionCount: Int = 0,
        edgeOverlayRepeatCount: Int = 0,
        duplicatedAreaRatio: Double = 0
    ) {
        self.contrast = contrast
        self.overlapRatio = overlapRatio
        self.duplicateRunCount = duplicateRunCount
        self.seamCount = seamCount
        self.repeatedSectionCount = repeatedSectionCount
        self.edgeOverlayRepeatCount = edgeOverlayRepeatCount
        self.duplicatedAreaRatio = duplicatedAreaRatio
    }
}

struct E2EValidationReport {
    let checks: [E2EValidationCheck]
    let issues: [E2EValidationIssue]
    let stats: E2EValidationStats
    let policy: E2EValidationPolicy

    var passed: Bool {
        checks.allSatisfy { $0.passed } && !issues.contains { policy.blocks($0.severity) }
    }
}
