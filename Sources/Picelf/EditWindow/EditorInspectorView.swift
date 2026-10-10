import SwiftUI

struct EditorInspectorView: View {
    @ObservedObject var document: EditorDocument
    var onExportTranslatedCopy: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorTheme.spacing10) {
                Text(L10n.inspector)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(EditorTheme.primaryText)
                    .padding(.bottom, 2)
                    .help(EditorTooltipProvider.text(for: .inspector))

                section(L10n.summary) {
                    summaryRow(L10n.tool, value: document.selectedTool?.rawValue ?? "—", tooltip: EditorTooltipProvider.text(for: .summaryTool))
                    summaryRow(L10n.annotations, value: "\(document.annotations.count)", tooltip: EditorTooltipProvider.text(for: .summaryAnnotations))
                    summaryRow(L10n.image, value: "\(Int(document.imageWidth))×\(Int(document.imageHeight))", tooltip: EditorTooltipProvider.text(for: .summaryImage))
                }

                section(L10n.style) {
                    formRow(L10n.stroke, tooltip: EditorTooltipProvider.text(for: .strokeColor)) {
                        ColorPicker("", selection: Binding(
                            get: { document.primarySelectedAnnotation?.color ?? document.strokeColor },
                            set: { document.updateSelectedStrokeColor($0) }
                        ))
                        .labelsHidden()
                        .help(EditorTooltipProvider.text(for: .strokeColor))
                    }

                    formRow(L10n.fill, tooltip: EditorTooltipProvider.text(for: .fillColor)) {
                        ColorPicker("", selection: Binding(
                            get: { document.primarySelectedAnnotation?.fillColor ?? document.fillColor },
                            set: { document.updateSelectedFillColor($0) }
                        ))
                        .labelsHidden()
                        .help(EditorTooltipProvider.text(for: .fillColor))
                    }

                    formRow(L10n.line, tooltip: EditorTooltipProvider.text(for: .lineWidth)) {
                        HStack(spacing: EditorTheme.spacing8) {
                            Slider(
                                value: Binding(
                                    get: { document.primarySelectedAnnotation?.lineWidth ?? document.lineWidth },
                                    set: { document.updateSelectedLineWidth($0) }
                                ),
                                in: 1...24,
                                step: 1
                            )
                            .help(EditorTooltipProvider.text(for: .lineWidth))
                            Text("\(Int(document.primarySelectedAnnotation?.lineWidth ?? document.lineWidth)) px")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(EditorTheme.secondaryText)
                                .frame(width: 44, alignment: .trailing)
                                .help(EditorTooltipProvider.text(for: .lineWidth))
                        }
                    }
                }

                if let selected = document.primarySelectedAnnotation,
                   selected.kind == .text || selected.kind == .sticker {
                    section(L10n.textSection) {
                        formRow(L10n.size, tooltip: EditorTooltipProvider.text(for: .textSize)) {
                            HStack(spacing: EditorTheme.spacing8) {
                                Slider(
                                    value: Binding(
                                        get: { document.primarySelectedAnnotation?.fontSize ?? 18 },
                                        set: { document.updateSelectedFontSize($0) }
                                    ),
                                    in: 12...64,
                                    step: 1
                                )
                                .help(EditorTooltipProvider.text(for: .textSize))
                                Text("\(Int(selected.fontSize))")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(EditorTheme.secondaryText)
                                    .frame(width: 34, alignment: .trailing)
                                    .help(EditorTooltipProvider.text(for: .textSize))
                            }
                        }

                        if selected.kind == .text {
                            formRow(L10n.width, tooltip: EditorTooltipProvider.text(for: .textWidth)) {
                                HStack(spacing: EditorTheme.spacing8) {
                                    Slider(
                                        value: Binding(
                                            get: { document.primarySelectedAnnotation?.textBoxWidth ?? document.preferredTextBoxWidth },
                                            set: { document.updateSelectedTextBoxWidth($0) }
                                        ),
                                        in: EditorAnnotation.textBoxWidthRange,
                                        step: 1
                                    )
                                    .help(EditorTooltipProvider.text(for: .textWidth))
                                    Text("\(Int(selected.textBoxWidth)) px")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(EditorTheme.secondaryText)
                                        .frame(width: 54, alignment: .trailing)
                                        .help(EditorTooltipProvider.text(for: .textWidth))
                                }
                            }
                        }

                        if selected.kind == .sticker {
                            formRow(L10n.replace, tooltip: EditorTooltipProvider.text(for: .replaceSticker)) {
                                Menu(L10n.choose) {
                                    ForEach(["★", "✅", "❗", "🔥", "💡", "📌", "🔒", "🙂"], id: \.self) { sticker in
                                        Button(sticker) {
                                            document.updateSelectedSticker(sticker)
                                        }
                                        .help(EditorTooltipProvider.text(for: .stickerOption(sticker)))
                                    }
                                }
                                .controlSize(.small)
                                .help(EditorTooltipProvider.text(for: .replaceSticker))
                            }
                        }
                    }
                }

                section(L10n.stickerLibrary) {
                    StickerLibraryView(document: document)
                }

                if let selected = document.primarySelectedAnnotation, selected.kind == .mosaic {
                    section(L10n.mosaicSection) {
                        formRow(L10n.block, tooltip: EditorTooltipProvider.text(for: .mosaicBlock)) {
                            HStack(spacing: EditorTheme.spacing8) {
                                Slider(
                                    value: Binding(
                                        get: { document.primarySelectedAnnotation?.mosaicBlockSize ?? 14 },
                                        set: { document.updateSelectedMosaicBlockSize($0) }
                                    ),
                                    in: 6...40,
                                    step: 1
                                )
                                .help(EditorTooltipProvider.text(for: .mosaicBlock))
                                Text("\(Int(selected.mosaicBlockSize)) px")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(EditorTheme.secondaryText)
                                    .frame(width: 44, alignment: .trailing)
                                    .help(EditorTooltipProvider.text(for: .mosaicBlock))
                            }
                        }
                    }
                }

                section(L10n.export) {
                    Picker("", selection: $document.selectedFormat) {
                        Text("PNG").tag(ImageFormat.png)
                        Text("JPEG").tag(ImageFormat.jpeg)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .help(EditorTooltipProvider.text(for: .exportFormat))

                    if document.selectedFormat == .jpeg {
                        formRow(L10n.quality, tooltip: EditorTooltipProvider.text(for: .jpegQuality)) {
                            HStack(spacing: EditorTheme.spacing8) {
                                Slider(value: $document.jpegQuality, in: 0.1...1.0)
                                    .help(EditorTooltipProvider.text(for: .jpegQuality))
                                Text("\(Int(document.jpegQuality * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(EditorTheme.secondaryText)
                                    .frame(width: 44, alignment: .trailing)
                                    .help(EditorTooltipProvider.text(for: .jpegQuality))
                            }
                        }
                    }
                }

                section(L10n.translation) {
                    formRow(L10n.sourceLanguage, tooltip: EditorTooltipProvider.text(for: .ocr)) {
                        Text(document.translationSourceLanguageLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(EditorTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    formRow(L10n.targetLanguage, tooltip: EditorTooltipProvider.text(for: .translationTarget)) {
                        Picker("", selection: $document.selectedTranslationTarget) {
                            ForEach(TranslationLanguageOption.allCases) { language in
                                Text(language.localizedName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .help(EditorTooltipProvider.text(for: .translationTarget))
                    }

                    formRow(L10n.overlayMode, tooltip: EditorTooltipProvider.text(for: .translationOverlay)) {
                        Picker("", selection: $document.translationOverlayMode) {
                            ForEach(TranslationOverlayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .help(EditorTooltipProvider.text(for: .translationOverlay))
                    }

                    Group {
                        switch document.translationState {
                        case .extractingText, .translating:
                            HStack(spacing: EditorTheme.spacing8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(document.translationStatusMessage ?? L10n.translating)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(EditorTheme.secondaryText)
                            }
                        case .unsupported, .failed:
                            Text(document.translationStatusMessage ?? L10n.translationFailed)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(EditorTheme.secondaryText)
                        case .ready:
                            Text(document.translationStatusMessage ?? L10n.translationReady)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(EditorTheme.secondaryText)
                        case .idle:
                            Text(L10n.translationPreviewHint)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(EditorTheme.secondaryText)
                        }
                    }

                    HStack(spacing: EditorTheme.spacing8) {
                        Button(document.isTranslationRunning ? L10n.translating : L10n.translate) {
                            document.beginTranslation(forceRefresh: true)
                        }
                        .buttonStyle(EditorPrimaryButtonStyle())
                        .disabled(document.isTranslationRunning)

                        Button(L10n.copyTranslation) {
                            document.copyTranslationToPasteboard()
                        }
                        .buttonStyle(EditorSecondaryButtonStyle())
                        .disabled(!document.hasTranslationResults)
                        .help(EditorTooltipProvider.text(for: .translationCopy))

                        Button(L10n.exportTranslatedCopy) {
                            onExportTranslatedCopy()
                        }
                        .buttonStyle(EditorSecondaryButtonStyle())
                        .disabled(!document.hasTranslationResults)
                        .help(EditorTooltipProvider.text(for: .translationExport))
                    }

                    if document.hasTranslationResults {
                        ScrollView {
                            VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
                                ForEach(document.translationSegments) { segment in
                                    Button {
                                        document.selectTranslationSegment(segment.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(segment.translatedText)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(EditorTheme.primaryText)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if !segment.sourceText.isEmpty {
                                                Text(segment.sourceText)
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundStyle(EditorTheme.secondaryText)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(EditorTheme.spacing8)
                                        .background(
                                            RoundedRectangle(cornerRadius: EditorTheme.radiusSmall, style: .continuous)
                                                .fill(document.selectedTranslationSegmentID == segment.id
                                                      ? EditorTheme.selectedFill
                                                      : EditorTheme.panelBackground)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(minHeight: 140, maxHeight: 260)
                    }
                }

                section(L10n.translationRawOCR) {
                    if document.isOCRRunning {
                        HStack(spacing: EditorTheme.spacing8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.recognizing)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(EditorTheme.secondaryText)
                        }
                    } else if document.ocrText != nil {
                        TextEditor(text: Binding(
                            get: { document.ocrText ?? "" },
                            set: { document.ocrText = $0 }
                        ))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 140, maxHeight: 360)
                            .scrollContentBackground(.hidden)
                            .background(EditorTheme.fieldBackground)
                            .cornerRadius(EditorTheme.radiusSmall)

                        Button(L10n.copyAll) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(document.ocrText ?? "", forType: .string)
                        }
                        .buttonStyle(EditorSecondaryButtonStyle())
                    } else {
                        Button(L10n.recognizeText) {
                            document.performOCR()
                        }
                        .buttonStyle(EditorSecondaryButtonStyle())
                    }
                }

            }
            .padding(EditorTheme.spacing12)
        }
        .background(EditorTheme.panelBackground)
        .tint(EditorTheme.accent)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(EditorTheme.secondaryText)

            content()
        }
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .fill(EditorTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }

    private func formRow<Value: View>(_ title: String, tooltip: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .center, spacing: EditorTheme.spacing10) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 54, alignment: .leading)
                .help(tooltip)
            value()
        }
    }

    private func summaryRow(_ title: String, value: String, tooltip: String) -> some View {
        HStack(spacing: EditorTheme.spacing8) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EditorTheme.secondaryText)
                .help(tooltip)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(EditorTheme.primaryText)
                .help(tooltip)
        }
    }
}
