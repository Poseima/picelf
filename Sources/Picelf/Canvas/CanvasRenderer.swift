import AppKit
import CoreGraphics

struct CanvasRenderer {
    @MainActor
    static func render(document: CanvasDocument) -> NSImage? {
        let size = document.canvasSize
        guard size.width > 0, size.height > 0 else { return nil }

        let pixelsWide = Int(size.width)
        let pixelsHigh = Int(size.height)

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        guard let nsCtx = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let ctx = nsCtx.cgContext

        // 1. Draw background
        switch document.background {
        case .white:
            ctx.setFillColor(CGColor.white)
            ctx.fill(CGRect(origin: .zero, size: size))
        case .transparent:
            break
        case .solidColor(let color):
            ctx.setFillColor(NSColor(color).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        case .customImage(let bg):
            if let cgBg = bg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cgBg, in: CGRect(origin: .zero, size: size))
            }
        }

        // 2. Draw items in z-order (lowest first)
        let sorted = document.visibleItems

        for item in sorted {
            guard let image = document.resolveImage(for: item) else { continue }
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let bounds = item.bounds

            ctx.saveGState()
            ctx.setAlpha(item.opacity)

            if item.hasShadow {
                ctx.setShadow(
                    offset: CGSize(width: 2, height: -2),
                    blur: 4,
                    color: NSColor.black.withAlphaComponent(0.3).cgColor
                )
            }

            // Transform: translate to center, rotate, flip, translate back
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            // CGContext is y-up, so flip the whole coordinate space first
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)

            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: -item.rotation) // negate because we flipped y
            if item.flipH { ctx.scaleBy(x: -1, y: 1) }
            if item.flipV { ctx.scaleBy(x: 1, y: -1) }
            ctx.translateBy(x: -center.x, y: -center.y)

            // Corner radius clipping
            if item.cornerRadius > 0 {
                let path = CGPath(
                    roundedRect: bounds,
                    cornerWidth: item.cornerRadius,
                    cornerHeight: item.cornerRadius,
                    transform: nil
                )
                ctx.addPath(path)
                ctx.clip()
            }

            // Border
            if item.borderWidth > 0 {
                ctx.setStrokeColor(NSColor(item.borderColor).cgColor)
                ctx.setLineWidth(item.borderWidth)
                ctx.stroke(bounds)
            }

            ctx.draw(cgImage, in: bounds)
            ctx.restoreGState()
        }

        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: size)
        result.addRepresentation(bitmapRep)
        
        // Apply watermark
        let watermarkConfig = AppPreferences.shared.watermarkConfig
        return WatermarkRenderer.apply(to: result, config: watermarkConfig)
    }
}
