import AppKit
import SwiftUI
import KeyboardShortcuts
import Combine
import os

private let log = Logger(subsystem: "com.picelf", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var orchestrator: CaptureOrchestrator!
    private var editWindowController: EditWindowController?
    private var canvasWindowController: CanvasWindowController?
    private var workbenchStore: WorkbenchStore!
    private var workbenchWindowController: WorkbenchWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isMenuCaptureRequestInFlight = false

    // Pin-to-desktop
    private var pinnedPanels: [UUID: PinnedImagePanel] = [:]
    private static let maxPins = 20
    private var bindingMonitor = PinBindingMonitor()
    private let captureShortcutMigrationFlag = "picelf_migrated_capture_shortcut_option_a_v1"
    private let captureShortcutDefaultsKey = "KeyboardShortcuts_startCapture"
    private let legacyCommandAModifierMask = 256
    private let optionAModifierMask = 2048

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("App launched — applicationDidFinishLaunching")
        if ProcessInfo.processInfo.arguments.contains("--uitest-open-preferences"),
           let suite = ProcessInfo.processInfo.environment["PICELF_UI_TEST_PREFERENCES_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            defaults.removePersistentDomain(forName: suite)
            AppPreferences.shared = AppPreferences(defaults: defaults)
            AppPreferences.shared.appLanguage = AppLanguageOption.en.rawValue
            if ProcessInfo.processInfo.environment["PICELF_UI_TEST_PREFERENCES_FIXTURES"] == "1" {
                AppPreferences.shared.defaultFormat = .jpeg
                AppPreferences.shared.savePath = "/Users/example/Documents/Research/A very long folder name for exported captures/Images"
                AppPreferences.shared.presets = (1...20).map {
                    RegionPreset(name: "Research capture region \($0)", width: 1920, height: 1080)
                }
            }
        }
        NSApp.setActivationPolicy(.regular)
        setupMenuBar()
        migrateCaptureShortcutIfNeeded()
        let purgedArtifacts = AppDataHygiene.purgeWorkbenchTestArtifactsInTemporaryDirectory()
        if purgedArtifacts > 0 {
            log.notice("Purged \(purgedArtifacts) stale workbench test artifact(s) from temporary directory")
        }

        workbenchStore = WorkbenchStore(maxConcurrentJobs: 2)
        RelayMacController.shared.workbenchStore = workbenchStore
        workbenchStore.onOpenImage = { [weak self] image, url in
            self?.showEditWindow(image: image, sourceURL: url)
        }
        workbenchStore.onOpenCanvas = { [weak self] images in
            self?.showCanvas(images: images)
        }
        workbenchStore.onAddToCanvas = { [weak self] image in
            self?.addToCanvas(image: image)
        }
        workbenchStore.onPinImage = { [weak self] image, jobID in
            self?.pinImage(image: image, sourceJobID: jobID)
        }
        workbenchStore.$jobs
            .sink { [weak self] _ in
                self?.refreshStatusItemState()
            }
            .store(in: &cancellables)
        workbenchWindowController = WorkbenchWindowController(store: workbenchStore)
        refreshStatusItemState()

        preferencesWindowController = PreferencesWindowController()

        orchestrator = CaptureOrchestrator()
        orchestrator.onCaptureSubmitted = { [weak self] submission in
            guard let self else { return }
            self.workbenchStore.enqueue(submission: submission)
        }
        orchestrator.onStitchingComplete = { [weak self] image in
            log.info("Stitching complete callback — image \(Int(image.size.width))x\(Int(image.size.height)), showing edit window")
            self?.showEditWindow(image: image)
        }
        orchestrator.onSnapEditConfirmed = { [weak self] image, windowInfo, captureRect in
            self?.workbenchStore.addCompletedSnap(image: image, windowInfo: windowInfo, captureRect: captureRect)
        }
        orchestrator.onOpenEditorWithOCR = { [weak self] image in
            self?.showEditWindow(image: image, autoOCR: true)
        }
        orchestrator.onOpenEditorWithTranslation = { [weak self] image in
            self?.showEditWindow(
                image: image,
                autoTranslate: AppPreferences.shared.translationAutoRunFromSnapEdit
            )
        }
        orchestrator.onOpenEditorWithExtract = { [weak self] image in
            self?.showEditWindow(image: image, autoExtract: true)
        }
        orchestrator.onPinImage = { [weak self] image in
            self?.pinImage(image: image)
        }
        orchestrator.onPinFromSnapEdit = { [weak self] image, windowInfo, captureRect in
            guard let self else { return }
            let jobID = self.workbenchStore.addCompletedSnap(image: image, windowInfo: windowInfo, captureRect: captureRect)
            self.workbenchStore.markPinned(jobID: jobID)
            self.pinImage(image: image, sourceJobID: jobID)
        }
        orchestrator.onWillActivate = { [weak self] in
            self?.lowerPinLevels()
        }
        orchestrator.onDidDeactivate = { [weak self] in
            self?.raisePinLevels()
        }

        NSApp.servicesProvider = RelayMacController.shared
        NSUpdateDynamicServices()
        // Deterministic test hosts must not react to desktop hotkeys. Signed
        // live tests can explicitly opt in to the normal shortcut callbacks.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            || ProcessInfo.processInfo.environment["PICELF_RUN_LIVE_TESTS"] == "1" {
            KeyboardShortcuts.onKeyUp(for: .startCapture) { [weak self] in
                log.info("[USER] Global hotkey pressed — starting capture")
                self?.startCapture()
            }
            KeyboardShortcuts.onKeyUp(for: .sendToIPad) {
                RelayMacController.shared.sendClipboard()
            }
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
           UserDefaults.standard.string(forKey: "relay.lastPeerName") != nil {
            RelayMacController.shared.hub.start()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-open-relay") {
            RelayMacController.shared.show()
        }

        restorePins()

        bindingMonitor.onShowPin = { [weak self] id in
            self?.pinnedPanels[id]?.orderFront(nil)
        }
        bindingMonitor.onHidePin = { [weak self] id in
            self?.pinnedPanels[id]?.orderOut(nil)
        }
        bindingMonitor.onOrderPinAbove = { [weak self] id, windowNumber in
            guard let panel = self?.pinnedPanels[id] else { return }
            if !panel.isVisible { panel.orderFront(nil) }
            panel.order(.above, relativeTo: windowNumber)
        }
        bindingMonitor.reconfigure(panels: pinnedPanels)

        UpdateController.shared.onInstallationDeferred = { [weak self] in
            self?.preferencesWindowController?.show(tab: .general)
        }
        UpdateController.shared.start { [weak self] in
            self?.updateActivity ?? UpdateActivity()
        }

        if ProcessInfo.processInfo.arguments.contains("--uitest-open-preferences") {
            preferencesWindowController?.show()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-open-editor") {
            showEditWindow(image: makeUITestImage())
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-open-canvas") {
            showCanvas(images: [makeUITestImage()])
        }
    }

    private var updateActivity: UpdateActivity {
        let capture = orchestrator?.captureState
        let recording = orchestrator?.recordingOrchestrator
        let relay = RelayMacController.shared.hub
        return UpdateActivity(
            capture: capture?.isCapturing == true || capture?.isStitching == true ||
                capture?.isSnapEditing == true || orchestrator?.framePanel?.isVisible == true,
            recording: recording?.showingConfig == true || recording?.isPreparingRecording == true ||
                recording?.isRecording == true,
            jobs: (workbenchStore?.runningCount ?? 0) + (workbenchStore?.queuedCount ?? 0) > 0,
            relay: relay.collaboration.activeID != nil || relay.tasks.contains {
                $0.state == .editing || $0.state == .returning
            },
            editor: editWindowController?.hasOpenWindow == true || RelayMacController.shared.hasOpenEditor,
            canvas: canvasWindowController?.hasOpenWindow == true
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        UpdateController.shared.shouldAllowTermination() ? .terminateNow : .terminateCancel
    }

    private func migrateCaptureShortcutIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: captureShortcutMigrationFlag) == false else { return }
        defer { defaults.set(true, forKey: captureShortcutMigrationFlag) }

        // Only migrate the legacy default (Command + A). User-customized shortcuts are preserved.
        guard let rawShortcut = defaults.string(forKey: captureShortcutDefaultsKey),
              let data = rawShortcut.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyCode = object["carbonKeyCode"] as? Int,
              let modifiers = object["carbonModifiers"] as? Int else {
            return
        }

        guard keyCode == 0, modifiers == legacyCommandAModifierMask else { return }

        let migrated = #"{"carbonKeyCode":0,"carbonModifiers":\#(optionAModifierMask)}"#
        defaults.set(migrated, forKey: captureShortcutDefaultsKey)
        log.info("Migrated capture shortcut default from Command+A to Option+A")
    }

    private func setupMenuBar() {
        ensureStatusItem()
        refreshStatusItemState()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWorkbench()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard NSApp.windows.contains(where: { $0.isVisible }) == false else { return }
        if let orchestrator {
            let hasOverlayPanels = orchestrator.framePanel != nil
                || orchestrator.toolbarPanel != nil
                || orchestrator.previewPanel != nil
                || orchestrator.dimmingWindow != nil
                || orchestrator.magnifierPanel != nil
            guard hasOverlayPanels == false else { return }
        }
        openWorkbench()
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(handleLeftClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        statusItem = item
    }

    private func refreshStatusItemState() {
        ensureStatusItem()
        guard let button = statusItem?.button else { return }
        let running = workbenchStore?.runningCount ?? 0
        let queued = workbenchStore?.queuedCount ?? 0
        let pending = running + queued

        if button.image == nil {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true
            button.image = icon
        }

        if pending > 0 {
            button.toolTip = L10n.appStatus(running, queued)
        } else {
            button.toolTip = "Picelf"
        }
    }

    @objc private func handleLeftClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            log.info("[USER] Right-clicked menu bar icon — showing context menu")
            showContextMenu()
        } else {
            log.info("[USER] Left-clicked menu bar icon — opening workbench")
            openWorkbench()
        }
    }

    @objc private func startCapture() {
        Task {
            await orchestrator.activate()
        }
    }

    private func showEditWindow(
        image: NSImage,
        sourceURL: URL? = nil,
        autoOCR: Bool = false,
        autoExtract: Bool = false,
        autoTranslate: Bool = false
    ) {
        log.info("Opening edit window for image \(Int(image.size.width))x\(Int(image.size.height)) autoOCR=\(autoOCR) autoExtract=\(autoExtract) autoTranslate=\(autoTranslate)")
        if editWindowController == nil {
            editWindowController = EditWindowController()
            editWindowController?.workbenchStore = workbenchStore
            editWindowController?.onPinImage = { [weak self] composed in
                self?.pinImage(image: composed)
            }
        }
        editWindowController?.show(
            image: image,
            sourceURL: sourceURL,
            autoOCR: autoOCR,
            autoExtract: autoExtract,
            autoTranslate: autoTranslate
        )
    }

    private func showCanvas(images: [NSImage]) {
        if canvasWindowController == nil {
            canvasWindowController = CanvasWindowController()
            canvasWindowController?.workbenchStore = workbenchStore
        }
        canvasWindowController?.show(images: images)
    }

    private func addToCanvas(image: NSImage) {
        if canvasWindowController == nil {
            canvasWindowController = CanvasWindowController()
            canvasWindowController?.workbenchStore = workbenchStore
        }
        canvasWindowController?.addItem(image: image)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let shortcutItem = NSMenuItem(title: captureShortcutMenuTitle(), action: #selector(startCaptureFromMenu), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)
        menu.addItem(NSMenuItem.separator())


        let running = workbenchStore.runningCount
        let queued = workbenchStore.queuedCount
        let workbenchTitle = (running + queued) > 0
            ? L10n.workbenchStatus(running, queued)
            : L10n.workbench
        let workbenchItem = NSMenuItem(title: workbenchTitle, action: #selector(openWorkbench), keyEquivalent: "w")
        workbenchItem.target = self
        menu.addItem(workbenchItem)

        let relayItem = NSMenuItem(title: L10n.localized("接力画板 · iPad 标注", "Relay Canvas · Annotate on iPad"), action: #selector(openRelay), keyEquivalent: "")
        relayItem.target = self
        menu.addItem(relayItem)
        let sendItem = NSMenuItem(title: L10n.localized("发送剪贴板图片到 iPad", "Send Clipboard Image to iPad"), action: #selector(sendClipboardToIPad), keyEquivalent: "")
        sendItem.target = self
        menu.addItem(sendItem)

        let prefsItem = NSMenuItem(title: L10n.preferences, action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(UpdateController.shared.makeMenuItem())

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Clear so left-click works again
    }

    @objc private func openRelay() { RelayMacController.shared.show() }
    @objc private func sendClipboardToIPad() { RelayMacController.shared.sendClipboard() }

    @objc func openPreferences() {
        preferencesWindowController?.show()
    }

    @objc private func startCaptureFromMenu() {
        guard !isMenuCaptureRequestInFlight else {
            log.debug("[USER] Context menu start capture ignored — request already in flight")
            return
        }

        isMenuCaptureRequestInFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isMenuCaptureRequestInFlight = false }
            log.info("[USER] Context menu start capture selected")
            await self.orchestrator.startOrRestartFromMenu()
        }
    }

    @objc private func openWorkbench() {
        workbenchWindowController?.show(activate: true)
    }

    private func captureShortcutMenuTitle() -> String {
        let shortcutLabel = KeyboardShortcuts.getShortcut(for: .startCapture)?.description ?? L10n.notSet
        return L10n.startCaptureWithShortcut(shortcutLabel)
    }

    // MARK: - Pin to Desktop

    private func pinImage(image: NSImage, sourceJobID: UUID? = nil) {
        guard pinnedPanels.count < Self.maxPins else {
            log.warning("Max pin count reached (\(Self.maxPins))")
            return
        }

        let pinID = UUID()
        let originalSize = image.size

        // Reuse workbench output file if available; otherwise create a new one
        let imageURL: URL
        if let jobID = sourceJobID,
           let job = workbenchStore.jobs.first(where: { $0.id == jobID }),
           let existingURL = job.outputURL,
           FileManager.default.fileExists(atPath: existingURL.path) {
            imageURL = existingURL
        } else {
            let dir = AppDataPaths.workbenchResultsDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            imageURL = dir.appendingPathComponent("pin-\(pinID.uuidString.prefix(8)).png")
            try? ImageExporter.export(image, to: imageURL, format: .png)
        }

        let panel = PinnedImagePanel(pinID: pinID, image: image, originalImageSize: originalSize)
        panel.sourceImageURL = imageURL

        // Position at center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let origin = CGPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panel.onEdit = { [weak self, weak panel] in
            guard let url = panel?.sourceImageURL,
                  let img = NSImage(contentsOf: url) else { return }
            self?.showEditWindow(image: img, sourceURL: url)
        }
        panel.onCopy = { [weak panel] in
            guard let url = panel?.sourceImageURL,
                  let img = NSImage(contentsOf: url) else { return }
            try? img.copyToClipboard()
        }
        panel.onSaveAs = { [weak panel] in
            guard let sourceURL = panel?.sourceImageURL else { return }
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.nameFieldStringValue = "Picelf-pin-\(pinID.uuidString.prefix(8)).png"
            savePanel.begin { response in
                guard response == .OK, let destURL = savePanel.url else { return }
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }
        panel.onExtractSubject = { [weak panel] in
            guard let panel, let url = panel.sourceImageURL,
                  let img = NSImage(contentsOf: url) else { return }
            Task {
                guard let extracted = try? await SubjectExtractor.extractSubject(from: img) else { return }
                panel.updateImage(extracted)
                if let url = panel.sourceImageURL {
                    try? ImageExporter.export(extracted, to: url, format: .png)
                }
            }
        }
        panel.onClose = { [weak self] in
            self?.unpinImage(id: pinID)
        }
        configureBindingCallbacks(panel: panel, pinID: pinID)

        panel.orderFront(nil)
        pinnedPanels[pinID] = panel

        // Persist pin state
        let state = PinnedState(
            id: pinID,
            imageURL: imageURL,
            frame: panel.frame,
            zoomScale: panel.zoomScale,
            opacity: panel.pinOpacity,
            sourceJobID: sourceJobID,
            originalImageSize: originalSize
        )
        PinStateStore.append(state)

        log.info("Pinned image \(pinID.uuidString.prefix(8)) at \(panel.frame.debugDescription)")
    }

    private func configureBindingCallbacks(panel: PinnedImagePanel, pinID: UUID, binding: PinBinding = .allDesktops) {
        panel.currentBinding = binding
        panel.onBindingChanged = { [weak self] newBinding in
            self?.updateBinding(pinID: pinID, binding: newBinding)
        }
        applyCollectionBehavior(panel: panel, binding: binding)
    }

    private func updateBinding(pinID: UUID, binding: PinBinding) {
        guard let panel = pinnedPanels[pinID] else { return }
        panel.currentBinding = binding
        applyCollectionBehavior(panel: panel, binding: binding)
        PinStateStore.update(id: pinID, binding: binding)
        bindingMonitor.startTrackingIfNeeded(pinID: pinID, binding: binding)
        log.info("Pin \(pinID.uuidString.prefix(8)) binding changed to \(String(describing: binding))")
    }

    private func applyCollectionBehavior(panel: PinnedImagePanel, binding: PinBinding) {
        switch binding {
        case .currentDesktopOnly:
            panel.collectionBehavior = [.fullScreenAuxiliary]
            panel.level = .floating
        case .desktop:
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        case .window:
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.level = .normal
        default:
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.level = .floating
        }
    }

    private func unpinImage(id: UUID) {
        if let panel = pinnedPanels.removeValue(forKey: id) {
            panel.orderOut(nil)
        }
        bindingMonitor.stopTracking(pinID: id)
        PinStateStore.remove(id: id)
        log.info("Unpinned image \(id.uuidString.prefix(8))")
    }

    private func lowerPinLevels() {
        for (_, panel) in pinnedPanels {
            switch panel.currentBinding {
            case .desktop, .window:
                break // These manage their own levels
            default:
                panel.level = .normal
            }
        }
    }

    private func raisePinLevels() {
        for (_, panel) in pinnedPanels {
            applyCollectionBehavior(panel: panel, binding: panel.currentBinding)
        }
    }

    private func restorePins() {
        let states = PinStateStore.load()
        guard !states.isEmpty else { return }

        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero

        for state in states {
            guard let image = NSImage(contentsOf: state.imageURL) else {
                PinStateStore.remove(id: state.id)
                continue
            }

            let panel = PinnedImagePanel(pinID: state.id, image: image, originalImageSize: state.originalImageSize)
            panel.sourceImageURL = state.imageURL
            panel.zoomScale = state.zoomScale
            panel.pinOpacity = state.opacity
            panel.alphaValue = state.opacity

            // Clamp frame to visible screen area
            var frame = state.frame
            if !visibleFrame.isEmpty {
                frame.origin.x = min(max(visibleFrame.minX, frame.origin.x), visibleFrame.maxX - frame.width)
                frame.origin.y = min(max(visibleFrame.minY, frame.origin.y), visibleFrame.maxY - frame.height)
            }
            panel.setFrame(frame, display: false)
            panel.applyZoom()

            let stateID = state.id
            panel.onEdit = { [weak self, weak panel] in
                guard let url = panel?.sourceImageURL,
                      let img = NSImage(contentsOf: url) else { return }
                self?.showEditWindow(image: img, sourceURL: url)
            }
            panel.onCopy = { [weak panel] in
                guard let url = panel?.sourceImageURL,
                      let img = NSImage(contentsOf: url) else { return }
                try? img.copyToClipboard()
            }
            panel.onSaveAs = { [weak panel] in
                guard let sourceURL = panel?.sourceImageURL else { return }
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.png]
                savePanel.nameFieldStringValue = "Picelf-pin-\(stateID.uuidString.prefix(8)).png"
                savePanel.begin { response in
                    guard response == .OK, let destURL = savePanel.url else { return }
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
            panel.onExtractSubject = { [weak panel] in
                guard let panel, let url = panel.sourceImageURL,
                      let img = NSImage(contentsOf: url) else { return }
                Task {
                    guard let extracted = try? await SubjectExtractor.extractSubject(from: img) else { return }
                    panel.updateImage(extracted)
                    if let url = panel.sourceImageURL {
                        try? ImageExporter.export(extracted, to: url, format: .png)
                    }
                }
            }
            panel.onClose = { [weak self] in
                self?.unpinImage(id: state.id)
            }
            configureBindingCallbacks(panel: panel, pinID: state.id, binding: state.binding)

            // For window/screen bindings, start hidden — monitor will show if target is visible
            switch state.binding {
            case .window, .screen:
                break // Don't orderFront; monitor will handle visibility
            default:
                panel.orderFront(nil)
            }
            pinnedPanels[state.id] = panel
        }

        log.info("Restored \(self.pinnedPanels.count) pinned images")
    }

    private func makeUITestImage() -> NSImage {
        let width = 900
        let height = 1400
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        let colors: [NSColor] = [
            NSColor(calibratedRed: 0.93, green: 0.97, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.97, green: 0.94, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.94, green: 1.0, blue: 0.96, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.93, alpha: 1.0),
        ]
        let stripeHeight = 120
        for y in stride(from: 0, to: height, by: stripeHeight) {
            let idx = (y / stripeHeight) % colors.count
            colors[idx].setFill()
            NSBezierPath(rect: NSRect(x: 0, y: y, width: width, height: stripeHeight)).fill()
        }

        return image
    }

}
