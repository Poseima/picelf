// IOSEditorDocument.swift
// PicelfIOS — Annotation editor document model for iOS
//
// Target: iOS 16+, Swift 5.9+

import SwiftUI
import UIKit
import CoreImage

// MARK: - iOS Editor Tool

enum IOSEditorTool: String, CaseIterable, Identifiable {
    case arrow = "Arrow"
    case text = "Text"
    case rectangle = "Rect"
    case ellipse = "Ellipse"
    case pencil = "Pencil"
    case mosaic = "Mosaic"
    case highlight = "Highlight"
    case step = "Step"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arrow: return L10n.localized("箭头", "Arrow")
        case .text: return L10n.localized("文本", "Text")
        case .rectangle: return L10n.localized("矩形", "Rectangle")
        case .ellipse: return L10n.localized("椭圆", "Ellipse")
        case .pencil: return L10n.localized("画笔", "Pencil")
        case .mosaic: return L10n.localized("马赛克", "Mosaic")
        case .highlight: return L10n.localized("高亮", "Highlight")
        case .step: return L10n.localized("步骤", "Step")
        }
    }

    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .pencil: return "pencil.tip"
        case .mosaic: return "square.grid.3x3.fill"
        case .highlight: return "highlighter"
        case .step: return "list.number"
        }
    }
}

// MARK: - Annotation Kind

enum IOSAnnotationKind {
    case rectangle
    case ellipse
    case arrow
    case freehand
    case mosaic
    case text
    case step
    case highlight
}

// MARK: - Resize Corner

enum IOSResizeCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case endpointStart
    case endpointEnd
}

// MARK: - Annotation Model

struct IOSAnnotation: Identifiable {
    static let textBoxWidthRange: ClosedRange<CGFloat> = 120...1200
    static let defaultTextBoxWidth: CGFloat = 280

    let id: UUID
    let kind: IOSAnnotationKind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    var text: String?
    var color: Color
    var lineWidth: CGFloat
    var fillColor: Color
    var isHidden: Bool
    var zIndex: Int
    var fontSize: CGFloat
    var textBoxWidth: CGFloat
    var mosaicBlockSize: CGFloat

    init(
        id: UUID = UUID(),
        kind: IOSAnnotationKind,
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint] = [],
        text: String? = nil,
        color: Color,
        lineWidth: CGFloat,
        fillColor: Color = .clear,
        isHidden: Bool = false,
        zIndex: Int = 0,
        fontSize: CGFloat = 18,
        textBoxWidth: CGFloat = Self.defaultTextBoxWidth,
        mosaicBlockSize: CGFloat = 14
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.points = points
        self.text = text
        self.color = color
        self.lineWidth = lineWidth
        self.fillColor = fillColor
        self.isHidden = isHidden
        self.zIndex = zIndex
        self.fontSize = fontSize
        self.textBoxWidth = min(max(textBoxWidth, Self.textBoxWidthRange.lowerBound), Self.textBoxWidthRange.upperBound)
        self.mosaicBlockSize = mosaicBlockSize
    }

    var bounds: CGRect {
        if kind == .freehand {
            guard let first = points.first else {
                return CGRect(x: start.x, y: start.y, width: 1, height: 1)
            }
            var minX = first.x, minY = first.y
            var maxX = first.x, maxY = first.y
            for p in points {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
                .insetBy(dx: -lineWidth, dy: -lineWidth)
        }

        if kind == .step {
            return CGRect(x: start.x - 16, y: start.y - 16, width: 32, height: 32)
        }

        if kind == .text {
            let width = min(max(textBoxWidth, Self.textBoxWidthRange.lowerBound), Self.textBoxWidthRange.upperBound)
            let displayText = (text ?? "").isEmpty ? "Text" : (text ?? "Text")
            let font = UIFont.systemFont(ofSize: max(12, fontSize), weight: .semibold)
            let constrainedSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            let rect = (displayText as NSString).boundingRect(
                with: constrainedSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            let height = max(24, ceil(rect.height))
            return CGRect(x: start.x, y: start.y, width: width, height: height)
        }

        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(1, abs(end.x - start.x)),
            height: max(1, abs(end.y - start.y))
        )
    }
}

// MARK: - iOS Editor Document

@MainActor
final class IOSEditorDocument: ObservableObject {

    private struct Snapshot {
        var annotations: [IOSAnnotation]
        var selectedAnnotationIDs: Set<UUID>
        var editingTextID: UUID?
        var stepCounter: Int
        var nextZIndex: Int
    }

    // MARK: Published state

    @Published var baseImage: UIImage
    let imageSize: CGSize

    @Published var selectedTool: IOSEditorTool? = nil
    @Published var annotations: [IOSAnnotation] = []
    @Published var draftAnnotation: IOSAnnotation?
    @Published var selectedAnnotationIDs: Set<UUID> = []
    @Published var editingTextID: UUID?

    @Published var strokeColor: Color = IOSBrandColor.emerald
    @Published var lineWidth: CGFloat = 3.0
    @Published var fontSize: CGFloat = 18
    @Published var mosaicBlockSize: CGFloat = 14

    // MARK: Internal state

    private(set) var stepCounter: Int = 1
    private var nextZIndex: Int = 1
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var interactionBaseline: Snapshot?
    private let maxHistoryDepth = 100

    // MARK: Init

    init(baseImage: UIImage) {
        self.baseImage = baseImage
        self.imageSize = baseImage.size
    }

    // MARK: Computed properties

    var imageWidth: CGFloat { imageSize.width }
    var imageHeight: CGFloat { imageSize.height }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var visibleAnnotations: [IOSAnnotation] {
        annotations.filter { !$0.isHidden }.sorted { $0.zIndex < $1.zIndex }
    }

    var selectedAnnotations: [IOSAnnotation] {
        annotations.filter { selectedAnnotationIDs.contains($0.id) }
    }

    var primarySelectedAnnotation: IOSAnnotation? {
        guard let id = selectedAnnotationIDs.first else { return nil }
        return annotations.first { $0.id == id }
    }

    // MARK: Tool management

    func toggleTool(_ tool: IOSEditorTool) {
        selectedTool = selectedTool == tool ? nil : tool
    }

    // MARK: Annotation creation

    func beginAnnotation(at point: CGPoint) {
        guard let tool = selectedTool, let kind = kindForTool(tool) else { return }
        beginInteractionChangeIfNeeded()

        let z = nextZIndex
        nextZIndex += 1

        switch kind {
        case .text:
            let id = UUID()
            let margin: CGFloat = 8
            let availableWidth = max(
                IOSAnnotation.textBoxWidthRange.lowerBound,
                imageWidth - point.x - margin
            )
            let effectiveTextBoxWidth = min(IOSAnnotation.defaultTextBoxWidth, availableWidth)
            annotations.append(IOSAnnotation(
                id: id,
                kind: .text,
                start: point,
                end: point,
                text: "",
                color: strokeColor,
                lineWidth: lineWidth,
                zIndex: z,
                fontSize: fontSize,
                textBoxWidth: effectiveTextBoxWidth
            ))
            selectedAnnotationIDs = [id]
            editingTextID = id
            finalizeInteractionChange()

        case .step:
            let id = UUID()
            annotations.append(IOSAnnotation(
                id: id,
                kind: .step,
                start: point,
                end: point,
                text: "\(stepCounter)",
                color: strokeColor,
                lineWidth: lineWidth,
                zIndex: z
            ))
            stepCounter += 1
            selectedAnnotationIDs = [id]
            finalizeInteractionChange()

        case .freehand:
            draftAnnotation = IOSAnnotation(
                kind: .freehand,
                start: point,
                end: point,
                points: [point],
                color: strokeColor,
                lineWidth: lineWidth,
                zIndex: z
            )

        case .rectangle, .ellipse, .arrow, .mosaic, .highlight:
            draftAnnotation = IOSAnnotation(
                kind: kind,
                start: point,
                end: point,
                color: strokeColor,
                lineWidth: lineWidth,
                zIndex: z,
                mosaicBlockSize: mosaicBlockSize
            )
        }
    }

    func updateAnnotation(at point: CGPoint) {
        guard var draft = draftAnnotation else { return }
        draft.end = point
        if draft.kind == .freehand {
            draft.points.append(point)
        }
        draftAnnotation = draft
    }

    func commitAnnotation() {
        guard let draft = draftAnnotation else { return }
        draftAnnotation = nil

        guard isDraftMeaningful(draft) else {
            cancelInteractionChange()
            return
        }

        let id = draft.id
        annotations.append(draft)
        selectedAnnotationIDs = [id]
        finalizeInteractionChange()
    }

    func cancelDraft() {
        draftAnnotation = nil
        interactionBaseline = nil
    }

    // MARK: Undo/Redo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(from: previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(from: next)
    }

    // MARK: Selection

    func clearSelection() {
        selectedAnnotationIDs = []
        editingTextID = nil
    }

    func hitTest(at point: CGPoint) -> UUID? {
        let ordered = visibleAnnotations.reversed()
        for annotation in ordered {
            if annotation.kind == .arrow {
                if distanceToSegment(point: point, a: annotation.start, b: annotation.end) <= max(12, annotation.lineWidth + 6) {
                    return annotation.id
                }
                continue
            }
            let bounds = annotation.bounds
            if bounds.insetBy(dx: -10, dy: -10).contains(point) {
                return annotation.id
            }
        }
        return nil
    }

    func selectionBounds() -> CGRect? {
        let selected = selectedAnnotations.filter { !$0.isHidden }
        guard !selected.isEmpty else { return nil }
        var rect = selected[0].bounds
        for annotation in selected.dropFirst() {
            rect = rect.union(annotation.bounds)
        }
        return rect
    }

    // MARK: Move

    func moveSelection(by delta: CGSize) {
        guard delta != .zero else { return }
        beginInteractionChangeIfNeeded()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].start.x += delta.width
            annotations[index].start.y += delta.height
            annotations[index].end.x += delta.width
            annotations[index].end.y += delta.height
            if !annotations[index].points.isEmpty {
                annotations[index].points = annotations[index].points.map {
                    CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
                }
            }
        }
    }

    // MARK: Resize

    func resizePrimarySelection(to point: CGPoint, corner: IOSResizeCorner) {
        guard let id = selectedAnnotationIDs.first else { return }
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        beginInteractionChangeIfNeeded()

        switch corner {
        case .topLeft:
            annotations[index].start = point
        case .topRight:
            annotations[index].start.y = point.y
            annotations[index].end.x = point.x
        case .bottomLeft:
            annotations[index].start.x = point.x
            annotations[index].end.y = point.y
        case .bottomRight:
            annotations[index].end = point
        case .endpointStart:
            annotations[index].start = point
        case .endpointEnd:
            annotations[index].end = point
        }
    }

    // MARK: Text editing

    func beginTextEditing(_ id: UUID) {
        editingTextID = id
        selectedAnnotationIDs = [id]
    }

    func commitTextEditing(_ text: String) {
        guard let id = editingTextID else { return }
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let committed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty {
            pushUndoSnapshot()
            annotations.remove(at: index)
            selectedAnnotationIDs.remove(id)
            editingTextID = nil
            return
        }
        guard annotations[index].text != committed else {
            editingTextID = nil
            return
        }
        pushUndoSnapshot()
        annotations[index].text = committed
        editingTextID = nil
    }

    @discardableResult
    func commitActiveTextEditing() -> Bool {
        guard let id = editingTextID else { return false }
        guard let annotation = annotations.first(where: { $0.id == id }) else {
            editingTextID = nil
            return false
        }
        commitTextEditing(annotation.text ?? "")
        return true
    }

    func updateText(for id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].text = text
    }

    // MARK: Delete

    func deleteSelection() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        annotations.removeAll { selectedAnnotationIDs.contains($0.id) }
        selectedAnnotationIDs = []
        editingTextID = nil
    }

    // MARK: Style updates

    func updateSelectedStrokeColor(_ color: Color) {
        if !selectedAnnotationIDs.isEmpty {
            pushUndoSnapshot()
        }
        strokeColor = color
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].color = color
        }
    }

    func updateSelectedLineWidth(_ width: CGFloat) {
        let clamped = min(max(width, 1), 24)
        if !selectedAnnotationIDs.isEmpty {
            pushUndoSnapshot()
        }
        lineWidth = clamped
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].lineWidth = clamped
        }
    }

    func updateSelectedFontSize(_ size: CGFloat) {
        let clamped = min(max(size, 12), 64)
        fontSize = clamped
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].fontSize = clamped
        }
    }

    // MARK: Interaction change tracking

    func beginInteractionChangeIfNeeded() {
        guard interactionBaseline == nil else { return }
        interactionBaseline = currentSnapshot()
    }

    func finalizeInteractionChange() {
        guard let baseline = interactionBaseline else { return }
        interactionBaseline = nil
        undoStack.append(baseline)
        if undoStack.count > maxHistoryDepth {
            undoStack.removeFirst(undoStack.count - maxHistoryDepth)
        }
        redoStack.removeAll()
    }

    func cancelInteractionChange() {
        interactionBaseline = nil
    }

    // MARK: Export

    func renderAnnotatedImage() -> UIImage {
        let size = imageSize
        guard size.width > 0, size.height > 0 else { return baseImage }

        let scale = baseImage.scale
        let pixelW = Int(size.width * scale)
        let pixelH = Int(size.height * scale)

        guard let baseCG = baseImage.cgImage,
              let ctx = CGContext(
                  data: nil, width: pixelW, height: pixelH,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return baseImage }

        ctx.interpolationQuality = .high
        // Draw base image (CG context is y-up)
        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        // Scale context to point coordinates
        ctx.scaleBy(x: scale, y: scale)

        let canvasSize = size
        for annotation in visibleAnnotations {
            IOSAnnotationExporter.draw(annotation: annotation, in: ctx, baseImage: baseCG, canvasSize: canvasSize)
        }

        guard let composedCG = ctx.makeImage() else { return baseImage }
        return UIImage(cgImage: composedCG, scale: scale, orientation: .up)
    }

    // MARK: - Private helpers

    private func kindForTool(_ tool: IOSEditorTool) -> IOSAnnotationKind? {
        switch tool {
        case .arrow: return .arrow
        case .text: return .text
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .pencil: return .freehand
        case .mosaic: return .mosaic
        case .highlight: return .highlight
        case .step: return .step
        }
    }

    private func isDraftMeaningful(_ draft: IOSAnnotation) -> Bool {
        let minSpan: CGFloat = 2
        switch draft.kind {
        case .rectangle, .ellipse, .arrow, .mosaic, .highlight:
            let dx = abs(draft.end.x - draft.start.x)
            let dy = abs(draft.end.y - draft.start.y)
            return max(dx, dy) >= minSpan
        case .freehand:
            return freehandPathLength(draft.points) >= minSpan
        default:
            return true
        }
    }

    private func freehandPathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var length: CGFloat = 0
        for index in 1..<points.count {
            length += hypot(points[index].x - points[index - 1].x,
                            points[index].y - points[index - 1].y)
        }
        return length
    }

    private func distanceToSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if dx == 0, dy == 0 {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func pushUndoSnapshot() {
        undoStack.append(currentSnapshot())
        if undoStack.count > maxHistoryDepth {
            undoStack.removeFirst(undoStack.count - maxHistoryDepth)
        }
        redoStack.removeAll()
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            annotations: annotations,
            selectedAnnotationIDs: selectedAnnotationIDs,
            editingTextID: editingTextID,
            stepCounter: stepCounter,
            nextZIndex: nextZIndex
        )
    }

    private func restore(from snapshot: Snapshot) {
        annotations = snapshot.annotations
        selectedAnnotationIDs = snapshot.selectedAnnotationIDs
        editingTextID = snapshot.editingTextID
        stepCounter = snapshot.stepCounter
        nextZIndex = snapshot.nextZIndex
        draftAnnotation = nil
    }

    func isPointTool(_ tool: IOSEditorTool) -> Bool {
        tool == .text || tool == .step
    }
}

// MARK: - Annotation Exporter (CGContext rendering for export)

enum IOSAnnotationExporter {
    private static let mosaicContext = CIContext(options: [.workingColorSpace: NSNull()])

    static func draw(
        annotation: IOSAnnotation,
        in context: CGContext,
        baseImage: CGImage?,
        canvasSize: CGSize
    ) {
        guard !annotation.isHidden else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(UIColor(annotation.color).cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let rect = annotation.bounds
        let drawRect = topLeftRectToContext(rect, canvasHeight: canvasSize.height)

        switch annotation.kind {
        case .rectangle:
            context.setFillColor(UIColor(annotation.fillColor).withAlphaComponent(0.18).cgColor)
            context.fill(drawRect)
            context.stroke(drawRect)
        case .ellipse:
            context.setFillColor(UIColor(annotation.fillColor).withAlphaComponent(0.18).cgColor)
            context.fillEllipse(in: drawRect)
            context.strokeEllipse(in: drawRect)
        case .arrow:
            let start = topLeftPointToContext(annotation.start, canvasHeight: canvasSize.height)
            let end = topLeftPointToContext(annotation.end, canvasHeight: canvasSize.height)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            drawArrowHead(in: context, from: start, to: end,
                          size: max(8, annotation.lineWidth * 3),
                          color: UIColor(annotation.color).cgColor)
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
                context.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
                context.fill(drawRect)
                return
            }
            context.draw(
                mosaicImage,
                in: topLeftRectToContext(parameters.documentRectTopLeft, canvasHeight: canvasSize.height)
            )
        case .highlight:
            context.setFillColor(UIColor(annotation.color).withAlphaComponent(0.28).cgColor)
            context.fill(drawRect)
        case .text:
            var textRect = annotation.bounds
            let maxWidth = canvasSize.width - annotation.start.x
            if textRect.width > maxWidth {
                textRect.size.width = maxWidth
            }
            drawWrappedText(
                annotation.text ?? "",
                topLeftRect: textRect,
                font: UIFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
                color: UIColor(annotation.color),
                in: context,
                canvasHeight: canvasSize.height
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
            context.setFillColor(UIColor(annotation.color).cgColor)
            context.fillEllipse(in: circle)
            let text = annotation.text ?? "1"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textPoint = CGPoint(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2
            )
            UIGraphicsPushContext(context)
            (text as NSString).draw(at: textPoint, withAttributes: attributes)
            UIGraphicsPopContext()
        }
    }

    // MARK: Mosaic helpers

    struct ResolvedMosaicParameters {
        let documentRectTopLeft: CGRect
        let sourceCropRect: CGRect
        let effectiveBlockScale: CGFloat
    }

    static func resolveMosaicParameters(
        documentRectTopLeft rect: CGRect,
        canvasSize: CGSize,
        sourcePixelSize: CGSize,
        block: CGFloat
    ) -> ResolvedMosaicParameters? {
        guard canvasSize.width > 0, canvasSize.height > 0,
              sourcePixelSize.width > 0, sourcePixelSize.height > 0 else { return nil }

        let visibleDocumentRect = rect.standardized.intersection(
            CGRect(origin: .zero, size: canvasSize)
        )
        guard !visibleDocumentRect.isNull, !visibleDocumentRect.isEmpty,
              visibleDocumentRect.width > 0, visibleDocumentRect.height > 0 else { return nil }

        let scaleX = sourcePixelSize.width / canvasSize.width
        let scaleY = sourcePixelSize.height / canvasSize.height
        let sourceBounds = CGRect(origin: .zero, size: sourcePixelSize)
        let mappedSourceRect = CGRect(
            x: visibleDocumentRect.origin.x * scaleX,
            y: visibleDocumentRect.origin.y * scaleY,
            width: visibleDocumentRect.width * scaleX,
            height: visibleDocumentRect.height * scaleY
        ).integral.intersection(sourceBounds)

        guard !mappedSourceRect.isNull, !mappedSourceRect.isEmpty,
              mappedSourceRect.width >= 1, mappedSourceRect.height >= 1 else { return nil }

        let sourceScale = max(scaleX, scaleY)
        return ResolvedMosaicParameters(
            documentRectTopLeft: visibleDocumentRect,
            sourceCropRect: mappedSourceRect,
            effectiveBlockScale: max(1, max(6, block) * sourceScale)
        )
    }

    static func makeMosaicImage(from sourceImage: CGImage, parameters: ResolvedMosaicParameters) -> CGImage? {
        guard let cropped = sourceImage.cropping(to: parameters.sourceCropRect) else { return nil }
        let ciInput = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else { return cropped }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(parameters.effectiveBlockScale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: ciInput.extent.midX, y: ciInput.extent.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else { return cropped }
        return mosaicContext.createCGImage(output, from: output.extent) ?? cropped
    }

    // MARK: Coordinate helpers

    private static func topLeftPointToContext(_ point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }

    private static func topLeftRectToContext(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: canvasHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Arrow head

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

    // MARK: Text rendering

    private static func drawWrappedText(
        _ text: String,
        topLeftRect: CGRect,
        font: UIFont,
        color: UIColor,
        in context: CGContext,
        canvasHeight: CGFloat
    ) {
        let drawRect = topLeftRectToContext(topLeftRect, canvasHeight: canvasHeight)
        let displayText = text.isEmpty ? "Text" : text

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        // White stroke outline
        let outlineAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.white,
            .strokeWidth: 4.0,
            .paragraphStyle: paragraph
        ]

        // Color fill
        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        UIGraphicsPushContext(context)
        // We need to flip for UIKit drawing in CG context
        context.saveGState()
        context.translateBy(x: 0, y: canvasHeight)
        context.scaleBy(x: 1, y: -1)
        let flippedRect = topLeftRect
        NSAttributedString(string: displayText, attributes: outlineAttributes)
            .draw(with: flippedRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        NSAttributedString(string: displayText, attributes: fillAttributes)
            .draw(with: flippedRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        context.restoreGState()
        UIGraphicsPopContext()
    }
}
