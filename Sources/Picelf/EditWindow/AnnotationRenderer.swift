import SwiftUI
import AppKit
import CoreImage

struct EditorCompositor {
    static func compose(
        baseImage: NSImage,
        imageSize: CGSize,
        annotations: [EditorAnnotation],
        draft: EditorAnnotation?,
        pixelScale: CGFloat? = nil
    ) -> NSImage? {
        let size = NSSize(width: imageSize.width, height: imageSize.height)
        guard size.width > 0, size.height > 0 else { return nil }

        let screenScale = pixelScale ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelW = Int(size.width * screenScale)
        let pixelH = Int(size.height * screenScale)

        guard let baseCG = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(
                  data: nil, width: pixelW, height: pixelH,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        // Scale context so annotations draw in point coordinates
        ctx.scaleBy(x: screenScale, y: screenScale)
        for annotation in annotations {
            AnnotationRenderer.draw(
                annotation: annotation,
                in: ctx,
                baseImage: baseCG,
                canvasSize: size
            )
        }
        if let draft {
            AnnotationRenderer.draw(
                annotation: draft,
                in: ctx,
                baseImage: baseCG,
                canvasSize: size
            )
        }

        guard let composedCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: composedCG, size: size)
    }
}

struct AnnotationRenderer {
    enum TextRenderSpace {
        case canvasTopLeft
        case exportBottomLeft(canvasHeight: CGFloat)
    }

    struct ResolvedMosaicParameters: Equatable {
        let documentRectTopLeft: CGRect
        let sourceCropRect: CGRect
        let effectiveBlockScale: CGFloat
    }

    private static let textLayoutOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    private static let mosaicContext = CIContext(options: [.workingColorSpace: NSNull()])

    static func draw(
        annotation: EditorAnnotation,
        in context: CGContext,
        baseImage: CGImage?,
        canvasSize: CGSize
    ) {
        guard !annotation.isHidden else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(NSColor(annotation.color).cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let rect = annotation.bounds
        let drawRect = topLeftRectToContext(rect, canvasHeight: canvasSize.height)

        switch annotation.kind {
        case .rectangle:
            context.setFillColor(NSColor(annotation.fillColor).withAlphaComponent(0.18).cgColor)
            context.fill(drawRect)
            context.stroke(drawRect)
        case .ellipse:
            context.setFillColor(NSColor(annotation.fillColor).withAlphaComponent(0.18).cgColor)
            context.fillEllipse(in: drawRect)
            context.strokeEllipse(in: drawRect)
        case .line:
            let start = topLeftPointToContext(annotation.start, canvasHeight: canvasSize.height)
            let end = topLeftPointToContext(annotation.end, canvasHeight: canvasSize.height)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        case .arrow:
            let start = topLeftPointToContext(annotation.start, canvasHeight: canvasSize.height)
            let end = topLeftPointToContext(annotation.end, canvasHeight: canvasSize.height)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            drawArrowHead(in: context, from: start, to: end, size: max(8, annotation.lineWidth * 3), color: NSColor(annotation.color).cgColor)
        case .freehand:
            guard let first = annotation.points.first else { return }
            context.move(to: topLeftPointToContext(first, canvasHeight: canvasSize.height))
            for point in annotation.points.dropFirst() {
                context.addLine(to: topLeftPointToContext(point, canvasHeight: canvasSize.height))
            }
            context.strokePath()
        case .mosaic:
            guard let baseImage,
                  let parameters = resolveMosaicParameters(
                      documentRectTopLeft: rect,
                      canvasSize: canvasSize,
                      sourcePixelSize: CGSize(width: baseImage.width, height: baseImage.height),
                      block: annotation.mosaicBlockSize
                  ),
                  let mosaicImage = makeMosaicImage(from: baseImage, parameters: parameters) else {
                context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
                context.fill(drawRect)
                return
            }
            context.draw(
                mosaicImage,
                in: topLeftRectToContext(
                    parameters.documentRectTopLeft,
                    canvasHeight: canvasSize.height
                )
            )
        case .highlight:
            context.setFillColor(NSColor(annotation.color).withAlphaComponent(0.28).cgColor)
            context.fill(drawRect)
        case .text:
            var textRect = annotation.bounds
            let maxWidth = canvasSize.width - annotation.start.x
            if textRect.width > maxWidth {
                textRect.size.width = maxWidth
            }
            drawTopLeftAnchoredWrappedText(
                annotation.text ?? "",
                topLeftRect: textRect,
                font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
                color: NSColor(annotation.color),
                in: context,
                renderSpace: .exportBottomLeft(canvasHeight: canvasSize.height)
            )
        case .step:
            let radius: CGFloat = 14
            let center = topLeftPointToContext(annotation.start, canvasHeight: canvasSize.height)
            let circle = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.setFillColor(NSColor(annotation.color).cgColor)
            context.fillEllipse(in: circle)
            let text = annotation.text ?? "1"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.white
            ]
            drawCenteredText(
                text,
                center: center,
                attributes: attributes,
                in: context
            )
        case .sticker:
            if let stickerID = annotation.stickerImageID,
               let stickerCG = StickerLibrary.cgImageSyncShared(for: stickerID) {
                context.saveGState()
                context.setAlpha(annotation.opacity)
                if annotation.hasShadow {
                    context.setShadow(offset: CGSize(width: 2, height: -2), blur: 4,
                                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
                }
                let center = CGPoint(x: drawRect.midX, y: drawRect.midY)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: -annotation.rotation)
                if annotation.flipH { context.scaleBy(x: -1, y: 1) }
                if annotation.flipV { context.scaleBy(x: 1, y: -1) }
                context.translateBy(x: -center.x, y: -center.y)
                context.draw(stickerCG, in: drawRect)
                context.restoreGState()
            } else if annotation.stickerImageID != nil {
                // Broken reference — draw placeholder
                context.setFillColor(NSColor.gray.withAlphaComponent(0.2).cgColor)
                context.fill(drawRect)
            } else {
                let text = annotation.text ?? "★"
                drawTopLeftAnchoredText(
                    text,
                    topLeftPoint: annotation.start,
                    font: NSFont.systemFont(ofSize: annotation.fontSize),
                    color: NSColor(annotation.color),
                    in: context,
                    canvasHeight: canvasSize.height
                )
            }
        }
    }

    static func resolveMosaicParameters(
        documentRectTopLeft rect: CGRect,
        canvasSize: CGSize,
        sourcePixelSize: CGSize,
        block: CGFloat
    ) -> ResolvedMosaicParameters? {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              sourcePixelSize.width > 0,
              sourcePixelSize.height > 0 else {
            return nil
        }

        let visibleDocumentRect = rect.standardized.intersection(
            CGRect(origin: .zero, size: canvasSize)
        )
        guard !visibleDocumentRect.isNull,
              !visibleDocumentRect.isEmpty,
              visibleDocumentRect.width > 0,
              visibleDocumentRect.height > 0 else {
            return nil
        }

        let scaleX = sourcePixelSize.width / canvasSize.width
        let scaleY = sourcePixelSize.height / canvasSize.height
        let sourceBounds = CGRect(origin: .zero, size: sourcePixelSize)
        let mappedSourceRect = CGRect(
            x: visibleDocumentRect.origin.x * scaleX,
            y: visibleDocumentRect.origin.y * scaleY,
            width: visibleDocumentRect.width * scaleX,
            height: visibleDocumentRect.height * scaleY
        ).integral.intersection(sourceBounds)

        guard !mappedSourceRect.isNull,
              !mappedSourceRect.isEmpty,
              mappedSourceRect.width >= 1,
              mappedSourceRect.height >= 1 else {
            return nil
        }

        let sourceScale = max(scaleX, scaleY)
        return ResolvedMosaicParameters(
            documentRectTopLeft: visibleDocumentRect,
            sourceCropRect: mappedSourceRect,
            effectiveBlockScale: max(1, max(6, block) * sourceScale)
        )
    }

    static func makeMosaicImage(
        from sourceImage: CGImage,
        parameters: ResolvedMosaicParameters
    ) -> CGImage? {
        guard let cropped = sourceImage.cropping(to: parameters.sourceCropRect) else {
            return nil
        }

        let ciInput = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else {
            return cropped
        }

        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(parameters.effectiveBlockScale, forKey: kCIInputScaleKey)
        filter.setValue(
            CIVector(x: ciInput.extent.midX, y: ciInput.extent.midY),
            forKey: kCIInputCenterKey
        )

        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else {
            return cropped
        }

        return mosaicContext.createCGImage(output, from: output.extent) ?? cropped
    }

    static func measureWrappedText(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGSize {
        let width = max(1, maxWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let normalized = text.isEmpty ? "Text" : text
        let rect = NSAttributedString(string: normalized, attributes: attributes)
            .boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: textLayoutOptions
            )
        return CGSize(width: ceil(width), height: max(ceil(rect.height), ceil(font.ascender - font.descender)))
    }

    static func drawTopLeftAnchoredWrappedText(
        _ text: String,
        topLeftRect: CGRect,
        font: NSFont,
        color: NSColor,
        in context: CGContext,
        renderSpace: TextRenderSpace
    ) {
        let drawRect = resolvedWrappedTextDrawRect(
            fromTopLeftRect: topLeftRect,
            renderSpace: renderSpace
        )
        drawWrappedText(
            text.isEmpty ? "Text" : text,
            in: drawRect,
            font: font,
            color: color,
            context: context,
            flipped: wrappedTextContextIsFlipped(for: renderSpace)
        )
    }

    static func resolvedWrappedTextDrawRect(
        fromTopLeftRect rect: CGRect,
        renderSpace: TextRenderSpace
    ) -> CGRect {
        switch renderSpace {
        case .canvasTopLeft:
            return rect
        case .exportBottomLeft(let canvasHeight):
            return topLeftRectToContext(rect, canvasHeight: canvasHeight)
        }
    }

    static func wrappedTextContextIsFlipped(for renderSpace: TextRenderSpace) -> Bool {
        switch renderSpace {
        case .canvasTopLeft:
            return true
        case .exportBottomLeft:
            return false
        }
    }

    private static func topLeftPointToContext(_ point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }

    private static func topLeftRectToContext(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: canvasHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func drawArrowHead(in context: CGContext, from start: CGPoint, to end: CGPoint, size: CGFloat, color: CGColor) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let left = CGPoint(
            x: end.x - size * cos(angle - .pi / 6),
            y: end.y - size * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - size * cos(angle + .pi / 6),
            y: end.y - size * sin(angle + .pi / 6)
        )
        context.move(to: end)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.setFillColor(color)
        context.fillPath()
    }

    private static func drawTopLeftAnchoredText(
        _ text: String,
        topLeftPoint: CGPoint,
        font: NSFont,
        color: NSColor,
        in context: CGContext,
        canvasHeight: CGFloat
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let drawPoint = CGPoint(
            x: topLeftPoint.x,
            y: canvasHeight - topLeftPoint.y - textSize.height
        )
        drawSingleLineText(text, at: drawPoint, attributes: attributes, in: context)
    }

    private static func drawCenteredText(
        _ text: String,
        center: CGPoint,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) {
        let textSize = (text as NSString).size(withAttributes: attributes)
        let drawPoint = CGPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2
        )
        drawSingleLineText(text, at: drawPoint, attributes: attributes, in: context)
    }

    private static func drawSingleLineText(
        _ text: String,
        at point: CGPoint,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.current = previous
    }

    private static func drawWrappedText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        context: CGContext,
        flipped: Bool
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        // First pass: white stroke outline for visibility on any background
        let outlineAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.white,
            .strokeWidth: 4.0,
            .paragraphStyle: paragraph
        ]

        // Second pass: normal fill
        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: flipped)
        NSAttributedString(string: text, attributes: outlineAttributes)
            .draw(with: rect, options: textLayoutOptions, context: nil)
        NSAttributedString(string: text, attributes: fillAttributes)
            .draw(with: rect, options: textLayoutOptions, context: nil)
        NSGraphicsContext.current = previous
    }
}
