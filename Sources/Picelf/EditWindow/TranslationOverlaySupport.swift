import SwiftUI
import AppKit

struct TranslationOverlayView: View {
    let imageSize: CGSize
    let zoomScale: CGFloat
    let segments: [TranslationSegment]
    let overlayMode: TranslationOverlayMode
    let highlightedSegmentID: UUID?
    let hoverLocation: CGPoint?
    let isInteracting: Bool

    private var scaledCanvasSize: CGSize {
        CGSize(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
    }

    private var activeBubbleSegment: TranslationSegment? {
        if let highlightedSegmentID,
           let highlighted = segments.first(where: { $0.id == highlightedSegmentID }) {
            return highlighted
        }
        guard overlayMode == .hover,
              let hoverLocation else { return nil }
        let imagePoint = CGPoint(x: hoverLocation.x / max(zoomScale, 0.001), y: hoverLocation.y / max(zoomScale, 0.001))
        return segments.last(where: { $0.rect(in: imageSize).insetBy(dx: -6, dy: -6).contains(imagePoint) })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if overlayMode == .replace && !isInteracting {
                ForEach(segments) { segment in
                    replaceCard(for: segment)
                }
            }

            ForEach(segments) { segment in
                if shouldHighlight(segment) {
                    highlightFrame(for: segment)
                }
            }

            if let bubbleSegment = activeBubbleSegment, overlayMode != .off {
                hoverBubble(for: bubbleSegment)
            }
        }
        .frame(width: scaledCanvasSize.width, height: scaledCanvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func shouldHighlight(_ segment: TranslationSegment) -> Bool {
        if highlightedSegmentID == segment.id { return true }
        if overlayMode == .hover, let bubbleSegment = activeBubbleSegment {
            return bubbleSegment.id == segment.id
        }
        return false
    }

    private func replaceCard(for segment: TranslationSegment) -> some View {
        let rect = scaledRect(for: segment)
        let fontSize = max(11, min(22, rect.height * 0.34))

        return VStack(alignment: .leading, spacing: 4) {
            Text(segment.translatedText)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: max(70, rect.width), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(segment.id == highlightedSegmentID ? EditorTheme.selectedStroke : EditorTheme.panelBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
        .offset(x: rect.minX, y: rect.minY)
    }

    private func highlightFrame(for segment: TranslationSegment) -> some View {
        let rect = scaledRect(for: segment)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(EditorTheme.selectionStroke.opacity(0.95), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(EditorTheme.subtleAccentFill)
            )
            .frame(width: max(20, rect.width), height: max(20, rect.height))
            .offset(x: rect.minX, y: rect.minY)
    }

    private func hoverBubble(for segment: TranslationSegment) -> some View {
        let rect = scaledRect(for: segment)
        let width = min(max(220, rect.width + 40), 360)
        let preferredX = min(max(8, rect.minX), max(8, scaledCanvasSize.width - width - 8))
        let estimatedHeight: CGFloat = 120
        let preferredY: CGFloat
        if rect.minY >= estimatedHeight + 14 {
            preferredY = rect.minY - estimatedHeight - 10
        } else {
            preferredY = min(rect.maxY + 10, max(8, scaledCanvasSize.height - estimatedHeight - 8))
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.translate)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(segment.translatedText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if !segment.sourceText.isEmpty {
                Text(segment.sourceText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 5)
        .offset(x: preferredX, y: preferredY)
    }

    private func scaledRect(for segment: TranslationSegment) -> CGRect {
        let rect = segment.rect(in: imageSize)
        return CGRect(
            x: rect.origin.x * zoomScale,
            y: rect.origin.y * zoomScale,
            width: rect.width * zoomScale,
            height: rect.height * zoomScale
        )
    }
}

enum TranslationOverlayRenderer {
    static func renderTranslatedCopy(
        baseImage: NSImage,
        imageSize: CGSize,
        segments: [TranslationSegment]
    ) -> NSImage? {
        let size = NSSize(width: imageSize.width, height: imageSize.height)
        guard size.width > 0, size.height > 0 else { return nil }

        let rendered = NSImage(size: size)
        rendered.lockFocus()
        defer { rendered.unlockFocus() }

        baseImage.draw(in: NSRect(origin: .zero, size: size))
        guard let context = NSGraphicsContext.current?.cgContext else {
            return rendered
        }

        context.saveGState()
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)

        for segment in segments {
            draw(segment: segment, in: context, imageSize: imageSize)
        }

        context.restoreGState()
        return rendered
    }

    private static func draw(segment: TranslationSegment, in context: CGContext, imageSize: CGSize) {
        let rect = segment.rect(in: imageSize)
        let cardRect = rect.insetBy(dx: -2, dy: -2)
        let roundedPath = CGPath(
            roundedRect: cardRect,
            cornerWidth: 14,
            cornerHeight: 14,
            transform: nil
        )

        context.addPath(roundedPath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
        context.fillPath()

        context.addPath(roundedPath)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        context.setLineWidth(1)
        context.strokePath()

        let textInset = CGSize(width: 12, height: 10)
        let textRect = CGRect(
            x: cardRect.minX + textInset.width,
            y: cardRect.minY + textInset.height,
            width: max(40, cardRect.width - textInset.width * 2),
            height: max(20, cardRect.height - textInset.height * 2)
        )
        let fontSize = max(13, min(28, cardRect.height * 0.34))
        AnnotationRenderer.drawTopLeftAnchoredWrappedText(
            segment.translatedText,
            topLeftRect: textRect,
            font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            color: .white,
            in: context,
            renderSpace: .canvasTopLeft
        )
    }
}
