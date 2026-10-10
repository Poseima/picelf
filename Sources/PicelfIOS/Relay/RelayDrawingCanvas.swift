import SwiftUI
import UIKit
import PencilKit
import Combine

final class RelayPencilCanvasView: PKCanvasView {
    let documentUndoManager = UndoManager()
    override var undoManager: UndoManager? { documentUndoManager }
}

@MainActor
final class RelayDrawingModel: ObservableObject {
    let taskID: UUID
    let baseImage: UIImage
    @Published var macBackground: UIImage?
    private var remoteBytes: Data?
    private var observation: AnyCancellable?
    private var lastChange = Date.distantPast
    private var lastCommittedRevision = -1
    private var sharedEncoding = false
    private var visible = true
    let pixelSize: CGSize
    let hub: RelayCoordinator
    let canvas = RelayPencilCanvasView()
    @Published var revision: Int
    @Published var busy = false
    @Published var fingerDrawing = UserDefaults.standard.bool(forKey: "relay.fingerDrawing") {
        didSet {
            canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
            UserDefaults.standard.set(fingerDrawing, forKey: "relay.fingerDrawing")
        }
    }
    @Published var texts = RelayTextDocument()
    @Published var textMode = false
    @Published var selectedTextID: UUID?
    @Published var editingTextID: UUID?
    @Published var textInsertionArmed = false
    @Published var hasMarkedText = false
    var finishTextInput: (() -> Void)?
    var textUndo: (() -> Void)?
    var textRedo: (() -> Void)?
    var textUndoState: (() -> (Bool, Bool))?
    var documentUndo: UndoManager { canvas.documentUndoManager }
    var selectedText: RelayTextBox? { texts.boxes.first { $0.id == selectedTextID } }
    func chooseText() {
        finishTextInput?()
        if hub.collaboration.isLive(taskID), hub.transport.connected, !hub.collaboration.peerSupportsText {
            hub.errorMessage = L10n.localized("请更新 Mac 后使用文字共同编辑；当前画作已保留。", "Update the Mac app to share editable text. Your current work was saved."); return
        }
        textMode = true; textInsertionArmed = true; selectedTextID = nil
        setToolsActive?(true)
    }
    func chooseDrawing() {
        finishTextInput?(); editingTextID = nil; selectedTextID = nil
        textMode = false; textInsertionArmed = false; setToolsActive?(true); updateUndoState()
    }
    func addText(at point: CGPoint, zoom: CGFloat) {
        guard texts.boxes.count < 200 else { hub.errorMessage = L10n.localized("每张图最多添加 200 个文本框。", "Each image can contain up to 200 text boxes."); return }
        do { try hub.collaboration.requireText(taskID) } catch { hub.errorMessage = error.localizedDescription; return }
        let font = min(512, max(8, 24 / max(zoom, 0.01)))
        let width = min(pixelSize.width, max(160, 260 / max(zoom, 0.01)))
        let box = RelayTextBox(x: max(0, min(point.x, pixelSize.width - width)),
                               y: max(0, min(point.y, pixelSize.height - font * 2)), width: width, fontSize: font)
        let previous = texts
        texts.boxes.append(box); textInsertionArmed = false; selectedTextID = box.id; editingTextID = box.id
        // New empty boxes are temporary. The host groups creation and typing.
        pendingTextBaseline = previous
    }
    var pendingTextBaseline: RelayTextDocument?
    func replaceTexts(_ value: RelayTextDocument, undo: Bool = true) {
        guard value != texts else { return }
        let previous = texts
        texts = value
        if undo { registerTextUndo(previous) }
        changed()
    }
    func registerTextUndo(_ previous: RelayTextDocument) {
        guard previous != texts else { return }
        documentUndo.registerUndo(withTarget: self) { target in target.replaceTexts(previous) }
        documentUndo.setActionName(L10n.localized("文字标注", "Text Annotation")); updateUndoState()
    }
    func updateTextBox(_ id: UUID, undo: Bool = true, _ change: (inout RelayTextBox) -> Void) {
        var value = texts
        guard let index = value.boxes.firstIndex(where: { $0.id == id }) else { return }
        change(&value.boxes[index]); replaceTexts(value, undo: undo)
    }
    func deleteSelectedText() {
        finishTextInput?()
        guard let id = selectedTextID else { return }
        var value = texts; value.boxes.removeAll { $0.id == id }
        replaceTexts(value); selectedTextID = nil
    }
    func updateUndoState() {
        if editingTextID != nil, let state = textUndoState?() { canUndo = state.0; canRedo = state.1 }
        else { canUndo = documentUndo.canUndo; canRedo = documentUndo.canRedo }
    }
    @Published var canUndo = false
    @Published var canRedo = false
    var fitCanvas: (() -> Void)?
    var setToolsActive: ((Bool) -> Void)?
    func suspendTools() { setToolsActive?(false) }
    private var saveWork: Task<Void, Never>?
    private var previewWork: Task<Void, Never>?
    private var generatingPreview = false
    private var lastPreviewRevision = -1
    private(set) var snapshotMilliseconds: Double = 0

    init(task: RelayTask, hub: RelayCoordinator) throws {
        self.taskID = task.id; self.hub = hub; revision = task.revision
        pixelSize = CGSize(width: task.width, height: task.height)
        guard let image = UIImage(data: try hub.data(task.id, "base.png")) else { throw RelayError.message(L10n.localized("无法打开画布图片。", "Could not open the canvas image.")) }
        baseImage = image
        canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        canvas.overrideUserInterfaceStyle = .light // Ink color must not change with UI appearance.
        if let data = try? hub.data(task.id, "ink.drawing") { canvas.drawing = try PKDrawing(data: data) }
        if let data = try? hub.data(task.id, RelayTextDocument.filename) { texts = try RelayTextDocument.decode(data) }
        hub.collaboration.flushLocal[task.id] = { [weak self] in try await self?.flushShared() }
        observation = hub.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refreshShared() }
        }
        refreshShared()
        resume()
    }
    func changed() {
        guard !busy else { return }
        lastChange = Date(); hub.collaboration.markDirty(taskID)
        revision += 1; updateUndoState()
        saveWork?.cancel()
        saveWork = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
        if previewWork == nil {
            previewWork = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    guard !Task.isCancelled, let self else { return }
                    await self.publishPreview()
                    await self.publishSharedIfIdle()
                }
            }
        }
    }
    @discardableResult
    func flush() -> Bool {
        saveWork?.cancel()
        do { try hub.saveDrawing(taskID, ink: canvas.drawing.dataRepresentation(), revision: revision, padText: try texts.encoded()); return true }
        catch { hub.errorMessage = L10n.localized("草稿保存失败：\(error.localizedDescription)", "Could not save draft: \(error.localizedDescription)"); return false }
    }
    func resume() {
        visible = true
        setToolsActive?(true)
        // A reconnect needs a fresh preview even when no new stroke is added.
        lastPreviewRevision = -1
        if previewWork == nil { startPreviewLoop() }
    }
    private func startPreviewLoop() {
        previewWork = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.publishPreview()
                await self.publishSharedIfIdle()
            }
        }
    }
    func pause() {
        finishTextInput?()
        visible = false
        suspendTools()
        flush(); previewWork?.cancel(); previewWork = nil
        if hub.collaboration.isLive(taskID) { Task { do { try await flushShared() } catch { hub.errorMessage = error.localizedDescription } } }
    }
    func publishPreview() async {
        guard !hasMarkedText, !generatingPreview, !sharedEncoding, !busy, revision != lastPreviewRevision, hub.canSendPreview(taskID),
              let task = hub.task(taskID), task.state == .editing || task.state == .queued else { return }
        generatingPreview = true
        defer { generatingPreview = false }
        let version = revision
        let drawing = canvas.drawing
        var scale = min(1, 2048 / max(pixelSize.width, pixelSize.height))
        for _ in 0..<3 {
            guard !Task.isCancelled, !busy else { return }
            guard let data = try? await encoded(drawing: drawing, scale: scale, includeBase: !hub.collaboration.isLive(taskID)) else { return }
            guard !Task.isCancelled, !busy else { return }
            if data.count <= RelayLimits.maxPreviewBytes {
                if hub.collaboration.isLive(taskID) { hub.collaboration.preview(taskID, revision: version, image: data) }
                else { hub.sendPreview(taskID, revision: version, png: data) }
                lastPreviewRevision = version
                return
            }
            scale *= 0.65
        }
    }
    // PencilKit snapshot stays on its owning actor. Bitmap composition and PNG
    // compression use immutable CGImages and never touch the live canvas.
    func encoded(drawing: PKDrawing, scale: CGFloat = 1, includeBase: Bool = true) async throws -> Data {
        let snapshotStart = CACurrentMediaTime()
        guard let base = baseImage.cgImage,
              let ink = drawing.image(from: CGRect(origin: .zero, size: pixelSize), scale: scale).cgImage else {
            throw RelayError.message(L10n.localized("图片导出失败。", "Image export failed."))
        }
        let textImage = texts.boxes.isEmpty ? nil : RelayTextLayout.image(texts, size: pixelSize, scale: scale).cgImage
        snapshotMilliseconds = (CACurrentMediaTime() - snapshotStart) * 1000
        let width = max(1, Int((pixelSize.width * scale).rounded()))
        let height = max(1, Int((pixelSize.height * scale).rounded()))
        return try await Task.detached(priority: .userInitiated) {
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw RelayError.message(L10n.localized("无法准备画布图片。", "Could not prepare the canvas image."))
            }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if includeBase { context.draw(base, in: rect) }; context.draw(ink, in: rect)
            if let textImage { context.draw(textImage, in: rect) }
            guard let result = context.makeImage() else { throw RelayError.message(L10n.localized("图片导出失败。", "Image export failed.")) }
            return try RelayImage.png(result)
        }.value
    }
    func render(scale: CGFloat = 1) -> UIImage {
        let rect = CGRect(origin: .zero, size: pixelSize)
        let ink = canvas.drawing.image(from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = false
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            baseImage.draw(in: rect)
            ink.draw(in: rect)
            RelayTextLayout.draw(texts)
        }
    }
    func refreshShared() {
        let bytes = hub.collaboration.layerPreviews[taskID] ?? hub.collaboration.layerData(taskID, role: .mac)
        if bytes != remoteBytes { remoteBytes = bytes; macBackground = bytes.flatMap(UIImage.init(data:)) }
        if visible, hub.collaboration.isLive(taskID), previewWork == nil { resume() }
    }
    private func publishSharedIfIdle() async {
        guard !hasMarkedText, hub.collaboration.isLive(taskID), Date().timeIntervalSince(lastChange) >= 0.8,
              revision != lastCommittedRevision, !sharedEncoding else { return }
        do { try await flushShared() } catch { hub.errorMessage = L10n.localized("自动保存失败：\(error.localizedDescription)", "Auto-save failed: \(error.localizedDescription)") }
    }
    func flushShared() async throws {
        guard hub.collaboration.isLive(taskID) else { return }
        if hub.collaboration.session(taskID)?.closing == true { finishTextInput?() }
        guard !hasMarkedText else { throw RelayError.message(L10n.localized("请先确认正在输入的文字，再结束共同编辑。", "Finish entering text before ending the shared edit.")) }
        while sharedEncoding || generatingPreview { try await Task.sleep(nanoseconds: 20_000_000) }
        guard revision != lastCommittedRevision || hub.collaboration.session(taskID)?.pad == nil else { return }
        sharedEncoding = true; defer { sharedEncoding = false }
        guard flush() else { throw RelayError.message(L10n.localized("请重试保存草稿。", "Try saving the draft again.")) }
        let version = revision, drawing = canvas.drawing, textData = try texts.encoded()
        let png = try await encoded(drawing: drawing, includeBase: false)
        guard revision == version else { return }
        try hub.collaboration.commit(taskID, image: png, document: drawing.dataRepresentation(), editRevision: version, padText: textData)
        lastCommittedRevision = version
    }
    func startShared() {
        guard flush() else { return }
        do { try hub.collaboration.start(taskID); lastCommittedRevision = -1; resume() }
        catch { hub.errorMessage = error.localizedDescription }
    }
    func complete() {
        finishTextInput?()
        if hub.collaboration.isLive(taskID) { hub.collaboration.end(taskID); return }
        guard !busy else { return }
        guard flush() else { return }; busy = true
        // Yield once so the progress indicator appears before the full-size render.
        Task { @MainActor in
            await Task.yield()
            do {
                let drawing = canvas.drawing
                let ink = drawing.dataRepresentation()
                let version = revision
                let png = try await encoded(drawing: drawing)
                try hub.complete(taskID, png: png, ink: ink, revision: version, padText: try texts.encoded())
            } catch { hub.errorMessage = error.localizedDescription }
            busy = false
        }
    }
    func undo() { if editingTextID != nil { textUndo?() } else { documentUndo.undo() }; updateUndoState() }
    func redo() { if editingTextID != nil { textRedo?() } else { documentUndo.redo() }; updateUndoState() }
}

struct RelayDrawingCanvas: UIViewRepresentable {
    @ObservedObject var model: RelayDrawingModel
    var editable = true
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> RelayCanvasHost {
        let host = RelayCanvasHost(model: model)
        host.editable = editable
        host.scroll.delegate = context.coordinator
        model.canvas.delegate = context.coordinator
        model.fitCanvas = { [weak host] in host?.fit() }
        context.coordinator.content = host.content
        return host
    }
    func updateUIView(_ uiView: RelayCanvasHost, context: Context) {
        uiView.background.image = model.macBackground ?? model.baseImage
        uiView.scroll.panGestureRecognizer.minimumNumberOfTouches = model.fingerDrawing ? 2 : 1
        model.canvas.isUserInteractionEnabled = editable && !model.busy && !model.textMode
        uiView.editable = editable
        uiView.textOverlay.refresh()
        uiView.updateToolVisibility()
    }
    static func dismantleUIView(_ uiView: RelayCanvasHost, coordinator: Coordinator) {
        uiView.setToolsActive(false)
        uiView.textOverlay.finishEditing()
        uiView.model.pause()
        uiView.model.setToolsActive = nil
        uiView.model.fitCanvas = nil
        uiView.picker.removeObserver(uiView.model.canvas)
    }
    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        let model: RelayDrawingModel
        weak var content: UIView?
        init(model: RelayDrawingModel) { self.model = model }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView.superview as? RelayCanvasHost)?.centerContent()
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { model.changed() }
    }
}
final class RelayCanvasHost: UIView {
    let model: RelayDrawingModel
    let scroll = UIScrollView()
    let content = UIView()
    let picker = PKToolPicker()
    let background = UIImageView()
    lazy var textOverlay = RelayTextOverlay(model: model, host: self)
    var editable = true
    private var toolsActive = true
    var keyboardInset: CGFloat = 0
    private var lastSize = CGSize.zero
    init(model: RelayDrawingModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        scroll.frame = bounds; scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.bouncesZoom = true; scroll.contentInsetAdjustmentBehavior = .never
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addSubview(scroll)
        // Keep drawable coordinates equal to source pixels at every zoom level.
        content.frame = CGRect(origin: .zero, size: model.pixelSize)
        content.backgroundColor = .white
        background.image = model.macBackground ?? model.baseImage
        background.frame = content.bounds; background.contentMode = .scaleToFill
        content.addSubview(background)
        model.canvas.frame = content.bounds
        model.canvas.isScrollEnabled = false
        model.canvas.contentSize = model.pixelSize
        model.canvas.backgroundColor = .clear
        content.addSubview(model.canvas)
        textOverlay.frame = content.bounds
        content.addSubview(textOverlay)
        scroll.addSubview(content); scroll.contentSize = model.pixelSize
        picker.showsDrawingPolicyControls = false
        picker.addObserver(model.canvas)
        model.setToolsActive = { [weak self] active in self?.setToolsActive(active) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateToolVisibility(activateCanvas: true)
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        // Hide while still attached: PencilKit owns a separate palette window.
        if newWindow == nil { hideTools() }
        super.willMove(toWindow: newWindow)
    }
    func setToolsActive(_ active: Bool) {
        toolsActive = active
        updateToolVisibility(activateCanvas: active && !model.textMode)
    }
    func updateToolVisibility(activateCanvas: Bool = false) {
        guard toolsActive, editable, !model.textMode, window != nil else { hideTools(); return }
        picker.setVisible(true, forFirstResponder: model.canvas)
        if activateCanvas && !model.canvas.isFirstResponder { model.canvas.becomeFirstResponder() }
    }
    private func hideTools() {
        picker.setVisible(false, forFirstResponder: model.canvas)
        model.canvas.resignFirstResponder()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastSize else { return }
        let oldSize = lastSize
        let oldCenter = CGPoint(x: (scroll.contentOffset.x + oldSize.width / 2) / scroll.zoomScale,
                                y: (scroll.contentOffset.y + oldSize.height / 2) / scroll.zoomScale)
        lastSize = bounds.size
        if oldSize == .zero { fit(); return }
        // Rotation changes the viewport, not the user's chosen magnification.
        updateLimits()
        centerContent()
        let x = oldCenter.x * scroll.zoomScale - bounds.width / 2
        let y = oldCenter.y * scroll.zoomScale - bounds.height / 2
        scroll.contentOffset = CGPoint(
            x: min(max(x, -scroll.contentInset.left), max(-scroll.contentInset.left, scroll.contentSize.width - bounds.width + scroll.contentInset.right)),
            y: min(max(y, -scroll.contentInset.top), max(-scroll.contentInset.top, scroll.contentSize.height - bounds.height + scroll.contentInset.bottom)))
    }
    private func updateLimits() {
        let scale = min(scroll.bounds.width / model.pixelSize.width, scroll.bounds.height / model.pixelSize.height)
        scroll.minimumZoomScale = min(scroll.zoomScale, scale * 0.5)
        scroll.maximumZoomScale = max(4, scale * 8)
    }
    func centerContent() {
        let horizontal = max(0, (scroll.bounds.width - content.frame.width) / 2)
        let vertical = max(0, (scroll.bounds.height - content.frame.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical + keyboardInset, right: horizontal)
    }
    func fit() {
        let scale = min(scroll.bounds.width / model.pixelSize.width, scroll.bounds.height / model.pixelSize.height)
        guard scale > 0 else { return }
        updateLimits()
        scroll.setZoomScale(scale, animated: false)
        centerContent()
        scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
    }
}
