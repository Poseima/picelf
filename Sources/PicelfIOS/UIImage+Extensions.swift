// UIImage+Extensions.swift
// PicelfIOS — UIImage convenience extensions
//
// Target: iOS 16+, Swift 5.9+

import UIKit

extension UIImage {

    /// Copy this image to the system clipboard as PNG data.
    func copyToClipboard() {
        guard let pngData = self.pngData() else { return }
        UIPasteboard.general.setData(pngData, forPasteboardType: "public.png")
    }

    /// Create a new image by cropping rows from the top and/or bottom.
    ///
    /// Uses CGImage coordinate system where y=0 is at the visual top.
    ///
    /// - Parameters:
    ///   - top: Number of points to trim from the top.
    ///   - bottom: Number of points to trim from the bottom.
    /// - Returns: The trimmed image, or self if cropping produces an invalid rect.
    func trimmed(top: CGFloat = 0, bottom: CGFloat = 0) -> UIImage {
        guard let cgImage = self.cgImage else { return self }

        let scale = self.scale
        let topPixels = Int((top * scale).rounded())
        let bottomPixels = Int((bottom * scale).rounded())
        let fullHeight = cgImage.height
        let fullWidth = cgImage.width

        let cropHeight = fullHeight - topPixels - bottomPixels
        guard cropHeight > 0, topPixels >= 0, bottomPixels >= 0 else { return self }

        // CGImage.cropping uses image coordinates: y=0 at visual top
        let cropRect = CGRect(x: 0, y: topPixels, width: fullWidth, height: cropHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else { return self }

        return UIImage(cgImage: cropped, scale: scale, orientation: self.imageOrientation)
    }
}
