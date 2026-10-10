import AppKit
import SwiftUI
import Combine

@MainActor
final class RelayMacController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var collapsed = false
    @Published private(set) var sendGeneration = 0
    private var dismissed = false
    private var expandedFrame: NSRect?
    static let shared = RelayMacController()
    let hub = RelayCoordinator(role: .mac)
    private var panel: NSPanel?
    private var presentingPairing = false
    private var frameBeforePairing: NSRect?
    private var visibleBeforePairing = false
    private var dismissedBeforePairing = false
    private var pairingObservation: AnyCancellable?
    var workbenchStore: WorkbenchStore?
    private var editor: EditWindowController?
    private var liveEditors: [UUID: RelayMacLiveEditor] = [:]
    private var liveObservation: AnyCancellable?
    private var languageObservation: AnyCancellable?
    private override init() {
        super.init()
        hub.copyImage = { data in try Self.writePNG(data, to: .general) }
        hub.collaboration.clipboardChangeCount = { NSPasteboard.general.changeCount }
        liveObservation = hub.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.prepareLiveEditor() }
        }
        prepareLiveEditor()
        languageObservation = AppPreferences.shared.$appLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.panel?.title = L10n.localized("Picelf · 接力画板", "Picelf · Relay Canvas")
            }
        pairingObservation = hub.transport.pairing.$notice.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updatePairingWindow() }
        }
        hub.onShowPreview = { [weak self] in self?.show(automatically: true) }
    }
    private func updatePairingWindow() {
        if hub.transport.pairing.notice != nil {
            guard !presentingPairing else { return }
            visibleBeforePairing = panel?.isVisible == true
            frameBeforePairing = panel?.frame
            dismissedBeforePairing = dismissed
            presentingPairing = true
            show() // Reuse the relay panel; never create a second pairing window.
            panel?.contentMinSize = NSSize(width: 380, height: 520)
            if let panel {
                var frame = panel.frame
                let height = max(frame.height, 560)
                frame.origin.y -= height - frame.height
                frame.size = NSSize(width: max(frame.width, 380), height: height)
                if let screen = panel.screen { frame.origin.y = max(screen.visibleFrame.minY, frame.origin.y) }
                panel.setFrame(frame, display: true)
            }
        } else if presentingPairing {
            panel?.contentMinSize = collapsed ? NSSize(width: 320, height: 64) : NSSize(width: 320, height: 360)
            if let frameBeforePairing { panel?.setFrame(frameBeforePairing, display: true) }
            if !visibleBeforePairing { panel?.orderOut(nil) }
            dismissed = dismissedBeforePairing
            presentingPairing = false
        }
    }
    static func writePNG(_ data: Data, to pasteboard: NSPasteboard) throws {
        _ = try RelayImage.pngDimensions(data)
        // Validate and construct the item BEFORE replacing any user clipboard contents.
        let item = NSPasteboardItem()
        guard item.setData(data, forType: .png) else { throw RelayError.message(L10n.localized("无法准备剪贴板图片。", "Could not prepare the clipboard image.")) }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw RelayError.message(L10n.localized("无法写入剪贴板，请点击再次复制。", "Could not write to the clipboard. Click Copy Again.")) }
    }
    func show(automatically: Bool = false) {
        hub.start()
        if automatically && dismissed { return }
        if !automatically { dismissed = false }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.title = L10n.localized("Picelf · 接力画板", "Picelf · Relay Canvas")
            panel.titlebarAppearsTransparent = true
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentMinSize = NSSize(width: 320, height: 360)
            let hosting = NSHostingView(rootView: RelayMacView(hub: hub, controller: self))
            // Window size belongs to this controller. The pairing card's outgoing
            // intrinsic minimum must not prevent restoration to the compact bar.
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.center()
            if let saved = UserDefaults.standard.string(forKey: "relay.previewFrame") {
                let frame = NSRectFromString(saved)
                if frame.width >= 320, frame.height >= 360,
                   NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { panel.setFrame(frame, display: false) }
            }
            panel.delegate = self
            self.panel = panel
        }
        panel?.orderFrontRegardless() // No NSApp.activate / makeKey call: keep the user's typing focus.
    }
    func toggleCollapsed() {
        guard let panel else { return }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !collapsed {
            expandedFrame = panel.frame
            collapsed = true
            panel.contentMinSize = NSSize(width: 320, height: 64)
            let height = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: panel.frame.width, height: 64)).height
            panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - height, width: panel.frame.width, height: height), display: true, animate: animate)
        } else {
            let height = expandedFrame?.height ?? 488
            panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - height, width: panel.frame.width, height: height), display: true, animate: animate)
            panel.contentMinSize = NSSize(width: 320, height: 360)
            collapsed = false
            saveFrame()
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if presentingPairing {
            visibleBeforePairing = false; dismissedBeforePairing = true
            hub.transport.dismissPairingNotice(); sender.orderOut(nil); return false
        }
        dismissed = true; sender.orderOut(nil); return false
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        guard !collapsed, !presentingPairing, let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "relay.previewFrame")
    }
    func sendImage(_ image: NSImage, title: String = L10n.localized("Picelf 图片", "Picelf Image")) {
        sendGeneration += 1
        show()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            hub.errorMessage = L10n.localized("无法读取图片。", "Could not read the image."); return
        }
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) { try RelayImage.png(cg) }.value
                try hub.addImage(data, width: cg.width, height: cg.height, title: title)
            } catch { hub.errorMessage = error.localizedDescription }
        }
    }
    func sendClipboard() {
        show()
        if let image = NSImage(pasteboard: .general) { sendImage(image, title: L10n.localized("剪贴板图片", "Clipboard Image")); return }
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            sendFiles(urls); return
        }
        hub.errorMessage = L10n.localized("剪贴板中没有图片。请先复制图片，再按快捷键。", "There is no image on the clipboard. Copy an image, then use the shortcut again.")
    }
    func sendFiles(_ urls: [URL]) {
        sendGeneration += 1
        show()
        Task {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? Int.max) <= RelayLimits.maxResourceBytes else {
                        throw RelayError.message(L10n.localized("图片文件过大，请先裁剪或缩小。", "The image is too large. Crop or resize it first."))
                    }
                    let data = try Data(contentsOf: url)
                    try await hub.importImage(data, title: url.deletingPathExtension().lastPathComponent)
                } catch { hub.errorMessage = error.localizedDescription }
            }
        }
    }
    func chooseFile() {
        // Explicit user input needs a key window even though incoming previews do not.
        NSApp.activate()
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png, .jpeg, .heic]
        picker.allowsMultipleSelection = true
        picker.begin { [weak self] response in
            if response == .OK { self?.sendFiles(picker.urls) }
        }
    }
    private func prepareLiveEditor() {
        liveEditors = liveEditors.filter { hub.collaboration.isLive($0.key) }
        guard let id = hub.collaboration.activeID, liveEditors[id] == nil else { return }
        do { liveEditors[id] = try RelayMacLiveEditor(id: id, hub: hub) }
        catch { hub.errorMessage = error.localizedDescription }
    }
    func openLive(_ id: UUID) {
        do {
            if !hub.collaboration.isLive(id) { try hub.collaboration.start(id) }
            prepareLiveEditor()
            guard let live = liveEditors[id] else { return }
            if editor == nil { editor = EditWindowController() }
            editor?.workbenchStore = workbenchStore
            editor?.show(image: live.document.baseImage, applyWatermark: false, relayEditor: live)
        } catch { hub.errorMessage = error.localizedDescription }
    }
    func openResult(_ id: UUID) {
        guard let url = hub.fileURL(id, "result.png"), let image = NSImage(contentsOf: url) else { return }
        if editor == nil { editor = EditWindowController() }
        // The handoff is already rendered; open as a new copy, never overwrite the source task.
        editor?.workbenchStore = workbenchStore
        editor?.show(image: image, applyWatermark: false)
    }
    @objc func annotateOnIPad(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            error.pointee = L10n.localized("请选择 PNG、JPEG 或 HEIC 图片文件。", "Choose PNG, JPEG, or HEIC image files.") as NSString; return
        }
        sendFiles(urls)
    }
}

private struct RelayMacView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject var hub: RelayCoordinator
    @ObservedObject var controller: RelayMacController
    @State private var selectedID: UUID?
    @State private var showHistory = false
    private var selected: RelayTask? {
        if let id = selectedID, let task = hub.task(id) { return task }
        if let id = hub.collaboration.activeID ?? hub.focusedTaskID, let task = hub.task(id) { return task }
        return hub.history.first
    }
    var body: some View {
        let _ = preferences.appLanguage
        VStack(spacing: 0) {
            if hub.transport.pairing.notice != nil {
                RelayPairingCard(transport: hub.transport)
            } else if controller.collapsed {
                HStack(spacing: 12) {
                    Image(systemName: selected?.state == .completed ? "checkmark.circle.fill" : "ipad.and.arrow.forward")
                        .foregroundStyle(RelayPalette.glow).font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.map { hub.collaboration.status($0.id) ?? RelayTaskPresentation(task: $0, role: .mac, connected: hub.transport.connected).title } ?? L10n.localized("接力画板", "Relay Canvas"))
                            .font(.callout.weight(.medium)).lineLimit(1)
                        Text(selected?.title ?? L10n.localized("发送图片，随手标注", "Send an image and annotate it")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { controller.toggleCollapsed() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.plain).help(L10n.localized("展开预览", "Expand Preview")).accessibilityIdentifier("relay.expand")
                }.padding(16).frame(maxHeight: .infinity)
            } else {
                RelayDiscoveryBanner(transport: hub.transport)
                header.padding(.horizontal, 16).padding(.vertical, 12).background(.white.opacity(0.045))
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                if let task = selected {
                    VStack(spacing: 12) {
                        RelayMacPreview(task: task, preview: hub.previews[task.id], hub: hub)
                        HStack {
                            Text(task.title).lineLimit(1)
                            Spacer()
                            Text("\(task.width) × \(task.height)").monospacedDigit().foregroundStyle(.tertiary)
                        }.font(.caption)
                        result(task).padding(12).relayGlassSurface(radius: 14)
                    }.padding(16)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "ipad.and.arrow.forward").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(RelayPalette.glow)
                        Text(L10n.localized("交给 iPad，画完就粘贴", "Annotate on iPad, then paste" )).font(.headline)
                        Text(L10n.localized("复制一张图片，\n从这里开始接力。", "Copy an image, then start here."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button(L10n.localized("发送剪贴板图片", "Send Clipboard Image")) { controller.sendClipboard() }.buttonStyle(RelayActionStyle(prominent: true))
                            .accessibilityIdentifier("relay.sendClipboard")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
                }
                if let error = hub.errorMessage {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        Spacer()
                        Button { hub.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L10n.localized("关闭提示", "Dismiss"))
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .tint(RelayPalette.glow)
        .background { RelayGlassBackground() }
        .environment(\.colorScheme, .dark)
        .onChange(of: controller.sendGeneration) { selectedID = nil }
    }
    private var header: some View {
        HStack(spacing: 12) {
            RelayMacConnection(transport: hub.transport)
            Spacer(minLength: 0)
            Menu {
                Button(L10n.localized("发送剪贴板图片", "Send Clipboard Image")) { controller.sendClipboard() }.accessibilityIdentifier("relay.sendClipboard")
                Button(L10n.localized("打开图片…", "Open Images…")) { controller.chooseFile() }
            } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).help(L10n.localized("发送图片", "Send Image"))
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.plain).help(L10n.localized("最近记录", "Recent Items")).accessibilityIdentifier("relay.history")
                .popover(isPresented: $showHistory) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.localized("最近记录", "Recent Items")).font(.headline)
                            Spacer()
                            Button(L10n.localized("实时预览", "Live Preview")) { selectedID = nil; showHistory = false }
                        }
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(hub.history) { task in
                                    Button { selectedID = task.id; showHistory = false } label: { RelayMacHistoryRow(task: task, hub: hub) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }.padding(16).frame(width: 330, height: 380).background { RelayGlassBackground() }
                }
            Button { controller.toggleCollapsed() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(.plain).help(L10n.localized("收起为状态条", "Collapse to Status Bar")).accessibilityIdentifier("relay.collapse")
        }
    }
    private func result(_ task: RelayTask) -> some View {
        let status = RelayTaskPresentation(task: task, role: .mac, connected: hub.transport.connected)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Label(hub.collaboration.status(task.id) ?? status.title, systemImage: hub.collaboration.isLive(task.id) ? "link" : status.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(status.isFailure ? Color.orange : task.state == .completed ? RelayPalette.glow : .primary)
                    .accessibilityIdentifier("relay.resultState")
                if selectedID != nil {
                    Button(L10n.localized("返回实时预览", "Return to Live Preview")) { selectedID = nil }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                } else if hub.pendingTasks.count > 1 {
                    Text(L10n.localized("\(hub.pendingTasks.count) 张待完成", "\(hub.pendingTasks.count) pending")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if hub.collaboration.isLive(task.id) {
                Button(L10n.localized("打开共同编辑", "Open Shared Edit")) { controller.openLive(task.id) }.controlSize(.small).accessibilityIdentifier("relay.openLive")
            } else if task.state == .editing || task.state == .queued {
                Button(L10n.localized("共同编辑", "Shared Edit")) { controller.openLive(task.id) }.controlSize(.small).accessibilityIdentifier("relay.startLive")
            } else if task.state == .completed || task.state == .copyFailed {
                Button(L10n.localized("再次复制", "Copy Again")) { hub.copyAgain(task.id) }.controlSize(.small)
            } else if task.state == .cancelled {
                Button(L10n.localized("继续标注", "Continue Editing")) { hub.reopen(task.id); selectedID = nil }.controlSize(.small)
            }
            Menu {
                if hub.collaboration.isLive(task.id) {
                    Button(L10n.localized("复制最新并恢复", "Copy Latest and Resume")) { hub.collaboration.resumeClipboard(task.id) }
                    Button(L10n.localized("结束共同编辑", "End Shared Edit")) { hub.collaboration.end(task.id) }
                } else if task.state == .completed || task.state == .copyFailed {
                    Button(L10n.localized("继续在 iPad 标注", "Continue on iPad")) { hub.reopen(task.id); selectedID = nil }
                    Button(L10n.localized("在 Picelf 编辑", "Edit in Picelf")) { controller.openResult(task.id) }
                } else if !task.state.isHistory {
                    Button(L10n.localized("重新发送", "Send Again")) { hub.retryTransfer() }
                    Button(L10n.localized("保留草稿并停止", "Keep Draft and Stop")) { hub.cancel(task.id) }
                }
                if task.state.isHistory { Button(L10n.localized("删除记录", "Delete Item"), role: .destructive) { hub.remove(task.id); selectedID = nil } }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
        }.frame(minHeight: 44).buttonStyle(RelayActionStyle())
    }
}
private struct RelayMacPreview: View {
    let task: RelayTask
    let preview: Data?
    @ObservedObject var hub: RelayCoordinator
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.16))
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(12) }
            else { ProgressView() }
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 160)
        .task(id: "\(task.id)-\(task.state.rawValue)") { await load() }
        .task(id: preview) { await load() }
    }
    private func load() async {
        let name = task.state == .completed || task.state == .copyFailed ? "result.png" : "base.png"
        let currentPreview = name == "result.png" ? nil : preview
        let url = hub.fileURL(task.id, name)
        let cg = await Task.detached(priority: .userInitiated) {
            let bytes = currentPreview ?? url.flatMap { try? Data(contentsOf: $0) }
            return bytes.flatMap { RelayImage.thumbnail($0) }
        }.value
        guard !Task.isCancelled else { return }
        if let cg { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
    }
}
private struct RelayMacHistoryRow: View {
    let task: RelayTask
    let hub: RelayCoordinator
    @State private var thumbnail: NSImage?
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: "doc.richtext") }
            }.frame(width: 56, height: 44).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).lineLimit(1)
                Text(task.state.relayLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(task.updatedAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 8).contentShape(Rectangle())
        .task(id: "\(task.id)-\(task.revision)-\(task.state.rawValue)") {
            let url = hub.fileURL(task.id, task.state == .completed || task.state == .copyFailed ? "result.png" : "base.png")
            if let url, let cg = await Task.detached(priority: .utility, operation: { (try? Data(contentsOf: url)).flatMap { RelayImage.thumbnail($0, edge: 160) } }).value {
                thumbnail = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }
}
private struct RelayMacConnection: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject var transport: RelayTransport
    @State private var expanded = false
    var body: some View {
        Button { expanded = true } label: {
            Label(transport.connected ? L10n.localized("已连接 iPad", "Connected to iPad") : L10n.localized("等待连接", "Waiting to Connect"), systemImage: transport.connected ? "link" : "wifi.slash")
                .font(.callout).foregroundStyle(transport.connected ? RelayPalette.glow : .secondary)
        }.buttonStyle(.plain).accessibilityIdentifier("relay.connection")
        .disabled(transport.pairing.notice != nil)
        .popover(isPresented: $expanded) { details.padding(20).frame(width: 320).background { RelayGlassBackground() } }
        .onChange(of: transport.pairing.notice?.id) { if $0 != nil { expanded = false } }
        .onChange(of: transport.connected) { if $0 { expanded = false } }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.localized("设备连接", "Device Connection")).font(.headline)
            Text(transport.status).font(.callout).foregroundStyle(.secondary)
            if transport.pairing.notice != nil {
                Text(L10n.localized("请在配对窗口中核对并确认。", "Check and confirm the code in the pairing window.")).foregroundStyle(.secondary)
            } else if !transport.connected {
                ForEach(transport.devices) { device in Button(L10n.localized("连接 \(device.name)", "Connect to \(device.name)")) { transport.connect(device) } }
                if transport.devices.isEmpty { Text(L10n.localized("请打开 iPad 接力画板，并允许两端的本地网络访问。", "Open Relay Canvas on iPad and allow Local Network access on both devices.")).foregroundStyle(.secondary) }
            }
            Divider()
            Button(L10n.localized("重新连接", "Reconnect")) { transport.stop(); transport.start() }
            if transport.hasTrustedPeer { Button(L10n.localized("解除配对", "Unpair"), role: .destructive) { transport.forgetPairing() } }
        }
    }
}
