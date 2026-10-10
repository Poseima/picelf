import Foundation
import Combine

@MainActor
final class RelayCoordinator: ObservableObject {
    let role: RelayRole
    let transport: RelayTransport
    @Published private(set) var tasks: [RelayTask] = []
    @Published private(set) var previews: [UUID: Data] = [:]
    @Published var errorMessage: String?
    @Published private(set) var lastEvent = L10n.localized("等待图片", "Waiting for an Image")
    @Published private(set) var lastResultID: UUID?
    @Published private(set) var focusedTaskID: UUID?
    var copyImage: ((Data) throws -> Void)?
    var onShowPreview: (() -> Void)?
    lazy var collaboration = RelayCollaboration(hub: self)
    private var store: RelayStore?
    private var observation: AnyCancellable?
    private var connectionObservation: AnyCancellable?
    #if DEBUG
    private var pairingFixtureScheduled = false
    #endif
    private var sentTasks = Set<UUID>()
    private var acceptedTasks = Set<UUID>()
    private var sentFinals = Set<String>()
    private var previewWaiting: [UUID: Date] = [:]
    private var previewVersions: [UUID: Int] = [:]
    private var previewSentAt: [UUID: Date] = [:]
    private let startTransport: @MainActor (RelayTransport) -> Void

    init(role: RelayRole, directory: URL? = nil,
         startTransport: @escaping @MainActor (RelayTransport) -> Void = { $0.start() }) {
        self.role = role
        self.startTransport = startTransport
        transport = RelayTransport(role: role)
        do {
            var directory = directory
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--relay-ui-isolated") {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("relay-ui-\(UUID())")
            }
            #endif
            let store = try directory.map { try RelayStore(directory: $0) } ?? RelayStore()
            self.store = store
            observation = store.$tasks.sink { [weak self] in self?.tasks = $0 }
        } catch { errorMessage = L10n.localized("无法打开接力画板存储：\(error.localizedDescription)", "Could not open Relay Canvas storage: \(error.localizedDescription)") }
        connectionObservation = transport.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        transport.onPacket = { [weak self] packet in self?.receive(packet) }
        transport.onConnection = { [weak self] connected in
            guard let self else { return }
            self.sentTasks.removeAll(); self.acceptedTasks.removeAll(); self.sentFinals.removeAll(); self.previewWaiting.removeAll()
            self.collaboration.connectionChanged(connected)
            if connected { self.synchronize() }
        }
        transport.onError = { [weak self] in self?.errorMessage = $0 }
    }
    var activeTask: RelayTask? {
        collaboration.activeID.flatMap(task) ?? tasks.first { $0.state == .editing } ?? tasks.first { $0.state == .queued }
    }
    var pendingTasks: [RelayTask] { tasks.filter { !$0.state.isHistory } }
    var history: [RelayTask] { tasks.sorted { $0.updatedAt > $1.updatedAt } }
    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--relay-ui-no-network") {
            if !pairingFixtureScheduled, ProcessInfo.processInfo.arguments.contains("--relay-ui-pairing") {
                pairingFixtureScheduled = true
                let delayed = ProcessInfo.processInfo.arguments.contains("--relay-ui-pairing-delayed")
                let presentation = transport.pairing
                let fixturePeer = role == .mac ? "Picelf iPad · TEST" : "Picelf Mac · TEST"
                let present = {
                    let id = UUID(); presentation.begin(id, peer: fixturePeer)
                    presentation.request(id, code: "123456")
                }
                let delay: UInt64 = role == .mac ? 15_000_000_000 : 3_000_000_000
                if delayed { Task { try? await Task.sleep(nanoseconds: delay); present() } }
                else { present() }
            }
            return
        }
        #endif
        if store != nil { startTransport(transport) }
    }
    func task(_ id: UUID) -> RelayTask? { tasks.first { $0.id == id } }
    func data(_ id: UUID, _ name: String) throws -> Data {
        guard let store else { throw RelayError.message(L10n.localized("接力画板存储不可用。", "Relay Canvas storage is unavailable.")) }
        return try store.data(id, name)
    }
    func fileURL(_ id: UUID, _ name: String) -> URL? { store?.url(id, name) }
    @discardableResult
    func importImage(_ data: Data, title: String) async throws -> UUID {
        let normalized = try await Task.detached(priority: .userInitiated) { try RelayImage.normalize(data) }.value
        return try addImage(normalized.0, width: normalized.1, height: normalized.2, title: title)
    }
    @discardableResult
    func addImage(_ png: Data, width: Int, height: Int, title: String, ink: Data? = nil, macDocument: Data? = nil, padText: Data? = nil) throws -> UUID {
        guard let store else { throw RelayError.message(L10n.localized("接力画板存储不可用。", "Relay Canvas storage is unavailable.")) }
        try RelayLimits.validate(width: width, height: height)
        let task = RelayTask(title: title, origin: role, width: width, height: height)
        try store.save(task, base: png, ink: ink, padText: padText)
        if let macDocument { try macDocument.write(to: store.url(task.id, "mac-draft.json"), options: .atomic) }
        lastEvent = transport.connected
            ? L10n.localized("图片已加入标注队列", "Image added to the edit queue")
            : L10n.localized("图片已保存，等待设备连接", "Image saved. Waiting for a device")
        focusedTaskID = task.id
        onShowPreview?(); start(); synchronize()
        return task.id
    }
    func beginEditing(_ id: UUID) {
        guard var task = task(id), task.state == .queued else { return }
        task.state = .editing
        persist(task)
    }
    func saveDrawing(_ id: UUID, ink: Data, revision: Int, padText: Data? = nil) throws {
        guard var task = task(id), !task.state.isHistory, task.state != .returning, let store else { return }
        guard revision >= task.revision else { return }
        task.revision = revision; task.updatedAt = Date()
        try store.save(task, ink: ink, padText: padText)
    }
    func canSendPreview(_ id: UUID) -> Bool {
        guard transport.connected else { return false }
        if let sent = previewWaiting[id], Date().timeIntervalSince(sent) < 2 { return false }
        if let sent = previewSentAt[id], Date().timeIntervalSince(sent) < 0.2 { return false }
        return true
    }
    func sendPreview(_ id: UUID, revision: Int, png: Data) {
        guard role == .iPad, canSendPreview(id), png.count <= RelayLimits.maxPreviewBytes,
              let task = task(id), task.state == .editing || task.state == .queued else { return }
        previewWaiting[id] = Date(); previewSentAt[id] = Date()
        transport.send(RelayPacket(kind: .preview, taskID: id, revision: revision, image: png))
    }
    func complete(_ id: UUID, png: Data, ink: Data, revision: Int, padText: Data? = nil) throws {
        guard role == .iPad, var task = task(id), !task.state.isHistory, let store else { return }
        let dimensions = try RelayImage.pngDimensions(png)
        guard dimensions == (task.width, task.height) else { throw RelayError.message(L10n.localized("导出尺寸与原图不一致。", "The exported image size does not match the original.")) }
        task.revision = max(task.revision, revision); task.state = .returning; task.updatedAt = Date()
        try store.save(task, ink: ink, result: png, padText: padText)
        lastEvent = transport.connected
            ? L10n.localized("正在回传，等待 Mac 复制确认…", "Sending back. Waiting for Mac to confirm…")
            : L10n.localized("画作已保存，等待连接后回传", "Saved. Waiting to reconnect and send")
        synchronize()
    }
    func cancel(_ id: UUID) {
        guard !collaboration.isLive(id), var task = task(id) else { return }
        task.state = .cancelled; task.updatedAt = Date()
        persist(task)
        transport.send(RelayPacket(kind: .cancel, taskID: id, revision: task.revision))
        lastEvent = L10n.localized("已停止本次标注，草稿已保留", "Editing stopped. Draft kept")
    }
    func remove(_ id: UUID) {
        guard !collaboration.isLive(id) else { return }
        if let task = task(id), !task.state.isHistory { cancel(id) }
        do { try store?.remove(id); previews[id] = nil } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult
    func reopen(_ id: UUID) -> UUID? {
        do {
            guard let previous = task(id) else { return nil }
            let inheritedText = collaboration.textData(id) ?? (try? data(id, RelayTextDocument.filename))
            if role == .mac, let inheritedText,
               !(try RelayTextDocument.decode(inheritedText)).boxes.isEmpty,
               !collaboration.peerSupportsText {
                throw RelayError.message(L10n.localized("请连接已更新的 iPad，再继续编辑文字。完整图片仍可直接复制。", "Connect an updated iPad to keep editing text. You can still copy the finished image."))
            }
            if collaboration.session(id) != nil, collaboration.activeID != nil {
                throw RelayError.message(L10n.localized("请先结束当前图片的共同编辑。", "End the current shared edit first."))
            }
            let newID = try addImage(data(id, "base.png"), width: previous.width, height: previous.height,
                             title: previous.title, ink: collaboration.layerData(id, role: .iPad, document: true) ?? (try? data(id, "ink.drawing")),
                             macDocument: collaboration.layerData(id, role: .mac, document: true),
                             padText: inheritedText)
            if collaboration.session(id) != nil { try collaboration.start(newID, allowOffline: true) }
            return newID
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func copyAgain(_ id: UUID) {
        if collaboration.session(id) != nil { collaboration.resumeClipboard(id); return }
        guard role == .mac, var task = task(id), let copyImage, let store else { return }
        do {
            let png = try data(id, "result.png")
            _ = try RelayImage.pngDimensions(png)
            try copyImage(png)
            task.state = .completed; task.copyFailureMessage = nil; task.receiptRevision = task.revision; task.updatedAt = Date()
            try store.save(task)
            lastResultID = id; lastEvent = L10n.localized("已复制，可以 ⌘V", "Copied. Press ⌘V to paste")
            transport.send(RelayPacket(kind: .receipt, taskID: id, revision: task.revision, success: true))
        } catch { errorMessage = error.localizedDescription }
    }
    func retryTransfer() {
        sentTasks.removeAll(); sentFinals.removeAll()
        synchronize()
    }
    private func persist(_ task: RelayTask) {
        do { try store?.save(task) } catch { errorMessage = error.localizedDescription }
    }
    private func synchronize() {
        guard transport.connected, let store else { return }
        for task in tasks {
            if task.state == .cancelled {
                transport.send(RelayPacket(kind: .cancel, taskID: task.id, revision: task.revision)); continue
            }
            if task.state == .completed || task.state == .copyFailed || task.state == .copying { continue }
            do {
                // The originating device owns the immutable base; the iPad owns ink revisions.
                if task.origin == role, !sentTasks.contains(task.id) {
                    if role == .mac, let archive = try? store.data(task.id, RelayTextDocument.filename),
                       !(try RelayTextDocument.decode(archive)).boxes.isEmpty, !collaboration.peerSupportsText {
                        // Wait for the capability reply before sending editable text to an iPad.
                        if collaboration.peerSupportsLive { errorMessage = L10n.localized("请更新 iPad 后继续编辑文字；作品已保留。", "Update the iPad app to keep editing text. Your work was saved.") }
                        continue
                    }
                    transport.send(RelayPacket(kind: .task, taskID: task.id, task: task,
                                               image: try store.data(task.id, "base.png"),
                                               ink: try? store.data(task.id, "ink.drawing"), macDocument: try? store.data(task.id, "mac-draft.json"), liveVersion: 1,
                                               padText: try? store.data(task.id, "pad-text.json"), textVersion: 1), resource: true)
                    sentTasks.insert(task.id)
                }
                let key = "\(task.id):\(task.revision)"
                if role == .iPad, task.state == .returning,
                   (task.origin == .mac || acceptedTasks.contains(task.id)), !sentFinals.contains(key) {
                    transport.send(RelayPacket(kind: .final, taskID: task.id, revision: task.revision,
                                               image: try store.data(task.id, "result.png"),
                                               ink: try store.data(task.id, "ink.drawing"), padText: try? store.data(task.id, "pad-text.json"), textVersion: 1), resource: true)
                    sentFinals.insert(key)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    // Internal for deterministic protocol tests without radios or OS clipboard side effects.
    func receive(_ packet: RelayPacket) {
        guard let store else { return }
        if packet.liveVersion == 1 { collaboration.discoveredPeer(textVersion: packet.textVersion) }
        if packet.kind == .task || packet.kind == .final,
           let revision = store.completedRevisions[packet.taskID] {
            transport.send(RelayPacket(kind: .receipt, taskID: packet.taskID, revision: revision, success: true))
            return
        }
        do {
            switch packet.kind {
            case .live: try collaboration.receive(packet)
            case .task:
                guard var incoming = packet.task, incoming.id == packet.taskID, incoming.origin != role,
                      let base = packet.image else { throw RelayError.message(L10n.localized("收到的图片任务不完整。", "The received image task is incomplete.")) }
                if store.cancelledIDs.contains(incoming.id) {
                    transport.send(RelayPacket(kind: .cancel, taskID: incoming.id)); return
                }
                if store.task(incoming.id) == nil {
                    let dimensions = try RelayImage.pngDimensions(base)
                    guard dimensions == (incoming.width, incoming.height) else { throw RelayError.message(L10n.localized("图片尺寸校验失败。", "Image size verification failed.")) }
                    incoming.state = .queued; incoming.receiptRevision = nil
                    try store.save(incoming, base: base, ink: packet.ink, padText: packet.padText)
                    if let document = packet.macDocument, document.count <= 32 * 1024 * 1024 {
                        try document.write(to: store.url(incoming.id, "mac-draft.json"), options: .atomic)
                    }
                    focusedTaskID = incoming.id
                    lastEvent = role == .iPad
                        ? L10n.localized("收到 Mac 图片", "Image Received from Mac")
                        : L10n.localized("iPad 正在绘画", "Drawing on iPad")
                    onShowPreview?()
                }
                transport.send(RelayPacket(kind: .accepted, taskID: incoming.id, liveVersion: 1, textVersion: 1))
            case .accepted:
                acceptedTasks.insert(packet.taskID)
                synchronize()
            case .preview:
                guard !collaboration.isLive(packet.taskID) else { return }
                guard role == .mac, var task = task(packet.taskID), !task.state.isHistory,
                      let image = packet.image, image.count <= RelayLimits.maxPreviewBytes else { return }
                if packet.revision >= (previewVersions[packet.taskID] ?? -1) {
                    let dimensions = try RelayImage.pngDimensions(image)
                    guard max(dimensions.0, dimensions.1) <= 2048 else { return }
                    if task.state == .queued { task.state = .editing; try store.save(task) }
                    if collaboration.activeID == nil { focusedTaskID = packet.taskID }
                    previews[packet.taskID] = image; previewVersions[packet.taskID] = packet.revision
                    lastEvent = L10n.localized("iPad 正在标注 · 实时预览", "Editing on iPad · Live Preview")
                }
                transport.send(RelayPacket(kind: .previewAck, taskID: packet.taskID, revision: packet.revision))
            case .previewAck: previewWaiting[packet.taskID] = nil
            case .final:
                guard !collaboration.isLive(packet.taskID) else { return }
                guard role == .mac else { return }
                try receiveFinal(packet)
            case .receipt:
                guard role == .iPad, var task = task(packet.taskID), task.state == .returning,
                      packet.revision == task.revision else { return }
                if packet.success == true {
                    task.state = .completed; task.copyFailureMessage = nil; task.receiptRevision = packet.revision; task.updatedAt = Date()
                    try store.save(task); try store.prune()
                    lastResultID = task.id; focusedTaskID = task.id; lastEvent = L10n.localized("Mac 已复制，可以直接粘贴", "Copied on Mac. Ready to paste")
                } else {
                    lastEvent = L10n.localized("Mac 已收到图片，复制失败，请在 Mac 点击再次复制", "Mac received the image, but copying failed. Click Copy Again on Mac")
                    task.copyFailureMessage = packet.message ?? L10n.localized("请在 Mac 重试复制。", "Try copying again on Mac.")
                    try store.save(task)
                }
            case .cancel:
                guard !collaboration.isLive(packet.taskID) else { return }
                guard var task = task(packet.taskID), !task.state.isHistory else { return }
                task.state = .cancelled; task.updatedAt = Date(); try store.save(task)
                lastEvent = L10n.localized("另一台设备已停止本次标注，草稿已保留", "The other device stopped editing. Draft kept")
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func setLivePreview(_ id: UUID, image: Data) {
        previews[id] = image
        if collaboration.activeID == id { focusedTaskID = id }
    }
    func saveLiveResult(_ id: UUID, result: Data) throws {
        guard let task = task(id), let store else { return }
        try store.save(task, result: result)
    }
    func finishLive(_ id: UUID, result: Data, copied: Bool) throws {
        guard var task = task(id), let store else { return }
        task.state = .completed; task.updatedAt = Date()
        task.receiptRevision = task.revision
        try store.save(task, ink: collaboration.layerData(id, role: .iPad, document: true), result: result, padText: collaboration.textData(id))
        lastResultID = id
        do { try store.prune() } catch { errorMessage = L10n.localized("作品已保存，历史清理失败：\(error.localizedDescription)", "Work saved, but history cleanup failed: \(error.localizedDescription)") }
    }
    private func receiveFinal(_ packet: RelayPacket) throws {
        guard let store, var task = task(packet.taskID), task.state != .cancelled,
              packet.revision >= task.revision else { return }
        if let receiptRevision = task.receiptRevision {
            // Ledger survives restart and duplicate/reordered final resources.
            transport.send(RelayPacket(kind: .receipt, taskID: task.id, revision: receiptRevision,
                                       success: task.state == .completed, message: task.state == .completed ? nil : L10n.localized("请在 Mac 重试复制。", "Try copying again on Mac.")))
            return
        }
        guard let png = packet.image, let ink = packet.ink, ink.count <= 32 * 1024 * 1024 else {
            throw RelayError.message(L10n.localized("回传结果不完整。", "The returned result is incomplete."))
        }
        let dimensions = try RelayImage.pngDimensions(png)
        guard dimensions == (task.width, task.height) else { throw RelayError.message(L10n.localized("回传图片尺寸不正确。", "The returned image has the wrong size.")) }
        task.revision = packet.revision; task.receiptRevision = packet.revision
        task.state = .copying; task.updatedAt = Date()
        // Record the attempt before the external side effect, so a crash cannot cause a surprise re-copy.
        try store.save(task, ink: ink, result: png, padText: packet.padText)
        do {
            guard let copyImage else { throw RelayError.message(L10n.localized("Mac 剪贴板尚未就绪。", "The Mac clipboard is not ready.")) }
            try copyImage(png)
            task.state = .completed
            try store.save(task)
            lastResultID = task.id; focusedTaskID = task.id; lastEvent = L10n.localized("已复制，可以 ⌘V", "Copied. Press ⌘V to paste")
            transport.send(RelayPacket(kind: .receipt, taskID: task.id, revision: task.revision, success: true))
            onShowPreview?()
            do { try store.prune() }
            catch { errorMessage = L10n.localized("图片已复制，但历史清理失败：\(error.localizedDescription)", "Image copied, but history cleanup failed: \(error.localizedDescription)") }
        } catch {
            task.state = .copyFailed
            try store.save(task)
            lastResultID = task.id; focusedTaskID = task.id; lastEvent = L10n.localized("图片已收到，复制失败", "Image received, but copying failed")
            errorMessage = error.localizedDescription
            transport.send(RelayPacket(kind: .receipt, taskID: task.id, revision: task.revision,
                                       success: false, message: error.localizedDescription))
            onShowPreview?()
        }
    }
}
