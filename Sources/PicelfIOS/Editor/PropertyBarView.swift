// PropertyBarView.swift
// PicelfIOS — Color picker, line width, and font size controls
//
// Target: iOS 16+, Swift 5.9+

import SwiftUI

struct PropertyBarView: View {
    @ObservedObject var document: IOSEditorDocument

    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green,
        IOSTheme.accent, // emerald
        .blue, .purple, .black
    ]

    var body: some View {
        VStack(spacing: IOSTheme.spacing8) {
            // Color row
            HStack(spacing: IOSTheme.spacing6) {
                ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                    ColorDot(
                        color: color,
                        isSelected: colorsApproximatelyEqual(document.strokeColor, color),
                        action: {
                            IOSHaptics.light()
                            document.updateSelectedStrokeColor(color)
                        }
                    )
                }

                // Custom color picker
                ColorPicker("", selection: Binding(
                    get: { document.strokeColor },
                    set: { document.updateSelectedStrokeColor($0) }
                ))
                .labelsHidden()
                .frame(width: 28, height: 28)
                .accessibilityIdentifier("editor.property.colorpicker")
            }

            // Line width slider
            HStack(spacing: IOSTheme.spacing8) {
                Image(systemName: "lineweight")
                    .font(.system(size: 12))
                    .foregroundStyle(IOSTheme.textSecondary)

                Slider(
                    value: Binding(
                        get: { document.lineWidth },
                        set: { document.updateSelectedLineWidth($0) }
                    ),
                    in: 1...24,
                    step: 1
                )
                .tint(IOSTheme.accent)
                .accessibilityIdentifier("editor.property.linewidth")

                Text("\(Int(document.lineWidth))")
                    .font(IOSTheme.caption(11))
                    .foregroundStyle(IOSTheme.textSecondary)
                    .frame(width: 24, alignment: .trailing)
            }

            // Font size slider (only when text tool selected)
            if document.selectedTool == .text {
                HStack(spacing: IOSTheme.spacing8) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12))
                        .foregroundStyle(IOSTheme.textSecondary)

                    Slider(
                        value: Binding(
                            get: { document.fontSize },
                            set: { document.updateSelectedFontSize($0) }
                        ),
                        in: 12...64,
                        step: 1
                    )
                    .tint(IOSTheme.accent)
                    .accessibilityIdentifier("editor.property.fontsize")

                    Text("\(Int(document.fontSize))")
                        .font(IOSTheme.caption(11))
                        .foregroundStyle(IOSTheme.textSecondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, IOSTheme.spacing16)
        .padding(.vertical, IOSTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, IOSTheme.spacing12)
        .animation(.spring(duration: 0.2), value: document.selectedTool)
        .accessibilityIdentifier("editor.propertybar")
    }

    // MARK: - Color comparison

    private func colorsApproximatelyEqual(_ a: Color, _ b: Color) -> Bool {
        let aComponents = UIColor(a).cgColor.components ?? [0, 0, 0, 0]
        let bComponents = UIColor(b).cgColor.components ?? [0, 0, 0, 0]
        let tolerance: CGFloat = 0.05
        guard aComponents.count >= 3, bComponents.count >= 3 else { return false }
        return abs(aComponents[0] - bComponents[0]) < tolerance
            && abs(aComponents[1] - bComponents[1]) < tolerance
            && abs(aComponents[2] - bComponents[2]) < tolerance
    }
}

// MARK: - Color Dot

private struct ColorDot: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.white : Color.clear,
                            lineWidth: 2.5
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? color.opacity(0.6) : Color.clear,
                            lineWidth: 1
                        )
                        .padding(3.5)
                )
        }
        .buttonStyle(ToolButtonPressStyle())
    }
}

private struct ToolButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}
