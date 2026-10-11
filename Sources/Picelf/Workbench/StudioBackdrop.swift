import SwiftUI

/// Shared emerald glass surface for the workbench and preferences.
struct StudioBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBlurView(material: .hudWindow, blendingMode: .behindWindow, state: .active)

            LinearGradient(
                colors: [
                    PicelfBrandColor.emeraldDeep.opacity(0.35),
                    PicelfBrandColor.emerald.opacity(0.28),
                    PicelfBrandColor.emeraldDeep.opacity(0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [PicelfBrandColor.emeraldGlow.opacity(0.15), .clear],
                center: .topLeading,
                startRadius: 60,
                endRadius: 600
            )

            RadialGradient(
                colors: [Color.black.opacity(0.25), .clear],
                center: .bottom,
                startRadius: 100,
                endRadius: 800
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
