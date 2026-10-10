import SwiftUI
import KeyboardShortcuts

enum PreferencesTab: Hashable {
    case general
    case shortcuts
    case capture
    case translation

    var contentSize: CGSize {
        let height: CGFloat
        switch self {
        case .general: height = 335
        case .shortcuts: height = 315
        case .capture: height = 410
        case .translation: height = 350
        }
        return CGSize(width: 760, height: height)
    }
}

@MainActor
final class PreferencesNavigationState: ObservableObject {
    @Published var selectedTab: PreferencesTab = .general
}

struct PreferencesView: View {
    @ObservedObject var navigation: PreferencesNavigationState
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        // Read the language here so the tab titles refresh immediately after a switch.
        let _ = prefs.appLanguage
        TabView(selection: $navigation.selectedTab) {
            GeneralTab()
                .tabItem { Label(L10n.general, systemImage: "gear") }
                .tag(PreferencesTab.general)

            ShortcutsTab()
                .tabItem { Label(L10n.shortcuts, systemImage: "keyboard") }
                .tag(PreferencesTab.shortcuts)

            CaptureTab()
                .tabItem { Label(L10n.capture, systemImage: "viewfinder") }
                .tag(PreferencesTab.capture)

            TranslationTab()
                .tabItem { Label(L10n.translationTab, systemImage: "globe") }
                .tag(PreferencesTab.translation)
        }
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 16) {
            prefSection {
                prefRow(L10n.language) {
                    Picker(L10n.language, selection: $prefs.appLanguage) {
                        Text(L10n.languageSystem).tag(AppLanguageOption.system.rawValue)
                        Text("English").tag(AppLanguageOption.en.rawValue)
                        Text("中文").tag(AppLanguageOption.zh.rawValue)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("preferences.language")
                }

                Divider()

                prefRow(L10n.launchAtLogin) {
                    Toggle(L10n.launchAtLogin, isOn: $prefs.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            prefSection {
                prefRow(L10n.defaultSaveLocation) {
                    HStack(spacing: 8) {
                        Text(displayPath(prefs.savePath))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(prefs.savePath.isEmpty ? L10n.askEachTime : prefs.savePath)

                        Button(L10n.chooseFolder) { chooseSaveFolder() }
                            .controlSize(.small)
                    }
                }

                Divider()

                prefRow(L10n.defaultFormat) {
                    Picker(L10n.defaultFormat, selection: $prefs.defaultFormat) {
                        Text("PNG").tag(ImageFormat.png)
                        Text("JPEG").tag(ImageFormat.jpeg)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if prefs.defaultFormat == .jpeg {
                    Divider()

                    prefRow(L10n.jpegQuality) {
                        HStack(spacing: 8) {
                            Slider(value: $prefs.jpegQuality, in: 0.1...1.0)
                                .frame(width: 120)
                            Text("\(Int(prefs.jpegQuality * 100))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com/Poseima/picelf-open/blob/main/docs/privacy.md") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(L10n.privacyPolicy)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func displayPath(_ path: String) -> String {
        if path.isEmpty { return L10n.askEachTime }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                prefs.savePath = url.path
            }
        }
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsTab: View {
    @ObservedObject private var prefs = AppPreferences.shared
    private struct ShortcutEntry {
        let name: KeyboardShortcuts.Name
        let title: String
        let description: String
        let symbol: String
    }

    private var entries: [ShortcutEntry] {
        [
            ShortcutEntry(
                name: .startCapture,
                title: L10n.startCapture,
                description: L10n.enterSelectionMode,
                symbol: "viewfinder"
            ),
            ShortcutEntry(
                name: .sendToIPad,
                title: L10n.sendToIPad,
                description: L10n.sendToIPadDescription,
                symbol: "ipad.and.arrow.forward"
            )
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ForEach(entries, id: \.title) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(entry.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        KeyboardShortcuts.Recorder(for: entry.name)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }

            HStack {
                Spacer()
                Button(L10n.resetToDefaults) {
                    for entry in entries {
                        KeyboardShortcuts.reset(entry.name)
                    }
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

// MARK: - Capture Tab

private struct CaptureTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 16) {
            prefSection {
                prefRow(L10n.autoSnap) {
                    Toggle(L10n.autoSnap, isOn: $prefs.autoSnapToWindows)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                prefRow(L10n.cacheFrames) {
                    Toggle(L10n.cacheFrames, isOn: $prefs.cacheFramesToDisk)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                prefRow(L10n.captureRetention) {
                    HStack(spacing: 8) {
                        Stepper(
                            value: $prefs.captureRetentionValue,
                            in: AppPreferences.retentionBounds(for: prefs.captureRetentionUnit)
                        ) {
                            Text("\(prefs.captureRetentionValue)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                        .fixedSize()

                        Picker(L10n.captureRetention, selection: $prefs.captureRetentionUnit) {
                            Text(L10n.retentionSeconds).tag(CaptureRetentionUnit.seconds)
                            Text(L10n.retentionHours).tag(CaptureRetentionUnit.hours)
                            Text(L10n.retentionDays).tag(CaptureRetentionUnit.days)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
            }

            Text(L10n.captureRetentionHint)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.regionPresets)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if prefs.presets.isEmpty {
                    HStack {
                        Spacer()
                        Text(L10n.noPresets)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(prefs.presets.enumerated()), id: \.element.id) { index, preset in
                            if index > 0 { Divider() }
                            HStack {
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("\(preset.width) \u{00D7} \(preset.height)")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    prefs.removePreset(id: preset.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .iconTip(.remove)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

// MARK: - Translation Tab

private struct TranslationTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 16) {
            prefSection {
                prefRow(L10n.translationDefaultTarget) {
                    Picker(L10n.translationDefaultTarget, selection: $prefs.translationTargetPreference) {
                        ForEach(TranslationTargetPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: prefControlWidth, alignment: .leading)
                }

                Divider()

                prefRow(L10n.translationDefaultOverlay) {
                    Picker(L10n.translationDefaultOverlay, selection: $prefs.translationOverlayMode) {
                        ForEach(TranslationOverlayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .frame(width: prefControlWidth, alignment: .leading)
                }

                Divider()

                prefRow(L10n.translationAutoRunFromSnapEditLabel) {
                    Toggle(L10n.translationAutoRunFromSnapEditLabel, isOn: $prefs.translationAutoRunFromSnapEdit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                prefRow(L10n.translationExportFormat) {
                    Picker(L10n.translationExportFormat, selection: $prefs.translationExportFormatPreference) {
                        ForEach(TranslationExportFormatPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .frame(width: prefControlWidth, alignment: .leading)
                }
            }

            Text(L10n.translationPrivacyNote)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

// MARK: - Shared Components

private let prefLabelWidth: CGFloat = 168
private let prefControlWidth: CGFloat = 200

private func prefSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        content()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
    )
}

private func prefRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .center, spacing: 12) {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .frame(width: prefLabelWidth, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        content()
        Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
}
