// FrameDownsampler.swift
// PicelfIOS — CGImage downscaler
//
// Scales down a CGImage maintaining aspect ratio if width exceeds maxWidth.
//
// Target: iOS 16+, Swift 5.9+

import CoreGraphics

enum FrameDownsampler {

    /// Downsample a CGImage to fit within `maxWidth`, preserving aspect ratio.
    ///
    /// Returns `nil` if the context cannot be created. Returns the original
    /// image unchanged if its width is already <= maxWidth.
    ///
    /// - Parameters:
    ///   - image: The source CGImage.
    ///   - maxWidth: Maximum width in pixels.
    /// - Returns: The downsampled CGImage, or nil on failure.
    static func downsample(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }

        let scale = CGFloat(maxWidth) / CGFloat(image.width)
        let newWidth = maxWidth
        let newHeight = Int((CGFloat(image.height) * scale).rounded())

        guard newWidth > 0, newHeight > 0 else { return nil }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage()
    }
}
