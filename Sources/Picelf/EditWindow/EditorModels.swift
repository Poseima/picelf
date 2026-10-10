import SwiftUI
import AppKit
#if canImport(Translation)
import Translation
#endif

enum EditorTool: String, CaseIterable, Identifiable {
    case rectangle = "Rect"
    case ellipse = "Ellipse"
    case line = "Line"
    case arrow = "Arrow"
    case pencil = "Pencil"
    case mosaic = "Mosaic"
    case text = "Text"
    case step = "Step"
    case highlight = "Highlight"
    case sticker = "Sticker"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pencil: return "pencil.tip"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        case .step: return "list.number"
        case .highlight: return "highlighter"
        case .sticker: return "star.fill"
        }
    }
}

enum EditToolbarSymbol {
    static let addImage = "plus.rectangle.on.rectangle"
    static let undo = "arrow.uturn.backward"
    static let redo = "arrow.uturn.forward"
    static let delete = "trash"
    static let fit = "arrow.up.left.and.down.right.magnifyingglass"
    static let zoomOut = "minus.magnifyingglass"
    static let zoomIn = "plus.magnifyingglass"
    static let pin = "pin.fill"
    static let scrollCapture = "scroll"
    static let record = "record.circle"
    static let ocr = "doc.viewfinder"
    static let translate = "globe"
    static let extractSubject = "person.and.background.dotted"
    static let watermarkOff = "drop"
    static let watermarkOn = "drop.fill"
    static let confirm = "checkmark"
    static let cancel = "xmark"
}

enum EditorAnnotationKind: String, Codable {
    case rectangle
    case ellipse
    case line
    case arrow
    case freehand
    case mosaic
    case text
    case step
    case highlight
    case sticker
}

enum LayerMoveDirection {
    case up
    case down
}

enum ResizeCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case endpointStart
    case endpointEnd
}

struct EditorAnnotation: Identifiable {
    static let textBoxWidthRange: ClosedRange<CGFloat> = 160...1200
    static let defaultTextBoxWidth: CGFloat = CGFloat(EditorToolState.defaultTextBoxWidth)

    let id: UUID
    let kind: EditorAnnotationKind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    var text: String?
    var color: Color
    var lineWidth: CGFloat
    var fillColor: Color
    var isLocked: Bool
    var isHidden: Bool
    var zIndex: Int
    var fontSize: CGFloat
    var textBoxWidth: CGFloat
    var mosaicBlockSize: CGFloat
    var stickerImageID: String?
    var rotation: CGFloat
    var opacity: CGFloat
    var flipH: Bool
    var flipV: Bool
    var hasShadow: Bool

    init(
        id: UUID = UUID(),
        kind: EditorAnnotationKind,
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint] = [],
        text: String? = nil,
        color: Color,
        lineWidth: CGFloat,
        fillColor: Color = .clear,
        isLocked: Bool = false,
        isHidden: Bool = false,
        zIndex: Int = 0,
        fontSize: CGFloat = 18,
        textBoxWidth: CGFloat = Self.defaultTextBoxWidth,
        mosaicBlockSize: CGFloat = 14,
        stickerImageID: String? = nil,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1.0,
        flipH: Bool = false,
        flipV: Bool = false,
        hasShadow: Bool = false
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
        self.isLocked = isLocked
        self.isHidden = isHidden
        self.zIndex = zIndex
        self.fontSize = fontSize
        self.textBoxWidth = Self.clampTextBoxWidth(textBoxWidth)
        self.mosaicBlockSize = mosaicBlockSize
        self.stickerImageID = stickerImageID
        self.rotation = rotation
        self.opacity = opacity
        self.flipH = flipH
        self.flipV = flipV
        self.hasShadow = hasShadow
    }

    func duplicated(newID: UUID = UUID(), offset: CGFloat = 20, zIndex: Int) -> EditorAnnotation {
        EditorAnnotation(
            id: newID,
            kind: kind,
            start: CGPoint(x: start.x + offset, y: start.y + offset),
            end: CGPoint(x: end.x + offset, y: end.y + offset),
            points: points.map { CGPoint(x: $0.x + offset, y: $0.y + offset) },
            text: text,
            color: color,
            lineWidth: lineWidth,
            fillColor: fillColor,
            isLocked: false,
            isHidden: isHidden,
            zIndex: zIndex,
            fontSize: fontSize,
            textBoxWidth: textBoxWidth,
            mosaicBlockSize: mosaicBlockSize,
            stickerImageID: stickerImageID,
            rotation: rotation,
            opacity: opacity,
            flipH: flipH,
            flipV: flipV,
            hasShadow: hasShadow
        )
    }

    var bounds: CGRect {
        if kind == .freehand {
            guard let first = points.first else {
                return CGRect(x: start.x, y: start.y, width: 1, height: 1)
            }
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for p in points {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY)).insetBy(dx: -lineWidth, dy: -lineWidth)
        }

        if kind == .step {
            return CGRect(x: start.x - 16, y: start.y - 16, width: 32, height: 32)
        }

        if kind == .text {
            let width = Self.clampTextBoxWidth(textBoxWidth)
            let font = NSFont.systemFont(ofSize: max(12, fontSize), weight: .semibold)
            let measured = AnnotationRenderer.measureWrappedText(
                (text ?? "").isEmpty ? "Text" : (text ?? "Text"),
                font: font,
                maxWidth: width
            )
            let height = max(24, ceil(measured.height))
            return CGRect(x: start.x, y: start.y, width: width, height: height)
        }

        if kind == .sticker {
            let width = max(24, abs(end.x - start.x))
            let height = max(24, abs(end.y - start.y))
            return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: width, height: height)
        }

        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(1, abs(end.x - start.x)),
            height: max(1, abs(end.y - start.y))
        )
    }

    static func clampTextBoxWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, textBoxWidthRange.lowerBound), textBoxWidthRange.upperBound)
    }
}

@MainActor
final class EditorDocument: ObservableObject {
    private struct Snapshot {
        var annotations: [EditorAnnotation]
        var selectedAnnotationIDs: Set<UUID>
        var editingTextID: UUID?
        var stepCounter: Int
        var nextZIndex: Int
    }

    @Published var baseImage: NSImage
    private var workingFullResImage: NSImage
    private var originalBaseImage: NSImage?
    private(set) var sourceImageURL: URL?
    let originalImageSize: CGSize

    private let prefs: AppPreferences
    private let context: EditorToolContext
    private var isHydratingToolState = false
    private var hasCustomizedTranslationTarget = false
    private var cachedTranslationImageHash: String?

    @Published var isExtractingSubject = false
    @Published var selectedTool: EditorTool? = nil {
        didSet {
            guard !isHydratingToolState else { return }
            persistSelectedToolPreference()
        }
    }
    @Published var zoomScale: CGFloat = 1.0
    @Published var strokeColor: Color = EditorTheme.defaultAnnotationStroke {
        didSet {
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    @Published var fillColor: Color = .clear {
        didSet {
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    @Published var lineWidth: CGFloat = 3.0 {
        didSet {
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    @Published var preferredTextFontSize: CGFloat = 18 {
        didSet {
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    @Published var preferredTextBoxWidth: CGFloat = EditorAnnotation.defaultTextBoxWidth {
        didSet {
            let clamped = EditorAnnotation.clampTextBoxWidth(preferredTextBoxWidth)
            if clamped != preferredTextBoxWidth {
                preferredTextBoxWidth = clamped
                return
            }
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    @Published var preferredMosaicBlockSize: CGFloat = 14 {
        didSet {
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    var onRelayChange: (() -> Void)?
    var isRelayDocument = false
    @Published var relayLocked = false
    @Published var relayInkOverlay: NSImage?
    @Published var annotations: [EditorAnnotation] = [] { didSet { onRelayChange?() } }
    @Published var draftAnnotation: EditorAnnotation? { didSet { onRelayChange?() } }
    @Published var selectedFormat: ImageFormat = .png {
        didSet {
            guard !isHydratingToolState else { return }
            persistExportPreferences()
        }
    }
    @Published var jpegQuality: Double = 0.9 {
        didSet {
            guard !isHydratingToolState else { return }
            persistExportPreferences()
        }
    }
    @Published var selectedAnnotationIDs: Set<UUID> = []
    @Published var editingTextID: UUID?
    @Published var selectedSticker: String = "★" {
        didSet {
            guard !isHydratingToolState else { return }
            persistStylePreferences()
        }
    }
    @Published var ocrText: String?
    @Published var isOCRRunning = false
    @Published var recognizedTextDocument: RecognizedTextDocument?
    @Published var translationSegments: [TranslationSegment] = []
    @Published var translationState: TranslationRuntimeState = .idle
    @Published var translationStatusMessage: String?
    @Published var translationOverlayMode: TranslationOverlayMode = .hover {
        didSet {
            guard !isHydratingToolState else { return }
            prefs.translationOverlayMode = translationOverlayMode
        }
    }
    @Published var selectedTranslationTarget: TranslationLanguageOption = .english {
        didSet {
            guard !isHydratingToolState else { return }
            hasCustomizedTranslationTarget = true
            prefs.translationLastUsedTargetLanguage = selectedTranslationTarget
        }
    }
    @Published var selectedTranslationSegmentID: UUID?
    @Published var pendingTranslationRequest: TranslationRequestToken?

    private(set) var stepCounter: Int = 1
    private var nextZIndex: Int = 1
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var interactionBaseline: Snapshot?
    private let maxHistoryDepth = 200

    /// Max pixel dimension for the display-resolution image kept in memory.
    /// Images smaller than this are kept as-is (e.g., snaps).
    private static let displayMaxDimension: CGFloat = 2880

    init(
        baseImage: NSImage,
        sourceURL: URL? = nil,
        context: EditorToolContext = .fullEditor,
        prefs: AppPreferences = .shared
    ) {
        self.prefs = prefs
        self.context = context
        self.sourceImageURL = sourceURL
        let initialFullRes = sourceURL.flatMap { NSImage(contentsOf: $0) } ?? baseImage
        self.originalImageSize = initialFullRes.size
        self.workingFullResImage = initialFullRes
        self.baseImage = Self.downsampleForDisplay(initialFullRes)

        applyPersistedToolState()
    }

    #if DEBUG
    deinit {
        print("[EditorDocument] deinit")
    }
    #endif

    private func applyPersistedToolState() {
        isHydratingToolState = true
        let state = prefs.editorToolState.sanitized()
        selectedTool = state.resolvedSelectedToolRaw(for: context).flatMap(EditorTool.init(rawValue:))
        strokeColor = state.strokeColor.color
        fillColor = state.fillColor.color
        lineWidth = CGFloat(state.lineWidth)
        preferredTextFontSize = CGFloat(state.textFontSize)
        preferredTextBoxWidth = CGFloat(state.textBoxWidth)
        preferredMosaicBlockSize = CGFloat(state.mosaicBlockSize)
        selectedSticker = state.selectedSticker
        selectedFormat = state.exportFormat
        jpegQuality = state.jpegQuality
        translationOverlayMode = prefs.translationOverlayMode
        selectedTranslationTarget = resolvedPreferredTranslationTarget(sourceLanguageCode: nil)
        isHydratingToolState = false
        hasCustomizedTranslationTarget = false
    }

    private func persistSelectedToolPreference() {
        let selectedRaw = selectedTool?.rawValue
        prefs.updateEditorToolState { state in
            state.selectedToolRaw = selectedRaw
            state.recordToolSelection(rawValue: selectedRaw)
        }
    }

    private func persistStylePreferences() {
        let stroke = CodableColor(color: strokeColor)
        let fill = CodableColor(color: fillColor)
        let line = Double(lineWidth)
        let font = Double(preferredTextFontSize)
        let textBoxWidth = Double(preferredTextBoxWidth)
        let mosaic = Double(preferredMosaicBlockSize)
        let sticker = selectedSticker
        prefs.updateEditorToolState { state in
            state.strokeColor = stroke
            state.fillColor = fill
            state.lineWidth = line
            state.textFontSize = font
            state.textBoxWidth = textBoxWidth
            state.mosaicBlockSize = mosaic
            state.selectedSticker = sticker
        }
    }

    private func persistExportPreferences() {
        let format = selectedFormat
        let quality = jpegQuality
        prefs.updateEditorToolState { state in
            state.exportFormat = format
            state.jpegQuality = quality
        }
    }

    var imageWidth: CGFloat { originalImageSize.width }
    var imageHeight: CGFloat { originalImageSize.height }

    /// Load the full-resolution working image for this editing session.
    func restoreRelayAnnotations(_ saved: [EditorAnnotation]) {
        annotations = saved
        nextZIndex = (saved.map(\.zIndex).max() ?? 0) + 1
        stepCounter = saved.filter { $0.kind == .step }.count + 1
    }
    func loadFullResImage() -> NSImage {
        return workingFullResImage
    }

    private static func downsampleForDisplay(_ image: NSImage) -> NSImage {
        let w = image.size.width, h = image.size.height
        guard max(w, h) > displayMaxDimension * 1.5 else { return image }
        let scale = displayMaxDimension / max(w, h)
        let newW = round(w * scale), newH = round(h * scale)
        let newSize = NSSize(width: newW, height: newH)
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelW = Int(newW * screenScale), pixelH = Int(newH * screenScale)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(
                  data: nil, width: pixelW, height: pixelH,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        guard let downsampled = ctx.makeImage() else { return image }
        return NSImage(cgImage: downsampled, size: newSize)
    }

    var visibleAnnotations: [EditorAnnotation] {
        annotations.filter { !$0.isHidden }.sorted { $0.zIndex < $1.zIndex }
    }

    var hasTranslationResults: Bool {
        !translationSegments.isEmpty
    }

    var isTranslationRunning: Bool {
        translationState == .extractingText || translationState == .translating
    }

    var translationSourceLanguageLabel: String {
        guard let code = recognizedTextDocument?.dominantLanguageCode else {
            return L10n.notSet
        }
        return localizedLanguageName(for: code)
    }

    var selectedAnnotations: [EditorAnnotation] {
        annotations.filter { selectedAnnotationIDs.contains($0.id) }
    }

    var primarySelectedAnnotation: EditorAnnotation? {
        guard let id = selectedAnnotationIDs.first else { return nil }
        return annotations.first(where: { $0.id == id })
    }

    func toggleTool(_ tool: EditorTool) {
        selectedTool = selectedTool == tool ? nil : tool
    }

    func setZoomScale(_ value: CGFloat) {
        zoomScale = max(0.1, min(8.0, value))
    }

    func zoomIn() {
        setZoomScale(zoomScale * 1.2)
    }

    func zoomOut() {
        setZoomScale(zoomScale / 1.2)
    }

    func actualSize() {
        setZoomScale(1.0)
    }

    func fitToWindow(viewport: CGSize) {
        guard imageWidth > 0, imageHeight > 0, viewport.width > 0, viewport.height > 0 else { return }
        let horizontal = viewport.width / imageWidth
        let vertical = viewport.height / imageHeight
        setZoomScale(min(horizontal, vertical))
    }

    func performOCR() {
        guard !isOCRRunning else { return }
        isOCRRunning = true
        ocrText = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.isOCRRunning = false }
            do {
                let document = try await self.extractRecognizedTextDocument(forceRefresh: true)
                self.ocrText = document.fullText
            } catch {
                self.ocrText = nil
            }
        }
    }

    func beginTranslation(forceRefresh: Bool = false) {
        guard !isTranslationRunning else { return }
        translationStatusMessage = nil
        selectedTranslationSegmentID = nil

        Task { [weak self] in
            guard let self else { return }

            guard #available(macOS 15.0, *) else {
                self.translationState = .unsupported
                self.translationStatusMessage = L10n.translationUnsupportedSystem
                return
            }

            do {
                if forceRefresh || self.recognizedTextDocument == nil {
                    self.translationState = .extractingText
                    self.translationStatusMessage = L10n.translationRunningOCR
                }
                let document = try await self.extractRecognizedTextDocument(forceRefresh: forceRefresh)
                guard document.hasContent else {
                    self.translationSegments = []
                    self.translationState = .failed
                    self.translationStatusMessage = L10n.translationNoText
                    self.pendingTranslationRequest = nil
                    return
                }

                self.applySuggestedTranslationTargetIfNeeded(sourceLanguageCode: document.dominantLanguageCode)

                if !forceRefresh,
                   let payload = self.cachedTranslationPayload(for: self.selectedTranslationTarget) {
                    self.recognizedTextDocument = payload.ocrDocument
                    self.ocrText = payload.ocrDocument.fullText
                    self.translationSegments = payload.segments
                    self.translationState = .ready
                    self.translationStatusMessage = L10n.translationReady
                    return
                }

                let availability = try await self.translationAvailabilityStatus(
                    for: document,
                    target: self.selectedTranslationTarget
                )
                guard availability == .installed || availability == .supported else {
                    self.translationSegments = []
                    self.translationState = .unsupported
                    self.translationStatusMessage = L10n.translationUnsupportedPair
                    self.pendingTranslationRequest = nil
                    return
                }

                self.translationSegments = []
                self.translationState = .translating
                self.translationStatusMessage = L10n.translating
                self.pendingTranslationRequest = TranslationRequestToken(
                    id: UUID(),
                    sourceLanguageCode: document.dominantLanguageCode,
                    targetLanguageCode: self.selectedTranslationTarget.rawValue
                )
            } catch {
                self.translationSegments = []
                self.translationState = .failed
                self.translationStatusMessage = self.translationFailureMessage(for: error)
                self.pendingTranslationRequest = nil
            }
        }
    }

    func copyTranslationToPasteboard() {
        let text = translationSegments
            .map(\.translatedText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func selectTranslationSegment(_ id: UUID?) {
        selectedTranslationSegmentID = id
    }

    // MARK: - Subject Extraction

    func extractSubject() {
        guard !isRelayDocument else { return }
        guard !isExtractingSubject else { return }
        isExtractingSubject = true
        let source = loadFullResImage()
        Task {
            do {
                let extracted = try await SubjectExtractor.extractSubject(from: source)
                if originalBaseImage == nil { originalBaseImage = source }
                workingFullResImage = extracted
                baseImage = Self.downsampleForDisplay(extracted)
                invalidateDerivedTextArtifacts()
            } catch {
                // No-op: spinner stops, image unchanged
            }
            isExtractingSubject = false
        }
    }

    func restoreOriginalImage() {
        guard !isRelayDocument else { return }
        guard let original = originalBaseImage else { return }
        workingFullResImage = original
        baseImage = Self.downsampleForDisplay(original)
        originalBaseImage = nil
        invalidateDerivedTextArtifacts()
    }

    var hasExtractedSubject: Bool { originalBaseImage != nil }

    func beginAnnotation(at point: CGPoint) {
        guard let tool = selectedTool, let kind = kindForTool(tool) else { return }
        let style = resolvedStyle(for: kind)

        beginInteractionChangeIfNeeded()

        let z = nextZIndex
        nextZIndex += 1

        switch kind {
        case .text:
            let id = UUID()
            let margin: CGFloat = 8
            let availableWidth = max(
                EditorAnnotation.textBoxWidthRange.lowerBound,
                imageWidth - point.x - margin
            )
            let effectiveTextBoxWidth = min(preferredTextBoxWidth, availableWidth)
            annotations.append(EditorAnnotation(
                id: id,
                kind: .text,
                start: point,
                end: point,
                text: "",
                color: style.stroke,
                lineWidth: lineWidth,
                fillColor: style.fill,
                zIndex: z,
                fontSize: preferredTextFontSize,
                textBoxWidth: effectiveTextBoxWidth
            ))
            selectedAnnotationIDs = [id]
            editingTextID = id
            finalizeInteractionChange()
        case .step:
            let id = UUID()
            annotations.append(EditorAnnotation(
                id: id,
                kind: .step,
                start: point,
                end: point,
                text: "\(stepCounter)",
                color: style.stroke,
                lineWidth: lineWidth,
                fillColor: style.fill,
                zIndex: z
            ))
            stepCounter += 1
            selectedAnnotationIDs = [id]
            finalizeInteractionChange()
            selectedTool = nil
        case .sticker:
            let id = UUID()
            annotations.append(EditorAnnotation(
                id: id,
                kind: .sticker,
                start: point,
                end: CGPoint(x: point.x + 56, y: point.y + 56),
                text: selectedSticker,
                color: style.stroke,
                lineWidth: lineWidth,
                fillColor: style.fill,
                zIndex: z,
                fontSize: preferredTextFontSize
            ))
            selectedAnnotationIDs = [id]
            finalizeInteractionChange()
            selectedTool = nil
        case .freehand:
            draftAnnotation = EditorAnnotation(
                kind: .freehand,
                start: point,
                end: point,
                points: [point],
                text: nil,
                color: style.stroke,
                lineWidth: lineWidth,
                fillColor: style.fill,
                zIndex: z
            )
        case .rectangle, .ellipse, .line, .arrow, .mosaic, .highlight:
            draftAnnotation = EditorAnnotation(
                kind: kind,
                start: point,
                end: point,
                points: [],
                text: nil,
                color: style.stroke,
                lineWidth: lineWidth,
                fillColor: style.fill,
                zIndex: z,
                mosaicBlockSize: preferredMosaicBlockSize
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

    func undo() {
        if hasExtractedSubject {
            restoreOriginalImage()
            return
        }
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(from: previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(from: next)
    }

    func clearSelectionLikeEscape() {
        cancelDraft()
        selectedAnnotationIDs = []
        editingTextID = nil
    }

    func clearSelection() {
        selectedAnnotationIDs = []
        editingTextID = nil
    }

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

    func deleteEditingTextIfEmpty() -> Bool {
        guard let id = editingTextID else { return false }
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        guard annotations[index].kind == .text else { return false }
        let content = (annotations[index].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty else { return false }

        pushUndoSnapshot()
        annotations.remove(at: index)
        selectedAnnotationIDs.remove(id)
        editingTextID = nil
        return true
    }

    func selectAnnotation(at point: CGPoint, additive: Bool = false) {
        guard let id = hitTest(at: point) else {
            if !additive {
                clearSelection()
            }
            return
        }

        if additive {
            if selectedAnnotationIDs.contains(id) {
                selectedAnnotationIDs.remove(id)
            } else {
                selectedAnnotationIDs.insert(id)
            }
        } else {
            selectedAnnotationIDs = [id]
        }
    }

    func activateToolForAnnotationIfSelectionMode(_ id: UUID) {
        guard selectedTool == nil else { return }
        guard let annotation = annotations.first(where: { $0.id == id }) else { return }
        guard let tool = toolForKind(annotation.kind) else { return }
        selectedTool = tool
    }

    func moveSelection(by delta: CGSize) {
        guard delta != .zero else { return }
        beginInteractionChangeIfNeeded()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            guard !annotations[index].isLocked else { continue }
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

    func resizePrimarySelection(to point: CGPoint) {
        guard let id = selectedAnnotationIDs.first else { return }
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard !annotations[index].isLocked else { return }
        beginInteractionChangeIfNeeded()
        annotations[index].end = point
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

    func reorder(_ id: UUID, direction: LayerMoveDirection) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        let original = annotations[index].zIndex
        let target = direction == .up ? original + 1 : max(0, original - 1)
        guard let swapIndex = annotations.firstIndex(where: { $0.zIndex == target }) else {
            annotations[index].zIndex = target
            return
        }
        annotations[index].zIndex = target
        annotations[swapIndex].zIndex = original
    }

    func toggleLock(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        annotations[index].isLocked.toggle()
    }

    func toggleVisibility(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        annotations[index].isHidden.toggle()
    }

    func deleteSelection() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        annotations.removeAll { selectedAnnotationIDs.contains($0.id) }
        selectedAnnotationIDs = []
        editingTextID = nil
    }

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

    func updateSelectedFillColor(_ color: Color) {
        if !selectedAnnotationIDs.isEmpty {
            pushUndoSnapshot()
        }
        fillColor = color
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].fillColor = color
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
        preferredTextFontSize = clamped
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].fontSize = clamped
        }
    }

    func updateSelectedTextBoxWidth(_ width: CGFloat) {
        let clamped = EditorAnnotation.clampTextBoxWidth(width)
        preferredTextBoxWidth = clamped
        guard !selectedAnnotationIDs.isEmpty else { return }
        let targetIDs = selectedAnnotationIDs.filter { id in
            annotations.first(where: { $0.id == id })?.kind == .text
        }
        guard !targetIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in targetIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].textBoxWidth = clamped
        }
    }

    func updateSelectedMosaicBlockSize(_ size: CGFloat) {
        let clamped = min(max(size, 6), 40)
        preferredMosaicBlockSize = clamped
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].mosaicBlockSize = clamped
        }
    }

    func updateSelectedSticker(_ sticker: String) {
        if !selectedAnnotationIDs.isEmpty {
            pushUndoSnapshot()
        }
        selectedSticker = sticker
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            if annotations[index].kind == .sticker {
                annotations[index].text = sticker
            }
        }
    }

    let stickerLibrary = StickerLibrary.shared

    func addImageSticker(id stickerID: String, at point: CGPoint) {
        beginInteractionChangeIfNeeded()
        let z = nextZIndex
        nextZIndex += 1

        var maxDim: CGFloat = 200
        if let img = stickerLibrary.image(for: stickerID) {
            let w = img.size.width
            let h = img.size.height
            if w <= maxDim && h <= maxDim {
                maxDim = max(w, h)
            }
        }
        let aspect: CGFloat
        if let img = stickerLibrary.image(for: stickerID), img.size.height > 0 {
            aspect = img.size.width / img.size.height
        } else {
            aspect = 1
        }
        let width: CGFloat
        let height: CGFloat
        if aspect >= 1 {
            width = maxDim
            height = maxDim / aspect
        } else {
            height = maxDim
            width = maxDim * aspect
        }

        let id = UUID()
        annotations.append(EditorAnnotation(
            id: id,
            kind: .sticker,
            start: CGPoint(x: point.x - width / 2, y: point.y - height / 2),
            end: CGPoint(x: point.x + width / 2, y: point.y + height / 2),
            color: strokeColor,
            lineWidth: lineWidth,
            zIndex: z,
            stickerImageID: stickerID
        ))
        selectedAnnotationIDs = [id]
        stickerLibrary.markUsed(stickerID)
        finalizeInteractionChange()
    }

    func updateSelectedOpacity(_ opacity: CGFloat) {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        let clamped = max(0.1, min(1.0, opacity))
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].opacity = clamped
        }
    }

    func flipSelectedHorizontally() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].flipH.toggle()
        }
    }

    func flipSelectedVertically() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].flipV.toggle()
        }
    }

    func toggleSelectedShadow() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedAnnotationIDs {
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { continue }
            annotations[index].hasShadow.toggle()
        }
    }

    func duplicateSelection() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        pushUndoSnapshot()
        var newIDs: Set<UUID> = []
        for id in selectedAnnotationIDs {
            guard let annotation = annotations.first(where: { $0.id == id }) else { continue }
            let z = nextZIndex
            nextZIndex += 1
            let copy = annotation.duplicated(zIndex: z)
            annotations.append(copy)
            newIDs.insert(copy.id)
        }
        selectedAnnotationIDs = newIDs
    }

    func resizePrimarySelection(to point: CGPoint, corner: ResizeCorner) {
        guard let id = selectedAnnotationIDs.first else { return }
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard !annotations[index].isLocked else { return }
        beginInteractionChangeIfNeeded()

        let isImageSticker = annotations[index].stickerImageID != nil
        let minDim: CGFloat = 24

        if isImageSticker {
            let current = annotations[index].bounds
            guard current.width > 0, current.height > 0 else { return }
            let aspect = current.width / current.height

            var anchor: CGPoint
            let target = point
            switch corner {
            case .topLeft:     anchor = CGPoint(x: current.maxX, y: current.maxY)
            case .topRight:    anchor = CGPoint(x: current.minX, y: current.maxY)
            case .bottomLeft:  anchor = CGPoint(x: current.maxX, y: current.minY)
            case .bottomRight: anchor = CGPoint(x: current.minX, y: current.minY)
            case .endpointStart, .endpointEnd: return
            }

            var newWidth = abs(target.x - anchor.x)
            var newHeight = abs(target.y - anchor.y)
            if newWidth / aspect > newHeight {
                newHeight = newWidth / aspect
            } else {
                newWidth = newHeight * aspect
            }
            newWidth = max(minDim, newWidth)
            newHeight = max(minDim, newHeight)

            let newStart: CGPoint
            let newEnd: CGPoint
            switch corner {
            case .topLeft:
                newEnd = anchor
                newStart = CGPoint(x: anchor.x - newWidth, y: anchor.y - newHeight)
            case .topRight:
                newStart = CGPoint(x: anchor.x, y: anchor.y - newHeight)
                newEnd = CGPoint(x: anchor.x + newWidth, y: anchor.y)
            case .bottomLeft:
                newStart = CGPoint(x: anchor.x - newWidth, y: anchor.y)
                newEnd = CGPoint(x: anchor.x, y: anchor.y + newHeight)
            case .bottomRight:
                newStart = anchor
                newEnd = CGPoint(x: anchor.x + newWidth, y: anchor.y + newHeight)
            case .endpointStart, .endpointEnd:
                return
            }
            annotations[index].start = newStart
            annotations[index].end = newEnd
        } else {
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
    }

    func rotatePrimarySelection(angle: CGFloat) {
        guard let id = selectedAnnotationIDs.first else { return }
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard !annotations[index].isLocked else { return }
        beginInteractionChangeIfNeeded()
        annotations[index].rotation = angle
    }

    func hitTest(at point: CGPoint) -> UUID? {
        let ordered = visibleAnnotations.reversed()
        for annotation in ordered {
            if annotation.isLocked { continue }
            if annotation.kind == .line || annotation.kind == .arrow {
                if distanceToSegment(point: point, a: annotation.start, b: annotation.end) <= max(8, annotation.lineWidth + 3) {
                    return annotation.id
                }
                continue
            }
            let bounds = annotation.bounds
            if annotation.rotation != 0 {
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                let cosA = cos(-annotation.rotation)
                let sinA = sin(-annotation.rotation)
                let dx = point.x - center.x
                let dy = point.y - center.y
                let localPoint = CGPoint(
                    x: center.x + dx * cosA - dy * sinA,
                    y: center.y + dx * sinA + dy * cosA
                )
                if bounds.insetBy(dx: -6, dy: -6).contains(localPoint) {
                    return annotation.id
                }
            } else {
                if bounds.insetBy(dx: -6, dy: -6).contains(point) {
                    return annotation.id
                }
            }
        }
        return nil
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

    private func kindForTool(_ tool: EditorTool) -> EditorAnnotationKind? {
        switch tool {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .pencil: return .freehand
        case .mosaic: return .mosaic
        case .text: return .text
        case .step: return .step
        case .highlight: return .highlight
        case .sticker: return .sticker
        }
    }

    private func toolForKind(_ kind: EditorAnnotationKind) -> EditorTool? {
        switch kind {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .freehand: return .pencil
        case .mosaic: return .mosaic
        case .text: return .text
        case .step: return .step
        case .highlight: return .highlight
        case .sticker: return .sticker
        }
    }

    private func isDraftMeaningful(_ draft: EditorAnnotation) -> Bool {
        let minLinearSpan: CGFloat = 2
        switch draft.kind {
        case .rectangle, .ellipse, .line, .arrow, .mosaic, .highlight:
            let dx = abs(draft.end.x - draft.start.x)
            let dy = abs(draft.end.y - draft.start.y)
            return max(dx, dy) >= minLinearSpan
        case .freehand:
            return freehandPathLength(draft.points) >= minLinearSpan
        default:
            return true
        }
    }

    private func freehandPathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var length: CGFloat = 0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            length += hypot(current.x - previous.x, current.y - previous.y)
        }
        return length
    }

    private func resolvedStyle(for kind: EditorAnnotationKind) -> (stroke: Color, fill: Color) {
        switch kind {
        case .highlight:
            if usesDefaultAnnotationStyle {
                return (EditorTheme.defaultAnnotationStroke, Color.clear)
            }
            return (strokeColor, fillColor)
        default:
            return (strokeColor, fillColor)
        }
    }

    private var usesDefaultAnnotationStyle: Bool {
        let stroke = CodableColor(color: strokeColor)
        let fill = CodableColor(color: fillColor)
        return stroke.approximatelyEquals(EditorToolState.defaultStrokeColor) &&
            fill.approximatelyEquals(EditorToolState.defaultFillColor)
    }

    private func extractRecognizedTextDocument(forceRefresh: Bool) async throws -> RecognizedTextDocument {
        if !forceRefresh, let existing = recognizedTextDocument, existing.hasContent {
            return existing
        }

        let fullRes = loadFullResImage()
        guard let cgImage = fullRes.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "Picelf.Translation", code: -1, userInfo: [
                NSLocalizedDescriptionKey: L10n.translationFailed
            ])
        }

        let document = try await TextRecognizer.recognizeDocument(image: cgImage)
        recognizedTextDocument = document
        ocrText = document.fullText
        return document
    }

    private func cachedTranslationPayload(for target: TranslationLanguageOption) -> TranslationCachePayload? {
        guard let imageHash = translationImageHash() else { return nil }
        return TranslationCacheStore.load(imageHash: imageHash, targetLanguageCode: target.rawValue)
    }

    private func translationImageHash() -> String? {
        if let cachedTranslationImageHash {
            return cachedTranslationImageHash
        }
        guard let data = translationImageData() else { return nil }
        let hash = TranslationCacheStore.imageHash(for: data)
        cachedTranslationImageHash = hash
        return hash
    }

    private func translationImageData() -> Data? {
        if originalBaseImage == nil,
           let sourceImageURL,
           let data = try? Data(contentsOf: sourceImageURL) {
            return data
        }
        return loadFullResImage().tiffRepresentation
    }

    private func invalidateDerivedTextArtifacts() {
        cachedTranslationImageHash = nil
        recognizedTextDocument = nil
        ocrText = nil
        translationSegments = []
        translationState = .idle
        translationStatusMessage = nil
        selectedTranslationSegmentID = nil
        pendingTranslationRequest = nil
    }

    private func applySuggestedTranslationTargetIfNeeded(sourceLanguageCode: String?) {
        guard !hasCustomizedTranslationTarget else { return }
        let suggested = resolvedPreferredTranslationTarget(sourceLanguageCode: sourceLanguageCode)
        guard suggested != selectedTranslationTarget else { return }
        isHydratingToolState = true
        selectedTranslationTarget = suggested
        isHydratingToolState = false
        hasCustomizedTranslationTarget = false
    }

    private func resolvedPreferredTranslationTarget(sourceLanguageCode: String?) -> TranslationLanguageOption {
        let sourceLanguage = sourceLanguageCode.map(TranslationLanguageOption.normalized(raw:))
        let preferred: TranslationLanguageOption
        switch prefs.translationTargetPreference {
        case .followAppLanguage:
            preferred = TranslationLanguageOption.defaultForAppLanguage(
                AppLanguageOption.normalized(raw: prefs.appLanguage)
            )
        case .english:
            preferred = .english
        case .chineseSimplified:
            preferred = .chineseSimplified
        case .lastUsed:
            preferred = prefs.translationLastUsedTargetLanguage
        }

        guard let sourceLanguage, sourceLanguage == preferred else {
            return preferred
        }
        return TranslationLanguageOption.fallbackOpposite(for: sourceLanguage)
    }

    private func localizedLanguageName(for code: String) -> String {
        TranslationLanguageOption.normalized(raw: code).localizedName
    }

    private func translationFailureMessage(for error: Error) -> String {
        #if canImport(Translation)
        if #available(macOS 15.0, *), TranslationError.unsupportedLanguagePairing ~= error {
            return L10n.translationUnsupportedPair
        }
        if #available(macOS 15.0, *), TranslationError.unsupportedTargetLanguage ~= error {
            return L10n.translationUnsupportedPair
        }
        if #available(macOS 15.0, *), TranslationError.unsupportedSourceLanguage ~= error {
            return L10n.translationUnsupportedPair
        }
        if #available(macOS 15.0, *), TranslationError.nothingToTranslate ~= error {
            return L10n.translationNoText
        }
        #endif
        return error.localizedDescription.isEmpty ? L10n.translationFailed : error.localizedDescription
    }

#if canImport(Translation)
    @available(macOS 15.0, *)
    private func translationAvailabilityStatus(
        for document: RecognizedTextDocument,
        target: TranslationLanguageOption
    ) async throws -> LanguageAvailability.Status {
        let availability = LanguageAvailability()
        if let sourceCode = document.dominantLanguageCode {
            return await availability.status(
                from: Locale.Language(identifier: sourceCode),
                to: target.localeLanguage
            )
        }
        return try await availability.status(for: document.fullText, to: target.localeLanguage)
    }

    @available(macOS 15.0, *)
    func handleTranslationSession(_ session: TranslationSession, request: TranslationRequestToken) async {
        guard pendingTranslationRequest == request,
              let document = recognizedTextDocument else { return }

        do {
            try await session.prepareTranslation()

            let batch = document.blocks.map {
                TranslationSession.Request(
                    sourceText: $0.text,
                    clientIdentifier: $0.id.uuidString
                )
            }
            let responses = try await session.translations(from: batch)
            guard pendingTranslationRequest == request else { return }

            var responsesByIdentifier: [UUID: TranslationSession.Response] = [:]
            responses.forEach { response in
                guard let rawIdentifier = response.clientIdentifier,
                      let uuid = UUID(uuidString: rawIdentifier) else {
                    return
                }
                responsesByIdentifier[uuid] = response
            }

            let segments = document.blocks.enumerated().compactMap { index, block -> TranslationSegment? in
                let response = responsesByIdentifier[block.id] ?? (index < responses.count ? responses[index] : nil)
                guard let response else { return nil }
                let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translatedText.isEmpty else { return nil }
                return TranslationSegment(
                    id: block.id,
                    sourceText: block.text,
                    translatedText: translatedText,
                    normalizedBounds: block.normalizedBounds,
                    sourceLanguageCode: block.dominantLanguageCode ?? response.sourceLanguage.languageCode?.identifier,
                    targetLanguageCode: response.targetLanguage.maximalIdentifier
                )
            }

            translationSegments = segments
            translationState = .ready
            translationStatusMessage = L10n.translationReady
            pendingTranslationRequest = nil

            if let imageHash = translationImageHash() {
                TranslationCacheStore.store(
                    TranslationCachePayload(
                        imageHash: imageHash,
                        targetLanguageCode: selectedTranslationTarget.rawValue,
                        ocrDocument: document,
                        segments: segments
                    )
                )
            }
        } catch {
            guard pendingTranslationRequest == request else { return }
            translationSegments = []
            translationState = .failed
            translationStatusMessage = translationFailureMessage(for: error)
            pendingTranslationRequest = nil
        }
    }
#endif

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
        interactionBaseline = nil
    }
}
