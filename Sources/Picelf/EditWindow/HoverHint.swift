import SwiftUI

extension View {
    func hoverHint(_ text: String) -> some View {
        modifier(HoverHintModifier(text: text))
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String

    @State private var isHovering = false
    @State private var isVisible = false
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                showTask?.cancel()

                if hovering {
                    showTask = Task {
                        try? await Task.sleep(nanoseconds: 320_000_000)
                        guard !Task.isCancelled, isHovering else { return }
                        await MainActor.run { isVisible = true }
                    }
                } else {
                    isVisible = false
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isVisible, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.88))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .fixedSize()
                        .offset(y: 30)
                        .zIndex(20)
                        .allowsHitTesting(false)
                }
            }
            .onDisappear {
                showTask?.cancel()
                showTask = nil
                isVisible = false
            }
    }
}
