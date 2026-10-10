import SwiftUI

struct StitchPreviewView: View {
    @ObservedObject var captureState: CaptureState
    @Environment(\.colorScheme) private var colorScheme

    private let panelWidth: CGFloat = 200
    private let maxImageHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            if let image = captureState.previewImage {
                previewImage(image)
            } else {
                placeholder
            }

            statusBar
        }
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(surfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .compositingGroup()
    }

    private func previewImage(_ image: NSImage) -> some View {
        let aspectRatio = image.size.width > 0
            ? image.size.height / image.size.width
            : 1.0
        let imageWidth = panelWidth - 16
        let imageHeight = min(maxImageHeight, imageWidth * aspectRatio)

        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageWidth, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.scroll)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: panelWidth - 16, height: 120)
        .padding(8)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("\(captureState.frameCount) \(L10n.frames.lowercased())")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var surfaceColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.78)
            : Color.white.opacity(0.94)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.08)
    }
}
