// ImageExporter.swift
// Picelf — Image Export Utilities

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers
import ImageIO

enum ImageExporter {

    /// Export format options.
    enum Format {
        case png
        case jpeg(quality: CGFloat)   // quality: 0.0 (worst) ... 1.0 (best)

        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            }
        }

        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
    }

    /// Export a CGImage to a file at the given URL.
    ///
    /// Uses ImageIO directly to avoid the expensive TIFF -> NSBitmapImageRep conversion path.
    ///
    /// - Parameters:
    ///   - image: The image to export.
    ///   - url: Destination file URL.
    ///   - format: Export format (PNG or JPEG with quality).
    /// - Throws: `StitchingError.exportFailed` on failure.
    static func export(_ image: CGImage, to url: URL, format: Format) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw StitchingError.exportFailed(
                format: format.fileExtension.uppercased(),
                reason: "Could not create image destination."
            )
        }

        var properties: [CFString: Any] = [:]
        if case .jpeg(let quality) = format {
            let clampedQuality = max(0.0, min(1.0, quality))
            properties[kCGImageDestinationLossyCompressionQuality] = clampedQuality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StitchingError.exportFailed(
                format: format.fileExtension.uppercased(),
                reason: "Image destination finalize failed."
            )
        }
    }

    #if canImport(AppKit)
    /// Export an NSImage to a file at the given URL.
    ///
    /// - Parameters:
    ///   - image: The image to export.
    ///   - url: Destination file URL.
    ///   - format: Export format (PNG or JPEG with quality).
    /// - Throws: `StitchingError.exportFailed` on failure.
    static func export(_ image: NSImage, to url: URL, format: Format) throws {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            try export(cgImage, to: url, format: format)
            return
        }

        // Fallback path for rare NSImage representations that can't provide CGImage.
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw StitchingError.exportFailed(
                format: format.fileExtension.uppercased(),
                reason: "Could not create bitmap representation."
            )
        }

        let data: Data?
        switch format {
        case .png:
            data = bitmap.representation(using: .png, properties: [:])
        case .jpeg(let quality):
            let clampedQuality = max(0.0, min(1.0, quality))
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: clampedQuality])
        }

        guard let imageData = data else {
            throw StitchingError.exportFailed(
                format: format.fileExtension.uppercased(),
                reason: "Encoding failed."
            )
        }
        try imageData.write(to: url, options: .atomic)
    }
    #endif

    #if canImport(UIKit)
    /// Export a UIImage to a file at the given URL.
    static func export(_ image: UIImage, to url: URL, format: Format) throws {
        if let cgImage = image.cgImage {
            try export(cgImage, to: url, format: format)
            return
        }
        throw StitchingError.exportFailed(
            format: format.fileExtension.uppercased(),
            reason: "Could not get CGImage from UIImage."
        )
    }
    #endif
}
