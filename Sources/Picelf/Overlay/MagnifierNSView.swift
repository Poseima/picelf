import AppKit
import CoreImage

/// High-performance magnifier view using CALayer for GPU-accelerated rendering.
/// Static elements (grid, crosshair) are rendered once; only dynamic elements (image, color) update.
final class MagnifierNSView: NSView {
    private let loupeSize: CGFloat = 140
    private let gridCount: Int = 21
    private let colorBarHeight: CGFloat = 30
    
    // Layer hierarchy
    private let containerLayer = CALayer()
    private let imageLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let crosshairLayer = CAShapeLayer()
    private let centerBorderLayer = CAShapeLayer()
    private let colorBarLayer = CALayer()
    private let colorSwatchLayer = CALayer()
    private let hexLabel: NSTextField
    
    override init(frame: NSRect) {
        hexLabel = NSTextField(labelWithString: "#------")
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        hexLabel = NSTextField(labelWithString: "#------")
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer = containerLayer
        
        let totalHeight = loupeSize + colorBarHeight
        containerLayer.frame = NSRect(x: 0, y: 0, width: loupeSize, height: totalHeight)
        containerLayer.masksToBounds = true
        
        // Rounded corners and shadow on container
        let cornerRadius: CGFloat = 10
        let maskPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: loupeSize, height: totalHeight),
            cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
        )
        let maskLayer = CAShapeLayer()
        maskLayer.path = maskPath
        containerLayer.mask = maskLayer
        
        containerLayer.shadowColor = NSColor.black.cgColor
        containerLayer.shadowOpacity = 0.5
        containerLayer.shadowRadius = 6
        containerLayer.shadowOffset = CGSize(width: 0, height: -2)
        containerLayer.shadowPath = maskPath
        
        // Border
        let borderLayer = CAShapeLayer()
        borderLayer.path = maskPath
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.3).cgColor
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        borderLayer.frame = containerLayer.bounds
        containerLayer.addSublayer(borderLayer)
        
        // Image layer (top portion)
        imageLayer.frame = NSRect(x: 0, y: colorBarHeight, width: loupeSize, height: loupeSize)
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .nearest
        imageLayer.magnificationFilter = .nearest
        containerLayer.addSublayer(imageLayer)
        
        // Grid layer (static)
        gridLayer.frame = imageLayer.frame
        gridLayer.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        gridLayer.lineWidth = 0.5
        gridLayer.fillColor = nil
        gridLayer.path = createGridPath()
        containerLayer.addSublayer(gridLayer)
        
        // Crosshair layer (static)
        crosshairLayer.frame = imageLayer.frame
        crosshairLayer.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        crosshairLayer.lineWidth = 1
        crosshairLayer.fillColor = nil
        crosshairLayer.path = createCrosshairPath()
        containerLayer.addSublayer(crosshairLayer)
        
        // Center border layer (static)
        centerBorderLayer.frame = imageLayer.frame
        centerBorderLayer.strokeColor = NSColor.white.cgColor
        centerBorderLayer.lineWidth = 1.5
        centerBorderLayer.fillColor = nil
        centerBorderLayer.path = createCenterBorderPath()
        containerLayer.addSublayer(centerBorderLayer)
        
        // Color bar background
        colorBarLayer.frame = NSRect(x: 0, y: 0, width: loupeSize, height: colorBarHeight)
        colorBarLayer.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        containerLayer.addSublayer(colorBarLayer)
        
        // Color swatch circle
        let swatchSize: CGFloat = 16
        let swatchX: CGFloat = 8
        let swatchY = (colorBarHeight - swatchSize) / 2
        colorSwatchLayer.frame = NSRect(x: swatchX, y: swatchY, width: swatchSize, height: swatchSize)
        colorSwatchLayer.cornerRadius = swatchSize / 2
        colorSwatchLayer.backgroundColor = NSColor.gray.cgColor
        colorSwatchLayer.borderWidth = 1
        colorSwatchLayer.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        containerLayer.addSublayer(colorSwatchLayer)
        
        // HEX label
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        hexLabel.textColor = .white
        hexLabel.backgroundColor = .clear
        hexLabel.isBezeled = false
        hexLabel.isEditable = false
        hexLabel.frame = NSRect(x: swatchX + swatchSize + 6, y: 0, width: loupeSize - swatchSize - 20, height: colorBarHeight)
        addSubview(hexLabel)
    }
    
    /// Update the magnifier with a new image and hex color.
    /// This is the only update method; combines image and color into a single call.
    func update(cgImage: CGImage, hexColor: String) {
        // Upscale image using CIContext (GPU accelerated)
        let upscaledImage = upscaleImage(cgImage, targetSize: loupeSize)
        
        // Update image layer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = upscaledImage
        CATransaction.commit()
        
        // Update color swatch
        if let nsColor = NSColor(hex: hexColor) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            colorSwatchLayer.backgroundColor = nsColor.cgColor
            CATransaction.commit()
        }
        
        // Update hex label
        hexLabel.stringValue = hexColor.isEmpty ? "#------" : hexColor
    }
    
    private func upscaleImage(_ cgImage: CGImage, targetSize: CGFloat) -> CGImage {
        // Use CGContext with nearest-neighbor interpolation for pixel-perfect upscaling
        // This is faster than CILanczosScaleTransform for our use case
        let width = Int(targetSize)
        let height = Int(targetSize)
        
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }
        
        ctx.interpolationQuality = .none  // Nearest-neighbor for crisp pixels
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return ctx.makeImage() ?? cgImage
    }
    
    private func createGridPath() -> CGPath {
        let path = CGMutablePath()
        let cellW = loupeSize / CGFloat(gridCount)
        let cellH = loupeSize / CGFloat(gridCount)
        
        for i in 1..<gridCount {
            // Horizontal lines
            let y = CGFloat(i) * cellH
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: loupeSize, y: y))
            
            // Vertical lines
            let x = CGFloat(i) * cellW
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: loupeSize))
        }
        return path
    }
    
    private func createCrosshairPath() -> CGPath {
        let path = CGMutablePath()
        let cellW = loupeSize / CGFloat(gridCount)
        let cellH = loupeSize / CGFloat(gridCount)
        let centerIdx = gridCount / 2
        let cx = CGFloat(centerIdx) * cellW
        let cy = CGFloat(centerIdx) * cellH
        
        // Horizontal crosshair (gap in center cell)
        let midY = cy + cellH / 2
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: cx, y: midY))
        path.move(to: CGPoint(x: cx + cellW, y: midY))
        path.addLine(to: CGPoint(x: loupeSize, y: midY))
        
        // Vertical crosshair (gap in center cell)
        let midX = cx + cellW / 2
        path.move(to: CGPoint(x: midX, y: 0))
        path.addLine(to: CGPoint(x: midX, y: cy))
        path.move(to: CGPoint(x: midX, y: cy + cellH))
        path.addLine(to: CGPoint(x: midX, y: loupeSize))
        
        return path
    }
    
    private func createCenterBorderPath() -> CGPath {
        let cellW = loupeSize / CGFloat(gridCount)
        let cellH = loupeSize / CGFloat(gridCount)
        let centerIdx = gridCount / 2
        let cx = CGFloat(centerIdx) * cellW
        let cy = CGFloat(centerIdx) * cellH
        
        return CGPath(rect: CGRect(x: cx, y: cy, width: cellW, height: cellH), transform: nil)
    }
}

// MARK: - NSColor Hex Extension

private extension NSColor {
    convenience init?(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        
        let r = CGFloat((val >> 16) & 0xFF) / 255
        let g = CGFloat((val >> 8) & 0xFF) / 255
        let b = CGFloat(val & 0xFF) / 255
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
