import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var document: EditorDocument
    let viewportSize: CGSize
    let onSave: () -> Void
    let onCopy: () -> Void
    var onRelay: (() -> Void)? = nil
    let onShare: () -> Void
    let onOCR: () -> Void
    let onTranslate: () -> Void
    let onExtractSubject: () -> Void
    var onPinImage: (() -> Void)?

    @State private var showWatermarkPopover = false
    @ObservedObject private var prefs = AppPreferences.shared

    private let stickerOptions = ["★", "✅", "❗", "🔥", "💡", "📌", "🔒", "🙂"]

    var body: some View {
        HStack(spacing: EditorTheme.spacing10) {
            pillGroup { toolGroup }
            pillGroup { editGroup }
            pillGroup { viewGroup }

            Spacer(minLength: 0)

            exportGroup
        }
        .padding(.horizontal, EditorTheme.spacing12)
        .frame(height: EditorTheme.toolbarHeight)
        .background(.regularMaterial)
        .tint(EditorTheme.accent)
    }

    private func pillGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: EditorTheme.spacing6, content: content)
            .padding(.horizontal, EditorTheme.spacing6)
            .padding(.vertical, EditorTheme.spacing4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(EditorTheme.toolbarGroupBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(EditorTheme.panelBorder, lineWidth: 1)
            )
    }

    private var toolGroup: some View {
        HStack(spacing: EditorTheme.spacing6) {
            ForEach(EditorTool.allCases) { tool in
                iconButton(
                    symbol: tool.symbolName,
                    isSelected: document.selectedTool == tool,
                    tooltip: EditorTooltipProvider.text(for: .tool(tool)),
                    accessibilityID: "toolbar.tool.\(tool.id.lowercased())"
                ) {
                    document.toggleTool(tool)
                }
            }

            Menu {
                ForEach(stickerOptions, id: \.self) { sticker in
                    Button(sticker) {
                        document.selectedSticker = sticker
                        document.selectedTool = .sticker
                    }
                    .help(EditorTooltipProvider.text(for: .stickerOption(sticker)))
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(document.selectedTool == .sticker ? EditorTheme.accent : EditorTheme.primaryText)
                    .background(
                        RoundedRectangle(cornerRadius: EditorTheme.radiusSmall)
                            .fill(document.selectedTool == .sticker ? EditorTheme.selectedFill : EditorTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorTheme.radiusSmall)
                            .stroke(document.selectedTool == .sticker ? EditorTheme.selectedStroke : Color.clear, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .iconTipText(EditorTooltipProvider.text(for: .stickerPicker))
            .accessibilityIdentifier("toolbar.sticker.menu")
        }
    }

    private var editGroup: some View {
        HStack(spacing: EditorTheme.spacing6) {
            iconButton(symbol: EditToolbarSymbol.undo, tooltip: EditorTooltipProvider.text(for: .undo), accessibilityID: "toolbar.undo") {
                document.undo()
            }
            iconButton(symbol: EditToolbarSymbol.redo, tooltip: EditorTooltipProvider.text(for: .redo), accessibilityID: "toolbar.redo") {
                document.redo()
            }
            iconButton(symbol: EditToolbarSymbol.delete, tooltip: EditorTooltipProvider.text(for: .delete), accessibilityID: "toolbar.delete") {
                document.deleteSelection()
            }
        }
    }

    private var viewGroup: some View {
        HStack(spacing: EditorTheme.spacing6) {
            iconButton(symbol: EditToolbarSymbol.fit, tooltip: EditorTooltipProvider.text(for: .fit), accessibilityID: "toolbar.fit") {
                document.fitToWindow(viewport: viewportSize)
            }
            iconButton(symbol: EditToolbarSymbol.zoomOut, tooltip: EditorTooltipProvider.text(for: .zoomOut), accessibilityID: "toolbar.zoom.out") {
                document.zoomOut()
            }
            Text("\(Int(document.zoomScale * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(minWidth: 44)
                .help(EditorTooltipProvider.text(for: .zoomPercent))
                .accessibilityIdentifier("toolbar.zoom.percent")
            iconButton(symbol: EditToolbarSymbol.zoomIn, tooltip: EditorTooltipProvider.text(for: .zoomIn), accessibilityID: "toolbar.zoom.in") {
                document.zoomIn()
            }
            textButton("1:1", tooltip: EditorTooltipProvider.text(for: .actualSize), accessibilityID: "toolbar.zoom.actual") {
                document.actualSize()
            }
        }
    }

    private var exportGroup: some View {
        HStack(spacing: EditorTheme.spacing8) {
            if let onPinImage {
                textButton(L10n.pinToDesktop, tooltip: L10n.pinToDesktop, accessibilityID: "toolbar.pin", action: onPinImage)
            }
            textButton(L10n.save, tooltip: EditorTooltipProvider.text(for: .save), accessibilityID: "toolbar.save", action: onSave)
            if let onRelay {
                textButton(
                    L10n.localized("在 iPad 标注", "Annotate on iPad"),
                    tooltip: L10n.localized("发送当前图片到 iPad 接力画板", "Send the current image to the iPad relay canvas"),
                    accessibilityID: "toolbar.relay",
                    action: onRelay
                )
            }
            textButton(L10n.copy, tooltip: EditorTooltipProvider.text(for: .copy), accessibilityID: "toolbar.copy", action: onCopy)
            textButton(L10n.share, tooltip: EditorTooltipProvider.text(for: .share), accessibilityID: "toolbar.share", action: onShare)
            textButton(L10n.ocr, tooltip: EditorTooltipProvider.text(for: .ocr), accessibilityID: "toolbar.ocr", action: onOCR)
            textButton(L10n.translate, tooltip: EditorTooltipProvider.text(for: .translate), accessibilityID: "toolbar.translate", action: onTranslate)
            textButton(
                document.isExtractingSubject ? L10n.extractingSubject : L10n.extractSubject,
                tooltip: L10n.extractSubject,
                accessibilityID: "toolbar.extract",
                action: onExtractSubject
            )
            .disabled(document.isExtractingSubject)
            
            // Watermark button with indicator
            ZStack(alignment: .topTrailing) {
                textButton(L10n.watermark, tooltip: L10n.watermark, accessibilityID: "toolbar.watermark") {
                    showWatermarkPopover = true
                }
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
        }
    }

    private func iconButton(
        symbol: String,
        isSelected: Bool = false,
        tooltip: String,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? EditorTheme.accent : EditorTheme.primaryText)
                .background(
                    RoundedRectangle(cornerRadius: EditorTheme.radiusSmall)
                        .fill(isSelected ? EditorTheme.selectedFill : EditorTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: EditorTheme.radiusSmall)
                        .stroke(isSelected ? EditorTheme.selectedStroke : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .iconTipText(tooltip)
        .accessibilityIdentifier(accessibilityID ?? "toolbar.icon.\(symbol)")
    }

    private func textButton(
        _ title: String,
        tooltip: String? = nil,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let hint = tooltip ?? title
        return Button(action: action) {
            Text(title)
        }
            .buttonStyle(EditorToolbarButtonStyle())
            .help(hint)
            .accessibilityLabel(hint)
            .accessibilityHint(hint)
            .accessibilityIdentifier(accessibilityID ?? "toolbar.text.\(title.lowercased())")
    }
}
