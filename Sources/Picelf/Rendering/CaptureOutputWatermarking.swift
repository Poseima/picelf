import AppKit

enum CaptureOutputWatermarking {
    @MainActor
    static func render(_ image: NSImage) -> NSImage {
        WatermarkRenderer.apply(to: image, config: AppPreferences.shared.watermarkConfig)
    }
}
