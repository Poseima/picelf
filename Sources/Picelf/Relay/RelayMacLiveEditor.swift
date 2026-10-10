import AppKit
import SwiftUI
import Combine

// Mac annotations remain editable; the iPad only needs their rendered plate.
struct RelayMacDocument: Codable {
    var annotations: [RelayMacAnnotation]
}
struct RelayMacAnnotation: Codable {
    var id: UUID
    var kind: EditorAnnotationKind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    var text: String?
    var color: [Double]
    var lineWidth: CGFloat
    var fillColor: [Double]
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
    init(_ a: EditorAnnotation) {
        id = a.id
        kind = a.kind
        start = a.start
        end = a.end
        points = a.points
        text = a.text
        color = Self.rgba(a.color)
        lineWidth = a.lineWidth
        fillColor = Self.rgba(a.fillColor)
        isLocked = a.isLocked
        isHidden = a.isHidden
        zIndex = a.zIndex
        fontSize = a.fontSize
        textBoxWidth = a.textBoxWidth
        mosaicBlockSize = a.mosaicBlockSize
        stickerImageID = a.stickerImageID
        rotation = a.rotation
        opacity = a.opacity
        flipH = a.flipH
        flipV = a.flipV
        hasShadow = a.hasShadow
    }
    var annotation: EditorAnnotation {
        EditorAnnotation(id: id, kind: kind, start: start, end: end, points: points, text: text, color: Self.color(color), lineWidth: lineWidth, fillColor: Self.color(fillColor), isLocked: isLocked, isHidden: isHidden, zIndex: zIndex, fontSize: fontSize, textBoxWidth: textBoxWidth, mosaicBlockSize: mosaicBlockSize, stickerImageID: stickerImageID, rotation: rotation, opacity: opacity, flipH: flipH, flipV: flipV, hasShadow: hasShadow)
    }
    private static func rgba(_ color: Color) -> [Double] {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
    private static func color(_ values: [Double]) -> Color {
        guard values.count == 4 else { return .black }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values[3])
    }
}

@MainActor
final class RelayMacLiveEditor {
    let id: UUID
    let hub: RelayCoordinator
    let document: EditorDocument
    private var observation: AnyCancellable?
    private var loop: Task<Void, Never>?
    private var draftSave: Task<Void, Never>?
    private var version = 0
    private var committed = -1
    private var previewed = -1
    private var changedAt = Date.distantPast
    private var encoding = false
    private var remoteBytes: Data?
    init(id: UUID, hub: RelayCoordinator) throws {
        self.id = id; self.hub = hub
        guard let task = hub.task(id), let image = NSImage(data: try hub.data(id, "base.png")) else { throw RelayError.message(L10n.localized("无法打开共同编辑图片。", "Could not open the shared-edit image.")) }
        image.size = NSSize(width: task.width, height: task.height)
        document = EditorDocument(baseImage: image)
        document.isRelayDocument = true
        version = (hub.collaboration.session(id)?.mac?.editRevision ?? 0) + 1
        let archive = (try? hub.data(id, "mac-draft.json")) ?? hub.collaboration.layerData(id, role: .mac, document: true)
        if let archive, !archive.isEmpty {
            let saved = try JSONDecoder().decode(RelayMacDocument.self, from: archive)
            document.restoreRelayAnnotations(saved.annotations.map(\.annotation))
        }
        document.onRelayChange = { [weak self] in self?.changed() }
        hub.collaboration.flushLocal[id] = { [weak self] in try await self?.flush() }
        observation = hub.objectWillChange.sink { [weak self] in Task { @MainActor [weak self] in self?.refresh() } }
        refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.hub.collaboration.isLive(id) else { break }
                do {
                    if Date().timeIntervalSince(self.changedAt) >= 0.8 { try await self.flush() }
                    else { try await self.preview() }
                } catch { self.hub.errorMessage = L10n.localized("自动保存失败：\(error.localizedDescription)", "Auto-save failed: \(error.localizedDescription)") }
            }
        }
        _ = task
    }
    deinit { loop?.cancel(); draftSave?.cancel() }
    func refresh() {
        let s = hub.collaboration.session(id)
        document.relayLocked = s?.closing == true || s?.completed == true
        let bytes = hub.collaboration.layerPreviews[id] ?? hub.collaboration.layerData(id, role: .iPad)
        if bytes != remoteBytes { remoteBytes = bytes; document.relayInkOverlay = bytes.flatMap(NSImage.init(data:)) }
    }
    private func archive() throws -> Data {
        try JSONEncoder().encode(RelayMacDocument(annotations: document.annotations.map(RelayMacAnnotation.init)))
    }
    private func changed() {
        version += 1; changedAt = Date(); hub.collaboration.markDirty(id)
        draftSave?.cancel()
        draftSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            do { try self.hub.collaboration.saveDraft(self.id, document: self.archive()) }
            catch { self.hub.errorMessage = L10n.localized("草稿保存失败：\(error.localizedDescription)", "Could not save draft: \(error.localizedDescription)") }
        }
    }
    private func plate(edge: Int? = nil) throws -> CGImage {
        guard let image = EditorCompositor.compose(baseImage: document.loadFullResImage(),
                  imageSize: document.originalImageSize, annotations: document.visibleAnnotations,
                  draft: document.draftAnnotation,
                  pixelScale: edge.map { min(1, CGFloat($0) / max(document.imageWidth, document.imageHeight)) } ?? 1),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw RelayError.message(L10n.localized("无法生成 Mac 标注图层。", "Could not render the Mac annotation layer.")) }
        return cg
    }
    private func preview() async throws {
        guard !encoding, previewed != version else { return }
        encoding = true; defer { encoding = false }
        let v = version, cg = try plate(edge: 2048)
        let png = try await Task.detached(priority: .utility) {
            return try RelayImage.png(cg)
        }.value
        if version == v { hub.collaboration.preview(id, revision: v, image: png); previewed = v }
    }
    func flush() async throws {
        while encoding { try await Task.sleep(nanoseconds: 20_000_000) }
        guard hub.collaboration.isLive(id), committed != version || hub.collaboration.session(id)?.mac == nil else { return }
        encoding = true; defer { encoding = false }
        if hub.collaboration.session(id)?.closing == true { _ = document.commitActiveTextEditing(); document.commitAnnotation() }
        let v = version, doc = try archive(), cg = try plate()
        try hub.collaboration.saveDraft(id, document: doc)
        let png = try await Task.detached(priority: .userInitiated) { try RelayImage.png(cg) }.value
        guard version == v else { return }
        try hub.collaboration.commit(id, image: png, document: doc, editRevision: v)
        committed = v
    }
}

struct RelayEditorSessionBar: View {
    @ObservedObject var hub: RelayCoordinator
    let taskID: UUID
    var body: some View {
        HStack {
            Label(hub.collaboration.status(taskID) ?? L10n.localized("共同编辑", "Shared Edit"), systemImage: "link").font(.callout)
            Spacer()
            if hub.collaboration.session(taskID)?.clipboardPaused == true || hub.collaboration.session(taskID)?.failure != nil {
                Button(L10n.localized("复制最新并恢复", "Copy Latest and Resume")) { hub.collaboration.resumeClipboard(taskID) }
            }
            if hub.collaboration.isLive(taskID) {
                Button(L10n.localized("结束共同编辑", "End Shared Edit")) { hub.collaboration.end(taskID) }
                    .disabled(hub.collaboration.session(taskID)?.closing == true)
            }
        }.padding(12).background(.regularMaterial)
    }
}
