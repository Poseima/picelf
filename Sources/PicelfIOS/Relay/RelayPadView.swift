import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct RelayPadView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var relayColorScheme
    @StateObject private var hub = RelayCoordinator(role: .iPad)
    @Environment(\.scenePhase) private var scenePhase
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showHistory = false
    @State private var showPaper = false
    @State private var importing = false
    @State private var visible = false
    @State private var selectedID: UUID?
    @State private var restored = false
    @ScaledMetric(relativeTo: .body) private var pairingCardHeight: CGFloat = 460
    @SceneStorage("relay.selectedTask") private var savedSelection = ""
    private var testColorScheme: ColorScheme? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--relay-ui-dark") ? .dark : nil
        #else
        return nil
        #endif
    }
    private var pairingVisible: Bool {
        visible && scenePhase == .active && hub.transport.pairing.notice != nil
            && !showPhotos && !showFiles && !showHistory && !showPaper && hub.errorMessage == nil
    }
    private var selected: RelayTask? { selectedID.flatMap(hub.task) }
    private var queue: [RelayTask] { hub.history.reversed().filter { $0.state == .queued && $0.id != selectedID } }

    var body: some View {
        let _ = preferences.appLanguage
        ZStack {
        NavigationStack {
            Group {
                if let task = selected {
                    RelayPadEditor(task: task, hub: hub, nextCount: queue.count,
                                   leave: { selectedID = nil },
                                   next: { selectedID = queue.first?.id },
                                   reopen: { if let id = hub.reopen(task.id) { selectedID = id } })
                        .id(task.id)
                } else { waiting }
            }
            .safeAreaInset(edge: .top, spacing: 0) { RelayDiscoveryBanner(transport: hub.transport) }
            .navigationTitle(selected == nil ? L10n.localized("接力画板", "Relay Canvas") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(selected == nil ? .visible : .hidden, for: .navigationBar)
            .toolbar(selected == nil ? .visible : .hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { RelayPadConnectionBadge(transport: hub.transport) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showHistory = true } label: { Label(L10n.localized("最近记录", "Recent Items"), systemImage: "clock.arrow.circlepath") }
                        .accessibilityIdentifier("relay.history").frame(minWidth: 44, minHeight: 44)
                }
            }
            .background { RelayGlassBackground() }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .sheet(isPresented: $showHistory) {
                RelayPadHistory(hub: hub) { selectedID = $0; showHistory = false }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.png, .jpeg, .heic], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    importData(try Data(contentsOf: url), title: url.deletingPathExtension().lastPathComponent)
                } catch { hub.errorMessage = error.localizedDescription }
            }
            .onChange(of: photo) { value in
                guard let value else { return }
                Task {
                    do { if let data = try await value.loadTransferable(type: Data.self) { importData(data, title: L10n.localized("iPad 照片", "iPad Photo")) } }
                    catch { hub.errorMessage = error.localizedDescription }
                    photo = nil
                }
            }
            .alert(L10n.localized("接力画板", "Relay Canvas"), isPresented: Binding(get: { hub.errorMessage != nil }, set: { if !$0 { hub.errorMessage = nil } })) {
                Button(L10n.localized("好", "OK"), role: .cancel) { hub.errorMessage = nil }
            } message: { Text(hub.errorMessage ?? "") }
        }
        .allowsHitTesting(!pairingVisible)
        .accessibilityHidden(pairingVisible)
            if pairingVisible {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea().onTapGesture {}
                        ScrollView {
                            RelayPairingCard(transport: hub.transport)
                        }
                        .frame(maxWidth: 440)
                        .frame(height: min(pairingCardHeight, max(100, geometry.size.height - 32)))
                        .relayGlassSurface(radius: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(16)
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .tint(RelayPalette.accent(in: relayColorScheme))
        .preferredColorScheme(testColorScheme)
        .onAppear {
            visible = true; setActive(true)
            if !restored {
                let saved = UUID(uuidString: savedSelection).flatMap(hub.task)
                selectedID = hub.collaboration.activeID ?? saved?.id ?? hub.activeTask?.id ?? hub.history.first(where: { $0.state == .returning })?.id
                restored = true
            }
        }
        .onDisappear { visible = false; setActive(false) }
        .onChange(of: selectedID) { savedSelection = $0?.uuidString ?? "" }
        .onChange(of: hub.collaboration.activeID) { id in
            // A session explicitly pins its document; queue arrivals never change it.
            if let id { selectedID = id }
        }
        .onChange(of: hub.focusedTaskID) { id in
            // Incoming work never replaces the work being viewed, including a result.
            if selectedID == nil, let id, hub.task(id)?.state == .queued { selectedID = id }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { setActive(false) }
            else if phase == .active { setActive(visible) }
        }
    }
    private var waiting: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image(systemName: "pencil.and.outline").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(RelayPalette.accent(in: relayColorScheme))
                    Text(L10n.localized("从一张图片开始", "Start with an Image")).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    Text(L10n.localized("Mac 发来的图片会在这里打开。\n也可以新建画布，随手画下想法。", "Images from your Mac open here.\nYou can also create a blank canvas and sketch an idea."))
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { startActions }
                    VStack(spacing: 12) { startActions }
                }.fixedSize(horizontal: false, vertical: true)
                if importing { ProgressView(L10n.localized("正在打开图片…", "Opening image…")) }
                if !queue.isEmpty {
                    Button(L10n.localized("继续下一张 · \(queue.count)", "Continue to Next · \(queue.count)")) { selectedID = queue.first?.id }.frame(minHeight: 44)
                }
                if !hub.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.localized("最近作品", "Recent Work")).font(.headline)
                            Spacer()
                            Button(L10n.localized("查看全部", "See All")) { showHistory = true }.frame(minHeight: 44)
                        }
                        ForEach(hub.history.prefix(3)) { task in
                            Button { selectedID = task.id } label: { RelayPadHistoryRow(task: task, hub: hub, showsStatus: false) }
                                .buttonStyle(.plain)
                        }
                    }.padding(20).relayGlassSurface()
                }
            }.frame(maxWidth: 560).padding(32).padding(.top, 40).frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private var startActions: some View {
        Button { showPaper = true } label: { Label(L10n.localized("新建画布", "New Canvas"), systemImage: "plus").padding(.vertical, 8).padding(.horizontal, 12) }
            .buttonStyle(RelayActionStyle(prominent: true)).controlSize(.large).accessibilityIdentifier("relay.newPaper")
            // Anchor to the actual button, not the full-height navigation content.
            .popover(isPresented: $showPaper, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                RelayPaperPicker { landscape in
                    showPaper = false
                    if let landscape { newPaper(landscape: landscape) }
                }
            }
        Menu {
            Button(L10n.localized("从照片选择", "Choose from Photos"), systemImage: "photo") { showPhotos = true }
            Button(L10n.localized("打开文件", "Open File"), systemImage: "folder") { showFiles = true }
            Button(L10n.localized("粘贴图片", "Paste Image"), systemImage: "doc.on.clipboard") {
                guard let image = UIPasteboard.general.image, let data = image.pngData() else {
                    hub.errorMessage = L10n.localized("剪贴板中没有可用的图片。", "There is no usable image on the clipboard."); return
                }
                importData(data, title: L10n.localized("iPad 剪贴板图片", "iPad Clipboard Image"))
            }
        } label: { Label(L10n.localized("导入图片", "Import Image"), systemImage: "photo.on.rectangle").padding(.vertical, 8).padding(.horizontal, 12) }
            .buttonStyle(RelayActionStyle()).controlSize(.large)
    }
    private func setActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active
        if active { hub.start() } else { hub.transport.stop() }
    }
    private func importData(_ data: Data, title: String) {
        importing = true
        Task {
            do { let id = try await hub.importImage(data, title: title); if hub.collaboration.activeID == nil { selectedID = id } }
            catch { hub.errorMessage = error.localizedDescription }
            importing = false
        }
    }
    private func newPaper(landscape: Bool) {
        let size = landscape ? CGSize(width: 2048, height: 1536) : CGSize(width: 1536, height: 2048)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        if let png = image.pngData() { importData(png, title: L10n.localized("白纸画作", "Blank Canvas")) }
    }
}

private struct RelayPaperPicker: View {
    @Environment(\.colorScheme) private var relayColorScheme
    let choose: (Bool?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.localized("画布方向", "Canvas Orientation")).font(.headline)
                Spacer(minLength: 12)
                Button(L10n.cancel) { choose(nil) }.frame(minHeight: 44)
            }
            orientation(L10n.localized("横向画布", "Landscape Canvas"), landscape: true)
            orientation(L10n.localized("竖向画布", "Portrait Canvas"), landscape: false)
        }
        .padding(20)
        .frame(idealWidth: 340, maxWidth: 380)
        .fixedSize(horizontal: false, vertical: true)
        .tint(RelayPalette.accent(in: relayColorScheme))
    }
    private func orientation(_ title: String, landscape: Bool) -> some View {
        Button { choose(landscape) } label: {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(RelayPalette.accent(in: relayColorScheme).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(RelayPalette.accent(in: relayColorScheme), lineWidth: 2))
                    .frame(width: landscape ? 42 : 30, height: landscape ? 30 : 42)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .relayGlassSurface(radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct RelayPadConnectionBadge: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var relayColorScheme
    @ObservedObject var transport: RelayTransport
    @State private var expanded = false
    var body: some View {
        let _ = preferences.appLanguage
        Button { expanded = true } label: {
            Label(transport.connected ? L10n.localized("已连接 Mac", "Connected to Mac") : L10n.localized("等待连接", "Waiting to Connect"), systemImage: transport.connected ? "link" : "wifi.slash")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(transport.connected ? RelayPalette.accent(in: relayColorScheme) : .secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("relay.connection")
        .disabled(transport.pairing.notice != nil)
        .popover(isPresented: $expanded) { details.padding(24).frame(idealWidth: 340) }
        .onChange(of: transport.pairing.notice?.id) { if $0 != nil { expanded = false } }
        .onChange(of: transport.connected) { if $0 { expanded = false } }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.localized("设备连接", "Device Connection")).font(.headline)
            Text(transport.status).font(.subheadline).foregroundStyle(.secondary)
            if transport.pairing.notice != nil {
                Text(L10n.localized("请在配对卡中核对并确认。", "Check and confirm the code on the pairing card.")).foregroundStyle(.secondary)
            } else if !transport.connected {
                ForEach(transport.devices) { device in Button(L10n.localized("连接 \(device.name)", "Connect to \(device.name)")) { transport.connect(device) }.frame(minHeight: 44) }
                if transport.devices.isEmpty { Text(L10n.localized("请打开 Mac 接力画板，并允许两端的本地网络访问。", "Open Relay Canvas on Mac and allow Local Network access on both devices.")).foregroundStyle(.secondary) }
            }
            Button(L10n.localized("重新连接", "Reconnect")) { transport.stop(); transport.start() }.frame(minHeight: 44)
            if transport.hasTrustedPeer { Button(L10n.localized("解除配对", "Unpair"), role: .destructive) { transport.forgetPairing() }.frame(minHeight: 44) }
            Button(L10n.done) { expanded = false }.frame(minHeight: 44)
        }
    }
}

private struct RelayPadEditor: View {
    let task: RelayTask
    @ObservedObject var hub: RelayCoordinator
    let nextCount: Int
    let leave: () -> Void
    let next: () -> Void
    let reopen: () -> Void
    @State private var model: RelayDrawingModel?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let model {
                RelayPadCanvasControls(model: model, task: task, hub: hub, nextCount: nextCount, leave: leave, next: next, reopen: reopen)
            } else { ProgressView(L10n.localized("正在打开画布…", "Opening canvas…")) }
        }
        .task {
            do { model = try RelayDrawingModel(task: task, hub: hub); hub.beginEditing(task.id) }
            catch { hub.errorMessage = error.localizedDescription }
        }
        .onDisappear { model?.pause() }
        .onChange(of: scenePhase) { phase in if phase == .background { model?.pause() } else if phase == .active { model?.resume() } }
        .onChange(of: hub.transport.connected) { connected in if connected { model?.resume() } }
    }
}
private struct RelayPadCanvasControls: View {
    @Environment(\.colorScheme) private var relayColorScheme
    @ObservedObject var model: RelayDrawingModel
    let task: RelayTask
    @ObservedObject var hub: RelayCoordinator
    let nextCount: Int
    let leave: () -> Void
    let next: () -> Void
    let reopen: () -> Void
    @State private var saveFailed = false
    @AppStorage("relay.didShowDictationHint") private var didShowDictationHint = false
    @State private var showDictationHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var live: Bool { hub.collaboration.isLive(task.id) }
    private var editable: Bool { (task.state == .editing || task.state == .queued) && hub.collaboration.session(task.id)?.closing != true }
    private var status: RelayTaskPresentation { .init(task: task, role: .iPad, connected: hub.transport.connected) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: exitCanvas) { Image(systemName: "chevron.backward").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.localized("保存并返回", "Save and Return")).accessibilityIdentifier("relay.back").disabled(model.busy)
                RelayPadConnectionBadge(transport: hub.transport).labelStyle(.iconOnly)
                if editable {
                    Button {
                        model.chooseText()
                        if !didShowDictationHint { showDictationHint = true; didShowDictationHint = true }
                    } label: {
                        Image(systemName: "textformat").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.localized("添加文字", "Add Text")).accessibilityIdentifier("relay.textTool")
                    if model.textMode || model.selectedTextID != nil {
                        Button { model.chooseDrawing(); showDictationHint = false } label: {
                            Image(systemName: "pencil.tip").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                        }.accessibilityLabel(L10n.localized("继续绘画", "Continue Drawing")).accessibilityIdentifier("relay.drawTool")
                    }
                }
                Spacer(minLength: 0)
                if editable {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }
                        .disabled(!model.canUndo || model.busy).accessibilityLabel(L10n.localized("撤销", "Undo")).accessibilityIdentifier("relay.undo")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }
                        .disabled(!model.canRedo || model.busy).accessibilityLabel(L10n.localized("重做", "Redo")).accessibilityIdentifier("relay.redo")
                }
                Menu {
                    Button(L10n.localized("适合屏幕", "Fit to Screen"), systemImage: "arrow.up.left.and.arrow.down.right") { model.fitCanvas?() }
                    if editable && !live { Button(L10n.localized("共同编辑", "Shared Edit")) { model.startShared() }.accessibilityIdentifier("relay.startLive") }
                    if editable {
                        Button(model.fingerDrawing ? L10n.localized("关闭手指绘画", "Disable Finger Drawing") : L10n.localized("开启手指绘画", "Enable Finger Drawing")) { model.fingerDrawing.toggle() }
                            .accessibilityIdentifier("relay.fingerDrawing")
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.localized("画布选项", "Canvas Options")).accessibilityIdentifier("relay.canvasOptions")
                if editable {
                    Button { model.complete() } label: {
                        HStack(spacing: 6) { if model.busy { ProgressView() }; Text(model.busy ? L10n.localized("正在准备", "Preparing") : live ? L10n.localized("结束共同编辑", "End Shared Edit") : L10n.done) }.frame(minHeight: 32)
                    }.buttonStyle(RelayActionStyle(prominent: true)).disabled(model.busy).accessibilityIdentifier("relay.complete")
                } else if task.state.isHistory {
                    Button(L10n.localized("继续修改", "Continue Editing"), action: reopen).buttonStyle(RelayActionStyle(prominent: true)).frame(minHeight: 44).accessibilityIdentifier("relay.continue")
                } else {
                    Image(systemName: status.isFailure ? "exclamationmark.circle" : "arrow.up.circle")
                        .foregroundStyle(status.isFailure ? .orange : RelayPalette.accent(in: relayColorScheme)).frame(width: 44, height: 44)
                }
            }.padding(.horizontal, 12).padding(.vertical, 6).relayGlassSurface(radius: 0)
            if editable, let box = model.selectedText { RelayTextStyleBar(model: model, box: box) }
            if editable && (showDictationHint || model.textInsertionArmed) {
                HStack {
                    Text(model.textInsertionArmed ? L10n.localized("点图片放置文本框", "Tap the image to place a text box") : L10n.localized("点键盘麦克风，可语音输入", "Tap the keyboard microphone to dictate"))
                        .font(.subheadline)
                    Spacer()
                    if showDictationHint {
                        Button(L10n.localized("知道了", "Got It")) { showDictationHint = false }.frame(minHeight: 44)
                    }
                }.padding(.horizontal, 20).relayGlassSurface(radius: 0)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Label(hub.collaboration.status(task.id) ?? status.title, systemImage: live ? "link" : status.symbol).font(.subheadline)
                        .foregroundStyle(status.isFailure ? Color.orange : task.state == .completed ? RelayPalette.accent(in: relayColorScheme) : .secondary)
                        .accessibilityIdentifier("relay.status")
                }
                Spacer(minLength: 0)
                if live && hub.collaboration.session(task.id)?.failure != nil { Button(L10n.localized("重试保存", "Retry Save")) { hub.collaboration.end(task.id) }.frame(minHeight: 44) }
                if task.state == .returning && !status.isFailure {
                    Button(L10n.localized("重新发送", "Send Again")) { hub.retryTransfer() }.frame(minHeight: 44)
                }
                if nextCount > 0 && !editable && !live {
                    Button(L10n.localized("下一张 · \(nextCount)", "Next · \(nextCount)")) { if model.flush() { next() } else { saveFailed = true } }
                        .frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("relay.next")
                }
            }.padding(.horizontal, 20).padding(.vertical, 10).relayGlassSurface(radius: 0)
            if !live && !model.texts.boxes.isEmpty && hub.transport.connected && !hub.collaboration.peerSupportsText {
                Text(L10n.localized("Mac 版本较旧：可回传完整图片；跨端保留可编辑文字需要更新 Mac。", "The Mac app is out of date. You can still send the finished image, but editable text across devices requires an update."))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
            }
            RelayDrawingCanvas(model: model, editable: editable).accessibilityIdentifier("relay.canvas")
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: task.state)
        .alert(L10n.localized("草稿暂未保存", "Draft Not Saved Yet"), isPresented: $saveFailed) {
            Button(L10n.localized("重试保存", "Retry Save"), action: exitCanvas)
            Button(L10n.localized("留在画布", "Stay on Canvas"), role: .cancel) {}
        } message: { Text(L10n.localized("画布已保留，请重试保存后再返回。", "Your canvas is still open. Retry saving before going back.")) }
    }
    private func exitCanvas() {
        model.finishTextInput?()
        guard model.flush() else { hub.errorMessage = nil; saveFailed = true; return }
        model.suspendTools()
        if editable && !live { hub.cancel(task.id) }
        leave()
    }
}

private struct RelayTextStyleBar: View {
    @ObservedObject var model: RelayDrawingModel
    let box: RelayTextBox
    private func change(_ action: (inout RelayTextBox) -> Void) {
        model.finishTextInput?()
        model.updateTextBox(box.id, action)
    }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if model.editingTextID != nil {
                    Button(L10n.localized("完成输入", "Finish Typing")) { model.chooseDrawing() }.frame(minHeight: 44)
                        .accessibilityIdentifier("relay.finishText")
                } else {
                    Button(L10n.localized("编辑", "Edit")) { model.textMode = true; model.editingTextID = box.id }
                        .frame(minHeight: 44).accessibilityIdentifier("relay.editText")
                }
                Menu {
                    ForEach([16, 24, 32, 48, 64, 96, 128, 192, 256], id: \.self) { size in
                        Button("\(size)") { change { $0.fontSize = Double(size) } }
                    }
                } label: { Text(L10n.localized("字号 \(Int(box.fontSize))", "Size \(Int(box.fontSize))")).frame(minHeight: 44) }
                    .accessibilityIdentifier("relay.textSize")
                Menu {
                    ForEach(RelayTextBox.Color.allCases, id: \.self) { color in
                        Button(colorName(color)) { change { $0.color = color } }
                    }
                } label: { Image(systemName: "circle.fill").foregroundStyle(Color(uiColor: RelayTextLayout.color(box.color))).frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.localized("文字颜色", "Text Color"))
                Button { change { $0.bold.toggle() } } label: {
                    Image(systemName: "bold").frame(width: 44, height: 44)
                }.accessibilityLabel(box.bold ? L10n.localized("取消粗体", "Turn Off Bold") : L10n.localized("粗体", "Bold")).accessibilityIdentifier("relay.textBold")
                Menu {
                    Button(L10n.localized("左对齐", "Align Left")) { change { $0.alignment = .left } }
                    Button(L10n.localized("居中", "Center")) { change { $0.alignment = .center } }
                    Button(L10n.localized("右对齐", "Align Right")) { change { $0.alignment = .right } }
                } label: { Image(systemName: "text.align\(box.alignment.rawValue)").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.localized("文字对齐", "Text Alignment"))
                Button { change { $0.background.toggle() } } label: {
                    Image(systemName: box.background ? "rectangle.fill" : "rectangle").frame(width: 44, height: 44)
                }.accessibilityLabel(box.background ? L10n.localized("移除浅色背景", "Remove Light Background") : L10n.localized("添加浅色背景", "Add Light Background")).accessibilityIdentifier("relay.textBackground")
                Button(role: .destructive) { model.deleteSelectedText() } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }.accessibilityLabel(L10n.localized("删除文本框", "Delete Text Box")).accessibilityIdentifier("relay.deleteText")
            }.font(.system(size: 17, weight: .medium)).padding(.horizontal, 16)
        }.fixedSize(horizontal: false, vertical: true).relayGlassSurface(radius: 0)
    }
    private func colorName(_ color: RelayTextBox.Color) -> String {
        switch color {
        case .charcoal: return L10n.localized("深灰", "Charcoal")
        case .white: return L10n.localized("白色", "White")
        case .emerald: return L10n.localized("翡翠绿", "Emerald")
        case .red: return L10n.localized("红色", "Red")
        case .blue: return L10n.localized("蓝色", "Blue")
        }
    }
}
private struct RelayPadHistoryRow: View {
    let task: RelayTask
    let hub: RelayCoordinator
    var showsStatus = true
    @State private var thumbnail: UIImage?
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: "doc.richtext").foregroundStyle(.secondary) }
            }.frame(width: 72, height: 56).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.06), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.body).lineLimit(1)
                if showsStatus { Text(task.state.relayLabel).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(task.updatedAt, style: .date).font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 6).contentShape(Rectangle())
        .task(id: "\(task.id)-\(task.revision)-\(task.state.rawValue)") {
            let url = hub.fileURL(task.id, task.state == .completed || task.state == .returning ? "result.png" : "base.png")
            if let url, let cg = await Task.detached(priority: .utility, operation: { (try? Data(contentsOf: url)).flatMap { RelayImage.thumbnail($0, edge: 160) } }).value {
                thumbnail = UIImage(cgImage: cg)
            }
        }
    }
}
private struct RelayPadHistory: View {
    @ObservedObject var hub: RelayCoordinator
    let select: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(hub.history) { task in
                Button { select(task.id) } label: { RelayPadHistoryRow(task: task, hub: hub) }.buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions { Button(L10n.stickerDelete, role: .destructive) { hub.remove(task.id) } }
            }
            .scrollContentBackground(.hidden)
            .background { RelayGlassBackground() }
            .navigationTitle(L10n.localized("最近记录", "Recent Items"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.done) { dismiss() } } }
        }
    }
}
