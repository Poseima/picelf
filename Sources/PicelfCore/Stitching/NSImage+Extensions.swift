// NSImage+Extensions.swift
// Picelf — NSImage Utility Extensions

#if canImport(AppKit)
import AppKit
import CoreGraphics

extension NSImage {
    
    // MARK: - Conversion
    
    /// Convert to CGImage for Vision framework
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    // MARK: - Dimensions
    
    /// Human-readable dimensions string
    var dimensionsDescription: String {
        "\(Int(size.width)) × \(Int(size.height))"
    }
    
    // MARK: - Trimming
    
    /// Trim pixels from top and bottom of the image
    /// - Parameters:
    ///   - top: Pixels to trim from top
    ///   - bottom: Pixels to trim from bottom
    /// - Returns: Trimmed image, or nil if parameters are invalid
    func trimmed(top: Int, bottom: Int) -> NSImage? {
        guard top > 0 || bottom > 0 else { return self }
        
        let newHeight = size.height - CGFloat(top) - CGFloat(bottom)
        guard newHeight > 0 else { return nil }
        
        let newSize = NSSize(width: size.width, height: newHeight)
        let trimmedImage = NSImage(size: newSize)
        
        trimmedImage.lockFocus()
        
        // In NSImage's flipped coordinate system, drawing from the source
        // Source rect: skip top pixels, take newHeight
        let sourceRect = NSRect(
            x: 0,
            y: CGFloat(bottom),  // Skip bottom pixels in source (flipped coords)
            width: size.width,
            height: newHeight
        )
        let destRect = NSRect(origin: .zero, size: newSize)
        
        draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        
        trimmedImage.unlockFocus()
        
        return trimmedImage
    }
    
    // MARK: - Clipboard
    
    /// Copy the image to the system clipboard as PNG (much smaller than TIFF).
    func copyToClipboard() throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let cgImg = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw StitchingError.exportFailed(format: "clipboard", reason: "Could not get CGImage.")
        }
        let rep = NSBitmapImageRep(cgImage: cgImg)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw StitchingError.exportFailed(format: "clipboard", reason: "PNG conversion failed.")
        }
        pasteboard.setData(pngData, forType: .png)
    }
}
#endif
