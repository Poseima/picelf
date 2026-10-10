import SwiftUI

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onSave: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void

    @State private var selectedFormat: ExportFormat = .png
    @State private var jpegQuality: Double = 90

    enum ExportFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case jpeg = "JPEG"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title
                Text(L10n.localized("导出长截图", "Export Scrolling Screenshot"))
                    .font(IOSTheme.title())
                    .foregroundStyle(IOSTheme.textPrimary)
                    .padding(.top, IOSTheme.spacing8)

                // Image dimensions info
                Text("\(Int(image.size.width)) x \(Int(image.size.height))")
                    .font(IOSTheme.caption())
                    .foregroundStyle(IOSTheme.textSecondary)

                // Format picker
                VStack(alignment: .leading, spacing: IOSTheme.spacing8) {
                    Text(L10n.localized("格式", "Format"))
                        .font(IOSTheme.caption())
                        .foregroundStyle(IOSTheme.textSecondary)

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("export.format.picker")
                }
                .padding(.horizontal, IOSTheme.spacing16)

                // Quality slider (JPEG only)
                if selectedFormat == .jpeg {
                    VStack(alignment: .leading, spacing: IOSTheme.spacing8) {
                        HStack {
                            Text(L10n.quality)
                                .font(IOSTheme.caption())
                                .foregroundStyle(IOSTheme.textSecondary)
                            Spacer()
                            Text("\(Int(jpegQuality))%")
                                .font(IOSTheme.caption())
                                .foregroundStyle(IOSTheme.accent)
                        }

                        Slider(value: $jpegQuality, in: 10...100, step: 5)
                            .tint(IOSTheme.accent)
                            .accessibilityIdentifier("export.quality.slider")
                    }
                    .padding(.horizontal, IOSTheme.spacing16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Action buttons
                HStack(spacing: IOSTheme.spacing12) {
                    ExportActionButton(
                        title: L10n.localized("保存相册", "Save to Photos"),
                        icon: "square.and.arrow.down",
                        style: .primary
                    ) {
                        IOSHaptics.medium()
                        onSave()
                        dismiss()
                    }
                    .accessibilityIdentifier("export.save.button")

                    ExportActionButton(
                        title: L10n.copy,
                        icon: "doc.on.doc",
                        style: .secondary
                    ) {
                        IOSHaptics.light()
                        onCopy()
                        dismiss()
                    }
                    .accessibilityIdentifier("export.copy.button")

                    ExportActionButton(
                        title: L10n.share,
                        icon: "square.and.arrow.up",
                        style: .secondary
                    ) {
                        IOSHaptics.light()
                        onShare()
                        dismiss()
                    }
                    .accessibilityIdentifier("export.share.button")
                }
                .padding(.horizontal, IOSTheme.spacing16)
                .padding(.bottom, 24)
            }
            .background(IOSTheme.canvasBG.ignoresSafeArea())
            .animation(.spring(duration: 0.2), value: selectedFormat)
        }
    }
}

// MARK: - Export Action Button

private struct ExportActionButton: View {
    let title: String
    let icon: String
    let style: ButtonVariant
    let action: () -> Void

    enum ButtonVariant {
        case primary, secondary
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: IOSTheme.spacing6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                Text(title)
                    .font(IOSTheme.caption(12))
            }
            .foregroundStyle(style == .primary ? .white : IOSTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .fill(
                        style == .primary
                            ? AnyShapeStyle(IOSTheme.emeraldGradient)
                            : AnyShapeStyle(IOSTheme.cardBG)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .stroke(
                        style == .primary ? Color.white.opacity(0.18) : IOSTheme.panelBorder,
                        lineWidth: style == .primary ? 0.8 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
