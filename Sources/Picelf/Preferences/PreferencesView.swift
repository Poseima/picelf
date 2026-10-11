import AppKit
import SwiftUI
import KeyboardShortcuts

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general, shortcuts, capture, translation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.general
        case .shortcuts: return L10n.shortcuts
        case .capture: return L10n.capture
        case .translation: return L10n.translationTab
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .capture: return "viewfinder"
        case .translation: return "globe"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return L10n.localized("让 Picelf 按你的习惯运行和保存。", "Make Picelf work and save the way you prefer.")
        case .shortcuts:
            return L10n.localized("用顺手的快捷键开始捕获和接力。", "Capture and relay with shortcuts that feel familiar.")
        case .capture:
            return L10n.localized("调整捕获行为，管理保留时间与区域预设。", "Choose capture behavior, retention, and region presets.")
        case .translation:
            return L10n.localized("设置本机翻译的默认语言、呈现和导出方式。", "Choose defaults for on-device translation and export.")
        }
    }
}

@MainActor
final class PreferencesNavigationState: ObservableObject {
    @Published var selectedTab: PreferencesTab = .general
}

struct PreferencesView: View {
    @ObservedObject var navigation: PreferencesNavigationState
    @ObservedObject private var prefs = AppPreferences.shared
    @FocusState private var focusedTab: PreferencesTab?

    var body: some View {
        // Both the navigation labels and window title follow language changes.
        let _ = prefs.appLanguage
        ZStack {
            StudioBackdrop()

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(24)

                    ScrollView {
                        selectedContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                    // Recreate only the scrolling region so each category starts
                    // at the top. The header and keyboard focus stay in place.
                    .id(navigation.selectedTab)
                }
            }
        }
        .frame(minWidth: PreferencesWindowAppearance.minimumSize.width,
               idealWidth: PreferencesWindowAppearance.defaultSize.width,
               maxWidth: .infinity,
               minHeight: PreferencesWindowAppearance.minimumSize.height,
               idealHeight: PreferencesWindowAppearance.defaultSize.height,
               maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .tint(PicelfBrandColor.emeraldGlow)
        .background(PreferencesWindowAppearanceBridge().frame(width: 1, height: 1)
            .allowsHitTesting(false).accessibilityHidden(true))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(navigation.selectedTab.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(navigation.selectedTab.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("preferences.title.\(navigation.selectedTab.rawValue)")
            Text(navigation.selectedTab.subtitle)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(navigation.selectedTab.subtitle)
                .accessibilityAddTraits(.isStaticText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Picelf")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(L10n.localized("设置", "Settings"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            VStack(spacing: 6) {
                ForEach(PreferencesTab.allCases) { tab in
                    navigationButton(tab)
                }
            }

            Spacer(minLength: 0)

            Label(L10n.localized("更顺手的每一次捕获", "Capture your way"), systemImage: "sparkles")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.50))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 24)
        .frame(width: 180)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
    }

    private func navigationButton(_ tab: PreferencesTab) -> some View {
        let selected = navigation.selectedTab == tab
        return Button {
            navigation.selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(selected ? PicelfBrandColor.emeraldGlow : Color.white.opacity(0.65))
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? .white : Color.white.opacity(0.75))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? PicelfBrandColor.emerald.opacity(0.35) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(focusedTab == tab ? PicelfBrandColor.emeraldGlow : Color.white.opacity(selected ? 0.12 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedTab, equals: tab)
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            navigation.selectedTab = tab
            return .handled
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("preferences.tab.\(tab.rawValue)")
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch navigation.selectedTab {
        case .general: GeneralTab()
        case .shortcuts: ShortcutsTab()
        case .capture: CaptureTab()
        case .translation: TranslationTab()
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 16) {
            PreferencesSection(L10n.localized("应用行为", "App behavior"), symbol: "gearshape") {
                prefRow(L10n.language) {
                    Picker(L10n.language, selection: $prefs.appLanguage) {
                        Text(L10n.languageSystem).tag(AppLanguageOption.system.rawValue)
                        Text("English").tag(AppLanguageOption.en.rawValue)
                        Text("中文").tag(AppLanguageOption.zh.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityIdentifier("preferences.language")
                }
                Divider()
                prefRow(L10n.launchAtLogin) {
                    Toggle(L10n.launchAtLogin, isOn: $prefs.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("preferences.launchAtLogin")
                }
            }

            SoftwareUpdateSection()

            PreferencesSection(L10n.localized("保存与导出", "Save & export"), symbol: "square.and.arrow.down") {
                prefRow(L10n.defaultSaveLocation) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(displayPath(prefs.savePath))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help(prefs.savePath.isEmpty ? L10n.askEachTime : prefs.savePath)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityLabel(prefs.savePath.isEmpty ? L10n.askEachTime : prefs.savePath)
                            .accessibilityIdentifier("preferences.savePath")
                        Button(L10n.chooseFolder) { chooseSaveFolder() }
                            .accessibilityIdentifier("preferences.chooseFolder")
                    }
                    .frame(width: 260)
                }
                Divider()
                prefRow(L10n.defaultFormat) {
                    Picker(L10n.defaultFormat, selection: $prefs.defaultFormat) {
                        Text("PNG").tag(ImageFormat.png)
                        Text("JPEG").tag(ImageFormat.jpeg)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .accessibilityIdentifier("preferences.defaultFormat")
                }
                if prefs.defaultFormat == .jpeg {
                    Divider()
                    prefRow(L10n.jpegQuality) {
                        HStack(spacing: 10) {
                            Slider(value: $prefs.jpegQuality, in: 0.1...1.0)
                                .accessibilityLabel(L10n.jpegQuality)
                                .accessibilityIdentifier("preferences.jpegQuality")
                            Text("\(Int(prefs.jpegQuality * 100))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        .frame(width: 220)
                    }
                }
            }

            HStack {
                Image(systemName: "hand.raised")
                    .accessibilityHidden(true)
                Button(L10n.privacyPolicy) {
                    if let url = URL(string: "https://github.com/Poseima/picelf-open/blob/main/docs/privacy.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                Spacer()
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.65))
            .padding(.horizontal, 4)
        }
    }

    private func displayPath(_ path: String) -> String {
        if path.isEmpty { return L10n.askEachTime }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { prefs.savePath = url.path }
        }
    }
}

private struct SoftwareUpdateSection: View {
    @ObservedObject private var updates = UpdateController.shared
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        let _ = prefs.appLanguage
        PreferencesSection(L10n.localized("软件更新", "Software updates"), symbol: "arrow.triangle.2.circlepath") {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.localized("当前版本", "Current version"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("v\(updates.versionNumber)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                        Text(L10n.localized("构建 \(updates.buildNumber)", "Build \(updates.buildNumber)"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(updates.versionDescription)
                    .accessibilityAddTraits([.isStaticText, .isHeader])
                    .accessibilityIdentifier("preferences.updateVersion")
                }
                Spacer(minLength: 8)
                Button { updates.checkForUpdates() } label: {
                    Label(L10n.localized("检查更新", "Check for Updates"), systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fixedSize()
                .disabled(!updates.canCheckForUpdates)
                .accessibilityIdentifier("preferences.checkForUpdates")
            }
            .padding(.vertical, 12)
            Divider()
            prefRow(L10n.localized("自动检查更新", "Automatically check for updates"),
                    description: L10n.localized("每天检查一次，安装前由你确认。", "Check daily. You decide when to install.")) {
                Toggle(L10n.localized("自动检查更新", "Automatically check for updates"), isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                ))
                .labelsHidden().toggleStyle(.switch)
                .disabled(!updates.isEnabled)
                .accessibilityIdentifier("preferences.automaticUpdates")
            }
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(L10n.localized("上次检查", "Last checked"), systemImage: "clock")
                Spacer(minLength: 8)
                if let date = updates.lastUpdateCheckDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute()
                        .locale(Locale(identifier: L10n.zh ? "zh_CN" : "en_US")))
                } else {
                    Text(L10n.localized("尚未检查", "Not checked yet"))
                }
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.65))
            .padding(.vertical, 14)
            if updates.isDevelopmentBuild {
                updateNote(L10n.localized("此开发或测试构建未启用在线更新，请使用正式安装版本。",
                                          "Online updates are disabled in this development or test build. Use an official release."))
            }
            if let version = updates.availableVersion {
                updateNote(L10n.localized("新版本 \(version) 已就绪，可点击检查更新查看详情。",
                                          "Version \(version) is available. Check for updates to see the details."))
            }
            if updates.waitingToInstall {
                updateNote(updates.localizedInstallationMessage)
                Button(L10n.localized("继续更新", "Continue Update")) { updates.continueInstallation() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("preferences.continueUpdate")
            }
            if let error = updates.lastError { updateNote(error) }
            Button(L10n.localized("查看 Release 下载页面", "Open release downloads")) { updates.openReleases() }
                .buttonStyle(.link)
                .font(.system(size: 12, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .accessibilityIdentifier("preferences.updateDownloads")
        }
        .accessibilityIdentifier("preferences.softwareUpdates")
    }

    private func updateNote(_ text: String) -> some View {
        Text(text).font(.system(size: 12, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 10)
            .accessibilityIdentifier("preferences.updateNotice")
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        let _ = prefs.appLanguage
        VStack(spacing: 16) {
            PreferencesSection(L10n.shortcuts, symbol: "keyboard") {
                shortcutRow(.startCapture, title: L10n.startCapture, description: L10n.enterSelectionMode, symbol: "viewfinder")
                Divider()
                shortcutRow(.sendToIPad, title: L10n.sendToIPad, description: L10n.sendToIPadDescription, symbol: "ipad.and.arrow.forward")
            }
            HStack {
                Spacer()
                Button(L10n.resetToDefaults) {
                    KeyboardShortcuts.reset(.startCapture)
                    KeyboardShortcuts.reset(.sendToIPad)
                }
                .accessibilityIdentifier("preferences.resetShortcuts")
            }
        }
    }

    private func shortcutRow(_ name: KeyboardShortcuts.Name, title: String, description: String, symbol: String) -> some View {
        prefRow(title, description: description, symbol: symbol) {
            KeyboardShortcuts.Recorder(for: name)
                .accessibilityLabel(title)
                .accessibilityIdentifier("preferences.shortcut.\(name.rawValue)")
        }
    }
}

// MARK: - Capture

private struct CaptureTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 16) {
            PreferencesSection(L10n.localized("捕获行为", "Capture behavior"), symbol: "viewfinder") {
                prefRow(L10n.autoSnap) {
                    Toggle(L10n.autoSnap, isOn: $prefs.autoSnapToWindows)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("preferences.autoSnap")
                }
                Divider()
                prefRow(L10n.cacheFrames) {
                    Toggle(L10n.cacheFrames, isOn: $prefs.cacheFramesToDisk)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("preferences.cacheFrames")
                }
            }

            PreferencesSection(L10n.localized("保留策略", "Retention"), symbol: "clock") {
                prefRow(L10n.captureRetention, description: L10n.captureRetentionHint) {
                    VStack(alignment: .trailing, spacing: 10) {
                        Stepper(value: $prefs.captureRetentionValue,
                                in: AppPreferences.retentionBounds(for: prefs.captureRetentionUnit)) {
                            Text("\(prefs.captureRetentionValue)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                        .fixedSize()
                        .accessibilityLabel(L10n.captureRetention)
                        .accessibilityIdentifier("preferences.retentionValue")
                        Picker(L10n.captureRetention, selection: $prefs.captureRetentionUnit) {
                            Text(L10n.retentionSeconds).tag(CaptureRetentionUnit.seconds)
                            Text(L10n.retentionHours).tag(CaptureRetentionUnit.hours)
                            Text(L10n.retentionDays).tag(CaptureRetentionUnit.days)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .accessibilityIdentifier("preferences.retentionUnit")
                    }
                }
            }

            PreferencesSection(L10n.regionPresets, symbol: "rectangle.dashed") {
                if prefs.presets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 24))
                            .accessibilityHidden(true)
                        Text(L10n.noPresets)
                            .font(.system(size: 13, design: .rounded))
                    }
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(Array(prefs.presets.enumerated()), id: \.element.id) { index, preset in
                        if index > 0 { Divider() }
                        HStack(spacing: 12) {
                            Text(preset.name)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(2)
                                .help(preset.name)
                            Spacer(minLength: 12)
                            Text("\(preset.width) × \(preset.height)")
                                .font(.system(size: 12, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.65))
                            Button(role: .destructive) { prefs.removePreset(id: preset.id) } label: {
                                Image(systemName: "trash")
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .iconTip(.remove)
                            .accessibilityLabel("\(L10n.remove) \(preset.name)")
                            .accessibilityIdentifier("preferences.preset.remove.\(preset.id)")
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

// MARK: - Translation

private struct TranslationTab: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 16) {
            PreferencesSection(L10n.localized("翻译默认行为", "Translation defaults"), symbol: "globe") {
                prefRow(L10n.translationDefaultTarget) {
                    Picker(L10n.translationDefaultTarget, selection: $prefs.translationTargetPreference) {
                        ForEach(TranslationTargetPreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityIdentifier("preferences.translationTarget")
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
                    .frame(width: 260)
                    .accessibilityIdentifier("preferences.translationOverlay")
                }
                Divider()
                prefRow(L10n.translationAutoRunFromSnapEditLabel) {
                    Toggle(L10n.translationAutoRunFromSnapEditLabel, isOn: $prefs.translationAutoRunFromSnapEdit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("preferences.translationAutoRun")
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
                    .frame(width: 260)
                    .accessibilityIdentifier("preferences.translationExportFormat")
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(PicelfBrandColor.emeraldGlow)
                    .accessibilityHidden(true)
                Text(L10n.translationPrivacyNote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

// MARK: - Shared settings components

private struct PreferencesSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.65))
            VStack(spacing: 0) { content }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private func prefRow<Content: View>(_ label: String, description: String? = nil, symbol: String? = nil,
                                   @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .center, spacing: 16) {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PicelfBrandColor.emeraldGlow)
                .frame(width: 24)
                .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 5) {
            Text(label.trimmingCharacters(in: CharacterSet(charactersIn: ":：")))
                .font(.system(size: 13, weight: .medium, design: .rounded))
            if let description {
                Text(description)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        content()
    }
    .frame(minHeight: 44)
    .padding(.vertical, 6)
}
