import SwiftUI
import UIKit

// MARK: - Brand Colors (shared with macOS)

enum IOSBrandColor {
    static let emeraldDeep = Color(red: 0.00, green: 0.42, blue: 0.30)   // #006B4C
    static let emerald = Color(red: 0.00, green: 0.55, blue: 0.40)       // #008C66
    static let emeraldGlow = Color(red: 0.31, green: 0.78, blue: 0.47)   // #50C878
}

// MARK: - iOS Theme

enum IOSTheme {
    // MARK: Spacing
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing10: CGFloat = 10
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16

    // MARK: Corner Radius
    static let radiusCard: CGFloat = 12
    static let radiusSheet: CGFloat = 16
    static let radiusFloating: CGFloat = 24

    // MARK: Typography
    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    // MARK: Semantic Colors

    static let accent = IOSBrandColor.emerald
    static let accentDeep = IOSBrandColor.emeraldDeep
    static let accentGlow = IOSBrandColor.emeraldGlow

    static let canvasBackground = Color("CanvasBG", bundle: nil)
    static let panelBackground = Color("PanelBG", bundle: nil)
    static let cardBackground = Color("CardBG", bundle: nil)
    static let primaryText = Color("PrimaryText", bundle: nil)
    static let secondaryText = Color("SecondaryText", bundle: nil)
    static let textOnAccent = Color.white

    // Fallback initializers for when asset catalog colors aren't set up yet
    static let canvasBG = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.078, green: 0.112, blue: 0.096, alpha: 1)
            : UIColor(red: 0.985, green: 0.995, blue: 0.989, alpha: 1)
    })
    static let panelBG = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.108, green: 0.145, blue: 0.126, alpha: 1)
            : UIColor(red: 0.954, green: 0.982, blue: 0.969, alpha: 1)
    })
    static let cardBG = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.138, green: 0.176, blue: 0.155, alpha: 1)
            : UIColor(red: 0.982, green: 0.993, blue: 0.987, alpha: 1)
    })
    static let textPrimary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.953, green: 0.961, blue: 0.969, alpha: 1)
            : UIColor(red: 0.145, green: 0.176, blue: 0.204, alpha: 1)
    })
    static let textSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.722, green: 0.753, blue: 0.780, alpha: 1)
            : UIColor(red: 0.333, green: 0.380, blue: 0.427, alpha: 1)
    })
    static let separator = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.08)
            : UIColor(red: 0.00, green: 0.42, blue: 0.30, alpha: 0.11)
    })
    static let panelBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.31, green: 0.78, blue: 0.47, alpha: 0.22)
            : UIColor(red: 0.00, green: 0.42, blue: 0.30, alpha: 0.17)
    })

    // MARK: Gradients

    static let emeraldGradient = LinearGradient(
        colors: [IOSBrandColor.emerald, IOSBrandColor.emeraldDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let emeraldGlowGradient = LinearGradient(
        colors: [IOSBrandColor.emeraldGlow, IOSBrandColor.emerald],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Shadows

    static func cardShadow() -> some ViewModifier {
        CardShadowModifier()
    }
}

// MARK: - Shadow Modifier

private struct CardShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Button Styles

struct IOSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .fill(IOSTheme.emeraldGradient)
                    .opacity(configuration.isPressed ? 0.85 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct IOSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(IOSTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .stroke(IOSTheme.panelBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct IOSTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(IOSTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Haptics

enum IOSHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
