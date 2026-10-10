import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Decode dimensions before creating a bitmap; imports normalize EXIF orientation once.
enum RelayImage {
    static func pngDimensions(_ data: Data) throws -> (Int, Int) {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw RelayError.message(L10n.localized("回传图片必须是 PNG 格式。", "Returned images must use PNG format."))
        }
        return try dimensions(data)
    }
    static func dimensions(_ data: Data) throws -> (Int, Int) {
        guard data.count <= RelayLimits.maxResourceBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw RelayError.message(L10n.localized("请选择 PNG、JPEG 或 HEIC 静态图片。", "Choose a static PNG, JPEG, or HEIC image."))
        }
        try RelayLimits.validate(width: width, height: height)
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }
    static func normalize(_ data: Data) throws -> (Data, Int, Int) {
        let (width, height) = try dimensions(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.heif.identifier].contains(type),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw RelayError.message(L10n.localized("无法读取图片。请选择 PNG、JPEG 或 HEIC 静态图片。", "Could not read the image. Choose a static PNG, JPEG, or HEIC image."))
        }
        return (try png(image), image.width, image.height)
    }
    static func png(_ image: CGImage) throws -> Data {
        try RelayLimits.validate(width: image.width, height: image.height)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RelayError.message(L10n.localized("无法创建 PNG 图片。", "Could not create the PNG image."))
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RelayError.message(L10n.localized("PNG 编码失败。", "PNG encoding failed.")) }
        return data as Data
    }
    static func compose(base: Data, overlay: Data?, width: Int, height: Int, edge: Int? = nil) throws -> Data {
        let scale = edge.map { min(1, Double($0) / Double(max(width, height))) } ?? 1
        let w = max(1, Int((Double(width) * scale).rounded()))
        let h = max(1, Int((Double(height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RelayError.message(L10n.localized("无法合成共同编辑图片。", "Could not compose the shared-edit image."))
        }
        for data in [base, overlay].compactMap({ $0 }) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = edge != nil ? thumbnail(data, edge: max(w, h)) : CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw RelayError.message(L10n.localized("图层无法解码。", "Could not decode the layer.")) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let image = context.makeImage() else { throw RelayError.message(L10n.localized("图层合成失败。", "Layer composition failed.")) }
        return try png(image)
    }
    static func thumbnail(_ data: Data, edge: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge
        ] as CFDictionary)
    }
}
