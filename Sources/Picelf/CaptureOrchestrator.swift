import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.picelf", category: "Orchestrator")

private enum OverlayWindowLevel {
    static let dimming = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 2)
    static let frame = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
    static let chrome = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
    static let snapEditImage = NSWindow.Level(rawValue: chrome.rawValue + 1)
    static let snapEditToolbar = NSWindow.Level(rawValue: chrome.rawValue + 2)
}

enum CaptureMenuStartPolicy {
    static func shouldForceRestart(
        isCapturing: Bool,
        isSnapEditing: Bool,
        isStitching: Bool,
        hasOverlayPanels: Bool
    ) -> Bool {
        isCapturing || isSnapEditing || isStitching || hasOverlayPanels
    }
}

enum SnapEditInputRoutingMode: Equatable {
    case inactive
    case frameAdjust
    case canvasEdit
}

struct SnapEditPanelPresentation: Equatable {
    let framePanelVisible: Bool
    let framePanelIgnoresMouseEvents: Bool
    let snapEditPanelIgnoresMouseEvents: Bool
    let showsStaticBorder: Bool
    let isToolActive: Bool
}

private enum RecordingLaunchContext {
    case framingToolbar
    case snapEditToolbar
}

private enum RecordingStartFailure: Error {
    case noCaptureTarget
    case windowNotFound(windowID: CGWindowID?)
    case displayNotFound(displayID: CGDirectDisplayID?)
    case invalidCaptureArea
    case captureRegionUnavailable
}

enum RecordingTargetDescriptor: Equatable {
    case window(windowID: CGWindowID, effectiveFrameRect: CGRect)
    case display(displayID: CGDirectDisplayID, effectiveFrameRect: CGRect)
}

private enum PreparedRecordingTarget {
    case window(windowID: CGWindowID, scDisplay: SCDisplay, requestedSourceRect: CGRect, effectiveFrameRect: CGRect)
    case display(displayID: CGDirectDisplayID, scDisplay: SCDisplay, requestedSourceRect: CGRect, effectiveFrameRect: CGRect)

    var effectiveFrameRect: CGRect {
        switch self {
        case .window(_, _, _, let effectiveFrameRect), .display(_, _, _, let effectiveFrameRect):
            return effectiveFrameRect
        }
    }

    var selectedWindowID: CGWindowID? {
        switch self {
        case .window(let windowID, _, _, _):
            return windowID
        case .display:
            return nil
        }
    }

    var screenRecorderTarget: ScreenRecorder.CaptureTarget {
        switch self {
        case .window(_, let scDisplay, let requestedSourceRect, _):
            return .display(scDisplay, requestedSourceRect: requestedSourceRect)
        case .display(_, let scDisplay, let requestedSourceRect, _):
            return .display(scDisplay, requestedSourceRect: requestedSourceRect)
        }
    }

    var logDescription: String {
        switch self {
        case .window(let windowID, let scDisplay, _, _):
            return "windowID=\(windowID) via displayID=\(scDisplay.displayID)"
        case .display(let displayID, _, _, _):
            return "displayID=\(displayID)"
        }
    }
}

struct RecordingFailureAlertContent: Equatable {
    let message: String
    let detail: String
}

struct CaptureSubmission {
    let runner: any WorkbenchStitchJobRuntime
    let windowInfo: WindowInfo?
    let acceptedFrameCount: Int
    let captureRect: CGRect
    let captureType: CaptureType
    let submittedAt: Date
}

final class SnapRunner: WorkbenchStitchJobRuntime {
    private var image: NSImage?
    init(image: NSImage) { self.image = image }
    func stitch(onProgress: ((StitchingProgress) -> Void)?) async throws -> NSImage {
        guard let image else { throw StitchingError.noFrames }
        onProgress?(StitchingProgress(fraction: 1.0, phase: L10n.phaseDone, currentFrame: 1, totalFrames: 1))
        return image
    }
    func cancel() {}
    func reset() { image = nil }
}

/// Orchestrates the full capture flow:
/// 1. Show frame overlay + pill toolbar
/// 2. User adjusts frame, selects window
/// 3. User clicks Start -> begin streaming frames
/// 4. User clicks Done -> either submit a background stitch job or stitch inline
@MainActor
class CaptureOrchestrator: ObservableObject {
    var framePanel: CaptureFramePanel?
    var toolbarPanel: PillToolbarPanel?
    var previewPanel: StitchPreviewPanel?
    var dimmingWindow: DimmingOverlayWindow?
    var magnifierPanel: MagnifierPanel?
    private var cancellables = Set<AnyCancellable>()
    private var suppressAutoSnap = false
    private var pendingAutoSnapCapture = false
    private var suppressHoverAutoSnapUntilMouseUp = false
    private var keyDownLocalMonitor: Any?
    private var keyDownGlobalMonitor: Any?
    private var pointerLocalMonitor: Any?
    private var pointerGlobalMonitor: Any?
    private var lastCommittedPointerUpTimestamp: TimeInterval?
    private var snapEditToolCancellable: AnyCancellable?
    private var activeScreen: NSScreen?
    private var activeScreenFrontToBackWindowIDs: [CGWindowID] = []
    private var frozenScreenCGImage: CGImage?
    private var currentSnapTask: Task<Void, Never>?
    private var snapRequestID: UInt64 = 0
    private var isRestartingFromMenuStart = false
    private var showsLiveContentInFrame = false {
        didSet {
            guard showsLiveContentInFrame != oldValue else { return }
            updateDimmingWindowPresentation()
        }
    }

    let windowEnumerator = WindowEnumerator()
    let captureStream = WindowCaptureStream()
    private(set) var stitchingCoordinator = StitchingCoordinator()
    let captureState = CaptureState()
    let recordingOrchestrator = RecordingOrchestrator()
    private var webHintProvider: ChromeDOMHintProvider?

    /// Preferred path: dispatch to Workbench as a background job.
    var onCaptureSubmitted: (@MainActor (CaptureSubmission) -> Void)?
    var onStitchingComplete: (@MainActor (NSImage) -> Void)?
    var onStitchingFailed: (@MainActor (Error) -> Void)?
    var suppressAlerts = false

    /// Called when user confirms snap edit (✅): (composedImage, windowInfo, captureRect)
    var onSnapEditConfirmed: (@MainActor (NSImage, WindowInfo?, CGRect) -> Void)?
    /// Called to pin an image to desktop
    var onPinImage: (@MainActor (NSImage) -> Void)?
    /// Called when user pins from snap edit: (composedImage, windowInfo, captureRect)
    var onPinFromSnapEdit: (@MainActor (NSImage, WindowInfo?, CGRect) -> Void)?
    /// Called when user clicks OCR from snap edit: opens editor with auto-OCR
    var onOpenEditorWithOCR: (@MainActor (NSImage) -> Void)?
    /// Called when user clicks Translate from snap edit: opens editor with auto-translate
    var onOpenEditorWithTranslation: (@MainActor (NSImage) -> Void)?
    /// Called when user clicks extract from snap edit: opens editor with auto-extract
    var onOpenEditorWithExtract: (@MainActor (NSImage) -> Void)?
    /// Called before capture overlays appear — lower pin panels
    var onWillActivate: (@MainActor () -> Void)?
    /// Called after capture overlays are dismissed — restore pin panels
    var onDidDeactivate: (@MainActor () -> Void)?

    // Snap edit mode state
    private var snapEditDocument: EditorDocument?
    private var snapEditImagePanel: SnapEditImagePanel?
    private var snapEditContainerView: SnapEditCanvasContainerView?
    private var snapEditCanvasHostingView: NSView?
    private var snapEditWindowInfo: WindowInfo?
    private struct SnapConfirmPayload {
        let baseImage: NSImage
        let imageSize: CGSize
        let annotations: [EditorAnnotation]
        let draft: EditorAnnotation?
        let windowInfo: WindowInfo?
        let captureRect: CGRect
    }

    /// Activate capture mode: show frame overlay and pill toolbar.
    func activate() async {
        log.info("activate() called")
        if framePanel != nil || dimmingWindow != nil || toolbarPanel != nil || previewPanel != nil {
            log.warning("activate() called while overlay is still active — cleaning up stale panels first")
            deactivate()
        }
        onWillActivate?()

        await windowEnumerator.refreshAvailableContent()
        log.info("Window enumeration complete: \(self.windowEnumerator.windows.count) windows found")

        // If no windows found, check if it's a permission error (TCC) or just no windows open
        if windowEnumerator.windows.isEmpty {
            if windowEnumerator.error != nil {
                log.error("0 windows + error from SCShareableContent — likely TCC permission denied")
                showPermissionAlert()
            } else {
                log.error("0 windows but no error — no capturable windows are open")
                showNoWindowsAlert()
            }
            return
        }

        let mousePos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePos) })
                ?? NSScreen.main else {
            log.error("No screen available — aborting activate()")
            return
        }
        activeScreen = screen

        activeScreenFrontToBackWindowIDs = frontToBackWindowIDs(on: screen)

        guard let frozenImage = captureFrozenImage(for: screen) else {
            showStitchingFailedAlert(
                message: L10n.invalidCaptureArea,
                detail: "Failed to capture frozen screen image."
            )
            return
        }
        frozenScreenCGImage = frozenImage
        captureState.frozenBackgroundImage = NSImage(cgImage: frozenImage, size: screen.frame.size)
        captureState.frozenScreenFrame = screen.frame
        captureState.frozenPixelScaleX = CGFloat(frozenImage.width) / max(screen.frame.width, 1)
        captureState.frozenPixelScaleY = CGFloat(frozenImage.height) / max(screen.frame.height, 1)

        let initialFrameRect = CGRect.zero
        captureState.frameRect = initialFrameRect
        captureState.selectedWindowID = nil
        captureState.mode = .idleSelecting
        pendingAutoSnapCapture = false
        suppressHoverAutoSnapUntilMouseUp = false
        snapRequestID = 0
        showsLiveContentInFrame = false
        log.info("Initial capture state: mode=\(String(describing: self.captureState.mode)), selectedWindowID=nil, frameRect=\(self.captureState.frameRect.debugDescription)")

        showOverlay(screen: screen, rect: initialFrameRect)
    }

    /// Start capture from status menu. If any capture UI/session is active, force a clean restart.
    func startOrRestartFromMenu() async {
        guard !isRestartingFromMenuStart else {
            log.debug("startOrRestartFromMenu() ignored — restart already in flight")
            return
        }
        isRestartingFromMenuStart = true
        defer { isRestartingFromMenuStart = false }

        let hasOverlayPanels = hasActiveOverlayPanels()
        let shouldForceRestart = CaptureMenuStartPolicy.shouldForceRestart(
            isCapturing: captureState.isCapturing,
            isSnapEditing: captureState.isSnapEditing,
            isStitching: captureState.isStitching,
            hasOverlayPanels: hasOverlayPanels
        )

        if shouldForceRestart {
            if captureState.isCapturing {
                log.info("[USER] Menu start capture — restart path: capturing")
                await cancelScrollCaptureAndExit()
            } else if captureState.isSnapEditing {
                log.info("[USER] Menu start capture — restart path: snap edit")
                cancelSnapEdit()
                if hasActiveOverlayPanels() {
                    deactivate()
                }
            } else {
                log.info("[USER] Menu start capture — restart path: overlay/stitching")
                deactivate()
            }
        } else {
            log.info("[USER] Menu start capture — restart path: idle")
        }

        await activate()
    }

    private func hasActiveOverlayPanels() -> Bool {
        framePanel != nil
            || toolbarPanel != nil
            || previewPanel != nil
            || dimmingWindow != nil
            || snapEditImagePanel != nil
    }

    private func showPermissionAlert() {
        guard !suppressAlerts else {
            log.warning("Alert suppressed: Screen Recording Permission Required")
            return
        }
        // Activate the app so the alert is visible (LSUIElement apps have no Dock icon)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L10n.screenRecordingRequired
        alert.informativeText = L10n.screenRecordingBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.openSystemSettings)
        alert.addButton(withTitle: L10n.cancel)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Try the direct deep link first, fall back to general privacy settings
            let urls = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
            for urlString in urls {
                if let url = URL(string: urlString) {
                    if NSWorkspace.shared.open(url) { break }
                }
            }
        }
    }

    private func showNoWindowsAlert() {
        guard !suppressAlerts else {
            log.warning("Alert suppressed: No Windows Found")
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L10n.noWindowsFound
        alert.informativeText = L10n.noWindowsBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
    }

    /// Dismiss all overlays without capturing.
    func deactivate() {
        log.info("deactivate() — dismissing all overlays")
        recordingOrchestrator.cleanup()
        webHintProvider?.stopSession()
        webHintProvider = nil
        stopKeyMonitoring()
        stopPointerMonitoring()
        currentSnapTask?.cancel()
        currentSnapTask = nil
        suppressAutoSnap = false
        pendingAutoSnapCapture = false
        suppressHoverAutoSnapUntilMouseUp = false
        lastCommittedPointerUpTimestamp = nil
        snapEditToolCancellable?.cancel()
        snapEditToolCancellable = nil
        snapRequestID = 0
        cancellables.removeAll()
        showsLiveContentInFrame = false
        captureState.previewImage = nil
        captureState.frozenBackgroundImage = nil
        captureState.frozenScreenFrame = .zero
        captureState.frozenPixelScaleX = 1
        captureState.frozenPixelScaleY = 1
        captureState.isSnapEditingToolActive = false
        frozenScreenCGImage = nil
        snapEditContainerView = nil
        snapEditCanvasHostingView = nil
        // Keep retired windows alive briefly after hiding them. AppKit can still
        // be inside a SwiftUI/NSHostingView constraint display cycle when the
        // user starts or cancels capture; immediate teardown can raise an AppKit
        // exception from _postWindowNeedsUpdateConstraints.
        orderOutAndDeferWindowRelease(framePanel)
        orderOutAndDeferWindowRelease(toolbarPanel)
        orderOutAndDeferWindowRelease(previewPanel)
        orderOutAndDeferWindowRelease(dimmingWindow)
        framePanel = nil
        toolbarPanel = nil
        previewPanel = nil
        dimmingWindow = nil
        activeScreen = nil
        activeScreenFrontToBackWindowIDs = []
        onDidDeactivate?()
    }

    // MARK: - Private

    private func orderOutAndDeferWindowRelease(_ window: NSWindow?) {
        guard let window else { return }
        let retainedContentView = window.contentView
        window.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [window, retainedContentView] in
            _ = window
            _ = retainedContentView
        }
    }

    private func showOverlay(screen: NSScreen, rect: CGRect) {
        // Dimming overlay
        dimmingWindow = DimmingOverlayWindow(
            screen: screen,
            backgroundImage: frozenScreenCGImage
        ) { [weak self] in
            self?.captureState.frameRect ?? .zero
        }
        dimmingWindow?.level = OverlayWindowLevel.dimming
        dimmingWindow?.orderFront(nil)
        updateDimmingWindowPresentation()

        recordingOrchestrator.configurePanelLevels(
            config: NSWindow.Level(rawValue: OverlayWindowLevel.chrome.rawValue + 1),
            toolbar: NSWindow.Level(rawValue: OverlayWindowLevel.chrome.rawValue + 2),
            countdown: NSWindow.Level(rawValue: OverlayWindowLevel.chrome.rawValue + 3)
        )

        // Full-screen interactive selection overlay.
        let panel = CaptureFramePanel(contentRect: screen.frame)
        panel.level = OverlayWindowLevel.frame
        panel.contentView = makeFrameOverlayContentView(for: screen)
        panel.orderFront(nil)
        self.framePanel = panel
        updateFramePanelInputPolicy()
        startKeyMonitoring()
        startPointerMonitoring()

        // Arrow key nudging
        panel.onArrowKey = { [weak self] delta in
            guard let self, !self.captureState.isCapturing, self.captureState.mode == .selectionReady else { return }
            self.captureState.frameRect.origin.x += delta.dx
            self.captureState.frameRect.origin.y += delta.dy
            self.captureState.frameRect = self.clampedToActiveScreen(self.captureState.frameRect)
        }
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.captureState.isCapturing {
                Task { await self.cancelScrollCaptureAndExit() }
            } else if self.captureState.isSnapEditing {
                self.cancelSnapEdit()
            } else {
                self.deactivate()
            }
        }

        // Wire recording start — keep overlays visible but pass-through
        recordingOrchestrator.onRecordingStarted = { [weak self] in
            guard let self else { return }
            self.showsLiveContentInFrame = true
            self.updateFramePanelInputPolicy()
            if let windowID = self.captureState.selectedWindowID {
                _ = self.activateTargetAppForRecording(windowID: windowID)
            }
            self.toolbarPanel?.orderOut(nil)
            log.info("Recording started — overlays set to pass-through, frozen preview hidden, target app activation requested")
        }

        // Wire recording failure — dismiss overlays when stop fails
        recordingOrchestrator.onRecordingFailed = { [weak self] failure in
            guard let self else { return }
            log.warning("Recording failed during \(failure.phase == .stop ? "stop" : "start", privacy: .public): \(failure.message, privacy: .public)")
            if let alert = Self.recordingFailureAlert(for: failure) {
                self.showCaptureAlert(message: alert.message, detail: alert.detail)
            }
            self.deactivate()
        }

        recordingOrchestrator.onWillOpenMicrophoneSystemSettings = { [weak self] in
            self?.deactivate()
        }

        // Wire recording completion
        recordingOrchestrator.onRecordingComplete = { [weak self] videoURL, duration in
            guard let self else { return }
            log.notice(
                "Recording complete callback — duration=\(String(format: "%.1f", duration), privacy: .public)s url=\(videoURL.path, privacy: .public)"
            )
            let runner = ScreenRecordingRunner(videoURL: videoURL, duration: duration)
            let windowInfo = self.windowEnumerator.windows.first(where: { $0.id == self.captureState.selectedWindowID })
            let submission = CaptureSubmission(
                runner: runner,
                windowInfo: windowInfo,
                acceptedFrameCount: 0,
                captureRect: self.captureState.frameRect,
                captureType: .recording,
                submittedAt: Date()
            )
            if let onCaptureSubmitted = self.onCaptureSubmitted {
                onCaptureSubmitted(submission)
                log.notice("Recording submitted to Workbench queue")
            } else {
                log.error("Recording complete but no onCaptureSubmitted handler is registered")
            }
            self.deactivate()
        }

        // Pill toolbar
        let toolbar = PillToolbarPanel()
        toolbar.level = OverlayWindowLevel.chrome
        let toolbarView = PillToolbarView(
            captureState: captureState,
            onCapture: { [weak self] in Task { await self?.startCapture() } },
            onRecord: { [weak self] in
                self?.startRecordFromFramingToolbar()
            },
            onDone: { [weak self] in Task { await self?.stopCapture() } },
            onCancel: { [weak self] in self?.deactivate() }
        )
        let toolbarHostingView = FirstMousePassthroughHostingView(rootView: toolbarView)
        toolbarHostingView.wantsLayer = true
        toolbarHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        toolbar.contentView = toolbarHostingView
        toolbar.fitToContent()
        toolbar.positionAbove(rect: rect, screen: screen)
        self.toolbarPanel = toolbar
        updateToolbarVisibility()

        // Observe frameRect changes to sync panel, dimming, and toolbar
        captureState.$frameRect
            .dropFirst()
            .sink { [weak self] newRect in
                guard let self else { return }
                self.dimmingWindow?.updateHole()
                self.updateToolbarPosition(for: newRect)
                self.updateSnapEditImagePanelFrame(for: newRect)
            }
            .store(in: &cancellables)

        captureState.$mode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }

                // Cancel snap edit when user starts adjusting the frame
                if mode == .dragSelecting, self.captureState.isSnapEditing {
                    self.exitSnapEditForRecapture()
                }

                self.updateToolbarVisibility()

                // Auto-snap only after a real manual drag commit.
                if mode == .selectionReady,
                   self.pendingAutoSnapCapture,
                   !self.captureState.isCapturing,
                   !self.captureState.isSnapEditing,
                   !self.suppressAutoSnap {
                    self.pendingAutoSnapCapture = false
                    self.startSnapCapture()
                }
            }
            .store(in: &cancellables)

        captureState.$isCapturing
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
                self?.updateFramePanelInputPolicy()
                self?.updateDimmingWindowPresentation()
            }
            .store(in: &cancellables)

        captureState.$isStitching
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
            }
            .store(in: &cancellables)

        captureState.$isSnapEditing
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateToolbarVisibility()
                self?.updateFramePanelInputPolicy()
                self?.updateDimmingWindowPresentation()
            }
            .store(in: &cancellables)

        recordingOrchestrator.$isRecording
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateFramePanelInputPolicy()
                self?.updateDimmingWindowPresentation()
            }
            .store(in: &cancellables)

        recordingOrchestrator.$isPreparingRecording
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateFramePanelInputPolicy()
                self?.updateDimmingWindowPresentation()
            }
            .store(in: &cancellables)
    }

    func startCapture() async {
        if captureState.selectedWindowID == nil {
            let center = CGPoint(x: captureState.frameRect.midX, y: captureState.frameRect.midY)
            let nearest = WindowEnumerator.findClosestWindow(to: center, in: windowEnumerator.windows)
            captureState.selectedWindowID = nearest?.id
        }

        log.info("startCapture() called, selectedWindowID=\(String(describing: self.captureState.selectedWindowID))")

        guard let windowID = captureState.selectedWindowID else {
            log.error("startCapture() aborted — no selectedWindowID")
            return
        }

        guard let scWindow = await windowEnumerator.scWindow(
                  for: WindowInfo(id: windowID, title: "", appName: "", appBundleID: "",
                                  frame: .zero, isOnScreen: true)
              ) else {
            log.error("startCapture() aborted — scWindow lookup failed for windowID=\(windowID)")
            return
        }

        log.info("SCWindow resolved: \(scWindow.title ?? "untitled") (\(Int(scWindow.frame.width))x\(Int(scWindow.frame.height)))")

        // captureState.frameRect is AppKit coords (y-up); scWindow.frame is CG (y-down).
        // Convert to CG for intersection and makeCaptureRegion.
        let selectedFrame = WindowInfo.appKitToCG(captureState.frameRect)
        let windowFrame = scWindow.frame
        let clampedFrame = selectedFrame.intersection(windowFrame)
        log.info("startCapture coords — frameRect(AppKit): \(self.captureState.frameRect.debugDescription), selectedFrame(CG): \(selectedFrame.debugDescription), windowFrame(CG): \(windowFrame.debugDescription), clamped(CG): \(clampedFrame.debugDescription)")
        guard !clampedFrame.isNull, !clampedFrame.isEmpty, clampedFrame.width > 0, clampedFrame.height > 0 else {
            log.error("startCapture() aborted — selected frame does not intersect window")
            showStitchingFailedAlert(
                message: L10n.invalidCaptureArea,
                detail: L10n.invalidCaptureAreaBody1
            )
            return
        }

        guard let captureRegion = WindowCaptureStream.makeCaptureRegion(
            selectedFrameInScreen: clampedFrame,
            windowFrameInScreen: windowFrame
        ) else {
            log.error("startCapture() aborted — failed to convert screen frame to window capture region")
            showStitchingFailedAlert(
                message: L10n.invalidCaptureArea,
                detail: L10n.invalidCaptureAreaBody2
            )
            return
        }

        // Reflect the effective capture area in the UI (convert CG back to AppKit).
        captureState.frameRect = WindowInfo.cgToAppKit(clampedFrame)

        captureState.isCapturing = true
        captureState.mode = .selectionReady
        captureState.frameCount = 0
        stitchingCoordinator.reset()

        if let selectedWindow = windowEnumerator.windows.first(where: { $0.id == windowID }),
           selectedWindow.appBundleID == ChromeDOMHintProvider.chromeBundleID {
            let provider = ChromeDOMHintProvider()
            provider.startSession()
            webHintProvider = provider
            log.info("WebHint enabled for Chrome window")
        } else {
            webHintProvider = nil
        }

        // Wire live preview callback
        let state = captureState
        stitchingCoordinator.onPreviewUpdate = { image in
            Task { @MainActor in
                state.previewImage = image
            }
        }

        // Show preview panel
        showPreviewPanel()

        // Capture at Retina resolution so text is sharp (not garbled by sub-pixel rendering)
        captureStream.scaleFactor = Int((activeScreen ?? NSScreen.main)?.backingScaleFactor ?? 1)

        // Let mouse events (scroll, click) pass through to the target window
        // during capture. The user interacts with their content, not the frame.
        updateFramePanelInputPolicy()

        do {
            try await captureStream.startCapture(window: scWindow, region: captureRegion) { [weak self] cgImage in
                let accepted = self?.stitchingCoordinator.appendFrame(cgImage) ?? false
                let count = self?.stitchingCoordinator.frameCount ?? 0
                self?.captureState.frameCount = count
                if accepted && count % 10 == 1 {
                    log.debug("Frame received: \(cgImage.width)x\(cgImage.height), accepted count=\(count)")
                }
            }
            showsLiveContentInFrame = true
            log.info("Capture stream started successfully")
        } catch {
            log.error("Capture stream failed to start: \(error.localizedDescription)")
            captureState.isCapturing = false
            showsLiveContentInFrame = false
        }
    }

    func stopCapture() async {
        log.info("stopCapture() called — stopping stream")
        webHintProvider?.stopSession()
        webHintProvider = nil
        captureState.isCapturing = false
        captureState.previewImage = nil
        updateFramePanelInputPolicy()
        captureState.isStitching = false

        // Dismiss capture chrome immediately so stitching truly behaves as a background task.
        deactivate()

        // SCStream teardown can stall on complex pages. Proceed after timeout in capture stream.
        await captureStream.stopCapture()

        let totalFrames = stitchingCoordinator.totalFrameCount
        log.info("Capture stopped. Total accepted frames: \(totalFrames), frameCount: \(self.stitchingCoordinator.frameCount)")

        // Early bail: not enough frames to stitch
        if totalFrames < 2 {
            log.error("Not enough frames to stitch: \(totalFrames)")
            captureState.isStitching = false
            showStitchingFailedAlert(
                message: L10n.notEnoughFrames,
                detail: totalFrames == 0
                    ? L10n.noFramesCaptured
                    : L10n.onlyOneFrame
            )
            onStitchingFailed?(StitchingError.noFrames)
            return
        }

        if let onCaptureSubmitted {
            let selectedWindow = windowEnumerator.windows.first(where: { $0.id == captureState.selectedWindowID })
            let completedCoordinator = stitchingCoordinator
            stitchingCoordinator = StitchingCoordinator()

            let submission = CaptureSubmission(
                runner: completedCoordinator,
                windowInfo: selectedWindow,
                acceptedFrameCount: totalFrames,
                captureRect: captureState.frameRect,
                captureType: .scroll,
                submittedAt: Date()
            )

            onCaptureSubmitted(submission)
            log.notice("Capture submitted to background queue: frames=\(totalFrames)")
            return
        }

        captureState.isStitching = true
        log.info("Beginning stitch of \(totalFrames) frames...")
        let stitchStart = CFAbsoluteTimeGetCurrent()

        do {
            let result = try await stitchingCoordinator.stitch { [weak self] progress in
                self?.captureState.stitchProgress = progress.fraction
                if Int(progress.fraction * 100) % 10 == 0 {
                    log.debug("Stitch progress: \(Int(progress.fraction * 100))% — \(progress.phase)")
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - stitchStart
            log.info("Stitch completed in \(String(format: "%.2f", elapsed))s — result: \(Int(result.size.width))x\(Int(result.size.height))")

            captureState.isStitching = false
            onStitchingComplete?(result)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - stitchStart
            log.error("Stitch FAILED after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            captureState.isStitching = false

            let detail: String
            if let stitchError = error as? StitchingError {
                switch stitchError {
                case .singleFrame, .noFrames:
                    detail = L10n.framesIdentical
                case .cancelled:
                    detail = L10n.stitchCancelledOrTimeout
                case .overlapDetectionFailed:
                    detail = L10n.overlapFailed
                default:
                    detail = stitchError.localizedDescription
                }
            } else {
                detail = error.localizedDescription
            }
            showStitchingFailedAlert(message: L10n.stitchingFailed, detail: detail)
            onStitchingFailed?(error)
        }
    }

    private func showStitchingFailedAlert(message: String, detail: String) {
        showCaptureAlert(message: message, detail: detail)
    }

    nonisolated static func recordingFailureAlert(for failure: RecordingFailureContext) -> RecordingFailureAlertContent? {
        let detail = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDetail: String
        if detail.isEmpty {
            resolvedDetail = failure.phase == .stop ? L10n.recordingSaveFailedBody : L10n.recordingStartNoTargetBody
        } else {
            resolvedDetail = detail
        }

        switch failure.phase {
        case .start:
            return RecordingFailureAlertContent(message: L10n.recordingStartFailed, detail: resolvedDetail)
        case .stop:
            return RecordingFailureAlertContent(message: L10n.recordingSaveFailed, detail: resolvedDetail)
        }
    }

    private func showRecordingStartFailureAlert(_ failure: RecordingStartFailure) {
        switch failure {
        case .noCaptureTarget:
            showCaptureAlert(
                message: L10n.recordingStartFailed,
                detail: L10n.recordingStartNoTargetBody
            )
        case .windowNotFound:
            showCaptureAlert(
                message: L10n.recordingStartFailed,
                detail: L10n.recordingStartWindowUnavailableBody
            )
        case .displayNotFound:
            showCaptureAlert(
                message: L10n.recordingStartFailed,
                detail: L10n.recordingStartDisplayUnavailableBody
            )
        case .invalidCaptureArea:
            showCaptureAlert(
                message: L10n.invalidCaptureArea,
                detail: L10n.invalidCaptureAreaBody1
            )
        case .captureRegionUnavailable:
            showCaptureAlert(
                message: L10n.invalidCaptureArea,
                detail: L10n.invalidCaptureAreaBody2
            )
        }
    }

    private func showCaptureAlert(message: String, detail: String) {
        guard !suppressAlerts else {
            log.warning("Alert suppressed: \(message) — \(detail)")
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
    }

    private func startRecordFromFramingToolbar() {
        guard !captureState.isCapturing else { return }
        Task { [weak self] in
            await self?.beginRecordingLaunch(context: .framingToolbar)
        }
    }

    private func beginRecordingLaunch(context: RecordingLaunchContext) async {
        suppressAutoSnap = true
        defer { suppressAutoSnap = false }

        switch await prepareRecordingTarget() {
        case .failure(let failure):
            log.error("Recording launch failed: \(String(describing: failure), privacy: .public)")
            showRecordingStartFailureAlert(failure)
        case .success(let target):
            captureState.selectedWindowID = target.selectedWindowID
            captureState.frameRect = target.effectiveFrameRect
            if context == .snapEditToolbar {
                exitSnapEditForRecapture()
                toolbarPanel?.orderOut(nil)
            }

            let center = CGPoint(x: target.effectiveFrameRect.midX, y: target.effectiveFrameRect.midY)
            guard let screen = screenContaining(center) ?? activeScreen ?? NSScreen.main else { return }
            recordingOrchestrator.showConfig(
                below: target.effectiveFrameRect,
                on: screen,
                target: target.screenRecorderTarget
            )
            log.notice("Recording config shown for \(target.logDescription, privacy: .public)")
        }
    }

    private func prepareRecordingTarget() async -> Result<PreparedRecordingTarget, RecordingStartFailure> {
        guard captureState.frameRect.width > 0, captureState.frameRect.height > 0 else {
            return .failure(.invalidCaptureArea)
        }

        let center = CGPoint(x: captureState.frameRect.midX, y: captureState.frameRect.midY)
        let screen = activeScreen ?? screenContaining(center) ?? NSScreen.main
        let activeDisplayID = screen.flatMap(Self.displayID(for:))

        var descriptor = Self.resolveRecordingTargetDescriptor(
            frameRect: captureState.frameRect,
            activeScreenFrame: screen?.frame,
            activeDisplayID: activeDisplayID,
            windows: windowEnumerator.windows,
            orderedFrontToBackBy: activeScreenFrontToBackWindowIDs
        )
        if descriptor == nil {
            await windowEnumerator.refreshAvailableContent()
            descriptor = Self.resolveRecordingTargetDescriptor(
                frameRect: captureState.frameRect,
                activeScreenFrame: screen?.frame,
                activeDisplayID: activeDisplayID,
                windows: windowEnumerator.windows,
                orderedFrontToBackBy: activeScreenFrontToBackWindowIDs
            )
        }
        guard let descriptor else {
            return .failure(.noCaptureTarget)
        }

        switch descriptor {
        case .window(let windowID, let effectiveFrameRect):
            guard let displayID = activeDisplayID else {
                return .failure(.displayNotFound(displayID: nil))
            }
            var scDisplay = await windowEnumerator.scDisplay(for: displayID)
            if scDisplay == nil {
                await windowEnumerator.refreshAvailableContent()
                scDisplay = await windowEnumerator.scDisplay(for: displayID)
            }
            guard let scDisplay else {
                return .failure(.displayNotFound(displayID: displayID))
            }

            let selectedFrame = WindowInfo.appKitToCG(effectiveFrameRect)
            let clampedFrame = selectedFrame.intersection(scDisplay.frame)
            guard !clampedFrame.isNull, !clampedFrame.isEmpty, clampedFrame.width > 0, clampedFrame.height > 0 else {
                return .failure(.invalidCaptureArea)
            }

            return .success(
                .window(
                    windowID: windowID,
                    scDisplay: scDisplay,
                    requestedSourceRect: clampedFrame,
                    effectiveFrameRect: WindowInfo.cgToAppKit(clampedFrame)
                )
            )
        case .display(let displayID, let effectiveFrameRect):
            var scDisplay = await windowEnumerator.scDisplay(for: displayID)
            if scDisplay == nil {
                scDisplay = await windowEnumerator.scDisplay(for: displayID)
            }
            guard let scDisplay else {
                return .failure(.displayNotFound(displayID: displayID))
            }

            let selectedFrame = WindowInfo.appKitToCG(effectiveFrameRect)
            let clampedFrame = selectedFrame.intersection(scDisplay.frame)
            guard !clampedFrame.isNull, !clampedFrame.isEmpty, clampedFrame.width > 0, clampedFrame.height > 0 else {
                return .failure(.invalidCaptureArea)
            }

            return .success(
                .display(
                    displayID: displayID,
                    scDisplay: scDisplay,
                    requestedSourceRect: clampedFrame,
                    effectiveFrameRect: WindowInfo.cgToAppKit(clampedFrame)
                )
            )
        }
    }

    private func updateFramePanelInputPolicy() {
        applySnapEditInputRouting(
            selectedTool: snapEditDocument?.selectedTool,
            source: "state-sync"
        )
    }

    private func updateDimmingWindowPresentation() {
        let shouldShowFrozenBackground = Self.shouldShowFrozenBackground(
            isCapturing: captureState.isCapturing,
            isPreparingRecording: recordingOrchestrator.isPreparingRecording,
            isRecording: recordingOrchestrator.isRecording,
            isSnapEditing: captureState.isSnapEditing,
            showsLiveContentInFrame: showsLiveContentInFrame
        )
        dimmingWindow?.setFrozenBackgroundVisible(shouldShowFrozenBackground)
    }

    private func applySnapEditInputRouting(
        selectedTool: EditorTool?,
        source: String
    ) {
        let mode = Self.snapEditRoutingMode(
            isSnapEditing: captureState.isSnapEditing,
            selectedTool: selectedTool
        )
        let presentation = Self.snapEditPanelPresentation(
            isCapturing: captureState.isCapturing,
            isPreparingRecording: recordingOrchestrator.isPreparingRecording,
            isRecording: recordingOrchestrator.isRecording,
            isSnapEditing: captureState.isSnapEditing,
            selectedTool: selectedTool
        )

        captureState.isSnapEditingToolActive = presentation.isToolActive

        if presentation.framePanelVisible {
            framePanel?.ignoresMouseEvents = presentation.framePanelIgnoresMouseEvents
            framePanel?.orderFrontRegardless()
        } else {
            framePanel?.orderOut(nil)
        }

        snapEditImagePanel?.ignoresMouseEvents = presentation.snapEditPanelIgnoresMouseEvents
        snapEditContainerView?.showsStaticBorder = presentation.showsStaticBorder

        if presentation.isToolActive {
            focusSnapEditCanvas(forceOrderFront: true)
        }

        log.debug(
            "Snap edit input routing: mode=\(String(describing: mode), privacy: .public) source=\(source, privacy: .public) frameVisible=\(presentation.framePanelVisible, privacy: .public) frameIgnore=\(presentation.framePanelIgnoresMouseEvents, privacy: .public) canvasIgnore=\(presentation.snapEditPanelIgnoresMouseEvents, privacy: .public) staticBorder=\(presentation.showsStaticBorder, privacy: .public)"
        )
    }

    /// Keep edit input stable: when a snap tool is active, route focus back to canvas
    /// so drag gestures render annotations instead of being eaten by other overlays.
    private func focusSnapEditCanvas(forceOrderFront: Bool = false) {
        guard captureState.isSnapEditing else { return }
        guard snapEditDocument?.editingTextID == nil else { return }
        guard let imagePanel = snapEditImagePanel else { return }
        NSApp.activate(ignoringOtherApps: true)
        if forceOrderFront {
            imagePanel.orderFrontRegardless()
        }
        imagePanel.makeKeyAndOrderFront(nil)
        if forceOrderFront {
            imagePanel.orderFrontRegardless()
        }
        if let hostingView = snapEditCanvasHostingView {
            imagePanel.makeFirstResponder(hostingView)
        }
    }

    nonisolated static func snapEditRoutingMode(
        isSnapEditing: Bool,
        selectedTool: EditorTool?
    ) -> SnapEditInputRoutingMode {
        guard isSnapEditing else { return .inactive }
        return selectedTool == nil ? .frameAdjust : .canvasEdit
    }

    nonisolated static func snapEditPanelPresentation(
        isCapturing: Bool,
        isPreparingRecording: Bool,
        isRecording: Bool,
        isSnapEditing: Bool,
        selectedTool: EditorTool?
    ) -> SnapEditPanelPresentation {
        if isPreparingRecording || isRecording {
            return SnapEditPanelPresentation(
                framePanelVisible: false,
                framePanelIgnoresMouseEvents: true,
                snapEditPanelIgnoresMouseEvents: true,
                showsStaticBorder: false,
                isToolActive: false
            )
        }

        let mode = snapEditRoutingMode(
            isSnapEditing: isSnapEditing,
            selectedTool: selectedTool
        )

        switch mode {
        case .inactive:
            return SnapEditPanelPresentation(
                framePanelVisible: true,
                framePanelIgnoresMouseEvents: shouldIgnoreFramePanelMouseEvents(
                    isCapturing: isCapturing,
                    isPreparingRecording: isPreparingRecording,
                    isRecording: isRecording,
                    isSnapEditing: isSnapEditing,
                    selectedTool: selectedTool
                ),
                snapEditPanelIgnoresMouseEvents: shouldIgnoreSnapEditImagePanelMouseEvents(
                    isSnapEditing: isSnapEditing,
                    selectedTool: selectedTool
                ),
                showsStaticBorder: false,
                isToolActive: false
            )
        case .frameAdjust:
            return SnapEditPanelPresentation(
                framePanelVisible: true,
                framePanelIgnoresMouseEvents: false,
                snapEditPanelIgnoresMouseEvents: true,
                showsStaticBorder: false,
                isToolActive: false
            )
        case .canvasEdit:
            return SnapEditPanelPresentation(
                framePanelVisible: false,
                framePanelIgnoresMouseEvents: true,
                snapEditPanelIgnoresMouseEvents: false,
                showsStaticBorder: true,
                isToolActive: true
            )
        }
    }

    func shouldIgnoreFramePanelMouseEvents() -> Bool {
        Self.shouldIgnoreFramePanelMouseEvents(
            isCapturing: captureState.isCapturing,
            isPreparingRecording: recordingOrchestrator.isPreparingRecording,
            isRecording: recordingOrchestrator.isRecording,
            isSnapEditing: captureState.isSnapEditing,
            selectedTool: snapEditDocument?.selectedTool
        )
    }

    func shouldIgnoreSnapEditImagePanelMouseEvents() -> Bool {
        Self.shouldIgnoreSnapEditImagePanelMouseEvents(
            isSnapEditing: captureState.isSnapEditing,
            selectedTool: snapEditDocument?.selectedTool
        )
    }

    nonisolated static func shouldIgnoreFramePanelMouseEvents(
        isCapturing: Bool,
        isPreparingRecording: Bool,
        isRecording: Bool,
        isSnapEditing: Bool,
        selectedTool: EditorTool?
    ) -> Bool {
        if isCapturing || isPreparingRecording || isRecording {
            // During capture/recording, input must pass through overlays.
            return true
        }
        return snapEditRoutingMode(isSnapEditing: isSnapEditing, selectedTool: selectedTool) == .canvasEdit
    }

    nonisolated static func shouldIgnoreSnapEditImagePanelMouseEvents(
        isSnapEditing: Bool,
        selectedTool: EditorTool?
    ) -> Bool {
        snapEditRoutingMode(isSnapEditing: isSnapEditing, selectedTool: selectedTool) == .frameAdjust
    }

    nonisolated static func shouldShowFrozenBackground(
        isCapturing: Bool,
        isPreparingRecording: Bool,
        isRecording: Bool,
        isSnapEditing: Bool,
        showsLiveContentInFrame: Bool
    ) -> Bool {
        if isRecording {
            return false
        }
        if isCapturing {
            return !showsLiveContentInFrame
        }
        if isPreparingRecording || isSnapEditing {
            return true
        }
        return !showsLiveContentInFrame
    }

    private func startKeyMonitoring() {
        stopKeyMonitoring()
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDownEvent(event) ? nil : event
        }
        keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            _ = self.handleKeyDownEvent(event)
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = keyDownLocalMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownLocalMonitor = nil
        }
        if let monitor = keyDownGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownGlobalMonitor = nil
        }
    }

    private func startPointerMonitoring() {
        stopPointerMonitoring()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        pointerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            guard !self.captureState.isSnapEditing else { return event }
            self.handlePointerEvent(event)
            return event
        }
        pointerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                guard let self, !self.captureState.isSnapEditing else { return }
                self.handlePointerEvent(event)
            }
        }
    }

    private func stopPointerMonitoring() {
        if let monitor = pointerLocalMonitor {
            NSEvent.removeMonitor(monitor)
            pointerLocalMonitor = nil
        }
        if let monitor = pointerGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            pointerGlobalMonitor = nil
        }
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard framePanel != nil else { return false }

        if captureState.isSnapEditing,
           let document = snapEditDocument {
            let noMods = event.modifierFlags
                .intersection([.command, .option, .shift, .control])
                .isEmpty

            // keyCode 51 = Backspace/Delete, 117 = Forward Delete
            if (event.keyCode == 51 || event.keyCode == 117), noMods {
                if document.deleteEditingTextIfEmpty() {
                    return true
                }
                guard document.editingTextID == nil else { return false }
                guard !document.selectedAnnotationIDs.isEmpty else { return false }
                document.deleteSelection()
                return true
            }

            // In snap-edit mode, Esc exits text editing first, then falls back to cancel.
            if event.keyCode == 53, document.commitActiveTextEditing() {
                document.clearSelection()
                return true
            }
        }

        if event.keyCode == 53 {
            if captureState.isCapturing {
                Task { [weak self] in
                    await self?.cancelScrollCaptureAndExit()
                }
            } else if captureState.isSnapEditing {
                cancelSnapEdit()
            } else {
                deactivate()
            }
            return true
        }
        return false
    }

    private func cancelScrollCaptureAndExit() async {
        guard captureState.isCapturing else {
            deactivate()
            return
        }
        log.info("ESC cancel during scroll capture — aborting without submission")
        webHintProvider?.stopSession()
        webHintProvider = nil
        captureState.isCapturing = false
        captureState.previewImage = nil
        captureState.isStitching = false
        updateFramePanelInputPolicy()
        deactivate()
        await captureStream.stopCapture()
        stitchingCoordinator = StitchingCoordinator()
    }

    private func handlePointerMove() {
        guard framePanel != nil else { return }
        guard !captureState.isCapturing,
              !recordingOrchestrator.isPreparingRecording,
              !recordingOrchestrator.isRecording,
              !captureState.isStitching,
              !captureState.isSnapEditing else { return }
        let mouseLocation = NSEvent.mouseLocation
        retargetFramingScreenIfNeeded(at: mouseLocation)
        guard captureState.mode == .idleSelecting else { return }
        guard !suppressHoverAutoSnapUntilMouseUp else {
            applyHoverSelection(window: nil)
            return
        }

        guard AppPreferences.shared.autoSnapToWindows else {
            applyHoverSelection(window: nil)
            return
        }

        guard let screen = activeScreen else {
            applyHoverSelection(window: nil)
            return
        }
        guard screen.frame.contains(mouseLocation) else {
            applyHoverSelection(window: nil)
            return
        }

        let candidates = windows(on: screen, from: windowEnumerator.windows)
        guard !candidates.isEmpty else {
            applyHoverSelection(window: nil)
            return
        }

        let hoveredWindow = WindowEnumerator.findTopmostWindow(
            containing: mouseLocation,
            in: candidates,
            orderedFrontToBackBy: activeScreenFrontToBackWindowIDs
        )
        applyHoverSelection(window: hoveredWindow)
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard !recordingOrchestrator.isPreparingRecording,
              !recordingOrchestrator.isRecording,
              !captureState.isSnapEditing else { return }
        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            handlePointerMove()
        case .leftMouseUp:
            if suppressHoverAutoSnapUntilMouseUp {
                suppressHoverAutoSnapUntilMouseUp = false
                handlePointerMove()
                return
            }
            let mouseLocation = NSEvent.mouseLocation
            retargetFramingScreenIfNeeded(at: mouseLocation)
            _ = tryCommitAutoSnapOnPointerUp(
                at: mouseLocation,
                timestamp: event.timestamp
            )
        case .leftMouseDown:
            break
        default:
            break
        }
    }

    @discardableResult
    func tryCommitAutoSnapOnPointerUp(
        at mouseLocation: CGPoint,
        timestamp: TimeInterval,
        screenFrameOverride: CGRect? = nil
    ) -> Bool {
        guard framePanel != nil else { return false }
        guard !captureState.isCapturing,
              !recordingOrchestrator.isPreparingRecording,
              !recordingOrchestrator.isRecording,
              !captureState.isStitching,
              !captureState.isSnapEditing else { return false }
        guard captureState.mode == .idleSelecting else { return false }
        guard !suppressHoverAutoSnapUntilMouseUp else { return false }
        guard AppPreferences.shared.autoSnapToWindows else { return false }
        guard captureState.frameRect.width > 0, captureState.frameRect.height > 0 else { return false }
        guard captureState.selectedWindowID != nil else { return false }

        let screenFrame = screenFrameOverride ?? activeScreen?.frame
        guard let screenFrame, screenFrame.contains(mouseLocation) else { return false }
        guard captureState.frameRect.contains(mouseLocation) else { return false }

        // Local + global monitors may observe the same click; de-duplicate by timestamp.
        if let lastCommittedPointerUpTimestamp,
           abs(lastCommittedPointerUpTimestamp - timestamp) < 0.001 {
            return false
        }
        lastCommittedPointerUpTimestamp = timestamp

        pendingAutoSnapCapture = true
        captureState.mode = .selectionReady
        return true
    }

    private func restartFramingFromAutoCoverDrag() {
        guard framePanel != nil else { return }
        pendingAutoSnapCapture = false
        suppressHoverAutoSnapUntilMouseUp = true
        captureState.mode = .idleSelecting
        captureState.selectedWindowID = nil
        captureState.frameRect = .zero
    }

    private func makeFrameOverlayContentView(for screen: NSScreen) -> NSView {
        let frameView = CaptureFrameView(
            captureState: captureState,
            screenFrame: screen.frame,
            onCancel: { [weak self] in self?.deactivate() },
            onManualSelectionCommitted: { [weak self] in
                guard let self else { return }
                self.pendingAutoSnapCapture = true
            },
            onRestartFramingRequested: { [weak self] in
                self?.restartFramingFromAutoCoverDrag()
            },
            onTapWithoutDrag: { [weak self] point in
                self?.handleSnapEditFrameTap(at: point)
            }
        )
        return FirstMousePassthroughHostingView(rootView: frameView.ignoresSafeArea())
    }

    private func handleSnapEditFrameTap(at screenPoint: CGPoint) {
        guard captureState.isSnapEditing else { return }
        guard let document = snapEditDocument else { return }
        guard document.selectedTool == nil else { return }

        let frame = captureState.frameRect
        guard frame.width > 0, frame.height > 0 else { return }
        guard frame.contains(screenPoint) else { return }

        let localPoint = CGPoint(
            x: min(max(0, screenPoint.x - frame.minX), frame.width),
            y: min(max(0, frame.maxY - screenPoint.y), frame.height)
        )
        guard let hit = document.hitTest(at: localPoint) else { return }

        document.selectedAnnotationIDs = [hit]
        document.activateToolForAnnotationIfSelectionMode(hit)
        applySnapEditInputRouting(
            selectedTool: document.selectedTool,
            source: "frame-tap-hit-annotation"
        )
    }

    private func retargetFramingScreenIfNeeded(at mouseLocation: CGPoint) {
        guard framePanel != nil else { return }
        guard Self.shouldRetargetFramingScreen(
            mode: captureState.mode,
            isCapturing: captureState.isCapturing,
            isRecording: recordingOrchestrator.isRecording,
            isStitching: captureState.isStitching,
            isSnapEditing: captureState.isSnapEditing
        ) else {
            return
        }
        guard let targetScreen = screenContaining(mouseLocation) else { return }
        guard !Self.isSameDisplay(activeScreen, targetScreen) else { return }
        switchFramingScreen(to: targetScreen)
    }

    private func switchFramingScreen(to screen: NSScreen) {
        guard let frozenImage = captureFrozenImage(for: screen) else {
            log.error("Retarget aborted — failed to capture frozen screen image")
            return
        }

        activeScreen = screen
        activeScreenFrontToBackWindowIDs = frontToBackWindowIDs(on: screen)
        frozenScreenCGImage = frozenImage
        captureState.frozenBackgroundImage = NSImage(cgImage: frozenImage, size: screen.frame.size)
        captureState.frozenScreenFrame = screen.frame
        captureState.frozenPixelScaleX = CGFloat(frozenImage.width) / max(screen.frame.width, 1)
        captureState.frozenPixelScaleY = CGFloat(frozenImage.height) / max(screen.frame.height, 1)

        pendingAutoSnapCapture = false
        captureState.mode = .idleSelecting
        captureState.selectedWindowID = nil
        captureState.frameRect = .zero
        lastCommittedPointerUpTimestamp = nil
        showsLiveContentInFrame = false

        if let dimmingWindow {
            dimmingWindow.orderOut(nil)
        }
        let newDimmingWindow = DimmingOverlayWindow(
            screen: screen,
            backgroundImage: frozenImage
        ) { [weak self] in
            self?.captureState.frameRect ?? .zero
        }
        newDimmingWindow.level = OverlayWindowLevel.dimming
        newDimmingWindow.orderFront(nil)
        dimmingWindow = newDimmingWindow

        if let framePanel {
            framePanel.setFrame(screen.frame, display: false)
            framePanel.contentView = makeFrameOverlayContentView(for: screen)
            framePanel.orderFront(nil)
        }
        dimmingWindow?.updateHole()
        updateDimmingWindowPresentation()
        updateFramePanelInputPolicy()
        updateToolbarPosition(for: captureState.frameRect)
        log.info("Framing retargeted to another display")
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }

    nonisolated static func shouldRetargetFramingScreen(
        mode: CaptureInteractionMode,
        isCapturing: Bool,
        isRecording: Bool,
        isStitching: Bool,
        isSnapEditing: Bool
    ) -> Bool {
        guard !isCapturing, !isRecording, !isStitching, !isSnapEditing else { return false }
        return mode == .idleSelecting
    }

    private static func isSameDisplay(_ lhs: NSScreen?, _ rhs: NSScreen?) -> Bool {
        guard let lhs, let rhs else { return false }
        if let lhsID = displayID(for: lhs), let rhsID = displayID(for: rhs) {
            return lhsID == rhsID
        }
        return lhs.frame == rhs.frame
    }

    private func captureFrozenImage(for screen: NSScreen) -> CGImage? {
        if let displayID = Self.displayID(for: screen),
           let displayImage = CGDisplayCreateImage(displayID) {
            return displayImage
        }

        // CGWindowListCreateImage is deprecated on macOS 14+.
        // Keep behavior explicit: if display capture fails, skip frozen snapshot.
        log.error("CGDisplayCreateImage failed; frozen background unavailable")
        return nil
    }

    private func updateToolbarVisibility() {
        let shouldShow: Bool
        if captureState.isCapturing || captureState.isStitching || captureState.isSnapEditing {
            shouldShow = true
        } else {
            shouldShow = false
        }
        if shouldShow {
            toolbarPanel?.level = captureState.isSnapEditing
                ? OverlayWindowLevel.snapEditToolbar
                : OverlayWindowLevel.chrome
            updateToolbarPosition(for: captureState.frameRect)
            toolbarPanel?.orderFront(nil)
            fitToolbarAfterDisplayCycle()
        } else {
            toolbarPanel?.orderOut(nil)
        }
    }

    private func fitToolbarAfterDisplayCycle() {
        guard let panel = toolbarPanel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self, weak panel] in
            guard let self, let panel, self.toolbarPanel === panel else { return }
            panel.fitToContent()
            self.updateToolbarPosition(for: self.captureState.frameRect)
        }
    }

    private func updateToolbarPosition(for rect: CGRect) {
        guard let screen = activeScreen ?? NSScreen.main else { return }
        if captureState.isSnapEditing {
            toolbarPanel?.positionForSnapEdit(rect: rect, screen: screen)
        } else {
            toolbarPanel?.positionAbove(rect: rect, screen: screen)
        }
        previewPanel?.positionBeside(rect: rect, screen: screen)
    }

    private func updateSnapEditImagePanelFrame(for rect: CGRect) {
        guard captureState.isSnapEditing else { return }
        guard let panel = snapEditImagePanel else { return }
        panel.setFrame(rect, display: true)
        snapEditContainerView?.needsLayout = true
    }

    private func showPreviewPanel() {
        guard let screen = activeScreen ?? NSScreen.main else { return }

        let panel = StitchPreviewPanel()
        panel.level = OverlayWindowLevel.chrome
        let previewView = StitchPreviewView(captureState: captureState)
        let hosting = NSHostingView(rootView: previewView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        panel.fitToContent()
        panel.positionBeside(rect: captureState.frameRect, screen: screen)
        panel.orderFront(nil)
        self.previewPanel = panel
    }

    private func clampedToActiveScreen(_ rect: CGRect) -> CGRect {
        guard let screen = activeScreen else { return rect }
        var clamped = rect
        clamped.size.width = min(max(24, clamped.width), screen.frame.width)
        clamped.size.height = min(max(24, clamped.height), screen.frame.height)
        clamped.origin.x = min(max(screen.frame.minX, clamped.origin.x), screen.frame.maxX - clamped.width)
        clamped.origin.y = min(max(screen.frame.minY, clamped.origin.y), screen.frame.maxY - clamped.height)
        return clamped
    }

    private func windows(on screen: NSScreen, from windows: [WindowInfo]) -> [WindowInfo] {
        windows.filter {
            let overlap = $0.frame.intersection(screen.frame)
            return !overlap.isNull && !overlap.isEmpty
        }
    }

    private func frontToBackWindowIDs(on screen: NSScreen) -> [CGWindowID] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        var ids: [CGWindowID] = []

        for info in windowInfoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

            if let pid = info[kCGWindowOwnerPID as String] as? pid_t,
               let app = NSRunningApplication(processIdentifier: pid),
               app.bundleIdentifier == ownBundleID {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            let appKitBounds = ScreenCoordinateSpace.cgRectToAppKit(cgBounds)
            let overlap = appKitBounds.intersection(screen.frame)
            guard !overlap.isNull, !overlap.isEmpty else { continue }

            if let number = info[kCGWindowNumber as String] as? NSNumber {
                ids.append(CGWindowID(number.uint32Value))
            } else if let number = info[kCGWindowNumber as String] as? Int {
                ids.append(CGWindowID(number))
            }
        }
        return ids
    }

    private func applyHoverSelection(window: WindowInfo?) {
        guard let screen = activeScreen else { return }

        guard let window else {
            if !captureState.frameRect.isEmpty || captureState.selectedWindowID != nil {
                captureState.frameRect = .zero
                captureState.selectedWindowID = nil
            }
            return
        }

        let clamped = window.frame.intersection(screen.frame)
        guard !clamped.isNull, !clamped.isEmpty else {
            if !captureState.frameRect.isEmpty || captureState.selectedWindowID != nil {
                captureState.frameRect = .zero
                captureState.selectedWindowID = nil
            }
            return
        }

        let rounded = CGRect(
            x: round(clamped.origin.x),
            y: round(clamped.origin.y),
            width: round(clamped.width),
            height: round(clamped.height)
        )

        if captureState.frameRect != rounded {
            captureState.frameRect = rounded
        }
        if captureState.selectedWindowID != window.id {
            captureState.selectedWindowID = window.id
        }
    }

    @discardableResult
    private func activateTargetAppForRecording(windowID: CGWindowID) -> Bool {
        guard let app = targetAppForRecording(windowID: windowID) else {
            log.warning("Recording focus: target app lookup failed for windowID=\(windowID, privacy: .public)")
            return false
        }

        NSApp.yieldActivation(to: app)
        let currentApp = NSRunningApplication.current
        let activated = app.activate(
            from: currentApp,
            options: [.activateAllWindows]
        ) || app.activate(options: [.activateAllWindows])
        log.info(
            "Recording focus: cooperative activation pid=\(app.processIdentifier, privacy: .public) success=\(activated, privacy: .public)"
        )
        return activated
    }

    private func targetAppForRecording(windowID: CGWindowID) -> NSRunningApplication? {
        let ownBundleID = Bundle.main.bundleIdentifier
        if let bundleID = windowEnumerator.windows.first(where: { $0.id == windowID })?.appBundleID,
           !bundleID.isEmpty,
           bundleID != ownBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }

        guard let app = appForWindowIDFromWindowList(windowID) else {
            return nil
        }
        if let ownBundleID, app.bundleIdentifier == ownBundleID {
            log.debug("Recording focus: skipped self activation for windowID=\(windowID, privacy: .public)")
            return nil
        }
        return app
    }

    private func appForWindowIDFromWindowList(_ windowID: CGWindowID) -> NSRunningApplication? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = infoList.first else {
            return nil
        }
        let ownerPIDKey = kCGWindowOwnerPID as String
        if let pid = info[ownerPIDKey] as? pid_t {
            return NSRunningApplication(processIdentifier: pid)
        }
        if let pidNumber = info[ownerPIDKey] as? NSNumber {
            return NSRunningApplication(processIdentifier: pid_t(pidNumber.intValue))
        }
        return nil
    }

    // MARK: - Snap Capture

    private func resolveSelectedWindowIDForCurrentFrame() -> CGWindowID? {
        if let selectedWindowID = captureState.selectedWindowID,
           windowEnumerator.windows.contains(where: { $0.id == selectedWindowID }) {
            return selectedWindowID
        }

        let center = CGPoint(x: captureState.frameRect.midX, y: captureState.frameRect.midY)
        let candidates: [WindowInfo]
        if let screen = activeScreen {
            let windowsOnScreen = windows(on: screen, from: windowEnumerator.windows)
            candidates = windowsOnScreen.isEmpty ? windowEnumerator.windows : windowsOnScreen
        } else {
            candidates = windowEnumerator.windows
        }

        guard let nearest = WindowEnumerator.findClosestWindow(to: center, in: candidates) else {
            return nil
        }
        captureState.selectedWindowID = nearest.id
        return nearest.id
    }

    nonisolated static func resolveRecordingTargetDescriptor(
        frameRect: CGRect,
        activeScreenFrame: CGRect?,
        activeDisplayID: CGDirectDisplayID?,
        windows: [WindowInfo],
        orderedFrontToBackBy windowIDs: [CGWindowID],
        minimumWindowCoverage: CGFloat = 0.5
    ) -> RecordingTargetDescriptor? {
        guard frameRect.width > 0, frameRect.height > 0 else { return nil }

        let clampedFrame: CGRect
        if let activeScreenFrame {
            clampedFrame = frameRect.intersection(activeScreenFrame)
        } else {
            clampedFrame = frameRect
        }
        guard !clampedFrame.isNull, !clampedFrame.isEmpty, clampedFrame.width > 0, clampedFrame.height > 0 else {
            return nil
        }

        let candidateWindows: [WindowInfo]
        if let activeScreenFrame {
            candidateWindows = windows.filter {
                let overlap = $0.frame.intersection(activeScreenFrame)
                return !overlap.isNull && !overlap.isEmpty
            }
        } else {
            candidateWindows = windows
        }

        let center = CGPoint(x: clampedFrame.midX, y: clampedFrame.midY)
        if let topmost = WindowEnumerator.findTopmostWindow(
            containing: center,
            in: candidateWindows,
            orderedFrontToBackBy: windowIDs
        ) {
            let effectiveFrameRect = clampedFrame.intersection(topmost.frame)
            if !effectiveFrameRect.isNull, !effectiveFrameRect.isEmpty, effectiveFrameRect.width > 0, effectiveFrameRect.height > 0 {
                return .window(windowID: topmost.id, effectiveFrameRect: effectiveFrameRect)
            }
        }

        let frameArea = max(clampedFrame.width * clampedFrame.height, 1)
        let zOrder = Dictionary(uniqueKeysWithValues: windowIDs.enumerated().map { ($1, $0) })
        let bestOverlap = candidateWindows.compactMap { window -> (WindowInfo, CGRect, CGFloat, Int)? in
            let intersection = clampedFrame.intersection(window.frame)
            guard !intersection.isNull, !intersection.isEmpty, intersection.width > 0, intersection.height > 0 else {
                return nil
            }
            let coverage = (intersection.width * intersection.height) / frameArea
            guard coverage >= minimumWindowCoverage else { return nil }
            return (window, intersection, coverage, zOrder[window.id] ?? .max)
        }.sorted { lhs, rhs in
            if lhs.2 != rhs.2 {
                return lhs.2 > rhs.2
            }
            if lhs.3 != rhs.3 {
                return lhs.3 < rhs.3
            }
            return lhs.0.id < rhs.0.id
        }.first

        if let bestOverlap {
            return .window(windowID: bestOverlap.0.id, effectiveFrameRect: bestOverlap.1)
        }

        guard let activeDisplayID else { return nil }
        return .display(displayID: activeDisplayID, effectiveFrameRect: clampedFrame)
    }

    private static func frozenPixelCropRect(
        frameInScreen: CGRect,
        screenFrame: CGRect,
        pixelScaleX: CGFloat,
        pixelScaleY: CGFloat,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect? {
        guard frameInScreen.width > 0, frameInScreen.height > 0 else { return nil }
        guard screenFrame.width > 0, screenFrame.height > 0 else { return nil }

        let localX = frameInScreen.minX - screenFrame.minX
        let localYFromTop = screenFrame.maxY - frameInScreen.maxY

        let scaledXMin = Int(floor(localX * pixelScaleX))
        let scaledYMin = Int(floor(localYFromTop * pixelScaleY))
        let scaledXMax = Int(ceil((localX + frameInScreen.width) * pixelScaleX))
        let scaledYMax = Int(ceil((localYFromTop + frameInScreen.height) * pixelScaleY))

        let clampedXMin = max(0, min(imageWidth, scaledXMin))
        let clampedYMin = max(0, min(imageHeight, scaledYMin))
        let clampedXMax = max(clampedXMin, min(imageWidth, scaledXMax))
        let clampedYMax = max(clampedYMin, min(imageHeight, scaledYMax))

        let width = clampedXMax - clampedXMin
        let height = clampedYMax - clampedYMin
        guard width > 0, height > 0 else { return nil }

        return CGRect(x: clampedXMin, y: clampedYMin, width: width, height: height)
    }

    private func startSnapCapture() {
        guard captureState.frameRect.width > 0, captureState.frameRect.height > 0 else { return }
        guard let frozenScreenCGImage else {
            log.error("Snap: frozen screen image not available")
            return
        }
        guard let screen = activeScreen else {
            log.error("Snap: active screen not available")
            return
        }

        let clampedFrame = captureState.frameRect.intersection(screen.frame)
        guard !clampedFrame.isNull, !clampedFrame.isEmpty else {
            log.error("Snap: frame does not intersect active screen")
            return
        }

        let requestID = snapRequestID &+ 1
        snapRequestID = requestID
        currentSnapTask?.cancel()

        let pixelScaleX = captureState.frozenPixelScaleX
        let pixelScaleY = captureState.frozenPixelScaleY
        let selectedWindowID = resolveSelectedWindowIDForCurrentFrame()
        let selectedWindow = windowEnumerator.windows.first(where: { $0.id == selectedWindowID })

        currentSnapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard requestID == self.snapRequestID else { return }

            guard let cropRect = Self.frozenPixelCropRect(
                frameInScreen: clampedFrame,
                screenFrame: screen.frame,
                pixelScaleX: pixelScaleX,
                pixelScaleY: pixelScaleY,
                imageWidth: frozenScreenCGImage.width,
                imageHeight: frozenScreenCGImage.height
            ) else {
                log.error("Snap: invalid pixel crop rect for frozen image")
                return
            }

            guard let croppedCG = frozenScreenCGImage.cropping(to: cropRect) else {
                log.error("Snap: failed to crop frozen image")
                return
            }

            guard requestID == self.snapRequestID else { return }

            let nsImage = NSImage(cgImage: croppedCG, size: clampedFrame.size)
            self.enterSnapEditMode(image: nsImage, windowInfo: selectedWindow)
            self.currentSnapTask = nil
        }
    }

    // MARK: - In-Frame Snap Edit

    private func enterSnapEditMode(image: NSImage, windowInfo: WindowInfo?) {
        log.info("Entering snap edit mode")
        captureState.isSnapEditing = true
        snapEditWindowInfo = windowInfo

        let document = EditorDocument(baseImage: image, context: .snapEdit)
        snapEditDocument = document
        snapEditToolCancellable?.cancel()
        snapEditToolCancellable = document.$selectedTool
            .receive(on: RunLoop.main)
            .sink { [weak self] tool in
                self?.applySnapEditInputRouting(
                    selectedTool: tool,
                    source: "document-publisher"
                )
            }

        // Frame panel stays visible (green border) and interactive at edges
        // so the user can resize/move the frame to re-snap

        // Create image panel at frameRect
        let frameRect = captureState.frameRect
        let imagePanel = SnapEditImagePanel(contentRect: frameRect)
        imagePanel.level = OverlayWindowLevel.snapEditImage

        let canvasView = EditorCanvasView(
            document: document,
            onMagnify: { _, _ in }
        )
        .frame(width: frameRect.width, height: frameRect.height)

        let containerView = SnapEditCanvasContainerView(
            frame: CGRect(origin: .zero, size: frameRect.size)
        )
        let hostingView = FirstMousePassthroughHostingView(rootView: canvasView)
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        imagePanel.contentView = containerView
        snapEditContainerView = containerView
        snapEditCanvasHostingView = hostingView
        NSApp.activate(ignoringOtherApps: true)
        imagePanel.makeKeyAndOrderFront(nil)
        snapEditImagePanel = imagePanel

        // Replace toolbar content with annotation tools + ✅/❌
        let toolbarView = PillToolbarView(
            captureState: captureState,
            onCapture: { [weak self] in self?.startScrollFromSnapEdit() },
            onRecord: { [weak self] in self?.startRecordFromSnapEdit() },
            onDone: { [weak self] in Task { await self?.stopCapture() } },
            onCancel: { [weak self] in self?.cancelSnapEdit() },
            onSnapConfirm: { [weak self] in self?.confirmSnapEdit() },
            onSnapCancel: { [weak self] in self?.cancelSnapEdit() },
            onPin: { [weak self] in self?.pinFromSnapEdit() },
            onRelay: { [weak self] in self?.relayFromSnapEdit() },
            onOCR: { [weak self] in self?.ocrFromSnapEdit() },
            onTranslate: { [weak self] in self?.translateFromSnapEdit() },
            onExtractSubject: { [weak self] in self?.extractFromSnapEdit() },
            onSnapEditToolChanged: { [weak self] tool in
                self?.applySnapEditInputRouting(
                    selectedTool: tool,
                    source: "toolbar-action"
                )
            },
            snapEditDocument: document
        )
        let toolbarHostingView = FirstMousePassthroughHostingView(rootView: toolbarView)
        toolbarHostingView.wantsLayer = true
        toolbarHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        toolbarPanel?.contentView = toolbarHostingView
        toolbarPanel?.level = OverlayWindowLevel.snapEditToolbar
        toolbarPanel?.fitToContent()

        updateToolbarPosition(for: frameRect)
        toolbarPanel?.orderFront(nil)
        applySnapEditInputRouting(
            selectedTool: document.selectedTool,
            source: "enter-snap-edit"
        )
    }

    func confirmSnapEdit() {
        guard let document = snapEditDocument else {
            exitSnapEditMode()
            return
        }

        let payload = SnapConfirmPayload(
            baseImage: document.baseImage,
            imageSize: CGSize(width: document.imageWidth, height: document.imageHeight),
            annotations: document.visibleAnnotations,
            draft: document.draftAnnotation,
            windowInfo: snapEditWindowInfo,
            captureRect: captureState.frameRect
        )

        exitSnapEditMode()
        let confirmStart = CFAbsoluteTimeGetCurrent()

        Task { @MainActor [weak self] in
            guard let self else { return }

            let composeStart = CFAbsoluteTimeGetCurrent()
            guard let composedImage = EditorCompositor.compose(
                baseImage: payload.baseImage,
                imageSize: payload.imageSize,
                annotations: payload.annotations,
                draft: payload.draft
            ) else {
                log.error("Snap edit confirm failed — compose returned nil")
                return
            }
            let composeMs = Int((CFAbsoluteTimeGetCurrent() - composeStart) * 1000.0)

            let storeStart = CFAbsoluteTimeGetCurrent()
            onSnapEditConfirmed?(composedImage, payload.windowInfo, payload.captureRect)
            let storeMs = Int((CFAbsoluteTimeGetCurrent() - storeStart) * 1000.0)

            scheduleDeferredClipboardCopy(for: composedImage)

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - confirmStart) * 1000.0)
            if composeMs > 120 || storeMs > 120 || totalMs > 120 {
                log.warning("Snap confirm slow compose=\(composeMs)ms store=\(storeMs)ms total=\(totalMs)ms")
            } else {
                log.info("Snap confirmed compose=\(composeMs)ms store=\(storeMs)ms total=\(totalMs)ms")
            }
        }
    }

    private func scheduleDeferredClipboardCopy(for image: NSImage) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            let copyStart = CFAbsoluteTimeGetCurrent()
            let clipboardImage = CaptureOutputWatermarking.render(image)
            do {
                try clipboardImage.copyToClipboard()
                let copyMs = Int((CFAbsoluteTimeGetCurrent() - copyStart) * 1000.0)
                if copyMs > 120 {
                    log.warning("Snap clipboard copy slow \(copyMs)ms")
                } else {
                    log.info("Snap clipboard copied in \(copyMs)ms")
                }
            } catch {
                log.error("Snap clipboard copy failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelSnapEdit() {
        log.info("Snap edit cancelled")
        exitSnapEditMode()
    }

    func pinFromSnapEdit() {
        guard let document = snapEditDocument else { return }
        guard let composedImage = renderComposedImage(from: document) else { return }
        onPinFromSnapEdit?(composedImage, snapEditWindowInfo, captureState.frameRect)
        log.info("Snap edit — pinned to desktop")
    }

    func relayFromSnapEdit() {
        guard let document = snapEditDocument,
              let composed = renderComposedImage(from: document) else { return }
        let image = CaptureOutputWatermarking.render(composed)
        exitSnapEditMode()
        Task { @MainActor in
            await Task.yield()
            RelayMacController.shared.sendImage(image, title: L10n.localized("Picelf 截图", "Picelf Screenshot"))
        }
    }

    func ocrFromSnapEdit() {
        guard let document = snapEditDocument else { return }
        guard let composedImage = renderComposedImage(from: document) else { return }
        onOpenEditorWithOCR?(composedImage)
        log.info("Snap edit — opening editor with OCR")
        exitSnapEditMode()
    }

    func translateFromSnapEdit() {
        guard let document = snapEditDocument else { return }
        guard let composedImage = renderComposedImage(from: document) else { return }
        onOpenEditorWithTranslation?(composedImage)
        log.info("Snap edit — opening editor with translation")
        exitSnapEditMode()
    }

    func extractFromSnapEdit() {
        guard let document = snapEditDocument else { return }
        guard let composedImage = renderComposedImage(from: document) else { return }
        onOpenEditorWithExtract?(composedImage)
        log.info("Snap edit — opening editor with extract")
        exitSnapEditMode()
    }

    private func exitSnapEditMode() {
        captureState.isSnapEditing = false
        snapEditToolCancellable?.cancel()
        snapEditToolCancellable = nil
        orderOutAndDeferWindowRelease(snapEditImagePanel)
        snapEditImagePanel = nil
        snapEditContainerView = nil
        snapEditCanvasHostingView = nil
        snapEditDocument = nil
        snapEditWindowInfo = nil
        deactivate()
    }

    /// Clean up snap edit state without tearing down overlay panels.
    /// Used when switching from snap to scroll/record capture.
    private func exitSnapEditForRecapture() {
        captureState.isSnapEditing = false
        snapEditToolCancellable?.cancel()
        snapEditToolCancellable = nil
        orderOutAndDeferWindowRelease(snapEditImagePanel)
        snapEditImagePanel = nil
        snapEditContainerView = nil
        snapEditCanvasHostingView = nil
        snapEditDocument = nil
        snapEditWindowInfo = nil
        updateFramePanelInputPolicy()
    }

    func startScrollFromSnapEdit() {
        suppressAutoSnap = true
        exitSnapEditForRecapture()
        Task {
            await startCapture()
            suppressAutoSnap = false
        }
    }

    func startRecordFromSnapEdit() {
        Task { [weak self] in
            await self?.beginRecordingLaunch(context: .snapEditToolbar)
        }
    }

    private func renderComposedImage(from document: EditorDocument) -> NSImage? {
        EditorCompositor.compose(
            baseImage: document.baseImage,
            imageSize: CGSize(width: document.imageWidth, height: document.imageHeight),
            annotations: document.visibleAnnotations,
            draft: document.draftAnnotation
        )
    }
}
