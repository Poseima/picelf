import AppKit
import AVFoundation
import XCTest
@testable import Picelf

final class CaptureOrchestratorScreenRetargetPolicyTests: XCTestCase {
    func test_pendingRecordingTarget_consumeForStart_returnsValueAndClearsState() {
        var pending = PendingRecordingTarget<Int>()

        pending.stage(77)

        XCTAssertTrue(pending.hasValue)
        XCTAssertEqual(pending.consumeForStart(), 77)
        XCTAssertFalse(pending.hasValue)
        XCTAssertNil(pending.consumeForStart())
    }

    func test_pendingRecordingTarget_clear_dropsValueWithoutStarting() {
        var pending = PendingRecordingTarget<String>()

        pending.stage("desktop")
        pending.clear()

        XCTAssertFalse(pending.hasValue)
        XCTAssertNil(pending.consumeForStart())
    }

    func test_recordingFailureAlert_forStartFailure_usesStartTitle() {
        let alert = CaptureOrchestrator.recordingFailureAlert(
            for: RecordingFailureContext(phase: .start, message: "Start boom", underlyingError: nil)
        )

        XCTAssertEqual(alert, RecordingFailureAlertContent(message: L10n.recordingStartFailed, detail: "Start boom"))
    }

    func test_recordingFailureAlert_forStopFailure_usesSaveTitle() {
        let alert = CaptureOrchestrator.recordingFailureAlert(
            for: RecordingFailureContext(phase: .stop, message: "Stop boom", underlyingError: nil)
        )

        XCTAssertEqual(alert, RecordingFailureAlertContent(message: L10n.recordingSaveFailed, detail: "Stop boom"))
    }

    func test_shouldRetarget_whenIdleAndNotCapturing() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .idleSelecting,
                isCapturing: false,
                isRecording: false,
                isStitching: false,
                isSnapEditing: false
            )
        )
    }

    func test_shouldNotRetarget_whenSelectionReady() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .selectionReady,
                isCapturing: false,
                isRecording: false,
                isStitching: false,
                isSnapEditing: false
            )
        )
    }

    func test_shouldNotRetarget_whenDraggingSelection() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .dragSelecting,
                isCapturing: false,
                isRecording: false,
                isStitching: false,
                isSnapEditing: false
            )
        )
    }

    func test_shouldNotRetarget_whenCapturing() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .idleSelecting,
                isCapturing: true,
                isRecording: false,
                isStitching: false,
                isSnapEditing: false
            )
        )
    }

    func test_shouldNotRetarget_whenRecording() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .idleSelecting,
                isCapturing: false,
                isRecording: true,
                isStitching: false,
                isSnapEditing: false
            )
        )
    }

    func test_shouldNotRetarget_whenStitching() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .idleSelecting,
                isCapturing: false,
                isRecording: false,
                isStitching: true,
                isSnapEditing: false
            )
        )
    }

    func test_shouldNotRetarget_whenSnapEditing() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldRetargetFramingScreen(
                mode: .idleSelecting,
                isCapturing: false,
                isRecording: false,
                isStitching: false,
                isSnapEditing: true
            )
        )
    }

    func test_resolveRecordingTargetDescriptor_prefersTopmostWindowContainingCenter() {
        let windows = [
            WindowInfo(
                id: 11,
                title: "Back",
                appName: "Back",
                appBundleID: "com.back",
                frame: CGRect(x: 80, y: 80, width: 500, height: 400),
                isOnScreen: true
            ),
            WindowInfo(
                id: 22,
                title: "Front",
                appName: "Front",
                appBundleID: "com.front",
                frame: CGRect(x: 120, y: 120, width: 500, height: 400),
                isOnScreen: true
            )
        ]

        let descriptor = CaptureOrchestrator.resolveRecordingTargetDescriptor(
            frameRect: CGRect(x: 150, y: 150, width: 240, height: 180),
            activeScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            activeDisplayID: 77,
            windows: windows,
            orderedFrontToBackBy: [22, 11]
        )

        XCTAssertEqual(
            descriptor,
            .window(windowID: 22, effectiveFrameRect: CGRect(x: 150, y: 150, width: 240, height: 180))
        )
    }

    func test_resolveRecordingTargetDescriptor_usesDisplayForDesktopArea() {
        let windows = [
            WindowInfo(
                id: 11,
                title: "Window",
                appName: "App",
                appBundleID: "com.app",
                frame: CGRect(x: 100, y: 100, width: 300, height: 240),
                isOnScreen: true
            )
        ]

        let descriptor = CaptureOrchestrator.resolveRecordingTargetDescriptor(
            frameRect: CGRect(x: 900, y: 420, width: 260, height: 180),
            activeScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            activeDisplayID: 77,
            windows: windows,
            orderedFrontToBackBy: [11]
        )

        XCTAssertEqual(
            descriptor,
            .display(displayID: 77, effectiveFrameRect: CGRect(x: 900, y: 420, width: 260, height: 180))
        )
    }

    func test_resolveRecordingTargetDescriptor_prefersWindowWhenOverlapIsMeaningful() {
        let windows = [
            WindowInfo(
                id: 11,
                title: "Window",
                appName: "App",
                appBundleID: "com.app",
                frame: CGRect(x: 100, y: 100, width: 300, height: 240),
                isOnScreen: true
            )
        ]

        let descriptor = CaptureOrchestrator.resolveRecordingTargetDescriptor(
            frameRect: CGRect(x: 20, y: 110, width: 320, height: 220),
            activeScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            activeDisplayID: 77,
            windows: windows,
            orderedFrontToBackBy: [11]
        )

        XCTAssertEqual(
            descriptor,
            .window(windowID: 11, effectiveFrameRect: CGRect(x: 100, y: 110, width: 240, height: 220))
        )
    }

    func test_resolveRecordingTargetDescriptor_usesDisplayWhenWindowOverlapIsTooSmall() {
        let windows = [
            WindowInfo(
                id: 11,
                title: "Window",
                appName: "App",
                appBundleID: "com.app",
                frame: CGRect(x: 100, y: 100, width: 220, height: 180),
                isOnScreen: true
            )
        ]

        let descriptor = CaptureOrchestrator.resolveRecordingTargetDescriptor(
            frameRect: CGRect(x: 280, y: 240, width: 260, height: 220),
            activeScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            activeDisplayID: 77,
            windows: windows,
            orderedFrontToBackBy: [11]
        )

        XCTAssertEqual(
            descriptor,
            .display(displayID: 77, effectiveFrameRect: CGRect(x: 280, y: 240, width: 260, height: 220))
        )
    }
}

@MainActor
final class RecordingMicrophonePermissionTests: XCTestCase {
    func test_sanitizePreferences_turnsOffPersistedMicWhenUnauthorized() {
        let prefs = makeRecordingPreferences()
        prefs.recordingCaptureMicrophone = true

        let coordinator = RecordingMicrophonePermissionCoordinator(
            controller: TestMicrophonePermissionController(state: .denied)
        )

        coordinator.sanitizePreferences(prefs)

        XCTAssertFalse(prefs.recordingCaptureMicrophone)
    }

    func test_enableMicrophone_requestsAccessAndPersistsGrantedState() async {
        let prefs = makeRecordingPreferences()
        let controller = TestMicrophonePermissionController(
            state: .notDetermined,
            requestAccessResult: true
        )
        let coordinator = RecordingMicrophonePermissionCoordinator(controller: controller)

        let result = await coordinator.enableMicrophone(in: prefs)

        XCTAssertEqual(result, .enabled)
        XCTAssertTrue(prefs.recordingCaptureMicrophone)
        XCTAssertEqual(controller.requestAccessCallCount, 1)
    }

    func test_enableMicrophone_keepsToggleOffWhenAccessDenied() async {
        let prefs = makeRecordingPreferences()
        let controller = TestMicrophonePermissionController(
            state: .notDetermined,
            requestAccessResult: false
        )
        let coordinator = RecordingMicrophonePermissionCoordinator(controller: controller)

        let result = await coordinator.enableMicrophone(in: prefs)

        XCTAssertEqual(result, .denied)
        XCTAssertFalse(prefs.recordingCaptureMicrophone)
        XCTAssertEqual(controller.requestAccessCallCount, 1)
    }

    func test_enableMicrophone_keepsToggleOffWhenBuildDiagnosticsAreInvalid() async {
        let prefs = makeRecordingPreferences()
        let controller = TestMicrophonePermissionController(
            state: .authorized,
            runtimeDiagnostics: MicrophonePermissionRuntimeDiagnostics(
                bundleIdentifier: "com.picelf.open.app",
                bundlePath: "/tmp/Picelf.app",
                isSigned: false,
                teamIdentifier: nil,
                hasAppSandbox: false,
                hasAudioInputEntitlement: false,
                hasLegacyMicrophoneEntitlement: true
            )
        )
        let coordinator = RecordingMicrophonePermissionCoordinator(controller: controller)

        let result = await coordinator.enableMicrophone(in: prefs)

        XCTAssertEqual(
            result,
            .invalidRuntimeEnvironment(message: controller.runtimeDiagnosticsValue?.userFacingMessage ?? "")
        )
        XCTAssertFalse(prefs.recordingCaptureMicrophone)
        XCTAssertEqual(controller.requestAccessCallCount, 0)
    }

    func test_preflightMicrophoneAccess_disablesMicAndContinuesWhenUserAcceptsFallback() async {
        let prefs = makeRecordingPreferences()
        prefs.recordingCaptureMicrophone = true
        let controller = TestMicrophonePermissionController(
            state: .notDetermined,
            requestAccessResult: false
        )
        let orchestrator = RecordingOrchestrator(
            microphonePermissionController: controller,
            microphonePermissionAlertPresenter: { context in
                XCTAssertEqual(context, .continueWithoutMicrophone)
                return .continueWithoutMicrophone
            }
        )

        let shouldProceed = await orchestrator.preflightMicrophoneAccess(for: prefs)

        XCTAssertTrue(shouldProceed)
        XCTAssertFalse(prefs.recordingCaptureMicrophone)
        XCTAssertEqual(controller.requestAccessCallCount, 1)
    }

    func test_preflightMicrophoneAccess_exitsCaptureBeforeOpeningSystemSettings() async {
        let prefs = makeRecordingPreferences()
        prefs.recordingCaptureMicrophone = true
        let controller = TestMicrophonePermissionController(state: .denied)
        let openedSettings = expectation(description: "opens microphone settings")
        var events: [String] = []
        controller.onOpenSystemSettings = {
            events.append("open")
            openedSettings.fulfill()
        }

        let orchestrator = RecordingOrchestrator(
            microphonePermissionController: controller,
            microphonePermissionAlertPresenter: { context in
                XCTAssertEqual(context, .continueWithoutMicrophone)
                return .openSystemSettings
            }
        )
        orchestrator.onWillOpenMicrophoneSystemSettings = {
            events.append("exit")
        }

        let shouldProceed = await orchestrator.preflightMicrophoneAccess(for: prefs)

        XCTAssertFalse(shouldProceed)
        await fulfillment(of: [openedSettings], timeout: 1.0)
        XCTAssertEqual(events, ["exit", "open"])
        XCTAssertEqual(controller.openSystemSettingsCallCount, 1)
        XCTAssertEqual(controller.requestAccessCallCount, 0)
    }

    func test_installConfigPanelForTesting_replacesExistingPanelAndDismissConfigClearsState() {
        let orchestrator = RecordingOrchestrator(
            microphonePermissionController: TestMicrophonePermissionController(state: .authorized)
        )
        let firstPanel = RecordingConfigPanel()
        firstPanel.contentView = NSView()
        let secondPanel = RecordingConfigPanel()
        secondPanel.contentView = NSView()

        orchestrator.installConfigPanelForTesting(firstPanel)

        XCTAssertEqual(orchestrator.configPanelIdentifierForTesting, ObjectIdentifier(firstPanel))
        XCTAssertTrue(orchestrator.showingConfig)

        orchestrator.installConfigPanelForTesting(secondPanel)

        XCTAssertEqual(orchestrator.configPanelIdentifierForTesting, ObjectIdentifier(secondPanel))
        XCTAssertTrue(orchestrator.showingConfig)
        XCTAssertFalse(firstPanel.isVisible)
        XCTAssertNotNil(firstPanel.contentView, "Retired hosting views remain attached during deferred window release")

        orchestrator.dismissConfig()

        XCTAssertFalse(orchestrator.showingConfig)
        XCTAssertNil(orchestrator.configPanelIdentifierForTesting)
        XCTAssertFalse(secondPanel.isVisible)
        XCTAssertNotNil(secondPanel.contentView, "Hiding the panel must not tear down its active layout tree")
    }

    func test_screenRecorder_validateMicrophoneAccessIfNeeded_throwsWhenMicUnauthorized() {
        let recorder = ScreenRecorder(
            configuration: RecordingConfiguration(microphoneDeviceID: "built-in-mic"),
            microphoneAuthorizationStatusProvider: { .denied }
        )

        XCTAssertThrowsError(try recorder.validateMicrophoneAccessIfNeeded()) { error in
            guard case RecordingError.microphoneAccessDenied = error else {
                return XCTFail("Expected microphoneAccessDenied, got \(error)")
            }
        }
    }

    private func makeRecordingPreferences() -> AppPreferences {
        let suiteName = "RecordingMicrophonePermissionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return AppPreferences(defaults: defaults)
    }
}

private final class TestMicrophonePermissionController: MicrophonePermissionControlling {
    var state: MicrophonePermissionState
    let requestAccessResult: Bool
    let runtimeDiagnosticsValue: MicrophonePermissionRuntimeDiagnostics?
    var onOpenSystemSettings: (() -> Void)?
    private(set) var requestAccessCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(
        state: MicrophonePermissionState,
        requestAccessResult: Bool = false,
        runtimeDiagnostics: MicrophonePermissionRuntimeDiagnostics? = nil
    ) {
        self.state = state
        self.requestAccessResult = requestAccessResult
        self.runtimeDiagnosticsValue = runtimeDiagnostics
    }

    func authorizationState() -> MicrophonePermissionState {
        state
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        state = requestAccessResult ? .authorized : .denied
        return requestAccessResult
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
        onOpenSystemSettings?()
    }

    func runtimeDiagnostics() -> MicrophonePermissionRuntimeDiagnostics? {
        runtimeDiagnosticsValue
    }
}
