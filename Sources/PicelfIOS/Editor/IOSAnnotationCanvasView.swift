// IOSAnnotationCanvasView.swift
// PicelfIOS — SwiftUI Canvas + gesture-based annotation drawing
//
// Target: iOS 16+, Swift 5.9+

import SwiftUI
import CoreImage

struct IOSAnnotationCanvasView: View {
    @ObservedObject var document: IOSEditorDocument

    @State private var interactionMode: InteractionMode = .none
    @State private var lastPoint: CGPoint?
    @State private var drawingStartPoint: CGPoint?
    @State private var hasActiveDrawingDraft = false

    private let drawingStartThreshold: CGFloat = 4

    private enum InteractionMode {
        case none
        case drawing
        case moving
        case resizing(IOSResizeCorner)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base image
            Image(uiImage: document.baseImage)
                .resizable()
                .frame(width: document.imageWidth, height: document.imageHeight)

            // Annotation canvas
            Canvas { context, _ in
                for annotation in document.visibleAnnotations {
                    draw(annotation: annotation, in: context)
                }
                if let draft = document.draftAnnotation {
                    draw(annotation: draft, in: context)
                }
            }
            .frame(width: document.imageWidth, height: document.imageHeight)

            // Selection overlay
            IOSSelectionOverlayView(
                selectionRect: selectionRect,
                showsResizeHandle: document.selectedAnnotationIDs.count == 1
                    && document.primarySelectedAnnotation?.kind != .text,
                endpointHandles: endpointHandlesForSelection
            )

            // Inline text editor
            if let editing = editingTextAnnotation {
                IOSTextInlineEditorView(
                    text: Binding(
                        get: { editing.text ?? "" },
                        set: { document.updateText(for: editing.id, text: $0) }
                    ),
                    textColor: editing.color,
                    fontSize: editing.fontSize,
                    onCommit: { text in
                        document.commitTextEditing(text)
                    }
                )
                .frame(
                    width: max(100, min(editing.textBoxWidth, document.imageWidth - editing.start.x)),
                    height: max(40, editing.bounds.height + 16)
                )
                .offset(x: editing.start.x, y: editing.start.y)
                .zIndex(10)
            }
        }
        .frame(width: document.imageWidth, height: document.imageHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .simultaneousGesture(doubleTapGesture)
    }

    // MARK: - Computed Properties

    private var editingTextAnnotation: IOSAnnotation? {
        guard let id = document.editingTextID else { return nil }
        return document.annotations.first { $0.id == id && $0.kind == .text }
    }

    private var selectionRect: CGRect? {
        document.selectionBounds()
    }

    private var endpointHandlesForSelection: (CGPoint, CGPoint)? {
        guard document.selectedAnnotationIDs.count == 1,
              let annotation = document.primarySelectedAnnotation,
              annotation.kind == .arrow else { return nil }
        return (annotation.start, annotation.end)
    }

    // MARK: - Gestures

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = value.location
                if tapIsInsideActiveTextEditor(point) {
                    return
                }
                let committedTextEditing = document.commitActiveTextEditing()
                if committedTextEditing {
                    if let hit = document.hitTest(at: point) {
                        document.selectedAnnotationIDs = [hit]
                    }
                    return
                }
                if let hit = document.hitTest(at: point) {
                    document.selectedAnnotationIDs = [hit]
                    return
                }
                if let tool = document.selectedTool,
                   document.isPointTool(tool),
                   document.selectedAnnotationIDs.isEmpty {
                    document.beginAnnotation(at: point)
                } else {
                    document.clearSelection()
                }
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let point = value.location
                if let hit = document.hitTest(at: point),
                   let annotation = document.annotations.first(where: { $0.id == hit }),
                   annotation.kind == .text {
                    document.beginTextEditing(hit)
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = value.location
                handleDragChanged(point)
            }
            .onEnded { value in
                let point = value.location
                let endedMode = interactionMode
                defer {
                    interactionMode = .none
                    lastPoint = nil
                    drawingStartPoint = nil
                    hasActiveDrawingDraft = false
                }

                switch endedMode {
                case .resizing(let corner):
                    document.resizePrimarySelection(to: point, corner: corner)
                    document.finalizeInteractionChange()
                case .moving:
                    if let lastPoint {
                        let delta = CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y)
                        if delta != .zero {
                            document.moveSelection(by: delta)
                        }
                    }
                    document.finalizeInteractionChange()
                case .drawing:
                    finalizeDrawing(endPoint: point)
                case .none:
                    document.cancelInteractionChange()
                }
            }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ point: CGPoint) {
        switch interactionMode {
        case .none:
            if document.editingTextID != nil { return }
            if let corner = hitResizeCorner(point) {
                interactionMode = .resizing(corner)
                lastPoint = point
            } else if let hit = document.hitTest(at: point) {
                if !document.selectedAnnotationIDs.contains(hit) {
                    document.selectedAnnotationIDs = [hit]
                }
                interactionMode = .moving
                lastPoint = point
            } else if let tool = document.selectedTool, !document.isPointTool(tool) {
                interactionMode = .drawing
                drawingStartPoint = point
                hasActiveDrawingDraft = false
                lastPoint = point
            } else {
                document.clearSelection()
            }
        case .moving:
            guard let lastPoint else { return }
            let delta = CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y)
            document.moveSelection(by: delta)
            self.lastPoint = point
        case .resizing(let corner):
            document.resizePrimarySelection(to: point, corner: corner)
        case .drawing:
            maybeStartOrUpdateDrawing(to: point)
        }
    }

    private func maybeStartOrUpdateDrawing(to point: CGPoint) {
        guard let start = drawingStartPoint else {
            drawingStartPoint = point
            return
        }
        if !hasActiveDrawingDraft {
            let distance = hypot(point.x - start.x, point.y - start.y)
            guard distance >= drawingStartThreshold else { return }
            document.beginAnnotation(at: start)
            hasActiveDrawingDraft = true
        }
        document.updateAnnotation(at: point)
    }

    private func finalizeDrawing(endPoint point: CGPoint) {
        guard let start = drawingStartPoint else {
            document.cancelInteractionChange()
            return
        }
        if !hasActiveDrawingDraft {
            let distance = hypot(point.x - start.x, point.y - start.y)
            guard distance >= drawingStartThreshold else {
                document.cancelInteractionChange()
                return
            }
            document.beginAnnotation(at: start)
            hasActiveDrawingDraft = true
        }
        document.updateAnnotation(at: point)
        document.commitAnnotation()
    }

    // MARK: - Hit Testing

    private func hitResizeCorner(_ point: CGPoint) -> IOSResizeCorner? {
        guard let bounds = document.selectionBounds(),
              document.selectedAnnotationIDs.count == 1 else { return nil }
        guard let annotation = document.primarySelectedAnnotation else { return nil }
        if annotation.kind == .text { return nil }
        let threshold: CGFloat = 20 // larger touch target for iOS

        if annotation.kind == .arrow {
            let endpoints: [(CGPoint, IOSResizeCorner)] = [
                (annotation.start, .endpointStart),
                (annotation.end, .endpointEnd),
            ]
            for (ep, corner) in endpoints {
                if hypot(point.x - ep.x, point.y - ep.y) <= threshold {
                    return corner
                }
            }
            return nil
        }

        let corners: [(CGPoint, IOSResizeCorner)] = [
            (CGPoint(x: bounds.minX, y: bounds.minY), .topLeft),
            (CGPoint(x: bounds.maxX, y: bounds.minY), .topRight),
            (CGPoint(x: bounds.minX, y: bounds.maxY), .bottomLeft),
            (CGPoint(x: bounds.maxX, y: bounds.maxY), .bottomRight),
        ]
        for (corner, resizeCorner) in corners {
            if hypot(point.x - corner.x, point.y - corner.y) <= threshold {
                return resizeCorner
            }
        }
        return nil
    }

    private func tapIsInsideActiveTextEditor(_ point: CGPoint) -> Bool {
        guard let editing = editingTextAnnotation else { return false }
        return editing.bounds.insetBy(dx: -10, dy: -10).contains(point)
    }

    // MARK: - Canvas Drawing

    private func draw(annotation: IOSAnnotation, in context: GraphicsContext) {
        let strokeStyle = StrokeStyle(
            lineWidth: max(1, annotation.lineWidth),
            lineCap: .round,
            lineJoin: .round
        )

        let start = annotation.start
        let end = annotation.end

        switch annotation.kind {
        case .rectangle:
            let rect = normalizedRect(start: start, end: end)
            context.fill(Path(rect), with: .color(annotation.fillColor.opacity(0.18)))
            context.stroke(Path(rect), with: .color(annotation.color), style: strokeStyle)
        case .ellipse:
            let rect = normalizedRect(start: start, end: end)
            context.fill(Path(ellipseIn: rect), with: .color(annotation.fillColor.opacity(0.18)))
            context.stroke(Path(ellipseIn: rect), with: .color(annotation.color), style: strokeStyle)
        case .arrow:
            var linePath = Path()
            linePath.move(to: start)
            linePath.addLine(to: end)
            context.stroke(linePath, with: .color(annotation.color), style: strokeStyle)
            let arrowHead = arrowHeadPath(from: start, to: end, size: max(8, annotation.lineWidth * 3))
            context.fill(arrowHead, with: .color(annotation.color))
        case .freehand:
            guard annotation.points.count > 1 else { return }
            var path = Path()
            path.move(to: annotation.points[0])
            for point in annotation.points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(annotation.color), style: strokeStyle)
        case .mosaic:
            let rect = normalizedRect(start: start, end: end)
            if let baseCG = document.baseImage.cgImage,
               let parameters = IOSAnnotationExporter.resolveMosaicParameters(
                   documentRectTopLeft: annotation.bounds,
                   canvasSize: document.imageSize,
                   sourcePixelSize: CGSize(width: baseCG.width, height: baseCG.height),
                   block: annotation.mosaicBlockSize
               ),
               let mosaicCG = IOSAnnotationExporter.makeMosaicImage(from: baseCG, parameters: parameters) {
                let destRect = CGRect(
                    x: parameters.documentRectTopLeft.origin.x,
                    y: parameters.documentRectTopLeft.origin.y,
                    width: parameters.documentRectTopLeft.width,
                    height: parameters.documentRectTopLeft.height
                )
                context.draw(Image(decorative: mosaicCG, scale: 1.0), in: destRect)
            } else {
                context.fill(Path(rect), with: .color(.black.opacity(0.45)))
            }
        case .highlight:
            let rect = normalizedRect(start: start, end: end)
            context.fill(Path(rect), with: .color(annotation.color.opacity(0.28)))
        case .text:
            if document.editingTextID == annotation.id { return }
            let clampedTextWidth = min(annotation.textBoxWidth, document.imageWidth - annotation.start.x)
            let displayText = (annotation.text ?? "").isEmpty ? "Text" : (annotation.text ?? "")

            // White stroke outline pass
            let outlineText = Text(displayText)
                .font(.system(size: max(12, annotation.fontSize), weight: .semibold))
                .foregroundColor(.white)

            // Draw outline by rendering offset copies
            let offsets: [CGSize] = [
                CGSize(width: -1, height: 0),
                CGSize(width: 1, height: 0),
                CGSize(width: 0, height: -1),
                CGSize(width: 0, height: 1),
            ]
            for offset in offsets {
                context.draw(
                    outlineText,
                    in: CGRect(
                        x: annotation.start.x + offset.width,
                        y: annotation.start.y + offset.height,
                        width: clampedTextWidth,
                        height: annotation.bounds.height
                    )
                )
            }

            // Main fill pass
            let fillText = Text(displayText)
                .font(.system(size: max(12, annotation.fontSize), weight: .semibold))
                .foregroundColor(annotation.color)

            context.draw(
                fillText,
                in: CGRect(
                    x: annotation.start.x,
                    y: annotation.start.y,
                    width: clampedTextWidth,
                    height: annotation.bounds.height
                )
            )
        case .step:
            let radius: CGFloat = 14
            let circle = CGRect(
                x: start.x - radius,
                y: start.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: circle), with: .color(annotation.color))
            context.draw(
                Text(annotation.text ?? "1")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white),
                at: CGPoint(x: start.x, y: start.y),
                anchor: .center
            )
        }
    }

    // MARK: - Geometry Helpers

    private func normalizedRect(start: CGPoint, end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func arrowHeadPath(from start: CGPoint, to end: CGPoint, size: CGFloat) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let left = CGPoint(
            x: end.x - size * cos(angle - .pi / 6),
            y: end.y - size * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - size * cos(angle + .pi / 6),
            y: end.y - size * sin(angle + .pi / 6)
        )
        var path = Path()
        path.move(to: end)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}

// MARK: - Selection Overlay

struct IOSSelectionOverlayView: View {
    let selectionRect: CGRect?
    let showsResizeHandle: Bool
    var endpointHandles: (CGPoint, CGPoint)? = nil

    var body: some View {
        Canvas { context, _ in
            guard let rect = selectionRect else { return }

            let selectionColor = IOSTheme.accent

            context.stroke(
                Path(rect),
                with: .color(selectionColor.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )

            if let (startPt, endPt) = endpointHandles {
                let handleSize: CGFloat = 14
                for ep in [startPt, endPt] {
                    let handleRect = CGRect(
                        x: ep.x - handleSize / 2,
                        y: ep.y - handleSize / 2,
                        width: handleSize,
                        height: handleSize
                    )
                    context.fill(Path(ellipseIn: handleRect), with: .color(.white))
                    context.stroke(Path(ellipseIn: handleRect), with: .color(selectionColor), lineWidth: 1.5)
                }
            } else if showsResizeHandle {
                let handleSize: CGFloat = 14
                let corners = [
                    CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                ]
                for corner in corners {
                    let handleRect = CGRect(
                        x: corner.x - handleSize / 2,
                        y: corner.y - handleSize / 2,
                        width: handleSize,
                        height: handleSize
                    )
                    context.fill(Path(roundedRect: handleRect, cornerRadius: 3), with: .color(.white))
                    context.stroke(Path(roundedRect: handleRect, cornerRadius: 3), with: .color(selectionColor), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Inline Text Editor

struct IOSTextInlineEditorView: View {
    @Binding var text: String
    let textColor: Color
    let fontSize: CGFloat
    let onCommit: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Text", text: $text, axis: .vertical)
            .font(.system(size: max(12, fontSize), weight: .semibold))
            .foregroundColor(textColor)
            .textFieldStyle(.plain)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(IOSBrandColor.emerald.opacity(0.6), lineWidth: 1)
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onSubmit {
                onCommit(text)
            }
            .accessibilityIdentifier("editor.text.inline")
    }
}
