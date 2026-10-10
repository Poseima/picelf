import Foundation

struct RelayLayer: Codable, Equatable {
    var revision: Int
    var editRevision: Int?
    var imageFile: String
    var documentFile: String
    var textFile: String?
}
struct RelayLiveSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var taskID: UUID
    var mac: RelayLayer?
    var pad: RelayLayer?
    var macSequence = 0
    var padSequence = 0
    var requiresPadText: Bool?
    var closing = false
    var completed = false
    var macReady: Int?
    var padReady: Int?
    var macDirty = true
    var padDirty = true
    var copiedMac: Int?
    var copiedPad: Int?
    var clipboardPaused = false
    var failure: String?
    func layer(_ role: RelayRole) -> RelayLayer? { role == .mac ? mac : pad }
}
struct RelayLiveMessage: Codable {
    var session: RelayLiveSession
    var action: String
    var owner: RelayRole
    var revision: Int = 0
    var document: Data?
    var editRevision: Int?
    var padText: Data?
}

// Each device owns one layer. Mac coordinates session admission and finalization;
// neither an acknowledgement nor a remote snapshot can replace the local layer.
@MainActor
final class RelayCollaboration {
    unowned let hub: RelayCoordinator
    private(set) var sessions: [UUID: RelayLiveSession] = [:]
    private(set) var peerSupportsLive = false
    private(set) var peerSupportsText = false
    private(set) var layerPreviews: [UUID: Data] = [:]
    var flushLocal: [UUID: () async throws -> Void] = [:]
    var clipboardChangeCount: (() -> Int)?
    var sendOverride: ((RelayPacket) -> Void)? // Deterministic radio-free tests.
    private var expectedClipboardCount: Int?
    private var closedAcknowledged = Set<UUID>()
    private var composedVersions: [UUID: String] = [:]
    private var acknowledged: [UUID: Int] = [:]
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var pending = Set<UUID>()
    private var preparing = Set<UUID>()
    private var previewRevisions: [UUID: Int] = [:]
    private var retryLoop: Task<Void, Never>?
    var activeID: UUID? { sessions.values.first { !$0.completed }?.taskID }
    var connected: Bool { hub.transport.connected || sendOverride != nil }
    init(hub: RelayCoordinator) {
        self.hub = hub
        for task in hub.tasks {
            if let bytes = try? hub.data(task.id, "collaboration.json"),
               var session = try? JSONDecoder().decode(RelayLiveSession.self, from: bytes) {
                // A restart cannot claim ownership of the user's current clipboard.
                if hub.role == .mac && !session.completed { session.clipboardPaused = true }
                sessions[task.id] = session
            }
        }
    }
    func session(_ id: UUID) -> RelayLiveSession? { sessions[id] }
    func isLive(_ id: UUID) -> Bool { sessions[id].map { !$0.completed } ?? false }
    func status(_ id: UUID) -> String? {
        guard let s = sessions[id] else { return nil }
        if let failure = s.failure { return failure }
        if s.completed { return s.clipboardPaused ? L10n.localized("已保存 · 自动复制已暂停", "Saved · Auto-copy Paused") : L10n.localized("已复制，直接粘贴", "Copied. Ready to Paste") }
        if !connected { return L10n.localized("已保存，等待重连", "Saved. Waiting to Reconnect") }
        if s.requiresPadText == true && !peerSupportsText { return L10n.localized("请更新另一台设备，以继续同步文字标注", "Update the other device to keep syncing text") }
        if s.closing { return L10n.localized("正在保存双方修改，结束共同编辑…", "Saving changes from both devices and ending shared edit…") }
        if s.clipboardPaused { return L10n.localized("共同编辑中 · 自动复制已暂停", "Shared Edit · Auto-copy Paused") }
        if s.macDirty || s.padDirty { return L10n.localized("共同编辑中 · 正在同步", "Shared Edit · Syncing") }
        if s.copiedMac == s.mac?.revision && s.copiedPad == s.pad?.revision, s.mac != nil, s.pad != nil {
            return L10n.localized("已复制，直接粘贴 · 共同编辑中", "Copied. Ready to Paste · Shared Edit")
        }
        return L10n.localized("共同编辑中 · 正在准备可粘贴图片", "Shared Edit · Preparing Image to Paste")
    }
    private func save(_ value: RelayLiveSession) throws {
        var s = value
        if hub.role == .mac { s.macSequence += 1 } else { s.padSequence += 1 }
        guard let url = hub.fileURL(s.taskID, "collaboration.json") else { throw RelayError.message(L10n.localized("无法保存共同编辑。", "Could not save the shared edit.")) }
        try JSONEncoder().encode(s).write(to: url, options: .atomic)
        sessions[s.taskID] = s
        hub.objectWillChange.send()
        if let folder = hub.fileURL(s.taskID, "collaboration.json")?.deletingLastPathComponent(),
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let retained = Set([s.mac?.imageFile, s.mac?.documentFile, s.pad?.imageFile, s.pad?.documentFile, s.pad?.textFile].compactMap { $0 })
            for file in files where file.lastPathComponent.hasPrefix("live-") && !retained.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    private func send(_ s: RelayLiveSession, _ action: String, revision: Int = 0, image: Data? = nil, document: Data? = nil, editRevision: Int? = nil, padText: Data? = nil) {
        guard s.requiresPadText != true || peerSupportsText else { return }
        guard connected, peerSupportsLive else { return }
        let s = sessions[s.taskID] ?? s
        let packet = RelayPacket(kind: .live, taskID: s.taskID, revision: revision, image: image,
                                 live: RelayLiveMessage(session: s, action: action, owner: hub.role, revision: revision, document: document, editRevision: editRevision, padText: padText), textVersion: 1)
        if let sendOverride { sendOverride(packet) }
        else { hub.transport.send(packet, resource: image != nil && action != "preview") }
    }
    func connectionChanged(_ connected: Bool) {
        peerSupportsLive = false; peerSupportsText = false; acknowledged.removeAll(); closedAcknowledged.removeAll(); previewRevisions.removeAll()
        retryLoop?.cancel(); retryLoop = nil
        if connected {
            // Existing peers safely ignore optional fields on accepted packets.
            hub.transport.send(.init(kind: .accepted, taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, liveVersion: 1, textVersion: 1))
            retryLoop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.synchronize()
                }
            }
        }
        hub.objectWillChange.send()
    }
    func discoveredPeer(textVersion: Int? = nil) {
        peerSupportsLive = true
        if textVersion == 1 { peerSupportsText = true }
        synchronize(); hub.objectWillChange.send()
    }
    func textData(_ id: UUID) -> Data? {
        guard let file = sessions[id]?.pad?.textFile else { return nil }
        return try? hub.data(id, file)
    }
    func requireText(_ id: UUID) throws {
        guard var s = sessions[id], !s.completed else { return }
        guard !connected || peerSupportsText else { throw RelayError.message(L10n.localized("请更新另一台设备后使用文字共同编辑。原有画作已保留。", "Update the other device before sharing editable text. Your existing work was saved.")) }
        if s.requiresPadText != true { s.requiresPadText = true; try save(s); send(s, "state") }
    }
    func start(_ id: UUID, allowOffline: Bool = false) throws {
        guard (peerSupportsLive && connected) || allowOffline else { throw RelayError.message(L10n.localized("请连接已更新的另一台设备后开始共同编辑。", "Connect an updated device before starting a shared edit.")) }
        guard activeID == nil || activeID == id else { throw RelayError.message(L10n.localized("请先结束当前图片的共同编辑。", "End the current shared edit first.")) }
        guard let task = hub.task(id), !task.state.isHistory, task.state != .returning else { return }
        if isLive(id) { return }
        let hasText = (try? hub.data(id, RelayTextDocument.filename)).flatMap { try? RelayTextDocument.decode($0) }?.boxes.isEmpty == false
        if hasText && !peerSupportsText && !allowOffline { throw RelayError.message(L10n.localized("请更新另一台设备后使用文字共同编辑；当前仍可完成并回传图片。", "Update the other device to share editable text. You can still finish and return the image.")) }
        var session = RelayLiveSession(taskID: id)
        session.requiresPadText = hasText
        try save(session)
        expectedClipboardCount = clipboardChangeCount?()
        hub.beginEditing(id)
        send(session, "offer")
    }
    func markDirty(_ id: UUID) {
        guard var s = sessions[id], !s.completed, !s.closing else { return }
        let wasDirty = hub.role == .mac ? s.macDirty : s.padDirty
        if wasDirty { return }
        if hub.role == .mac { s.macDirty = true } else { s.padDirty = true }
        s.failure = nil
        sessions[id] = s // In-memory dirty state also blocks an in-flight copy if disk saving fails.
        do { try save(s); send(s, "state") } catch { hub.errorMessage = error.localizedDescription }
    }
    func saveDraft(_ id: UUID, document: Data) throws {
        guard let url = hub.fileURL(id, hub.role == .mac ? "mac-draft.json" : "ink.drawing") else { return }
        try document.write(to: url, options: .atomic)
    }
    func layerData(_ id: UUID, role: RelayRole, document: Bool = false) -> Data? {
        guard let layer = sessions[id]?.layer(role) else { return nil }
        return try? hub.data(id, document ? layer.documentFile : layer.imageFile)
    }
    func commit(_ id: UUID, image: Data, document: Data, editRevision: Int? = nil, padText: Data? = nil) throws {
        guard var s = sessions[id], !s.completed, let task = hub.task(id) else { return }
        if let padText {
            let texts = try RelayTextDocument.decode(padText)
            if !texts.boxes.isEmpty { s.requiresPadText = true }
        }
        // Persist complete local layers even offline or while a peer needs updating.
        // The send/composite gates keep unsupported peers from discarding editable text.
        let size = try RelayImage.pngDimensions(image)
        guard size == (task.width, task.height), document.count <= 32 * 1024 * 1024 else { throw RelayError.message(L10n.localized("共同编辑图层尺寸或大小不正确。", "The shared-edit layer has an invalid size.")) }
        let revision = (s.layer(hub.role)?.revision ?? 0) + 1
        let layer = try writeLayer(s, role: hub.role, revision: revision, image: image, document: document, editRevision: editRevision, padText: padText)
        if hub.role == .mac { s.mac = layer; s.macDirty = false; s.macReady = nil }
        else { s.pad = layer; s.padDirty = false; s.padReady = nil }
        s.failure = nil
        try save(s); send(s, "layer", revision: revision, image: image, document: document, editRevision: editRevision, padText: padText)
        scheduleComposite(id)
    }
    private func writeLayer(_ s: RelayLiveSession, role: RelayRole, revision: Int, image: Data, document: Data, editRevision: Int? = nil, padText: Data? = nil) throws -> RelayLayer {
        let prefix = "live-\(s.id)-\(role.rawValue)-\(revision)"
        var layer = RelayLayer(revision: revision, editRevision: editRevision, imageFile: prefix + ".png", documentFile: prefix + ".json")
        guard let imageURL = hub.fileURL(s.taskID, layer.imageFile), let docURL = hub.fileURL(s.taskID, layer.documentFile) else { throw RelayError.message(L10n.localized("图层存储不可用。", "Layer storage is unavailable.")) }
        if role == .iPad, let padText {
            _ = try RelayTextDocument.decode(padText)
            layer.textFile = prefix + "-text.json"
            guard let url = hub.fileURL(s.taskID, layer.textFile!) else { throw RelayError.message(L10n.localized("文字存储不可用。", "Text storage is unavailable.")) }
            try padText.write(to: url, options: .atomic)
        }
        try image.write(to: imageURL, options: .atomic); try document.write(to: docURL, options: .atomic)
        return layer
    }
    func preview(_ id: UUID, revision: Int, image: Data) {
        guard let s = sessions[id], !s.completed, image.count <= RelayLimits.maxPreviewBytes,
              s.requiresPadText != true || peerSupportsText else { return }
        send(s, "preview", revision: revision, image: image)
    }
    func end(_ id: UUID) {
        guard var s = sessions[id], !s.completed else { return }
        s.closing = true
        do { try save(s); send(s, "state"); prepareClose(id) } catch { hub.errorMessage = error.localizedDescription }
    }
    private func prepareClose(_ id: UUID) {
        guard let s = sessions[id], s.closing, !s.completed, !preparing.contains(id),
              (hub.role == .mac ? s.macReady : s.padReady) == nil else { return }
        preparing.insert(id)
        Task { [weak self] in
            guard let self else { return }
            defer { self.preparing.remove(id) }
            do {
                if let flush = self.flushLocal[id] { try await flush() }
                guard var latest = self.sessions[id], let revision = latest.layer(self.hub.role)?.revision,
                      !(self.hub.role == .mac ? latest.macDirty : latest.padDirty) else { return }
                if self.hub.role == .mac { latest.macReady = revision } else { latest.padReady = revision }
                try self.save(latest); self.send(latest, "state"); self.scheduleComposite(id)
            } catch { self.fail(id, error) }
        }
    }
    func resumeClipboard(_ id: UUID) {
        guard hub.role == .mac, var s = sessions[id] else { return }
        if s.completed {
            do {
                guard let copy = hub.copyImage else { throw RelayError.message(L10n.localized("Mac 剪贴板尚未就绪。", "The Mac clipboard is not ready.")) }
                try copy(hub.data(id, "result.png"))
                s.clipboardPaused = false; s.failure = nil
                s.copiedMac = s.mac?.revision; s.copiedPad = s.pad?.revision
                try save(s); send(s, "closed")
            } catch { fail(id, error) }
            return
        }
        expectedClipboardCount = clipboardChangeCount?()
        s.clipboardPaused = false; s.failure = nil; composedVersions[id] = nil; s.copiedMac = nil; s.copiedPad = nil
        do { try save(s); send(s, "state"); scheduleComposite(id) } catch { fail(id, error) }
    }
    func synchronize() {
        if hub.role == .mac, let id = activeID, var s = sessions[id], !s.clipboardPaused,
           let expectedClipboardCount, clipboardChangeCount?() != expectedClipboardCount {
            s.clipboardPaused = true
            do { try save(s); send(s, "state") } catch { hub.errorMessage = error.localizedDescription }
        }
        guard peerSupportsLive, connected else { return }
        for s in sessions.values {
            guard hub.task(s.taskID) != nil else { continue }
            if s.completed {
                if hub.role == .mac && !closedAcknowledged.contains(s.taskID) { send(s, "closed") }
                continue
            }
            if s.requiresPadText == true && !peerSupportsText { continue }
            send(s, "offer")
            if !s.completed, let layer = s.layer(hub.role), acknowledged[s.taskID] != layer.revision,
               let image = layerData(s.taskID, role: hub.role), let doc = layerData(s.taskID, role: hub.role, document: true) {
                send(s, "layer", revision: layer.revision, image: image, document: doc, editRevision: layer.editRevision, padText: hub.role == .iPad ? textData(s.taskID) : nil)
            }
            if s.closing { prepareClose(s.taskID) }
        }
    }
    func receive(_ packet: RelayPacket) throws {
        guard let message = packet.live, message.owner != hub.role,
              packet.taskID == message.session.taskID, let task = hub.task(packet.taskID) else { return }
        let id = packet.taskID, remote = message.session
        if packet.textVersion == 1 { peerSupportsText = true }
        if remote.requiresPadText == true && !peerSupportsText { throw RelayError.message(L10n.localized("请更新另一台设备后使用文字共同编辑。", "Update the other device to share editable text.")) }
        if message.action == "reject" {
            if hub.role == .iPad, let current = sessions[id], current.id == remote.id {
                sessions[id] = nil
                if let url = hub.fileURL(id, "collaboration.json") { try? FileManager.default.removeItem(at: url) }
                hub.objectWillChange.send()
            }
            hub.errorMessage = L10n.localized("另一张图片正在共同编辑，请先结束它。", "Another image is being shared. End that edit first."); return
        }
        if sessions[id] == nil {
            guard message.action == "offer", !task.state.isHistory else { return }
            if let activeID, activeID != id {
                if hub.role == .mac { send(remote, "reject"); return }
                // Mac is admission authority. Preserve the local draft of a losing offer.
                sessions[activeID] = nil
                if let url = hub.fileURL(activeID, "collaboration.json") { try? FileManager.default.removeItem(at: url) }
            }
            var fresh = RelayLiveSession(id: remote.id, taskID: id)
            fresh.closing = remote.closing; fresh.requiresPadText = remote.requiresPadText
            try save(fresh); expectedClipboardCount = clipboardChangeCount?(); hub.beginEditing(id)
        }
        guard var s = sessions[id] else { return }
        if s.id != remote.id {
            // Simultaneous offers for the same image use the Mac's session ID.
            if hub.role == .mac { send(s, "offer"); return }
            guard message.action == "offer" else { return }
            s.id = remote.id; acknowledged[id] = nil
            try save(s)
        }
        s.requiresPadText = (s.requiresPadText == true || remote.requiresPadText == true)
        if message.action == "closedAck", hub.role == .mac { closedAcknowledged.insert(id); return }
        if s.completed {
            if hub.role == .mac {
                send(s, "closed", image: message.action == "needResult" ? (try? hub.data(id, "result.png")) : nil)
            }
            else if message.action == "closed", s.mac?.revision == remote.mac?.revision, s.pad?.revision == remote.pad?.revision {
                s.clipboardPaused = remote.clipboardPaused; s.failure = remote.failure
                s.copiedMac = remote.copiedMac; s.copiedPad = remote.copiedPad
                try save(s); send(s, "closedAck")
            }
            return
        }
        switch message.action {
        case "preview":
            guard let bytes = packet.image, bytes.count <= RelayLimits.maxPreviewBytes,
                  message.revision >= (previewRevisions[id] ?? -1),
                  message.revision > (s.layer(message.owner)?.editRevision ?? -1) else { return }
            let size = try RelayImage.pngDimensions(bytes)
            guard max(size.0, size.1) <= 2048 else { return }
            previewRevisions[id] = message.revision; layerPreviews[id] = bytes
            hub.objectWillChange.send(); if hub.role == .mac { schedulePreview(id) }
            return
        case "layer":
            guard let image = packet.image, let doc = message.document, doc.count <= 32 * 1024 * 1024,
                  message.revision > 0 else { return }
            if message.revision > (s.layer(message.owner)?.revision ?? 0) {
                guard try RelayImage.pngDimensions(image) == (task.width, task.height) else { throw RelayError.message(L10n.localized("共同编辑图层尺寸不正确。", "The shared-edit layer has the wrong size.")) }
                let layer = try writeLayer(s, role: message.owner, revision: message.revision, image: image, document: doc, editRevision: message.editRevision, padText: message.padText)
                if message.owner == .mac { s.mac = layer; if remote.macSequence >= s.macSequence { s.macDirty = remote.macDirty; s.macSequence = remote.macSequence } }
                else { s.pad = layer; if remote.padSequence >= s.padSequence { s.padDirty = remote.padDirty; s.padSequence = remote.padSequence } }
                if (previewRevisions[id] ?? -1) <= (message.editRevision ?? Int.max) { layerPreviews[id] = nil }
                try save(s)
            }
            send(s, "ack", revision: message.revision)
        case "ack":
            if message.revision == s.layer(hub.role)?.revision { acknowledged[id] = message.revision }
        case "offer", "state":
            if message.owner == .mac && remote.macSequence >= s.macSequence {
                s.macSequence = remote.macSequence
                s.macDirty = remote.macDirty || s.mac?.revision != remote.mac?.revision
                s.macReady = remote.macReady
                s.clipboardPaused = remote.clipboardPaused; s.failure = remote.failure
                s.copiedMac = remote.copiedMac; s.copiedPad = remote.copiedPad
            } else if message.owner == .iPad && remote.padSequence >= s.padSequence {
                s.padSequence = remote.padSequence
                s.padDirty = remote.padDirty || s.pad?.revision != remote.pad?.revision
                s.padReady = remote.padReady
            }
            s.closing = s.closing || remote.closing
            try save(s)
        case "closed":
            guard hub.role == .iPad, remote.macReady == s.mac?.revision,
                  remote.padReady == s.pad?.revision else { return }
            guard let image = packet.image else { send(s, "needResult"); return }
            guard try RelayImage.pngDimensions(image) == (task.width, task.height) else { return }
            s.completed = true; s.closing = true; s.clipboardPaused = remote.clipboardPaused
            s.copiedMac = remote.copiedMac; s.copiedPad = remote.copiedPad
            try hub.finishLive(id, result: image, copied: !s.clipboardPaused)
            try save(s); send(s, "closedAck"); return
        default: return
        }
        if s.closing { prepareClose(id) }
        scheduleComposite(id)
    }
    private func fail(_ id: UUID, _ error: Error) {
        guard var s = sessions[id] else { return }
        s.failure = L10n.localized("保存或复制失败：\(error.localizedDescription)", "Save or copy failed: \(error.localizedDescription)")
        try? save(s); send(s, "state")
    }
    private func schedulePreview(_ id: UUID) {
        // The same worker handles previews and durable composition, keeping memory bounded.
        scheduleComposite(id)
    }
    private func scheduleComposite(_ id: UUID) {
        guard hub.role == .mac else { return }
        pending.insert(id)
        guard workers[id] == nil else { return }
        workers[id] = Task { [weak self] in
            guard let self else { return }
            while self.pending.remove(id) != nil {
                do { try await self.compose(id) } catch { self.fail(id, error) }
            }
            self.workers[id] = nil
        }
    }
    private func compose(_ id: UUID) async throws {
        guard let s = sessions[id], let task = hub.task(id) else { return }
        let mac = try layerData(id, role: .mac) ?? hub.data(id, "base.png")
        let previewInk = layerPreviews[id] ?? layerData(id, role: .iPad)
        let preview = try await Task.detached(priority: .utility) {
            try RelayImage.compose(base: mac, overlay: previewInk, width: task.width, height: task.height, edge: 2048)
        }.value
        hub.setLivePreview(id, image: preview)
        guard (s.requiresPadText != true || peerSupportsText), s.failure == nil, !s.macDirty, !s.padDirty, let m = s.mac, let p = s.pad,
              acknowledged[id] == m.revision, connected else { return }
        if s.copiedMac == m.revision && s.copiedPad == p.revision && !s.closing { return }
        let key = "\(m.revision):\(p.revision)"
        if composedVersions[id] == key && s.clipboardPaused && !s.closing { return }
        let ink = layerData(id, role: .iPad)
        let result = try await Task.detached(priority: .userInitiated) {
            try RelayImage.compose(base: mac, overlay: ink, width: task.width, height: task.height)
        }.value
        guard var latest = sessions[id], latest.mac == m, latest.pad == p, !latest.macDirty, !latest.padDirty else { return }
        if !latest.clipboardPaused && (expectedClipboardCount == nil || clipboardChangeCount?() != expectedClipboardCount) {
            latest.clipboardPaused = true
        }
        try hub.saveLiveResult(id, result: result)
        composedVersions[id] = key
        if !latest.clipboardPaused && (latest.copiedMac != m.revision || latest.copiedPad != p.revision) {
            // Persist intent first. A crash restarts paused rather than re-copying unexpectedly.
            guard let copy = hub.copyImage else { throw RelayError.message(L10n.localized("Mac 剪贴板尚未就绪。", "The Mac clipboard is not ready.")) }
            try copy(result); expectedClipboardCount = clipboardChangeCount?()
            latest.copiedMac = m.revision; latest.copiedPad = p.revision
        }
        latest.failure = nil
        if latest.closing, latest.macReady == m.revision, latest.padReady == p.revision {
            latest.completed = true
            try hub.finishLive(id, result: result, copied: !latest.clipboardPaused)
        }
        try save(latest)
        send(latest, latest.completed ? "closed" : "state", image: latest.completed ? result : nil)
    }
}
