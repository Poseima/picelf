import SwiftUI
import AppKit
import os

private let editorPerfLog = Logger(subsystem: "com.picelf", category: "EditorPerf")

private enum MosaicRenderer {
    static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 96
        return cache
    }()
}

struct EditorInteractionUpdateGate {
    let minInterval: TimeInterval
    let minDistance: CGFloat

    private(set) var lastAcceptedTime: TimeInterval?
    private(set) var lastAcceptedPoint: CGPoint?

    init(minInterval: TimeInterval = 1.0 / 90.0, minDistance: CGFloat = 0.75) {
        self.minInterval = minInterval
        self.minDistance = minDistance
    }

    mutating func reset() {
        lastAcceptedTime = nil
        lastAcceptedPoint = nil
    }

    mutating func shouldAccept(point: CGPoint, now: TimeInterval) -> Bool {
        guard let lastTime = lastAcceptedTime, let lastPoint = lastAcceptedPoint else {
            lastAcceptedTime = now
            lastAcceptedPoint = point
            return true
        }
        guard now - lastTime >= minInterval else { return false }
        let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        guard distance >= minDistance else { return false }
        lastAcceptedTime = now
        lastAcceptedPoint = point
        return true
    }
}

struct EditorCanvasView: View {
    @ObservedObject var document: EditorDocument
    var onMagnify: ((CGFloat, CGPoint) -> Void)? = nil
    var onInteractionStateChanged: ((Bool) -> Void)? = nil

    @State private var interactionMode: InteractionMode = .none
    @State private var lastPoint: CGPoint?
    @State private var lastMagnificationValue: CGFloat = 1.0
    @State private var hoverLocation: CGPoint?
    @State private var drawingStartPoint: CGPoint?
    @State private var hasActiveDrawingDraft = false
    @State private var pendingInteractivePoint: CGPoint?
    @State private var interactionGate = EditorInteractionUpdateGate()
    @State private var interactionStartUptime: TimeInterval?
    @State private var interactionInputEvents = 0
    @State private var interactionAppliedEvents = 0
    @State private var interactionStateNotified = false

    private let drawingStartThreshold: CGFloat = 3
    private let interactiveUpdateInterval: TimeInterval = 1.0 / 90.0
    private let interactiveMinDelta: CGFloat = 0.75
    private let inlineTextEditorMaxHeight: CGFloat = 260

    private enum InteractionMode {
        case none
        case drawing
        case moving
        case resizing(ResizeCorner)
        case rotating
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: document.baseImage)
                .resizable()
                .interpolation(isInteracting ? .medium : .high)
                .frame(width: document.imageWidth * document.zoomScale,
                       height: document.imageHeight * document.zoomScale)

            if !document.translationSegments.isEmpty {
                TranslationOverlayView(
                    imageSize: CGSize(width: document.imageWidth, height: document.imageHeight),
                    zoomScale: document.zoomScale,
                    segments: document.translationSegments,
                    overlayMode: document.translationOverlayMode,
                    highlightedSegmentID: document.selectedTranslationSegmentID,
                    hoverLocation: hoverLocation,
                    isInteracting: isInteracting
                )
            }

            Canvas { context, _ in
                for annotation in document.visibleAnnotations {
                    draw(annotation: annotation, in: context)
                }
                if let draft = document.draftAnnotation {
                    draw(annotation: draft, in: context)
                }
                
                // 实时水印预览
                let watermarkConfig = AppPreferences.shared.watermarkConfig
                if !document.isRelayDocument && watermarkConfig.isEnabled && !watermarkConfig.text.isEmpty {
                    let canvasSize = CGSize(
                        width: document.imageWidth * document.zoomScale,
                        height: document.imageHeight * document.zoomScale
                    )
                    drawWatermark(config: watermarkConfig, in: context, canvasSize: canvasSize)
                }
            }
            .frame(width: document.imageWidth * document.zoomScale,
                   height: document.imageHeight * document.zoomScale)

            if let ink = document.relayInkOverlay {
                Image(nsImage: ink).resizable().interpolation(.high)
                    .frame(width: document.imageWidth * document.zoomScale, height: document.imageHeight * document.zoomScale)
                    .allowsHitTesting(false)
            }
            SelectionOverlayView(
                selectionRect: scaledSelectionRect,
                showsResizeHandle: document.selectedAnnotationIDs.count == 1 && document.primarySelectedAnnotation?.kind != .text,
                showsRotationHandle: showsRotationHandle,
                endpointHandles: endpointHandlesForSelection
            )

            if let editing = editingTextAnnotation {
                TextInlineEditorView(
                    initialText: editing.text ?? "",
                    textColor: editing.color,
                    fontSize: editing.fontSize * document.zoomScale,
                    onTextChange: { text in
                        document.updateText(for: editing.id, text: text)
                    },
                    onCommit: { text in
                        document.commitTextEditing(text)
                    }
                )
                .frame(width: {
                           let editorWidth = max(96, editing.textBoxWidth * document.zoomScale + 12)
                           let availableWidth = document.imageWidth * document.zoomScale - editing.start.x * document.zoomScale
                           return min(editorWidth, max(96, availableWidth))
                       }(),
                       height: max(36, min(inlineTextEditorMaxHeight, editing.bounds.height * document.zoomScale + 12)),
                       alignment: .topLeading)
                .offset(
                    x: editing.start.x * document.zoomScale,
                    y: editing.start.y * document.zoomScale
                )
                .zIndex(10)
            }
        }
        .frame(width: document.imageWidth * document.zoomScale,
               height: document.imageHeight * document.zoomScale,
               alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(singleTapGesture)
        .simultaneousGesture(doubleTapGesture)
        .simultaneousGesture(magnificationGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard !isInteracting else { return }
                hoverLocation = location
            case .ended:
                guard !isInteracting else { return }
                hoverLocation = nil
            }
        }
    }

    private var isInteracting: Bool {
        switch interactionMode {
        case .none:
            return false
        default:
            return true
        }
    }

    private var showsRotationHandle: Bool {
        guard document.selectedAnnotationIDs.count == 1,
              let annotation = document.primarySelectedAnnotation else { return false }
        return annotation.kind == .sticker && annotation.stickerImageID != nil
    }

    private var endpointHandlesForSelection: (CGPoint, CGPoint)? {
        guard document.selectedAnnotationIDs.count == 1,
              let annotation = document.primarySelectedAnnotation,
              annotation.kind == .arrow || annotation.kind == .line else { return nil }
        return (scaled(annotation.start), scaled(annotation.end))
    }

    private var editingTextAnnotation: EditorAnnotation? {
        guard let id = document.editingTextID else { return nil }
        return document.annotations.first(where: { $0.id == id && $0.kind == .text })
    }

    private var scaledSelectionRect: CGRect? {
        guard let rect = document.selectionBounds() else { return nil }
        return CGRect(
            x: rect.origin.x * document.zoomScale,
            y: rect.origin.y * document.zoomScale,
            width: rect.width * document.zoomScale,
            height: rect.height * document.zoomScale
        )
    }

    private var singleTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = toImagePoint(value.location)
                if tapIsInsideActiveTextEditor(point) {
                    return
                }
                let committedTextEditing = document.commitActiveTextEditing()
                if committedTextEditing {
                    if let hit = document.hitTest(at: point) {
                        document.selectedAnnotationIDs = [hit]
                    }
                    // Match WeChat screenshot flow: first click outside editor exits text editing only.
                    return
                }
                if let hit = document.hitTest(at: point) {
                    document.selectedAnnotationIDs = [hit]
                    document.activateToolForAnnotationIfSelectionMode(hit)
                    return
                }
                if let tool = document.selectedTool,
                   isPointTool(tool),
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
                let point = toImagePoint(value.location)
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
                let point = toImagePoint(value.location)
                handleDragChanged(point)
            }
            .onEnded { value in
                let point = toImagePoint(value.location)
                let endedMode = interactionMode
                defer {
                    finishInteractionTracking(mode: endedMode)
                    interactionMode = .none
                    lastPoint = nil
                    drawingStartPoint = nil
                    hasActiveDrawingDraft = false
                    pendingInteractivePoint = nil
                }

                switch endedMode {
                case .resizing(let corner):
                    let finalPoint = consumeFinalInteractivePoint(or: point)
                    document.resizePrimarySelection(to: finalPoint, corner: corner)
                    document.finalizeInteractionChange()
                case .rotating:
                    let finalPoint = consumeFinalInteractivePoint(or: point)
                    if let bounds = document.selectionBounds() {
                        let center = CGPoint(x: bounds.midX, y: bounds.midY)
                        let angle = atan2(finalPoint.y - center.y, finalPoint.x - center.x) + .pi / 2
                        document.rotatePrimarySelection(angle: angle)
                    }
                    document.finalizeInteractionChange()
                case .moving:
                    let finalPoint = consumeFinalInteractivePoint(or: point)
                    if let lastPoint {
                        let delta = CGSize(width: finalPoint.x - lastPoint.x, height: finalPoint.y - lastPoint.y)
                        if delta != .zero {
                            document.moveSelection(by: delta)
                        }
                    }
                    document.finalizeInteractionChange()
                case .drawing:
                    let finalPoint = consumeFinalInteractivePoint(or: point)
                    finalizeDrawing(endPoint: finalPoint)
                case .none:
                    document.cancelInteractionChange()
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnificationValue
                let resolvedHover = hoverLocation ?? CGPoint(
                    x: (document.imageWidth * document.zoomScale) / 2,
                    y: (document.imageHeight * document.zoomScale) / 2
                )
                if let onMagnify {
                    onMagnify(delta, resolvedHover)
                } else {
                    document.setZoomScale(document.zoomScale * delta)
                }
                lastMagnificationValue = value.magnification
            }
            .onEnded { _ in
                lastMagnificationValue = 1.0
            }
    }

    private func handleDragChanged(_ point: CGPoint) {
        switch interactionMode {
        case .none:
            if document.editingTextID != nil {
                return
            }
            if isNearRotationHandle(point) {
                startInteractionTracking()
                interactionMode = .rotating
                lastPoint = point
            } else if let corner = hitResizeCorner(point) {
                startInteractionTracking()
                interactionMode = .resizing(corner)
                lastPoint = point
            } else if let hit = document.hitTest(at: point) {
                if !document.selectedAnnotationIDs.contains(hit) {
                    document.selectedAnnotationIDs = [hit]
                }
                startInteractionTracking()
                interactionMode = .moving
                lastPoint = point
            } else if let tool = document.selectedTool, !isPointTool(tool) {
                startInteractionTracking()
                interactionMode = .drawing
                drawingStartPoint = point
                hasActiveDrawingDraft = false
                lastPoint = point
            } else {
                document.clearSelection()
            }
        case .moving:
            guard let lastPoint else { return }
            guard shouldApplyInteractiveUpdate(at: point) else { return }
            let delta = CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y)
            document.moveSelection(by: delta)
            self.lastPoint = point
        case .resizing(let corner):
            guard shouldApplyInteractiveUpdate(at: point) else { return }
            document.resizePrimarySelection(to: point, corner: corner)
        case .rotating:
            guard shouldApplyInteractiveUpdate(at: point) else { return }
            if let bounds = document.selectionBounds() {
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                let angle = atan2(point.y - center.y, point.x - center.x) + .pi / 2
                document.rotatePrimarySelection(angle: angle)
            }
        case .drawing:
            guard shouldApplyInteractiveUpdate(at: point) else { return }
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

    private func hitResizeCorner(_ point: CGPoint) -> ResizeCorner? {
        guard let bounds = document.selectionBounds(), document.selectedAnnotationIDs.count == 1 else { return nil }
        guard let annotation = document.primarySelectedAnnotation else { return nil }
        if annotation.kind == .text {
            return nil
        }
        let threshold: CGFloat = 12

        // Arrow/line: use 2 endpoint handles instead of 4 corner handles
        if annotation.kind == .arrow || annotation.kind == .line {
            let endpoints: [(CGPoint, ResizeCorner)] = [
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

        let corners: [(CGPoint, ResizeCorner)] = [
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

    private func isNearRotationHandle(_ point: CGPoint) -> Bool {
        guard showsRotationHandle, let bounds = document.selectionBounds() else { return false }
        let handlePoint = CGPoint(x: bounds.midX, y: bounds.minY - 24)
        return hypot(point.x - handlePoint.x, point.y - handlePoint.y) <= 12
    }

    private func toImagePoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x / document.zoomScale, y: location.y / document.zoomScale)
    }

    private func isPointTool(_ tool: EditorTool) -> Bool {
        tool == .text || tool == .step || tool == .sticker
    }

    private func tapIsInsideActiveTextEditor(_ point: CGPoint) -> Bool {
        guard let editing = editingTextAnnotation else { return false }
        return editing.bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    private func draw(annotation: EditorAnnotation, in context: GraphicsContext) {
        let strokeStyle = StrokeStyle(
            lineWidth: max(1, annotation.lineWidth * document.zoomScale),
            lineCap: .round,
            lineJoin: .round
        )

        let start = scaled(annotation.start)
        let end = scaled(annotation.end)

        switch annotation.kind {
        case .rectangle:
            let rect = normalizedRect(start: start, end: end)
            context.fill(Path(rect), with: .color(annotation.fillColor.opacity(0.18)))
            context.stroke(Path(rect), with: .color(annotation.color), style: strokeStyle)
        case .ellipse:
            let rect = normalizedRect(start: start, end: end)
            context.fill(Path(ellipseIn: rect), with: .color(annotation.fillColor.opacity(0.18)))
            context.stroke(Path(ellipseIn: rect), with: .color(annotation.color), style: strokeStyle)
        case .line:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.color), style: strokeStyle)
        case .arrow:
            var linePath = Path()
            linePath.move(to: start)
            linePath.addLine(to: end)
            context.stroke(linePath, with: .color(annotation.color), style: strokeStyle)
            let arrowHead = arrowHeadPath(from: start, to: end, size: 11 * document.zoomScale)
            context.fill(arrowHead, with: .color(annotation.color))
        case .freehand:
            guard annotation.points.count > 1 else { return }
            var path = Path()
            path.move(to: scaled(annotation.points[0]))
            for point in annotation.points.dropFirst() {
                path.addLine(to: scaled(point))
            }
            context.stroke(path, with: .color(annotation.color), style: strokeStyle)
        case .mosaic:
            let fallbackRect = normalizedRect(start: start, end: end)
            if let parameters = resolvedMosaicParameters(for: annotation),
               let image = makeMosaicImage(for: annotation, parameters: parameters) {
                context.draw(
                    Image(decorative: image, scale: 1.0),
                    in: scaledDocumentRect(parameters.documentRectTopLeft)
                )
            } else {
                context.fill(Path(fallbackRect), with: .color(.black.opacity(0.45)))
            }
        case .highlight:
            let rect = normalizedRect(start: start, end: end)
            context.fill(Path(rect), with: .color(annotation.color.opacity(0.28)))
        case .text:
            if document.editingTextID == annotation.id {
                return
            }
            let clampedTextWidth = min(annotation.textBoxWidth, document.imageWidth - annotation.start.x)
            let scaledRect = CGRect(
                x: annotation.start.x * document.zoomScale,
                y: annotation.start.y * document.zoomScale,
                width: clampedTextWidth * document.zoomScale,
                height: annotation.bounds.height * document.zoomScale
            )
            context.withCGContext { cgContext in
                AnnotationRenderer.drawTopLeftAnchoredWrappedText(
                    annotation.text ?? "",
                    topLeftRect: scaledRect,
                    font: NSFont.systemFont(
                        ofSize: max(12, annotation.fontSize * document.zoomScale),
                        weight: .semibold
                    ),
                    color: NSColor(annotation.color),
                    in: cgContext,
                    renderSpace: .canvasTopLeft
                )
            }
        case .step:
            let radius: CGFloat = 14 * document.zoomScale
            let circle = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: circle), with: .color(annotation.color))
            context.draw(
                Text(annotation.text ?? "1")
                    .font(.system(size: max(10, 12 * document.zoomScale), weight: .bold))
                    .foregroundColor(.white),
                at: CGPoint(x: start.x, y: start.y),
                anchor: .center
            )
        case .sticker:
            if let stickerID = annotation.stickerImageID,
               let nsImage = StickerLibrary.shared.image(for: stickerID) {
                let rect = normalizedRect(start: start, end: end)
                var localContext = context
                localContext.opacity = annotation.opacity
                if annotation.hasShadow && !isInteracting {
                    localContext.addFilter(.shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2))
                }
                let center = CGPoint(x: rect.midX, y: rect.midY)
                var transform = CGAffineTransform.identity
                    .translatedBy(x: center.x, y: center.y)
                    .rotated(by: annotation.rotation)
                if annotation.flipH { transform = transform.scaledBy(x: -1, y: 1) }
                if annotation.flipV { transform = transform.scaledBy(x: 1, y: -1) }
                transform = transform.translatedBy(x: -center.x, y: -center.y)
                localContext.concatenate(transform)
                localContext.draw(Image(nsImage: nsImage), in: rect)
            } else if annotation.stickerImageID != nil {
                let rect = normalizedRect(start: start, end: end)
                context.fill(Path(roundedRect: rect, cornerRadius: 4),
                             with: .color(.gray.opacity(0.2)))
                context.draw(Text("?").font(.system(size: 24)).foregroundColor(.gray),
                             at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            } else {
                context.draw(
                    Text(annotation.text ?? "★")
                        .font(.system(size: max(18, annotation.fontSize * document.zoomScale)))
                        .foregroundColor(annotation.color),
                    at: start,
                    anchor: .topLeading
                )
            }
        }
    }

    private func startInteractionTracking() {
        interactionGate = EditorInteractionUpdateGate(
            minInterval: interactiveUpdateInterval,
            minDistance: interactiveMinDelta
        )
        interactionStartUptime = ProcessInfo.processInfo.systemUptime
        interactionInputEvents = 0
        interactionAppliedEvents = 0
        pendingInteractivePoint = nil
        if !interactionStateNotified {
            interactionStateNotified = true
            onInteractionStateChanged?(true)
        }
    }

    private func shouldApplyInteractiveUpdate(at point: CGPoint) -> Bool {
        interactionInputEvents += 1
        let now = ProcessInfo.processInfo.systemUptime
        if interactionGate.shouldAccept(point: point, now: now) {
            interactionAppliedEvents += 1
            pendingInteractivePoint = nil
            return true
        }
        pendingInteractivePoint = point
        return false
    }

    private func consumeFinalInteractivePoint(or fallback: CGPoint) -> CGPoint {
        let finalPoint = pendingInteractivePoint ?? fallback
        pendingInteractivePoint = nil
        return finalPoint
    }

    private func finishInteractionTracking(mode: InteractionMode) {
        if interactionStateNotified {
            interactionStateNotified = false
            onInteractionStateChanged?(false)
        }
        #if DEBUG
        guard interactionInputEvents > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let start = interactionStartUptime ?? now
        let duration = now - start
        let dropped = max(0, interactionInputEvents - interactionAppliedEvents)
        let modeName = modeLabel(mode)
        editorPerfLog.debug(
            "mode=\(modeName, privacy: .public) duration=\(duration, privacy: .public) input=\(self.interactionInputEvents, privacy: .public) applied=\(self.interactionAppliedEvents, privacy: .public) dropped=\(dropped, privacy: .public)"
        )
        #endif
    }

    private func modeLabel(_ mode: InteractionMode) -> String {
        switch mode {
        case .none:
            return "none"
        case .drawing:
            return "drawing"
        case .moving:
            return "moving"
        case .resizing:
            return "resizing"
        case .rotating:
            return "rotating"
        }
    }

    private func resolvedMosaicParameters(for annotation: EditorAnnotation) -> AnnotationRenderer.ResolvedMosaicParameters? {
        guard let cg = document.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return AnnotationRenderer.resolveMosaicParameters(
            documentRectTopLeft: annotation.bounds,
            canvasSize: CGSize(width: document.imageWidth, height: document.imageHeight),
            sourcePixelSize: CGSize(width: cg.width, height: cg.height),
            block: annotation.mosaicBlockSize
        )
    }

    private func makeMosaicImage(
        for annotation: EditorAnnotation,
        parameters: AnnotationRenderer.ResolvedMosaicParameters
    ) -> CGImage? {
        guard let cg = document.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let baseImageIdentity = ObjectIdentifier(document.baseImage).hashValue
        let crop = parameters.sourceCropRect
        let cacheKey = "\(baseImageIdentity)-\(annotation.id.uuidString)-\(cg.width)x\(cg.height)-\(Int(crop.origin.x))-\(Int(crop.origin.y))-\(Int(crop.width))-\(Int(crop.height))-\(Int(parameters.effectiveBlockScale.rounded()))"
        if let cached = MosaicRenderer.cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        guard let rendered = AnnotationRenderer.makeMosaicImage(from: cg, parameters: parameters) else {
            return nil
        }
        MosaicRenderer.cache.setObject(rendered, forKey: cacheKey as NSString)
        return rendered
    }

    private func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * document.zoomScale, y: point.y * document.zoomScale)
    }

    private func scaledDocumentRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * document.zoomScale,
            y: rect.origin.y * document.zoomScale,
            width: rect.width * document.zoomScale,
            height: rect.height * document.zoomScale
        )
    }

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
    
    // MARK: - Watermark Drawing
    
    private func drawWatermark(config: WatermarkConfig, in context: GraphicsContext, canvasSize: CGSize) {
        let padding: CGFloat = 16
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let reducedDensity: Bool
        switch interactionMode {
        case .none:
            reducedDensity = false
        default:
            reducedDensity = true
        }
        
        // 不再随 zoomScale 缩放，使用原始尺寸
        if config.tiledEnabled {
            drawTiledWatermark(
                config: config,
                in: context,
                canvasSize: canvasSize,
                reducedDensity: reducedDensity
            )
        } else {
            let position = config.position.anchorPoint(in: canvasRect, padding: padding)
            drawWatermarkText(config: config, in: context, at: position)
        }
    }
    
    private func drawWatermarkText(config: WatermarkConfig, in context: GraphicsContext, at position: CGPoint) {
        let textColor = config.color.color.opacity(config.opacity)
        
        var textContext = context
        if config.hasShadow {
            textContext.addFilter(.shadow(
                color: .black.opacity(0.5),
                radius: config.shadowRadius,
                x: 1,
                y: -1
            ))
        }
        
        var resolvedContext = textContext
        if config.rotation != 0 {
            let transform = CGAffineTransform.identity
                .translatedBy(x: position.x, y: position.y)
                .rotated(by: config.rotation * .pi / 180)
                .translatedBy(x: -position.x, y: -position.y)
            resolvedContext.concatenate(transform)
        }
        
        let text = Text(config.text)
            .font(.system(size: config.fontSize, weight: .semibold))
            .foregroundStyle(textColor)
        
        resolvedContext.draw(text, at: position, anchor: anchorForPosition(config.position))
    }
    
    private func drawTiledWatermark(
        config: WatermarkConfig,
        in context: GraphicsContext,
        canvasSize: CGSize,
        reducedDensity: Bool
    ) {
        let angle = config.tiledAngle * .pi / 180
        let spacingScale: CGFloat = reducedDensity ? 1.8 : 1.0
        let spacingX = max(40, config.tiledSpacingX * spacingScale)
        let spacingY = max(40, config.tiledSpacingY * spacingScale)
        let step = reducedDensity ? 2 : 1
        
        // 旋转30度后，需要更大的覆盖范围
        let diagonal = sqrt(canvasSize.width * canvasSize.width + canvasSize.height * canvasSize.height)
        let coverSize = diagonal * (reducedDensity ? 1.15 : 1.5)
        
        let cols = Int(coverSize / spacingX) + 2
        let rows = Int(coverSize / spacingY) + 2
        let cosA = cos(angle)
        let sinA = sin(angle)
        
        for row in stride(from: -rows, through: rows, by: step) {
            for col in stride(from: -cols, through: cols, by: step) {
                let baseX = canvasSize.width / 2 + CGFloat(col) * spacingX
                let baseY = canvasSize.height / 2 + CGFloat(row) * spacingY
                
                // 应用旋转
                let rotatedX = (baseX - canvasSize.width / 2) * cosA - (baseY - canvasSize.height / 2) * sinA + canvasSize.width / 2
                let rotatedY = (baseX - canvasSize.width / 2) * sinA + (baseY - canvasSize.height / 2) * cosA + canvasSize.height / 2
                
                let pos = CGPoint(x: rotatedX, y: rotatedY)
                
                // 只绘制在画布范围内的水印
                if pos.x > -50 && pos.x < canvasSize.width + 50 &&
                   pos.y > -50 && pos.y < canvasSize.height + 50 {
                    drawWatermarkText(config: config, in: context, at: pos)
                }
            }
        }
    }
    
    private func anchorForPosition(_ position: WatermarkPosition) -> UnitPoint {
        switch position {
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .middleLeft: return .leading
        case .middleCenter: return .center
        case .middleRight: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }
}
