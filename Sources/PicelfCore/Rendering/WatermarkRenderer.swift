#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreGraphics
import SwiftUI

struct WatermarkRenderer {
    #if canImport(AppKit)
    /// Apply watermark to an NSImage
    @MainActor
    static func apply(to image: NSImage, config: WatermarkConfig) -> NSImage {
        guard config.isEnabled, !config.text.isEmpty else { return image }

        let result = NSImage(size: image.size)
        result.lockFocus()
        defer { result.unlockFocus() }

        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: image.size))

        // Draw watermark
        guard let ctx = NSGraphicsContext.current?.cgContext else { return result }
        draw(config: config, in: ctx, canvasSize: image.size)

        return result
    }
    #elseif canImport(UIKit)
    /// Apply watermark to a UIImage
    @MainActor
    static func apply(to image: UIImage, config: WatermarkConfig) -> UIImage {
        guard config.isEnabled, !config.text.isEmpty else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            draw(config: config, in: ctx.cgContext, canvasSize: image.size)
        }
    }
    #endif

    /// Draw watermark directly into a CGContext
    static func draw(
        config: WatermarkConfig,
        in context: CGContext,
        canvasSize: CGSize
    ) {
        guard config.isEnabled, !config.text.isEmpty else { return }

        if config.tiledEnabled {
            drawTiledWatermark(config: config, in: context, canvasSize: canvasSize)
        } else {
            drawSingleWatermark(config: config, in: context, canvasSize: canvasSize)
        }
    }

    private static func makeFont(name: String, size: CGFloat) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
        #elseif canImport(UIKit)
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        #endif
    }

    private static func makeTextColor(_ config: WatermarkConfig) -> PlatformColor {
        #if canImport(AppKit)
        return NSColor(config.color.color).withAlphaComponent(config.opacity)
        #elseif canImport(UIKit)
        return UIColor(config.color.color).withAlphaComponent(config.opacity)
        #endif
    }

    private static func shadowColor() -> CGColor {
        #if canImport(AppKit)
        return NSColor.black.withAlphaComponent(0.5).cgColor
        #elseif canImport(UIKit)
        return UIColor.black.withAlphaComponent(0.5).cgColor
        #endif
    }

    private static func drawAttributedString(_ attrString: NSAttributedString, at point: CGPoint, in context: CGContext) {
        #if canImport(AppKit)
        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsCtx
        attrString.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
        #elseif canImport(UIKit)
        UIGraphicsPushContext(context)
        attrString.draw(at: point)
        UIGraphicsPopContext()
        #endif
    }

    private static func drawSingleWatermark(
        config: WatermarkConfig,
        in context: CGContext,
        canvasSize: CGSize
    ) {
        let padding: CGFloat = 16
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let position = config.position.anchorPoint(in: canvasRect, padding: padding)

        let font = makeFont(name: config.fontName, size: config.fontSize)
        let textColor = makeTextColor(config)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attrString = NSAttributedString(string: config.text, attributes: attributes)
        let textSize = attrString.size()

        let drawPoint: CGPoint
        switch config.position.textAlignment {
        case .left:
            drawPoint = position
        case .center:
            drawPoint = CGPoint(x: position.x - textSize.width / 2, y: position.y - textSize.height / 2)
        case .right, .justified, .natural:
            drawPoint = CGPoint(x: position.x - textSize.width, y: position.y - textSize.height / 2)
        @unknown default:
            drawPoint = position
        }

        context.saveGState()
        defer { context.restoreGState() }

        if config.hasShadow {
            context.setShadow(
                offset: CGSize(width: 1, height: -1),
                blur: config.shadowRadius,
                color: shadowColor()
            )
        }

        if config.rotation != 0 {
            let rotationCenter: CGPoint
            switch config.position.textAlignment {
            case .left:
                rotationCenter = drawPoint
            case .center:
                rotationCenter = CGPoint(x: drawPoint.x + textSize.width / 2, y: drawPoint.y + textSize.height / 2)
            case .right, .justified, .natural:
                rotationCenter = CGPoint(x: drawPoint.x + textSize.width, y: drawPoint.y + textSize.height / 2)
            @unknown default:
                rotationCenter = drawPoint
            }

            context.translateBy(x: rotationCenter.x, y: rotationCenter.y)
            context.rotate(by: config.rotation * .pi / 180)
            context.translateBy(x: -rotationCenter.x, y: -rotationCenter.y)
        }

        drawAttributedString(attrString, at: drawPoint, in: context)
    }

    private static func drawTiledWatermark(
        config: WatermarkConfig,
        in context: CGContext,
        canvasSize: CGSize
    ) {
        let angle = config.tiledAngle * .pi / 180
        let spacingX = config.tiledSpacingX
        let spacingY = config.tiledSpacingY

        let font = makeFont(name: config.fontName, size: config.fontSize)
        let textColor = makeTextColor(config)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attrString = NSAttributedString(string: config.text, attributes: attributes)

        let diagonal = sqrt(canvasSize.width * canvasSize.width + canvasSize.height * canvasSize.height)
        let coverSize = diagonal * 1.5

        let cols = Int(coverSize / spacingX) + 2
        let rows = Int(coverSize / spacingY) + 2

        context.saveGState()
        defer { context.restoreGState() }

        if config.hasShadow {
            context.setShadow(
                offset: CGSize(width: 1, height: -1),
                blur: config.shadowRadius,
                color: shadowColor()
            )
        }

        for row in -rows...rows {
            for col in -cols...cols {
                let baseX = canvasSize.width / 2 + CGFloat(col) * spacingX
                let baseY = canvasSize.height / 2 + CGFloat(row) * spacingY

                let cosA = cos(angle)
                let sinA = sin(angle)
                let rotatedX = (baseX - canvasSize.width / 2) * cosA - (baseY - canvasSize.height / 2) * sinA + canvasSize.width / 2
                let rotatedY = (baseX - canvasSize.width / 2) * sinA + (baseY - canvasSize.height / 2) * cosA + canvasSize.height / 2

                if rotatedX > -50 && rotatedX < canvasSize.width + 50 &&
                   rotatedY > -50 && rotatedY < canvasSize.height + 50 {
                    let pos = CGPoint(x: rotatedX, y: rotatedY)

                    context.saveGState()
                    if config.rotation != 0 {
                        context.translateBy(x: pos.x, y: pos.y)
                        context.rotate(by: config.rotation * .pi / 180)
                        context.translateBy(x: -pos.x, y: -pos.y)
                    }

                    let textSize = attrString.size()
                    let drawPoint = CGPoint(x: pos.x - textSize.width / 2, y: pos.y - textSize.height / 2)

                    drawAttributedString(attrString, at: drawPoint, in: context)

                    context.restoreGState()
                }
            }
        }
    }
}

#if canImport(AppKit)
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#elseif canImport(UIKit)
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#endif
