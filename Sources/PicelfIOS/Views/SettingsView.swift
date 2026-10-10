import SwiftUI

struct SettingsView: View {
    @ObservedObject private var preferences = AppPreferences.shared


    // Intermediate binding for frame rate picker since AppPreferences
    // does not have a direct iOS-specific sampleFPS property.
    @AppStorage("ios_sampleFPS") private var sampleFPS: Double = 5.0

    var body: some View {
        NavigationStack {
            Form {
                // Export section
                Section {
                    Picker(L10n.localized("格式", "Format"), selection: $preferences.defaultFormat) {
                        ForEach(ImageFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    .accessibilityIdentifier("settings.format.picker")

                    if preferences.defaultFormat == .jpeg {
                        HStack {
                            Text(L10n.localized("JPEG 质量", "JPEG Quality"))
                            Spacer()
                            Text("\(Int(preferences.jpegQuality * 100))%")
                                .foregroundStyle(IOSTheme.accent)
                        }
                        Slider(value: $preferences.jpegQuality, in: 0.1...1.0, step: 0.05)
                            .tint(IOSTheme.accent)
                            .accessibilityIdentifier("settings.quality.slider")
                    }

                    Picker(L10n.localized("视频提帧速率", "Video Frame Rate"), selection: $sampleFPS) {
                        Text("5 fps").tag(5.0)
                        Text("10 fps").tag(10.0)
                        Text("15 fps").tag(15.0)
                    }
                    .accessibilityIdentifier("settings.framerate.picker")
                } header: {
                    Text(L10n.export)
                } footer: {
                    Text(L10n.localized("仅作用于导入视频时的提帧，不影响控制中心广播录屏。", "Applies only when importing video; Control Center recordings are not affected."))
                }

                // General section
                Section {
                    Picker(L10n.localized("语言", "Language"), selection: $preferences.appLanguage) {
                        Text(L10n.languageSystem).tag("system")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .accessibilityIdentifier("settings.language.picker")
                } header: {
                    Text(L10n.general)
                }

                // About section
                Section {
                    Link(destination: URL(string: "https://github.com/Poseima/picelf-open/blob/main/docs/privacy.md")!) {
                        HStack {
                            Text(L10n.privacyPolicy)
                                .foregroundStyle(IOSTheme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                                .foregroundStyle(IOSTheme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("settings.privacy.link")

                    HStack {
                        Text(L10n.localized("版本", "Version"))
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(IOSTheme.textSecondary)
                    }
                    .accessibilityIdentifier("settings.version.label")
                } header: {
                    Text(L10n.localized("关于", "About"))
                }
            }
            .navigationTitle(L10n.localized("设置", "Settings"))
            .tint(IOSTheme.accent)
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
