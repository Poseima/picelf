import SwiftUI
import AVFoundation

private enum MicrophoneInlineFeedback: Equatable {
    case none
    case permissionDenied
    case invalidRuntimeEnvironment(message: String)
}

struct RecordingConfigView: View {
    @ObservedObject var prefs: AppPreferences
    let microphonePermissionCoordinator: RecordingMicrophonePermissionCoordinator
    let onMicrophonePermissionRequestWillBegin: () -> Void
    let onMicrophonePermissionRequestCompleted: () -> Void
    let onOpenSystemSettings: () -> Void
    let onStart: () -> Void
    let onCancel: () -> Void

    @State private var availableMics: [(id: String, name: String)] = []
    @State private var captureMicrophone = false
    @State private var isRequestingMicrophoneAccess = false
    @State private var microphoneInlineFeedback: MicrophoneInlineFeedback = .none

    var body: some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing10) {
            Text(L10n.recordingConfig)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .padding(.bottom, 2)

            // MARK: - Video

            section(L10n.videoSection) {
                formRow(L10n.format) {
                    Picker("", selection: $prefs.recordingFormat) {
                        ForEach(RecordingFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue.uppercased()).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow(L10n.resolution) {
                    Picker("", selection: $prefs.recordingResolution) {
                        Text("720p").tag(RecordingResolution.hd)
                        Text("1080p").tag(RecordingResolution.fhd)
                        Text("Original").tag(RecordingResolution.original)
                    }
                    .pickerStyle(.segmented)
                }

                formRow(L10n.frameRate) {
                    Picker("", selection: $prefs.recordingFrameRate) {
                        Text("15").tag(15)
                        Text("24").tag(24)
                        Text("30").tag(30)
                        Text("60").tag(60)
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(L10n.showCursor, isOn: $prefs.recordingShowsCursor)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .controlSize(.small)
            }

            // MARK: - Audio

            section(L10n.audioSection) {
                Toggle(L10n.systemAudio, isOn: $prefs.recordingCaptureSystemAudio)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .controlSize(.small)

                Toggle(
                    L10n.microphone,
                    isOn: Binding(
                        get: { captureMicrophone },
                        set: { enabled in
                            Task {
                                await updateMicrophoneCapture(enabled: enabled)
                            }
                        }
                    )
                )
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .controlSize(.small)
                    .disabled(isRequestingMicrophoneAccess)

                if microphoneInlineFeedback != .none {
                    microphoneFeedbackView
                }

                if prefs.recordingCaptureMicrophone && !availableMics.isEmpty {
                    Picker(L10n.microphone, selection: $prefs.recordingMicrophoneDeviceID) {
                        ForEach(availableMics, id: \.id) { mic in
                            Text(mic.name).tag(mic.id)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 11, design: .rounded))
                    .pickerStyle(.menu)
                    .padding(.leading, 20)
                }
            }

            // MARK: - Timing

            section(L10n.timingSection) {
                formRow(L10n.countdown) {
                    Picker("", selection: $prefs.recordingCountdown) {
                        Text(L10n.noCountdown).tag(0)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                    }
                    .pickerStyle(.segmented)
                }

                formRow(L10n.durationLimit) {
                    Picker("", selection: $prefs.recordingDurationLimit) {
                        Text(L10n.unlimited).tag(0)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("5m").tag(300)
                        Text("10m").tag(600)
                    }
                    .pickerStyle(.menu)
                }
            }

            // MARK: - Actions

            HStack {
                Button(L10n.cancel) { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Spacer()
                Button(L10n.startRecording) { onStart() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                    .disabled(isRequestingMicrophoneAccess)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.top, EditorTheme.spacing4)
        }
        .padding(20)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .tint(EditorTheme.accent)
        .onAppear {
            microphonePermissionCoordinator.sanitizePreferences(prefs)
            refreshMics()
            captureMicrophone = prefs.recordingCaptureMicrophone
            microphoneInlineFeedback = .none
        }
        .onChange(of: prefs.recordingCaptureMicrophone) { _, enabled in
            captureMicrophone = enabled
            if enabled {
                microphoneInlineFeedback = .none
            }
        }
    }

    // MARK: - Section Card

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium, style: .continuous)
                .fill(EditorTheme.cardBackground.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium, style: .continuous)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }

    // MARK: - Form Row

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: EditorTheme.spacing8) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private var microphoneFeedbackView: some View {
        switch microphoneInlineFeedback {
        case .none:
            EmptyView()
        case .permissionDenied:
            microphoneFeedbackCard(
                title: L10n.microphonePermissionRequired,
                message: L10n.microphonePermissionInlineBody,
                showsOpenSettingsButton: true
            )
        case .invalidRuntimeEnvironment(let message):
            microphoneFeedbackCard(
                title: L10n.microphonePermissionTestingRequiresSignedBuild,
                message: message,
                showsOpenSettingsButton: false
            )
        }
    }

    private func microphoneFeedbackCard(
        title: String,
        message: String,
        showsOpenSettingsButton: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
            HStack(alignment: .top, spacing: EditorTheme.spacing8) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(message)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsOpenSettingsButton {
                Button(L10n.exitAndOpenSystemSettings) {
                    onOpenSystemSettings()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.leading, 20)
            }
        }
        .padding(EditorTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .padding(.leading, 20)
    }

    // MARK: - Mic Discovery

    private func refreshMics() {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
        availableMics = devices.map { (id: $0.uniqueID, name: $0.localizedName) }
        if prefs.recordingMicrophoneDeviceID.isEmpty, let first = availableMics.first {
            prefs.recordingMicrophoneDeviceID = first.id
        }
    }

    @MainActor
    private func updateMicrophoneCapture(enabled: Bool) async {
        guard !isRequestingMicrophoneAccess else { return }

        if !enabled {
            prefs.recordingCaptureMicrophone = false
            captureMicrophone = false
            microphoneInlineFeedback = .none
            return
        }

        microphoneInlineFeedback = .none
        isRequestingMicrophoneAccess = true
        defer {
            isRequestingMicrophoneAccess = false
            captureMicrophone = prefs.recordingCaptureMicrophone
        }

        let willRequestAccess = microphonePermissionCoordinator.authorizationState() == .notDetermined
        if willRequestAccess {
            onMicrophonePermissionRequestWillBegin()
        }
        let result = await microphonePermissionCoordinator.enableMicrophone(in: prefs)
        if willRequestAccess {
            onMicrophonePermissionRequestCompleted()
        }

        switch result {
        case .enabled:
            microphoneInlineFeedback = .none
            refreshMics()
        case .denied:
            microphoneInlineFeedback = .permissionDenied
        case .invalidRuntimeEnvironment(let message):
            microphoneInlineFeedback = .invalidRuntimeEnvironment(message: message)
        }
    }
}
