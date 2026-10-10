import SwiftUI
import AppKit

enum PicelfBrandColor {
    static let emeraldDeep = Color(red: 0.00, green: 0.42, blue: 0.30)   // #006B4C
    static let emerald = Color(red: 0.00, green: 0.55, blue: 0.40)       // #008C66
    static let emeraldGlow = Color(red: 0.31, green: 0.78, blue: 0.47)   // #50C878
    static let green = emerald
    static let teal = Color(red: 0.00, green: 0.63, blue: 0.75)
    static let blue = Color(red: 0.00, green: 0.50, blue: 0.88)
}

enum EditorTheme {
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }

    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing10: CGFloat = 10
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 20

    static let toolbarHeight: CGFloat = 48
    static let statusHeight: CGFloat = 24
    static let inspectorWidth: CGFloat = 360

    static let canvasBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.985, green: 0.995, blue: 0.989, alpha: 1),
        dark: NSColor(calibratedRed: 0.078, green: 0.112, blue: 0.096, alpha: 1)
    )
    static let workspaceBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.937, green: 0.970, blue: 0.953, alpha: 1),
        dark: NSColor(calibratedRed: 0.067, green: 0.094, blue: 0.081, alpha: 1)
    )
    static let panelBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.954, green: 0.982, blue: 0.969, alpha: 1),
        dark: NSColor(calibratedRed: 0.108, green: 0.145, blue: 0.126, alpha: 1)
    )
    static let cardBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.982, green: 0.993, blue: 0.987, alpha: 1),
        dark: NSColor(calibratedRed: 0.138, green: 0.176, blue: 0.155, alpha: 1)
    )
    static let toolbarGroupBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.980, green: 0.992, blue: 0.986, alpha: 0.96),
        dark: NSColor(calibratedRed: 0.118, green: 0.154, blue: 0.135, alpha: 0.90)
    )
    static let panelBorder = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.30, alpha: 0.17),
        dark: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.47, alpha: 0.22)
    )
    static let separator = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.30, alpha: 0.11),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    static let primaryText = dynamicColor(
        light: NSColor(calibratedRed: 0.145, green: 0.176, blue: 0.204, alpha: 1),
        dark: NSColor(calibratedRed: 0.953, green: 0.961, blue: 0.969, alpha: 1)
    )
    static let secondaryText = dynamicColor(
        light: NSColor(calibratedRed: 0.333, green: 0.380, blue: 0.427, alpha: 1),
        dark: NSColor(calibratedRed: 0.722, green: 0.753, blue: 0.780, alpha: 1)
    )
    static let tertiaryText = dynamicColor(
        light: NSColor(calibratedRed: 0.494, green: 0.529, blue: 0.565, alpha: 1),
        dark: NSColor(calibratedRed: 0.494, green: 0.529, blue: 0.565, alpha: 1)
    )
    static let textOnAccent = dynamicColor(
        light: NSColor.white,
        dark: NSColor(calibratedRed: 0.925, green: 1.0, blue: 0.969, alpha: 1)
    )
    static let accent = PicelfBrandColor.emerald
    static let accentStrong = PicelfBrandColor.emeraldDeep
    static let accentGlow = PicelfBrandColor.emeraldGlow
    static let defaultAnnotationStroke = PicelfBrandColor.emerald
    static let defaultAnnotationFill = Color.clear
    static let editorStageBackground = Color.white
    static let editorStageBorder = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.30, alpha: 0.12),
        dark: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.47, alpha: 0.24)
    )
    static let workspaceSurface = dynamicColor(
        light: NSColor(calibratedRed: 0.938, green: 0.969, blue: 0.953, alpha: 0.78),
        dark: NSColor(calibratedRed: 0.067, green: 0.094, blue: 0.081, alpha: 0.72)
    )
    static let subtleAccentFill = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.55, blue: 0.40, alpha: 0.07),
        dark: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.47, alpha: 0.10)
    )
    static let selectedFill = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.55, blue: 0.40, alpha: 0.16),
        dark: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.47, alpha: 0.20)
    )
    static let selectedStroke = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.30, alpha: 0.68),
        dark: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.47, alpha: 0.78)
    )
    static let selectionStroke = dynamicColor(
        light: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.30, alpha: 0.92),
        dark: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.47, alpha: 0.96)
    )
    static let handleFill = dynamicColor(
        light: NSColor.white,
        dark: NSColor(calibratedRed: 0.145, green: 0.185, blue: 0.163, alpha: 1)
    )
    static let fieldBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.960, green: 0.982, blue: 0.972, alpha: 1),
        dark: NSColor(calibratedRed: 0.128, green: 0.165, blue: 0.145, alpha: 1)
    )
}

struct PicelfGlassBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBlurView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active
            )

            LinearGradient(
                colors: [
                    PicelfBrandColor.emeraldDeep.opacity(0.34),
                    PicelfBrandColor.emerald.opacity(0.26),
                    PicelfBrandColor.emeraldDeep.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    PicelfBrandColor.emeraldGlow.opacity(0.14),
                    .clear
                ],
                center: .topLeading,
                startRadius: 60,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color.black.opacity(0.25),
                    .clear
                ],
                center: .bottom,
                startRadius: 100,
                endRadius: 860
            )
        }
        .ignoresSafeArea()
    }
}

struct EditorToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? EditorTheme.primaryText : EditorTheme.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                    .fill(
                        (configuration.isPressed ? EditorTheme.selectedFill : EditorTheme.cardBackground.opacity(0.94))
                            .opacity(isEnabled ? 1.0 : 0.78)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                            .stroke(configuration.isPressed ? EditorTheme.selectedStroke : EditorTheme.panelBorder, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? 1.0 : 0.64)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct EditorSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? EditorTheme.primaryText : EditorTheme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                    .fill(
                        (configuration.isPressed ? EditorTheme.selectedFill : EditorTheme.fieldBackground)
                            .opacity(isEnabled ? 1.0 : 0.76)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                            .stroke(configuration.isPressed ? EditorTheme.selectedStroke : EditorTheme.panelBorder, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? 1.0 : 0.64)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct EditorPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(EditorTheme.textOnAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                EditorTheme.accent.opacity(configuration.isPressed ? 0.88 : 1.0),
                                EditorTheme.accentStrong.opacity(configuration.isPressed ? 0.88 : 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
            )
            .opacity(isEnabled ? 1.0 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
