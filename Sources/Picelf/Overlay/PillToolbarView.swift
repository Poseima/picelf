import SwiftUI
import os

private let log = Logger(subsystem: "com.picelf", category: "UserAction")

struct PillToolbarView: View {
    @ObservedObject var captureState: CaptureState
    @Environment(\.colorScheme) private var colorScheme
    let onCapture: () -> Void
    let onRecord: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void
    var onSnapConfirm: (() -> Void)?
    var onSnapCancel: (() -> Void)?
    var onPin: (() -> Void)?
    var onRelay: (() -> Void)? = nil
    var onOCR: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onExtractSubject: (() -> Void)?
    var onSnapEditToolChanged: ((EditorTool?) -> Void)? = nil
    var snapEditDocument: EditorDocument?

    var body: some View {
        HStack(spacing: 10) {
            if captureState.isSnapEditing, let doc = snapEditDocument {
                SnapEditToolbarContent(
                    document: doc,
                    onToolChanged: { tool in onSnapEditToolChanged?(tool) },
                    onConfirm: { onSnapConfirm?() },
                    onCancel: { onSnapCancel?() },
                    onScroll: { onCapture() },
                    onRecord: { onRecord() },
                    onPin: { onPin?() },
                    onRelay: { onRelay?() },
                    onOCR: { onOCR?() },
                    onTranslate: { onTranslate?() },
                    onExtractSubject: { onExtractSubject?() }
                )
            } else if captureState.isCapturing {
                recordingContent
            } else {
                stitchingContent
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(toolbarSurfaceColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(toolbarBorderColor, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
        .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
        .compositingGroup()
        .onAppear {
            log.info("[UI] PillToolbarView appeared mode=\(String(describing: self.captureState.mode))")
        }
    }

    private var toolbarSurfaceColor: Color {
        EditorTheme.toolbarGroupBackground.opacity(colorScheme == .dark ? 0.94 : 0.98)
    }

    private var toolbarBorderColor: Color {
        EditorTheme.panelBorder
    }

    private var recordingContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(L10n.recording)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(L10n.scrollHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                log.info("[USER] Clicked 'Done'")
                onDone()
            } label: {
                Text(L10n.done)
                    .lineLimit(1)
            }
            .buttonStyle(PrimaryCaptureButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var stitchingContent: some View {
        HStack(spacing: 9) {
            ProgressView(value: captureState.stitchProgress)
                .frame(width: 96)
            Text("\(L10n.stitchingLabel) \(Int(captureState.stitchProgress * 100))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Snap Edit Toolbar Content

private struct SnapEditToolbarContent: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var showWatermarkPopover = false
    let onToolChanged: (EditorTool?) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onScroll: () -> Void
    let onRecord: () -> Void
    let onPin: () -> Void
    let onRelay: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onExtractSubject: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EditorTool.allCases.filter { $0 != .sticker }) { tool in
                Button {
                    document.toggleTool(tool)
                    onToolChanged(document.selectedTool)
                } label: {
                    Image(systemName: tool.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(document.selectedTool == tool ? EditorTheme.accent : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(document.selectedTool == tool ? EditorTheme.selectedFill : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(document.selectedTool == tool ? EditorTheme.selectedStroke : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .iconTipText(EditorTooltipProvider.text(for: .tool(tool)))
            }

            Divider().frame(height: 20)

            Button { document.undo() } label: {
                Image(systemName: EditToolbarSymbol.undo)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.undo)

            Button { document.redo() } label: {
                Image(systemName: EditToolbarSymbol.redo)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.redo)

            Divider().frame(height: 20)

            Button {
                log.info("[USER] Snap edit — pin to desktop")
                onPin()
            } label: {
                Image(systemName: EditToolbarSymbol.pin)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.pinToDesktop)

            Button(action: onRelay) {
                Image(systemName: "ipad.and.arrow.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTipText(L10n.localized("在 iPad 标注", "Annotate on iPad"))
            .accessibilityIdentifier("snap.relay")

            Button {
                log.info("[USER] Snap edit — scroll capture")
                onScroll()
            } label: {
                Image(systemName: EditToolbarSymbol.scrollCapture)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.scrollCapture)

            Button {
                log.info("[USER] Snap edit — record")
                onRecord()
            } label: {
                Image(systemName: EditToolbarSymbol.record)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.record)

            Button {
                log.info("[USER] Snap edit — OCR")
                onOCR()
            } label: {
                Image(systemName: EditToolbarSymbol.ocr)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.ocr)

            Button {
                log.info("[USER] Snap edit — translate")
                onTranslate()
            } label: {
                Image(systemName: EditToolbarSymbol.translate)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .iconTip(.translate)

            Button {
                log.info("[USER] Snap edit — extract subject")
                onExtractSubject()
            } label: {
                if document.isExtractingSubject {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: EditToolbarSymbol.extractSubject)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
            }
            .buttonStyle(.plain)
            .disabled(document.isExtractingSubject)
            .iconTip(.extractSubject)

            ZStack(alignment: .topTrailing) {
                Button {
                    showWatermarkPopover = true
                } label: {
                    Image(systemName: prefs.watermarkConfig.isEnabled ? EditToolbarSymbol.watermarkOn : EditToolbarSymbol.watermarkOff)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .iconTip(.watermark)

                if prefs.watermarkConfig.isEnabled {
                    Circle()
                        .fill(EditorTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -2)
                }
            }
            .popover(isPresented: $showWatermarkPopover, arrowEdge: .bottom) {
                WatermarkSettingsView(isPresented: $showWatermarkPopover)
            }

            Spacer().frame(width: 8)

            Button {
                log.info("[USER] Snap edit — cancel")
                onCancel()
            } label: {
                Image(systemName: EditToolbarSymbol.cancel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(SecondaryIconButtonStyle())
            .keyboardShortcut(.escape, modifiers: [])
            .iconTip(.cancel)

            Button {
                log.info("[USER] Snap edit — confirm")
                onConfirm()
            } label: {
                Image(systemName: EditToolbarSymbol.confirm)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(EditorTheme.accent)
            }
            .buttonStyle(SecondaryIconButtonStyle())
            .iconTip(.confirm)

            if document.editingTextID == nil {
                Button("", action: onConfirm)
                    .keyboardShortcut(.return, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Button Styles

private struct PrimaryCaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SecondaryCaptureButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fillColor.opacity(configuration.isPressed ? 0.88 : 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.78)
    }

    private var fillColor: Color {
        colorScheme == .dark ? EditorTheme.selectedFill.opacity(0.85) : EditorTheme.subtleAccentFill
    }

    private var borderColor: Color {
        EditorTheme.panelBorder
    }
}

private struct SecondaryIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(backgroundColor.opacity(configuration.isPressed ? 0.88 : 1.0))
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var iconColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.78)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? EditorTheme.selectedFill.opacity(0.92) : EditorTheme.subtleAccentFill
    }

    private var borderColor: Color {
        EditorTheme.panelBorder
    }
}
