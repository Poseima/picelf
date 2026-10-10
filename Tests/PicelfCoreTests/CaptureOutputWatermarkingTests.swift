import XCTest
import AppKit
@testable import Picelf

@MainActor
final class CaptureOutputWatermarkingTests: XCTestCase {
    func test_render_returnsOriginalPixels_whenWatermarkDisabled() {
        let prefs = AppPreferences.shared
        let original = prefs.watermarkConfig
        defer { prefs.watermarkConfig = original }

        var config = WatermarkConfig()
        config.isEnabled = false
        config.text = "Picelf"
        prefs.watermarkConfig = config

        let image = makeStripedImage(width: 180, height: 120)
        let output = CaptureOutputWatermarking.render(image)

        XCTAssertEqual(pixelData(of: output), pixelData(of: image))
    }

    func test_render_appliesWatermark_whenEnabledWithText() {
        let prefs = AppPreferences.shared
        let original = prefs.watermarkConfig
        defer { prefs.watermarkConfig = original }

        var config = WatermarkConfig()
        config.isEnabled = true
        config.text = "Picelf"
        config.tiledEnabled = false
        config.position = .middleCenter
        config.opacity = 1
        config.fontSize = 24
        prefs.watermarkConfig = config

        let image = makeStripedImage(width: 220, height: 140)
        let output = CaptureOutputWatermarking.render(image)

        XCTAssertNotEqual(pixelData(of: output), pixelData(of: image))
    }

    private func pixelData(of image: NSImage) -> Data {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let provider = cg.dataProvider,
              let cfData = provider.data else {
            XCTFail("Missing image data")
            return Data()
        }
        return cfData as Data
    }
}
