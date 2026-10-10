import SwiftUI
import AppKit

private struct EditorInspectorFreezeSnapshot {
    var toolName: String
    var annotationCount: Int
    var selectedCount: Int
    var zoomPercent: Int

    static let empty = EditorInspectorFreezeSnapshot(
        toolName: "—",
        annotationCount: 0,
        selectedCount: 0,
        zoomPercent: 100
    )
}

struct EditView: View {
    @StateObject private var document: EditorDocument
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var viewportSize: CGSize = .zero
    @State private var resolvedScrollView: NSScrollView?
    @State private var keyMonitor: Any?
    @State private var isCanvasInteracting = false
    @State private var inspectorFreezeSnapshot = EditorInspectorFreezeSnapshot.empty
    private let isUITestLaunch = ProcessInfo.processInfo.arguments.contains("--uitest-open-editor")
    private let autoOCR: Bool
    private let autoExtract: Bool
    private let autoTranslate: Bool
    private let applyWatermark: Bool
    private let relayEditor: RelayMacLiveEditor?
    var onPinImage: ((NSImage) -> Void)?

    init(
        originalImage: NSImage,
        sourceURL: URL? = nil,
        autoOCR: Bool = false,
        autoExtract: Bool = false,
        autoTranslate: Bool = false,
        applyWatermark: Bool = true,
        onPinImage: ((NSImage) -> Void)? = nil,
        relayEditor: RelayMacLiveEditor? = nil
    ) {
        _document = StateObject(wrappedValue: relayEditor?.document ?? EditorDocument(baseImage: originalImage, sourceURL: sourceURL))
        self.relayEditor = relayEditor
        self.autoOCR = autoOCR
        self.autoExtract = autoExtract
        self.autoTranslate = autoTranslate
        self.applyWatermark = applyWatermark
        self.onPinImage = onPinImage
    }

    var body: some View {
        ZStack {
            PicelfGlassBackdrop()

            VStack(spacing: 0) {
                if let relayEditor { RelayEditorSessionBar(hub: relayEditor.hub, taskID: relayEditor.id) }
                EditorToolbarView(
                    document: document,
                    viewportSize: viewportSize,
                    onSave: save,
                    onCopy: copyToClipboard,
                    onRelay: {
                        if let relayEditor { RelayMacController.shared.show(); _ = relayEditor; return }
                        if let image = renderComposedImage() {
                            RelayMacController.shared.sendImage(image)
                        }
                    },
                    onShare: share,
                    onOCR: { document.performOCR() },
                    onTranslate: { document.beginTranslation(forceRefresh: true) },
                    onExtractSubject: { document.extractSubject() },
                    onPinImage: onPinImage != nil ? {
                        if let composed = renderComposedImage() {
                            onPinImage?(composed)
                        }
                    } : nil
                )
                .disabled(document.relayLocked)
                .zIndex(1)

                Divider()

                HStack(spacing: 0) {
                    GeometryReader { geo in
                        ScrollView([.vertical, .horizontal]) {
                            EditorCanvasView(
                                document: document,
                                onMagnify: applyMagnification(delta:hoverInView:),
                                onInteractionStateChanged: handleCanvasInteractionStateChanged
                            )
                            .allowsHitTesting(!document.relayLocked)
                            .background(editorStageCard)
                            .clipShape(RoundedRectangle(cornerRadius: EditorTheme.radiusLarge, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)
                            .padding(EditorTheme.spacing16)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .center)
                            .background(
                                ScrollViewAccessor { scrollView in
                                    resolvedScrollView = scrollView
                                }
                                .frame(width: 0, height: 0)
                            )
                        }
                        .background(EditorTheme.workspaceSurface)
                        .onAppear {
                            viewportSize = geo.size
                            fitForInitialPresentation(geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            viewportSize = newSize
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        if shouldShowStickerToolbar {
                            StickerContextToolbar(document: document)
                                .padding(.bottom, 12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.2), value: shouldShowStickerToolbar)
                        }
                    }
                    .overlay {
                        if document.isExtractingSubject {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.large)
                                Text(L10n.extractingSubject)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(EditorTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial.opacity(0.6))
                        }
                    }

                    Divider()

                    inspectorPane.disabled(document.relayLocked)
                }

                Divider()
                statusBar
                    .frame(height: EditorTheme.statusHeight)
                    .background(.thinMaterial)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .tint(EditorTheme.accent)
        .onExitCommand {
            guard !document.relayLocked else { return }
            if document.commitActiveTextEditing() {
                document.clearSelection()
                return
            }
            document.clearSelectionLikeEscape()
        }
        .onDeleteCommand {
            guard !document.relayLocked else { return }
            if document.deleteEditingTextIfEmpty() { return }
            guard document.editingTextID == nil else { return }
            document.deleteSelection()
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // keyCode 51 = Backspace/Delete, 117 = Forward Delete
                if document.relayLocked { return event }
                let isDelete = event.keyCode == 51 || event.keyCode == 117
                let noMods = event.modifierFlags
                    .intersection([.command, .option, .shift, .control])
                    .isEmpty
                guard isDelete, noMods else { return event }
                if document.editingTextID != nil {
                    if document.deleteEditingTextIfEmpty() {
                        return nil
                    }
                    return event
                }
                guard !document.selectedAnnotationIDs.isEmpty else { return event }
                document.deleteSelection()
                return nil
            }
            if autoOCR {
                document.performOCR()
            }
            if autoExtract {
                document.extractSubject()
            }
            if autoTranslate {
                document.beginTranslation(forceRefresh: false)
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
        .onChange(of: document.selectedTranslationSegmentID) { _, newValue in
            guard let newValue else { return }
            centerTranslationSegmentIfNeeded(newValue)
        }
        .overlay(alignment: .topLeading) {
            shortcutLayer
                .frame(width: 0, height: 0)
                .opacity(0.001)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            translationTaskLayer
                .frame(width: 0, height: 0)
                .opacity(0.001)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            if isUITestLaunch {
                uiTestDiagnostics
                    .padding(4)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: EditorTheme.spacing10) {
            Text(L10n.zoom(Int(document.zoomScale * 100)))
                .help(EditorTooltipProvider.text(for: .statusZoom))
                .accessibilityIdentifier("status.zoom")
            Spacer(minLength: 0)
            Text(L10n.canvas(Int(document.imageWidth), Int(document.imageHeight)))
                .help(EditorTooltipProvider.text(for: .statusCanvas))
                .accessibilityIdentifier("status.canvas")
            Spacer(minLength: 0)
            Text(L10n.selected(document.selectedAnnotationIDs.count))
                .help(EditorTooltipProvider.text(for: .statusSelected))
                .accessibilityIdentifier("status.selected")
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(EditorTheme.secondaryText)
        .padding(.horizontal, EditorTheme.spacing12)
    }

    private var editorStageCard: some View {
        RoundedRectangle(cornerRadius: EditorTheme.radiusLarge, style: .continuous)
            .fill(EditorTheme.editorStageBackground)
            .overlay(
                RoundedRectangle(cornerRadius: EditorTheme.radiusLarge, style: .continuous)
                    .stroke(EditorTheme.editorStageBorder, lineWidth: 1)
            )
    }

    private var inspectorPane: some View {
        Group {
            if isCanvasInteracting {
                EditorInspectorFrozenView(snapshot: inspectorFreezeSnapshot)
            } else {
                EditorInspectorView(document: document, onExportTranslatedCopy: exportTranslatedCopy)
            }
        }
        .frame(width: EditorTheme.inspectorWidth)
    }

    @ViewBuilder
    private var translationTaskLayer: some View {
        if #available(macOS 15.0, *) {
            TranslationTaskHostView(document: document)
        }
    }

    private var shouldShowStickerToolbar: Bool {
        guard document.selectedAnnotationIDs.count == 1,
              let annotation = document.primarySelectedAnnotation else { return false }
        return annotation.kind == .sticker && annotation.stickerImageID != nil
    }

    private func makeInspectorFreezeSnapshot() -> EditorInspectorFreezeSnapshot {
        EditorInspectorFreezeSnapshot(
            toolName: document.selectedTool?.rawValue ?? "—",
            annotationCount: document.annotations.count,
            selectedCount: document.selectedAnnotationIDs.count,
            zoomPercent: Int(document.zoomScale * 100)
        )
    }

    private func handleCanvasInteractionStateChanged(_ isInteracting: Bool) {
        if isInteracting {
            inspectorFreezeSnapshot = makeInspectorFreezeSnapshot()
        }
        isCanvasInteracting = isInteracting
    }

    private func fitForInitialPresentation(_ viewport: CGSize) {
        document.fitToWindow(viewport: viewport)
        if document.zoomScale < 0.6 {
            document.setZoomScale(0.6)
        }
    }

    private func applyMagnification(delta: CGFloat, hoverInView: CGPoint) {
        let oldZoom = document.zoomScale
        let newZoom = max(0.1, min(8.0, oldZoom * delta))
        guard oldZoom > 0 else {
            document.setZoomScale(newZoom)
            return
        }

        guard let scrollView = resolvedScrollView else {
            document.setZoomScale(newZoom)
            return
        }

        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let currentVisible = clipView.bounds.size

        let anchorInContent = CGPoint(
            x: currentOrigin.x + hoverInView.x,
            y: currentOrigin.y + hoverInView.y
        )

        let ratio = newZoom / oldZoom
        let proposedAnchor = CGPoint(
            x: anchorInContent.x * ratio,
            y: anchorInContent.y * ratio
        )

        document.setZoomScale(newZoom)

        let contentWidth = document.imageWidth * newZoom + EditorTheme.spacing16 * 2
        let contentHeight = document.imageHeight * newZoom + EditorTheme.spacing16 * 2
        let maxX = max(0, contentWidth - currentVisible.width)
        let maxY = max(0, contentHeight - currentVisible.height)

        let nextOrigin = CGPoint(
            x: min(max(0, proposedAnchor.x - hoverInView.x), maxX),
            y: min(max(0, proposedAnchor.y - hoverInView.y), maxY)
        )
        clipView.setBoundsOrigin(nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func centerTranslationSegmentIfNeeded(_ id: UUID) {
        guard let segment = document.translationSegments.first(where: { $0.id == id }),
              let scrollView = resolvedScrollView else { return }

        let rect = segment.rect(in: CGSize(width: document.imageWidth, height: document.imageHeight))
        let scaledRect = CGRect(
            x: rect.origin.x * document.zoomScale + EditorTheme.spacing16,
            y: rect.origin.y * document.zoomScale + EditorTheme.spacing16,
            width: rect.width * document.zoomScale,
            height: rect.height * document.zoomScale
        )

        let visibleSize = scrollView.contentView.bounds.size
        let maxX = max(0, scrollView.documentView?.bounds.width ?? 0 - visibleSize.width)
        let maxY = max(0, scrollView.documentView?.bounds.height ?? 0 - visibleSize.height)
        let targetOrigin = CGPoint(
            x: min(max(0, scaledRect.midX - visibleSize.width / 2), maxX),
            y: min(max(0, scaledRect.midY - visibleSize.height / 2), maxY)
        )

        scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private var shortcutLayer: some View {
        Group {
            Button("", action: { if !document.relayLocked { document.undo() } })
                .keyboardShortcut("z", modifiers: [.command])
            Button("", action: { if !document.relayLocked { document.redo() } })
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("", action: { document.zoomIn() })
                .keyboardShortcut("=", modifiers: [.command])
            Button("", action: { document.zoomOut() })
                .keyboardShortcut("-", modifiers: [.command])
            Button("", action: { document.actualSize() })
                .keyboardShortcut("0", modifiers: [.command])
            Button("", action: { document.fitToWindow(viewport: viewportSize) })
                .keyboardShortcut("9", modifiers: [.command])
            Button("", action: { copyToClipboard() })
                .keyboardShortcut("c", modifiers: [.command])
            Button("", action: { save() })
                .keyboardShortcut("s", modifiers: [.command])
            Button("", action: { if !document.relayLocked { document.duplicateSelection() } })
                .keyboardShortcut("d", modifiers: [.command])
            Button("", action: { document.performOCR() })
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("", action: { document.beginTranslation(forceRefresh: true) })
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("", action: { document.extractSubject() })
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }

    private func save() {
        guard let composed = renderComposedImage() else { return }
        if let sourceURL = document.sourceImageURL {
            let format = exportFormatForSourceURL(sourceURL)
            try? ImageExporter.export(composed, to: sourceURL, format: format)
            return
        }
        saveAs(image: composed)
    }

    private func exportFormatForSourceURL(_ sourceURL: URL) -> ImageExporter.Format {
        switch sourceURL.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return .jpeg(quality: document.jpegQuality)
        case "png":
            return .png
        default:
            return .png
        }
    }

    private func saveAs(image: NSImage) {
        let selectedFormat = document.selectedFormat
        let jpegQuality = document.jpegQuality
        let panel = NSSavePanel()
        panel.allowedContentTypes = selectedFormat == .png
            ? [.png]
            : [.jpeg]
        panel.nameFieldStringValue = "Picelf-\(dateString()).\(selectedFormat == .png ? "png" : "jpg")"

        if !prefs.savePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: prefs.savePath)
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            AppPreferences.shared.savePath = url.deletingLastPathComponent().path
            let format: ImageExporter.Format = selectedFormat == .png
                ? .png
                : .jpeg(quality: jpegQuality)
            try? ImageExporter.export(image, to: url, format: format)
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private func copyToClipboard() {
        if let relayEditor {
            relayEditor.hub.collaboration.resumeClipboard(relayEditor.id)
            Task { do { try await relayEditor.flush() } catch { relayEditor.hub.errorMessage = error.localizedDescription } }
            return
        }
        guard let composed = renderComposedImage() else { return }
        try? composed.copyToClipboard()
    }

    private func share() {
        guard let composed = renderComposedImage() else { return }
        let picker = NSSharingServicePicker(items: [composed])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func exportTranslatedCopy() {
        guard let translated = renderTranslatedCopyImage() else { return }
        let exportFormat = prefs.translationExportFormatPreference
        let panel = NSSavePanel()
        let isPNG: Bool
        switch exportFormat {
        case .png:
            isPNG = true
        case .matchSource:
            guard let sourceURL = document.sourceImageURL else {
                isPNG = true
                break
            }
            switch exportFormatForSourceURL(sourceURL) {
            case .png:
                isPNG = true
            case .jpeg:
                isPNG = false
            }
        }
        panel.allowedContentTypes = isPNG ? [.png] : [.jpeg]
        panel.nameFieldStringValue = "Picelf-translation-\(dateString()).\(isPNG ? "png" : "jpg")"
        if !prefs.savePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: prefs.savePath)
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            AppPreferences.shared.savePath = url.deletingLastPathComponent().path
            let format: ImageExporter.Format = isPNG ? .png : .jpeg(quality: document.jpegQuality)
            try? ImageExporter.export(translated, to: url, format: format)
        }
    }

    private func renderComposedImage() -> NSImage? {
        let fullRes = document.loadFullResImage()
        guard let composed = EditorCompositor.compose(
            baseImage: fullRes,
            imageSize: CGSize(width: document.imageWidth, height: document.imageHeight),
            annotations: document.visibleAnnotations,
            draft: document.draftAnnotation,
            pixelScale: document.isRelayDocument ? 1 : nil
        ) else { return nil }
        
        // Apply watermark
        if let overlay = document.relayInkOverlay,
           let baseCG = composed.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let inkCG = overlay.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let base = try? RelayImage.png(baseCG), let ink = try? RelayImage.png(inkCG),
           let merged = try? RelayImage.compose(base: base, overlay: ink, width: baseCG.width, height: baseCG.height) {
            return NSImage(data: merged)
        }
        guard applyWatermark else { return composed }
        let watermarkConfig = AppPreferences.shared.watermarkConfig
        return WatermarkRenderer.apply(to: composed, config: watermarkConfig)
    }

    private func renderTranslatedCopyImage() -> NSImage? {
        guard let composed = renderComposedImage() else { return nil }
        guard document.hasTranslationResults else { return composed }
        return TranslationOverlayRenderer.renderTranslatedCopy(
            baseImage: composed,
            imageSize: CGSize(width: document.imageWidth, height: document.imageHeight),
            segments: document.translationSegments
        )
    }


    private var uiTestDiagnostics: some View {
        let zoomValue = "zoom=\(Int(document.zoomScale * 100))"
        let selectedValue = "selected=\(document.selectedTool?.id ?? "none")"
        let panAvailable = EditorTool.allCases.contains { $0.id.lowercased() == "hand" || $0.id.lowercased() == "pan" }
        let panValue = "panAvailable=\(panAvailable)"
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: zoomValue)
                .accessibilityIdentifier("uitest.zoom.value")
                .accessibilityValue(zoomValue)
            Text(verbatim: selectedValue)
                .accessibilityIdentifier("uitest.tool.selected")
                .accessibilityValue(selectedValue)
            Text(verbatim: panValue)
                .accessibilityIdentifier("uitest.tool.pan.available")
                .accessibilityValue(panValue)
        }
        .font(.system(size: 1))
    }
}

private struct EditorInspectorFrozenView: View {
    let snapshot: EditorInspectorFreezeSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorTheme.spacing10) {
                Text(L10n.inspector)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(EditorTheme.primaryText)
                    .padding(.bottom, 2)

                VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
                    Text(L10n.zh ? "正在拖拽，已暂停右侧刷新" : "Dragging in progress, inspector refresh is paused")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(EditorTheme.secondaryText)

                    HStack(spacing: EditorTheme.spacing8) {
                        Text(L10n.zh ? "工具" : "Tool")
                        Spacer(minLength: 0)
                        Text(snapshot.toolName)
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(EditorTheme.primaryText)

                    HStack(spacing: EditorTheme.spacing8) {
                        Text(L10n.zh ? "标注" : "Annotations")
                        Spacer(minLength: 0)
                        Text("\(snapshot.annotationCount)")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(EditorTheme.primaryText)

                    HStack(spacing: EditorTheme.spacing8) {
                        Text(L10n.zh ? "选中" : "Selected")
                        Spacer(minLength: 0)
                        Text("\(snapshot.selectedCount)")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(EditorTheme.primaryText)

                    HStack(spacing: EditorTheme.spacing8) {
                        Text(L10n.zh ? "缩放" : "Zoom")
                        Spacer(minLength: 0)
                        Text("\(snapshot.zoomPercent)%")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(EditorTheme.primaryText)
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
            .padding(EditorTheme.spacing12)
        }
        .background(EditorTheme.panelBackground)
    }
}
