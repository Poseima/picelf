import AppKit
import AVFoundation
import SwiftUI
import ScreenCaptureKit
import Combine
import Security
import os

private let log = Logger(subsystem: "com.picelf", category: "RecordingOrchestrator")

struct PendingRecordingTarget<Value> {
    private(set) var value: Value?

    var hasValue: Bool {
        value != nil
    }

    mutating func stage(_ value: Value) {
        self.value = value
    }

    mutating func consumeForStart() -> Value? {
        defer { value = nil }
        return value
    }

    mutating func clear() {
        value = nil
    }
}

struct RecordingFailureContext {
    enum Phase {
        case start
        case stop
    }

    let phase: Phase
    let message: String
    let underlyingError: Error?
}

enum MicrophonePermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
}

struct MicrophonePermissionRuntimeDiagnostics: Equatable {
    let bundleIdentifier: String
    let bundlePath: String
    let isSigned: Bool
    let teamIdentifier: String?
    let hasAppSandbox: Bool
    let hasAudioInputEntitlement: Bool
    let hasLegacyMicrophoneEntitlement: Bool

    var isRunningFromDerivedData: Bool {
        bundlePath.contains("/DerivedData/")
    }

    var isSuitableForPrivacyPermissionTesting: Bool {
        isSigned
            && teamIdentifier?.isEmpty == false
            && hasAppSandbox
            && hasAudioInputEntitlement
    }

    var logSummary: String {
        [
            "bundleID=\(bundleIdentifier)",
            "bundlePath=\(bundlePath)",
            "signed=\(isSigned)",
            "teamID=\(teamIdentifier ?? "nil")",
            "sandbox=\(hasAppSandbox)",
            "audioInputEntitlement=\(hasAudioInputEntitlement)",
            "legacyMicrophoneEntitlement=\(hasLegacyMicrophoneEntitlement)",
            "derivedData=\(isRunningFromDerivedData)"
        ].joined(separator: " ")
    }

    var userFacingMessage: String {
        let reasons = invalidReasons.joined(separator: "\n")
        if L10n.zh {
            return """
            当前这份 Picelf 构建不适合验证麦克风权限弹窗。

            \(reasons)

            路径：\(bundlePath)

            请从 Xcode 运行签名 Debug 构建，或测试 /Applications/Picelf.app。
            """
        }

        return """
        This Picelf build is not suitable for microphone permission testing.

        \(reasons)

        Path: \(bundlePath)

        Run a team-signed Debug build from Xcode, or test /Applications/Picelf.app.
        """
    }

    private var invalidReasons: [String] {
        var reasons: [String] = []

        if !isSigned {
            reasons.append(
                L10n.zh
                    ? "当前 app bundle 没有有效签名。"
                    : "The current app bundle is not validly signed."
            )
        }

        if teamIdentifier?.isEmpty != false {
            reasons.append(
                L10n.zh
                    ? "当前构建缺少开发者团队签名。"
                    : "The current build has no developer team signature."
            )
        }

        if !hasAppSandbox {
            reasons.append(
                L10n.zh
                    ? "缺少 App Sandbox entitlement。"
                    : "The App Sandbox entitlement is missing."
            )
        }

        if !hasAudioInputEntitlement {
            if hasLegacyMicrophoneEntitlement {
                reasons.append(
                    L10n.zh
                        ? "当前只有旧的 `com.apple.security.device.microphone`，macOS 沙盒需要 `com.apple.security.device.audio-input`。"
                        : "Only the legacy `com.apple.security.device.microphone` entitlement is present; macOS App Sandbox expects `com.apple.security.device.audio-input`."
                )
            } else {
                reasons.append(
                    L10n.zh
                        ? "缺少麦克风 entitlement `com.apple.security.device.audio-input`。"
                        : "The microphone entitlement `com.apple.security.device.audio-input` is missing."
                )
            }
        }

        if isRunningFromDerivedData {
            reasons.append(
                L10n.zh
                    ? "当前路径位于 DerivedData；如果它来自 unsigned CLI 构建，权限行为可能与签名发布版本不一致。"
                    : "The bundle is running from DerivedData; if it came from an unsigned CLI build, permission behavior may not match a signed release."
            )
        }

        return reasons.isEmpty
            ? [
                L10n.zh
                    ? "当前构建的签名或权限元数据不符合稳定的 TCC 验证条件。"
                    : "This build's signing or privacy metadata does not meet the requirements for stable TCC validation."
            ]
            : reasons
    }

    static func current() -> MicrophonePermissionRuntimeDiagnostics {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundleURL.path

        var isSigned = false
        var teamIdentifier: String?
        var entitlements: [String: Any] = [:]

        var staticCode: SecStaticCode?
        if SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
           let staticCode
        {
            isSigned = SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSBasicValidateOnly),
                nil
            ) == errSecSuccess

            var signingInfo: CFDictionary?
            if SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInfo
            ) == errSecSuccess,
               let signingInfo = signingInfo as? [String: Any]
            {
                teamIdentifier = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
                entitlements = signingInfo[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
            }
        }

        return MicrophonePermissionRuntimeDiagnostics(
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            isSigned: isSigned,
            teamIdentifier: teamIdentifier,
            hasAppSandbox: entitlements["com.apple.security.app-sandbox"] as? Bool == true,
            hasAudioInputEntitlement: entitlements["com.apple.security.device.audio-input"] as? Bool == true,
            hasLegacyMicrophoneEntitlement: entitlements["com.apple.security.device.microphone"] as? Bool == true
        )
    }
}

protocol MicrophonePermissionControlling {
    func authorizationState() -> MicrophonePermissionState
    func requestAccess() async -> Bool
    func openSystemSettings()
    func runtimeDiagnostics() -> MicrophonePermissionRuntimeDiagnostics?
    func logDiagnostics(trigger: String)
}

extension MicrophonePermissionControlling {
    func runtimeDiagnostics() -> MicrophonePermissionRuntimeDiagnostics? { nil }
    func logDiagnostics(trigger: String) {}
}

struct SystemMicrophonePermissionController: MicrophonePermissionControlling {
    func authorizationState() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestAccess() async -> Bool {
        logDiagnostics(trigger: "requestAccess")
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                break
            }
        }
    }

    func runtimeDiagnostics() -> MicrophonePermissionRuntimeDiagnostics? {
        MicrophonePermissionRuntimeDiagnostics.current()
    }

    func logDiagnostics(trigger: String) {
        let diagnostics = MicrophonePermissionRuntimeDiagnostics.current()
        log.notice(
            "Microphone permission diagnostics trigger=\(trigger, privacy: .public) \(diagnostics.logSummary, privacy: .public)"
        )
    }
}

enum MicrophonePermissionAlertContext: Equatable {
    case enableMicrophone
    case continueWithoutMicrophone
    case invalidRuntimeEnvironment(message: String)
}

enum MicrophonePermissionAlertAction: Equatable {
    case acknowledge
    case openSystemSettings
    case continueWithoutMicrophone
    case cancel
}

typealias MicrophonePermissionAlertPresenter =
    @MainActor (MicrophonePermissionAlertContext) -> MicrophonePermissionAlertAction

enum RecordingMicrophonePreflightResult: Equatable {
    case proceed
    case requiresContinueWithoutMicrophone
}

enum RecordingMicrophoneEnableResult: Equatable {
    case enabled
    case denied
    case invalidRuntimeEnvironment(message: String)
}

struct RecordingMicrophonePermissionCoordinator {
    let controller: any MicrophonePermissionControlling

    func authorizationState() -> MicrophonePermissionState {
        controller.authorizationState()
    }

    func sanitizePreferences(_ prefs: AppPreferences) {
        guard prefs.recordingCaptureMicrophone else { return }
        guard controller.authorizationState() != .authorized else { return }
        prefs.recordingCaptureMicrophone = false
    }

    func runtimeDiagnostics() -> MicrophonePermissionRuntimeDiagnostics? {
        controller.runtimeDiagnostics()
    }

    func enableMicrophone(in prefs: AppPreferences) async -> RecordingMicrophoneEnableResult {
        controller.logDiagnostics(trigger: "enableMicrophone")
        if let diagnostics = controller.runtimeDiagnostics(),
           !diagnostics.isSuitableForPrivacyPermissionTesting
        {
            prefs.recordingCaptureMicrophone = false
            return .invalidRuntimeEnvironment(message: diagnostics.userFacingMessage)
        }

        switch controller.authorizationState() {
        case .authorized:
            prefs.recordingCaptureMicrophone = true
            return .enabled
        case .notDetermined:
            let granted = await controller.requestAccess()
            prefs.recordingCaptureMicrophone = granted
            return granted ? .enabled : .denied
        case .denied:
            prefs.recordingCaptureMicrophone = false
            return .denied
        }
    }

    func preflightRecordingStart(in prefs: AppPreferences) async -> RecordingMicrophonePreflightResult {
        controller.logDiagnostics(trigger: "preflightRecordingStart")
        guard prefs.recordingCaptureMicrophone else {
            return .proceed
        }

        if let diagnostics = controller.runtimeDiagnostics(),
           !diagnostics.isSuitableForPrivacyPermissionTesting
        {
            prefs.recordingCaptureMicrophone = false
            return .requiresContinueWithoutMicrophone
        }

        switch controller.authorizationState() {
        case .authorized:
            return .proceed
        case .notDetermined:
            if await controller.requestAccess() {
                return .proceed
            }
            fallthrough
        case .denied:
            prefs.recordingCaptureMicrophone = false
            return .requiresContinueWithoutMicrophone
        }
    }

    func openSystemSettings() {
        controller.openSystemSettings()
    }
}

private enum RecordingOrchestratorError: LocalizedError {
    case missingTarget

    var errorDescription: String? {
        switch self {
        case .missingTarget:
            return L10n.recordingStartNoTargetBody
        }
    }
}

@MainActor
final class RecordingOrchestrator: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparingRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var showingConfig = false
    @Published private(set) var countdownValue: Int?

    private var hasSubmitted = false
    private var isStopping = false
    private var startToken = UUID()
    private var configPanel: RecordingConfigPanel?
    private var toolbarPanel: RecordingToolbarPanel?
    private var countdownPanel: NSPanel?
    private var screenRecorder: ScreenRecorder?
    private var countdownTask: Task<Void, Never>?
    private var elapsedObservation: AnyCancellable?
    private var pendingRecordingTarget = PendingRecordingTarget<ScreenRecorder.CaptureTarget>()
    private var activeDisplayID: CGDirectDisplayID?
    private var activeScreen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == activeDisplayID
        }
    }
    private var configPanelLevel: NSWindow.Level = .floating
    private var toolbarPanelLevel: NSWindow.Level = .floating + 1
    private var countdownPanelLevel: NSWindow.Level = .floating + 2
    private let microphonePermissionCoordinator: RecordingMicrophonePermissionCoordinator
    private let microphonePermissionAlertPresenter: MicrophonePermissionAlertPresenter

    var onRecordingNotice: ((String) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingComplete: ((_ videoURL: URL, _ duration: TimeInterval) -> Void)?
    var onRecordingFailed: ((RecordingFailureContext) -> Void)?
    var onWillOpenMicrophoneSystemSettings: (() -> Void)?

    init(
        microphonePermissionController: any MicrophonePermissionControlling = SystemMicrophonePermissionController(),
        microphonePermissionAlertPresenter: MicrophonePermissionAlertPresenter? = nil
    ) {
        self.microphonePermissionCoordinator = RecordingMicrophonePermissionCoordinator(
            controller: microphonePermissionController
        )
        self.microphonePermissionAlertPresenter =
            microphonePermissionAlertPresenter ?? RecordingOrchestrator.presentMicrophonePermissionAlert
    }

    func configurePanelLevels(config: NSWindow.Level, toolbar: NSWindow.Level, countdown: NSWindow.Level) {
        configPanelLevel = config
        toolbarPanelLevel = toolbar
        countdownPanelLevel = countdown
    }

    // MARK: - Config

    func showConfig(below frameRect: CGRect, on screen: NSScreen, target: ScreenRecorder.CaptureTarget) {
        guard !isRecording else { return }
        hideConfigPanel()
        pendingRecordingTarget.stage(target)
        activeDisplayID = target.display.displayID
        microphonePermissionCoordinator.sanitizePreferences(AppPreferences.shared)

        let panel = RecordingConfigPanel()
        panel.level = configPanelLevel
        let configView = RecordingConfigView(
            prefs: AppPreferences.shared,
            microphonePermissionCoordinator: microphonePermissionCoordinator,
            onMicrophonePermissionRequestWillBegin: { [weak self] in
                self?.prepareConfigPanelForPermissionRequest()
            },
            onMicrophonePermissionRequestCompleted: { [weak self] in
                self?.restoreConfigPanelFocus()
            },
            onOpenSystemSettings: { [weak self] in
                self?.exitCaptureAndOpenMicrophoneSystemSettings()
            },
            onStart: { [weak self] in
                Task { await self?.startRecording() }
            },
            onCancel: { [weak self] in
                self?.dismissConfig()
            }
        )
        panel.contentView = NSHostingView(rootView: configView)
        panel.positionBelow(rect: frameRect, on: screen)
        configPanel = panel
        showingConfig = true
        panel.orderFrontRegardless()
        log.info("Config panel shown")
    }

    func dismissConfig() {
        hideConfigPanel()
        pendingRecordingTarget.clear()
    }

    private func hideConfigPanel() {
        guard let panel = configPanel else {
            showingConfig = false
            return
        }
        orderOutAndDeferWindowRelease(panel)
        configPanel = nil
        showingConfig = false
    }

    // MARK: - Recording lifecycle

    func startRecording() async {
        guard !isPreparingRecording, !isRecording, !isStopping else { return }
        let token = UUID()
        startToken = token
        isPreparingRecording = true
        defer { if startToken == token { isPreparingRecording = false } }

        guard pendingRecordingTarget.hasValue else {
            log.error("Start recording requested without target")
            notifyFailure(phase: .start, error: RecordingOrchestratorError.missingTarget)
            return
        }

        let prefs = AppPreferences.shared
        guard await preflightMicrophoneAccess(for: prefs) else {
            return
        }

        guard startToken == token else { return }
        guard let target = pendingRecordingTarget.consumeForStart() else {
            log.error("Recording target disappeared before start")
            notifyFailure(phase: .start, error: RecordingOrchestratorError.missingTarget)
            return
        }

        hideConfigPanel()

        let countdown = prefs.recordingCountdown

        // Countdown
        if countdown > 0 {
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                await self.runCountdown(seconds: countdown)
            }
            countdownTask = task
            await task.value
            let wasCancelled = task.isCancelled
            countdownTask = nil
            if wasCancelled { return }
        }

        guard startToken == token else { return }
        guard let screen = activeScreen else {
            notifyFailure(phase: .start, error: RecordingError.displayConfigurationChanged)
            return
        }
        let config = RecordingConfiguration(
            format: prefs.recordingFormat,
            resolution: prefs.recordingResolution,
            frameRate: prefs.recordingFrameRate,
            captureSystemAudio: prefs.recordingCaptureSystemAudio,
            microphoneDeviceID: prefs.recordingCaptureMicrophone ? prefs.recordingMicrophoneDeviceID : nil,
            showsCursor: prefs.recordingShowsCursor,
            durationLimitSeconds: prefs.recordingDurationLimit,
            countdownSeconds: countdown,
            scaleFactor: 1
        )

        let recorder = ScreenRecorder(configuration: config)
        elapsedObservation?.cancel()
        elapsedObservation = nil
        screenRecorder = recorder

        hasSubmitted = false
        isStopping = false
        recorder.onAutomaticStop = { [weak self, weak recorder] result, reason in
            guard let self, let recorder, self.screenRecorder === recorder else { return }
            self.completeRecording(result, reason: reason)
        }

        do {
            try await recorder.startRecording(target: target)
            guard startToken == token, screenRecorder === recorder else {
                _ = try? await recorder.stopRecording()
                return
            }
            isRecording = true
            isPaused = false
            hasSubmitted = false
            showToolbar(on: screen)

            // Observe elapsed from recorder
            elapsedObservation = recorder.$elapsedSeconds
                .receive(on: RunLoop.main)
                .assign(to: \.elapsedSeconds, on: self)

            onRecordingStarted?()
            log.info("Recording started")
        } catch {
            log.error("Failed to start recording: \(error.localizedDescription)")
            guard startToken == token else { return }
            screenRecorder = nil
            notifyFailure(phase: .start, error: error)
        }
    }

    func pauseRecording() {
        guard isRecording, !isStopping, !isPaused else { return }
        screenRecorder?.pauseRecording()
        isPaused = true
        log.info("Paused")
    }

    func resumeRecording() {
        guard isRecording, !isStopping, isPaused else { return }
        screenRecorder?.resumeRecording()
        isPaused = false
        log.info("Resumed")
    }

    func stopRecording() {
        guard isRecording, !hasSubmitted, !isStopping, let recorder = screenRecorder else { return }
        isStopping = true
        Task {
            let result: Result<RecordingResult, Error>
            do { result = .success(try await recorder.stopRecording()) }
            catch { result = .failure(error) }
            guard screenRecorder === recorder else { return }
            completeRecording(result, reason: .user)
        }
    }

    private func completeRecording(_ result: Result<RecordingResult, Error>, reason: RecordingStopReason) {
        guard !hasSubmitted else { return }
        hasSubmitted = true
        isRecording = false
        isPaused = false
        isStopping = false
        dismissToolbar()
        elapsedObservation?.cancel()
        elapsedObservation = nil
        screenRecorder = nil
        switch result {
        case .success(let saved):
            onRecordingComplete?(saved.url, saved.duration)
            if let notice = reason.notice { onRecordingNotice?(notice) }
        case .failure(let error):
            log.error("Stop failed: \(error.localizedDescription)")
            notifyFailure(phase: .stop, error: error)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        startToken = UUID()
        // If recording, save it (Escape = save, not discard)
        if isRecording && !hasSubmitted {
            stopRecording()
        }

        // Cancel countdown
        countdownTask?.cancel()
        countdownTask = nil

        dismissConfig()
        dismissToolbar()
        dismissCountdown()
        isPreparingRecording = false
        elapsedObservation?.cancel()
        elapsedObservation = nil
        if !isRecording && !isStopping { screenRecorder = nil }
        pendingRecordingTarget.clear()
    }

    // MARK: - Countdown

    private func runCountdown(seconds: Int) async {
        guard let screen = activeScreen else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = countdownPanelLevel
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false

        let cx = screen.frame.midX - 100
        let cy = screen.frame.midY - 100
        panel.setFrameOrigin(NSPoint(x: cx, y: cy))
        countdownPanel = panel

        for i in stride(from: seconds, through: 1, by: -1) {
            countdownValue = i
            let countdownView = CountdownOverlay(value: i)
            panel.contentView = NSHostingView(rootView: countdownView)
            panel.orderFront(nil)

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                // Cancelled
                dismissCountdown()
                return
            }
        }

        dismissCountdown()
        countdownValue = nil
    }

    private func notifyFailure(phase: RecordingFailureContext.Phase, error: Error) {
        onRecordingFailed?(
            RecordingFailureContext(
                phase: phase,
                message: error.localizedDescription,
                underlyingError: error
            )
        )
    }

    private func dismissCountdown() {
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
        countdownValue = nil
    }

    func preflightMicrophoneAccess(for prefs: AppPreferences) async -> Bool {
        switch await microphonePermissionCoordinator.preflightRecordingStart(in: prefs) {
        case .proceed:
            return true
        case .requiresContinueWithoutMicrophone:
            log.notice("Microphone access unavailable at recording start; disabling mic")
            switch handleMicrophonePermissionAlert(.continueWithoutMicrophone) {
            case .continueWithoutMicrophone:
                return true
            case .openSystemSettings, .cancel, .acknowledge:
                return false
            }
        }
    }

    // MARK: - Toolbar

    private func showToolbar(on screen: NSScreen) {
        let panel = RecordingToolbarPanel()
        panel.level = toolbarPanelLevel
        let view = RecordingToolbarView(orchestrator: self)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        panel.positionTopCenter(on: screen)
        panel.orderFront(nil)
        toolbarPanel = panel
    }

    private func dismissToolbar() {
        orderOutAndDeferWindowRelease(toolbarPanel)
        toolbarPanel = nil
    }

    private func orderOutAndDeferWindowRelease(_ window: NSWindow?) {
        guard let window else { return }
        let retainedContentView = window.contentView
        window.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [window, retainedContentView] in
            _ = window
            _ = retainedContentView
        }
    }

    private func prepareConfigPanelForPermissionRequest() {
        guard let panel = configPanel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func restoreConfigPanelFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.configPanel else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    private func exitCaptureAndOpenMicrophoneSystemSettings() {
        log.info("Exiting capture flow before opening microphone system settings")
        if let onWillOpenMicrophoneSystemSettings {
            onWillOpenMicrophoneSystemSettings()
        } else {
            cleanup()
        }

        DispatchQueue.main.async { [microphonePermissionCoordinator] in
            microphonePermissionCoordinator.openSystemSettings()
        }
    }

    private func handleMicrophonePermissionAlert(
        _ context: MicrophonePermissionAlertContext
    ) -> MicrophonePermissionAlertAction {
        let action = microphonePermissionAlertPresenter(context)
        if action == .openSystemSettings {
            exitCaptureAndOpenMicrophoneSystemSettings()
        }
        return action
    }

    private static func presentMicrophonePermissionAlert(
        _ context: MicrophonePermissionAlertContext
    ) -> MicrophonePermissionAlertAction {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning

        switch context {
        case .enableMicrophone:
            alert.messageText = L10n.microphonePermissionRequired
            alert.informativeText = L10n.microphonePermissionBody
            alert.addButton(withTitle: L10n.exitAndOpenSystemSettings)
            alert.addButton(withTitle: L10n.ok)
        case .continueWithoutMicrophone:
            alert.messageText = L10n.microphoneDisabledForThisRecording
            alert.informativeText = L10n.microphoneDisabledForThisRecordingBody
            alert.addButton(withTitle: L10n.continueWithoutMicrophone)
            alert.addButton(withTitle: L10n.exitAndOpenSystemSettings)
            alert.addButton(withTitle: L10n.cancel)
        case .invalidRuntimeEnvironment(let message):
            alert.messageText = L10n.microphonePermissionTestingRequiresSignedBuild
            alert.informativeText = message
            alert.addButton(withTitle: L10n.ok)
        }

        let response = alert.runModal()
        switch context {
        case .enableMicrophone:
            return response == .alertFirstButtonReturn ? .openSystemSettings : .acknowledge
        case .continueWithoutMicrophone:
            switch response {
            case .alertFirstButtonReturn:
                return .continueWithoutMicrophone
            case .alertSecondButtonReturn:
                return .openSystemSettings
            default:
                return .cancel
            }
        case .invalidRuntimeEnvironment:
            return .acknowledge
        }
    }

#if DEBUG
    var configPanelIdentifierForTesting: ObjectIdentifier? {
        configPanel.map(ObjectIdentifier.init)
    }

    func installConfigPanelForTesting(_ panel: RecordingConfigPanel) {
        hideConfigPanel()
        configPanel = panel
        showingConfig = true
    }
#endif
}

// MARK: - Countdown Overlay

private struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 72, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            .frame(width: 200, height: 200)
    }
}
