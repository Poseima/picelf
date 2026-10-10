import SwiftUI

/// Shared relay chrome; image pixels and PencilKit rendering remain independent.
enum RelayPalette {
    static let emerald = Color(red: 0, green: 0.55, blue: 0.40)
    static let deep = Color(red: 0, green: 0.42, blue: 0.30)
    static let glow = Color(red: 0.31, green: 0.78, blue: 0.47)
    static func accent(in scheme: ColorScheme) -> Color { scheme == .dark ? glow : deep }
}

struct RelayGlassBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            #if os(macOS)
            if reduceTransparency { Color(red: 0.055, green: 0.15, blue: 0.115) }
            else { PicelfGlassBackdrop() }
            #else
            (scheme == .dark ? Color(red: 0.045, green: 0.095, blue: 0.075) : Color(red: 0.92, green: 0.97, blue: 0.945))
            LinearGradient(colors: [RelayPalette.emerald.opacity(0.20), .clear, RelayPalette.deep.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [RelayPalette.glow.opacity(scheme == .dark ? 0.18 : 0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 650)
            #endif
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct RelayGlassSurface: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if reduceTransparency {
                shape.fill(scheme == .dark ? Color(red: 0.10, green: 0.18, blue: 0.145) : Color(red: 0.96, green: 0.99, blue: 0.97))
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(scheme == .dark ? 0.035 : 0.18)))
            }
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.24 : 0.85), RelayPalette.emerald.opacity(0.16)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.09 : 0.035), radius: 16, y: 6)
    }
}

extension View {
    func relayGlassSurface(radius: CGFloat = 20) -> some View { modifier(RelayGlassSurface(radius: radius)) }
}

struct RelayActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : RelayPalette.accent(in: scheme))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [RelayPalette.emerald, RelayPalette.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.24), lineWidth: 1))
                } else { Color.clear.relayGlassSurface(radius: 12) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
