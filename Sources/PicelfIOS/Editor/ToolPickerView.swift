// ToolPickerView.swift
// PicelfIOS — Horizontal scrolling pill toolbar for annotation tools
//
// Target: iOS 16+, Swift 5.9+

import SwiftUI

struct ToolPickerView: View {
    @Binding var selectedTool: IOSEditorTool?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: IOSTheme.spacing8) {
                ForEach(IOSEditorTool.allCases) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool,
                        action: {
                            IOSHaptics.selection()
                            withAnimation(.spring(duration: 0.2)) {
                                selectedTool = selectedTool == tool ? nil : tool
                            }
                        }
                    )
                    .accessibilityIdentifier("editor.tool.\(tool.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, IOSTheme.spacing16)
            .padding(.vertical, IOSTheme.spacing8)
        }
        .background(
            RoundedRectangle(cornerRadius: IOSTheme.radiusFloating, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IOSTheme.radiusFloating, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, IOSTheme.spacing12)
        .accessibilityIdentifier("editor.toolpicker")
    }
}

// MARK: - Tool Button

private struct ToolButton: View {
    let tool: IOSEditorTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 18, weight: .medium))
                Text(tool.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : IOSTheme.textPrimary)
            .frame(width: 52, height: 46)
            .background(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(IOSTheme.emeraldGradient) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.2) : IOSTheme.panelBorder,
                        lineWidth: isSelected ? 0.8 : 0.5
                    )
            )
        }
        .buttonStyle(ToolButtonPressStyle())
    }
}

// MARK: - Press Style

private struct ToolButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}
