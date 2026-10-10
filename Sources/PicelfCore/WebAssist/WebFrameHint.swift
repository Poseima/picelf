import Foundation

/// Lightweight DOM telemetry sampled during web capture.
///
/// Values are captured in CSS pixels so they can be compared directly
/// across frames independent of Retina scale.
struct WebFrameHint: Codable {
    let timestamp: TimeInterval
    let scrollY: Double
    let viewportHeight: Double
    let documentHeight: Double
    let devicePixelRatio: Double
    let url: String

    init(
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        scrollY: Double,
        viewportHeight: Double,
        documentHeight: Double,
        devicePixelRatio: Double,
        url: String
    ) {
        self.timestamp = timestamp
        self.scrollY = scrollY
        self.viewportHeight = viewportHeight
        self.documentHeight = documentHeight
        self.devicePixelRatio = devicePixelRatio
        self.url = url
    }

    var isUsableForHeightEstimation: Bool {
        scrollY.isFinite
            && viewportHeight.isFinite
            && viewportHeight > 8
            && documentHeight.isFinite
            && documentHeight >= viewportHeight
            && devicePixelRatio.isFinite
            && devicePixelRatio > 0
    }
}
