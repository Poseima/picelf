import SwiftUI
import AppKit

@MainActor
final class CanvasDocument: ObservableObject {
    private struct Snapshot {
        var items: [CanvasItem]
        var selectedItemIDs: Set<UUID>
        var nextZIndex: Int
    }

    private let prefs: AppPreferences
    private var isHydratingExportState = false

    @Published var items: [CanvasItem] = []
    @Published var canvasSize: CGSize = CGSize(width: 1920, height: 1080)
    @Published var background: CanvasBackground = .white
    @Published var zoomScale: CGFloat = 1.0
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var selectedFormat: ImageFormat = .png {
        didSet {
            guard !isHydratingExportState else { return }
            persistExportSettings()
        }
    }
    @Published var jpegQuality: Double = 0.9 {
        didSet {
            guard !isHydratingExportState else { return }
            persistExportSettings()
        }
    }

    private(set) var nextZIndex: Int = 1
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var interactionBaseline: Snapshot?
    private let maxHistoryDepth = 200

    let imageCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 30
        cache.totalCostLimit = 128 * 1024 * 1024  // 128 MB
        return cache
    }()

    init(prefs: AppPreferences = .shared) {
        self.prefs = prefs
        isHydratingExportState = true
        let state = prefs.editorToolState.sanitized()
        selectedFormat = state.exportFormat
        jpegQuality = state.jpegQuality
        isHydratingExportState = false
    }

    #if DEBUG
    deinit {
        print("[CanvasDocument] deinit")
    }
    #endif

    private func persistExportSettings() {
        let format = selectedFormat
        let quality = jpegQuality
        prefs.updateEditorToolState { state in
            state.exportFormat = format
            state.jpegQuality = quality
        }
    }

    // MARK: - Computed Properties

    var visibleItems: [CanvasItem] {
        items.filter { !$0.isHidden }.sorted { $0.zIndex < $1.zIndex }
    }

    var selectedItems: [CanvasItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var primarySelectedItem: CanvasItem? {
        guard let id = selectedItemIDs.first else { return nil }
        return items.first { $0.id == id }
    }

    // MARK: - Zoom

    func setZoomScale(_ value: CGFloat) {
        zoomScale = max(0.05, min(8.0, value))
    }

    func zoomIn() { setZoomScale(zoomScale * 1.2) }
    func zoomOut() { setZoomScale(zoomScale / 1.2) }
    func actualSize() { setZoomScale(1.0) }

    func fitToWindow(viewport: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return }
        let h = viewport.width / canvasSize.width
        let v = viewport.height / canvasSize.height
        setZoomScale(min(h, v) * 0.9)
    }

    // MARK: - Adding Items

    func addImage(_ image: NSImage, kind: CanvasItemKind, positionOffset: CGPoint = .zero) {
        pushUndoSnapshot()
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1.0
        let maxDim = min(canvasSize.width * 0.6, canvasSize.height * 0.6)
        let displaySize: CGSize
        if aspect >= 1 {
            displaySize = CGSize(width: maxDim, height: maxDim / aspect)
        } else {
            displaySize = CGSize(width: maxDim * aspect, height: maxDim)
        }

        let id = UUID()
        let item = CanvasItem(
            id: id,
            kind: kind,
            position: CGPoint(
                x: canvasSize.width / 2 + positionOffset.x,
                y: canvasSize.height / 2 + positionOffset.y
            ),
            size: displaySize,
            zIndex: nextZIndex,
            intrinsicAspectRatio: aspect
        )
        nextZIndex += 1
        items.append(item)
        imageCache.setObject(image, forKey: id as NSUUID)
        selectedItemIDs = [id]
    }

    func addSticker(id stickerID: String) {
        guard let img = StickerLibrary.shared.image(for: stickerID) else { return }
        pushUndoSnapshot()
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1.0
        var maxDim: CGFloat = 200
        if img.size.width <= maxDim && img.size.height <= maxDim {
            maxDim = max(img.size.width, img.size.height)
        }
        let displaySize: CGSize
        if aspect >= 1 {
            displaySize = CGSize(width: maxDim, height: maxDim / aspect)
        } else {
            displaySize = CGSize(width: maxDim * aspect, height: maxDim)
        }

        let id = UUID()
        let item = CanvasItem(
            id: id,
            kind: .sticker(stickerID: stickerID),
            position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
            size: displaySize,
            zIndex: nextZIndex,
            intrinsicAspectRatio: aspect
        )
        nextZIndex += 1
        items.append(item)
        imageCache.setObject(img, forKey: id as NSUUID)
        selectedItemIDs = [id]
        StickerLibrary.shared.markUsed(stickerID)
    }

    // MARK: - Image Resolution

    func resolveImage(for item: CanvasItem) -> NSImage? {
        let key = item.id as NSUUID
        if let cached = imageCache.object(forKey: key) { return cached }
        let img: NSImage?
        switch item.kind {
        case .sticker(let stickerID):
            img = StickerLibrary.shared.image(for: stickerID)
        case .importedImage(let url):
            guard let url else { return nil }
            img = NSImage(contentsOf: url)
        case .workbenchImage(_, let url):
            guard let url else { return nil }
            img = NSImage(contentsOf: url)
        }
        if let img { imageCache.setObject(img, forKey: key) }
        return img
    }

    // MARK: - Selection

    func selectItem(at point: CGPoint, additive: Bool = false) {
        guard let id = hitTest(at: point) else {
            if !additive { clearSelection() }
            return
        }
        if additive {
            if selectedItemIDs.contains(id) {
                selectedItemIDs.remove(id)
            } else {
                selectedItemIDs.insert(id)
            }
        } else {
            selectedItemIDs = [id]
        }
    }

    func clearSelection() {
        selectedItemIDs = []
    }

    func hitTest(at point: CGPoint) -> UUID? {
        let ordered = visibleItems.reversed()
        for item in ordered {
            if item.isLocked { continue }
            let bounds = item.bounds
            if item.rotation != 0 {
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                let cosA = cos(-item.rotation)
                let sinA = sin(-item.rotation)
                let dx = point.x - center.x
                let dy = point.y - center.y
                let localPoint = CGPoint(
                    x: center.x + dx * cosA - dy * sinA,
                    y: center.y + dx * sinA + dy * cosA
                )
                if bounds.insetBy(dx: -6, dy: -6).contains(localPoint) {
                    return item.id
                }
            } else {
                if bounds.insetBy(dx: -6, dy: -6).contains(point) {
                    return item.id
                }
            }
        }
        return nil
    }

    // MARK: - Move / Resize / Rotate

    func moveSelection(by delta: CGSize) {
        guard delta != .zero else { return }
        beginInteractionChangeIfNeeded()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            guard !items[index].isLocked else { continue }
            items[index].position.x += delta.width
            items[index].position.y += delta.height
        }
    }

    func resizePrimarySelection(to point: CGPoint, corner: ResizeCorner) {
        guard let id = selectedItemIDs.first else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isLocked else { return }
        beginInteractionChangeIfNeeded()

        let current = items[index].bounds
        guard current.width > 0, current.height > 0 else { return }
        let aspect = items[index].intrinsicAspectRatio ?? (current.width / current.height)
        let minDim: CGFloat = 24

        let anchor: CGPoint
        switch corner {
        case .topLeft:     anchor = CGPoint(x: current.maxX, y: current.maxY)
        case .topRight:    anchor = CGPoint(x: current.minX, y: current.maxY)
        case .bottomLeft:  anchor = CGPoint(x: current.maxX, y: current.minY)
        case .bottomRight: anchor = CGPoint(x: current.minX, y: current.minY)
        case .endpointStart, .endpointEnd: return
        }

        var newWidth = abs(point.x - anchor.x)
        var newHeight = abs(point.y - anchor.y)
        if newWidth / aspect > newHeight {
            newHeight = newWidth / aspect
        } else {
            newWidth = newHeight * aspect
        }
        newWidth = max(minDim, newWidth)
        newHeight = max(minDim, newHeight)

        let newBounds: CGRect
        switch corner {
        case .topLeft:
            newBounds = CGRect(x: anchor.x - newWidth, y: anchor.y - newHeight, width: newWidth, height: newHeight)
        case .topRight:
            newBounds = CGRect(x: anchor.x, y: anchor.y - newHeight, width: newWidth, height: newHeight)
        case .bottomLeft:
            newBounds = CGRect(x: anchor.x - newWidth, y: anchor.y, width: newWidth, height: newHeight)
        case .bottomRight:
            newBounds = CGRect(x: anchor.x, y: anchor.y, width: newWidth, height: newHeight)
        case .endpointStart, .endpointEnd:
            return
        }

        items[index].position = CGPoint(x: newBounds.midX, y: newBounds.midY)
        items[index].size = newBounds.size
    }

    func rotatePrimarySelection(angle: CGFloat) {
        guard let id = selectedItemIDs.first else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isLocked else { return }
        beginInteractionChangeIfNeeded()
        items[index].rotation = angle
    }

    // MARK: - Item Properties

    func updateSelectedOpacity(_ opacity: CGFloat) {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        let clamped = max(0.1, min(1.0, opacity))
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].opacity = clamped
        }
    }

    func flipSelectedHorizontally() {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].flipH.toggle()
        }
    }

    func flipSelectedVertically() {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].flipV.toggle()
        }
    }

    func toggleSelectedShadow() {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].hasShadow.toggle()
        }
    }

    func updateSelectedCornerRadius(_ radius: CGFloat) {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].cornerRadius = max(0, radius)
        }
    }

    func updateSelectedBorderWidth(_ width: CGFloat) {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].borderWidth = max(0, width)
        }
    }

    func updateSelectedBorderColor(_ color: Color) {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].borderColor = color
        }
    }

    // MARK: - Layer Order

    func reorder(_ id: UUID, direction: LayerMoveDirection) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        let original = items[index].zIndex
        let target = direction == .up ? original + 1 : max(0, original - 1)
        if let swapIndex = items.firstIndex(where: { $0.zIndex == target }) {
            items[swapIndex].zIndex = original
        }
        items[index].zIndex = target
    }

    func toggleLock(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        items[index].isLocked.toggle()
    }

    func toggleVisibility(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        items[index].isHidden.toggle()
    }

    // MARK: - Delete / Duplicate

    func deleteSelection() {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        for id in selectedItemIDs { imageCache.removeObject(forKey: id as NSUUID) }
        items.removeAll { selectedItemIDs.contains($0.id) }
        selectedItemIDs = []
    }

    func duplicateSelection() {
        guard !selectedItemIDs.isEmpty else { return }
        pushUndoSnapshot()
        var newIDs: Set<UUID> = []
        for id in selectedItemIDs {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let z = nextZIndex
            nextZIndex += 1
            let copy = item.duplicated(zIndex: z)
            items.append(copy)
            newIDs.insert(copy.id)
            if let img = imageCache.object(forKey: id as NSUUID) { imageCache.setObject(img, forKey: copy.id as NSUUID) }
        }
        selectedItemIDs = newIDs
    }

    // MARK: - Canvas Size

    func fitToContent() {
        guard !items.isEmpty else { return }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for item in items {
            let b = item.bounds
            minX = min(minX, b.minX)
            minY = min(minY, b.minY)
            maxX = max(maxX, b.maxX)
            maxY = max(maxY, b.maxY)
        }
        let padding: CGFloat = 40
        let newWidth = max(200, maxX - minX + padding * 2)
        let newHeight = max(200, maxY - minY + padding * 2)
        let offsetX = padding - minX
        let offsetY = padding - minY
        canvasSize = CGSize(width: newWidth, height: newHeight)
        for i in items.indices {
            items[i].position.x += offsetX
            items[i].position.y += offsetY
        }
    }

    // MARK: - Selection Bounds

    func selectionBounds() -> CGRect? {
        let selected = selectedItems.filter { !$0.isHidden }
        guard !selected.isEmpty else { return nil }
        var rect = selected[0].bounds
        for item in selected.dropFirst() {
            rect = rect.union(item.bounds)
        }
        return rect
    }

    // MARK: - Undo / Redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

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
        Snapshot(items: items, selectedItemIDs: selectedItemIDs, nextZIndex: nextZIndex)
    }

    private func restore(from snapshot: Snapshot) {
        items = snapshot.items
        selectedItemIDs = snapshot.selectedItemIDs
        nextZIndex = snapshot.nextZIndex
        interactionBaseline = nil
    }
}
