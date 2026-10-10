import Foundation

struct DuplicationRules {
    var blockHeight: Int = 16
    var fingerprintBins: Int = 40
    var minOffsetPx: Int = 320
    var maxOffsetPx: Int = 4096
    var baseCorrelationThreshold: Float = 0.95
    var contentRangeFloor: UInt8 = 12
    var contentStdDevFloor: Float = 8

    var criticalHighRunLength: Int = 24
    var criticalHighAverageCorrelation: Float = 0.992
    var criticalHighMedianMAD: Float = 8

    var criticalLowRunLength: Int = 16
    var criticalLowAverageCorrelation: Float = 0.995
    var criticalLowMedianMAD: Float = 4

    var warningRunLength: Int = 8
    var warningAverageCorrelation: Float = 0.992
    var warningMedianMAD: Float = 6.5

    // Secondary warning lane for layout-level repeats where thumbnails/text
    // may differ slightly but the stitched structure is still duplicated.
    var layoutWarningRunLength: Int = 12
    var layoutWarningAverageCorrelation: Float = 0.995
    var layoutWarningMedianMAD: Float = 20.0

    var criticalAreaRatio: Double = 0.04
}

struct SeamRules {
    var bandHeight: Int = 8
    var minOffsetPx: Int = 96
    var maxOffsetPx: Int = 640
    var criticalMaxBandMAD: Float = 2.8
    var warningMaxBandMAD: Float = 4.5
    var contentRangeFloor: UInt8 = 12
    var contentStdDevFloor: Float = 8
    var criticalMinRunHeightPx: Int = 128
    var minRunHeightPx: Int = 96
    var offsetRunMultiplier: Float = 1.0
    var maxRunHeightPx: Int = 512
}

struct RepeatedSectionRules {
    var windowHeight: Int = 224
    var windowStride: Int = 64
    var fingerprintBins: Int = 32
    var minOffsetPx: Int = 320
    var maxOffsetPx: Int = 4096
    var maxFingerprintMAD: Float = 4.2
    var criticalMaxPixelMAD: Float = 4.0
    var warningMaxPixelMAD: Float = 6.8
    var criticalMinConsecutiveWindows: Int = 4
    var minConsecutiveWindows: Int = 2
    var contentRangeFloor: UInt8 = 12
    var contentStdDevFloor: Float = 8
}

struct EdgeOverlayRules {
    var enabled: Bool = true
    var stripWidth: Int = 72
    var windowHeight: Int = 144
    var windowStride: Int = 48
    var minOffsetPx: Int = 320
    var maxOffsetPx: Int = 4096
    var minFeatureRange: UInt8 = 28
    var minFeatureStdDev: Float = 16
    var darkPixelThreshold: UInt8 = 180
    var minFeatureDarkRatio: Float = 0.04
    var maxFeatureDarkRatio: Float = 0.70
    var maxStripMAD: Float = 12.0
    var minCenterMAD: Float = 10.0
    var minCenterToStripMADRatio: Float = 1.35
    var maxMatchedWindowCoverage: Float = 0.45
    var warningMinMatches: Int = 3
    var criticalMinMatches: Int = 5
}

struct E2EValidationProfile {
    var minContrast: Int = 150
    var minOverlapRatio: Double = 0.15
    var maxEdgeCrop: Int = 80
    var requireTallerThanWide: Bool = true

    var duplicationRules: DuplicationRules = .init()
    var seamRules: SeamRules = .init()
    var repeatedSectionRules: RepeatedSectionRules = .init()
    var edgeOverlayRules: EdgeOverlayRules = .init()

    static let highRecall = E2EValidationProfile()
}
