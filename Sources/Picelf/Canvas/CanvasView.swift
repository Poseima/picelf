import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CanvasView: View {
    @ObservedObject var document: CanvasDocument
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var viewportSize: CGSize = .zero
    @State private var resolvedScrollView: NSScrollView?
    @State private var keyMonitor: Any?
    @State private var showingFileImporter = false
    @State private var inspectorCollapsed = false

    var body: some View {
        ZStack {
            PicelfGlassBackdrop()

            VStack(spacing: 0) {
                CanvasToolbarView(
                    document: document,
                    viewportSize: viewportSize,
                    onSave: save,
                    onCopy: copyToClipboard,
                    onShare: share,
                    onAddImage: { showingFileImporter = true }
                )
                .zIndex(1)

                Divider()

                HStack(spacing: 0) {
                    GeometryReader { geo in
                        ScrollView([.vertical, .horizontal]) {
                            CanvasCanvasView(
                                document: document,
                                onMagnify: applyMagnification(delta:hoverInView:)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
                            .padding(24)
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
                            document.fitToWindow(viewport: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            viewportSize = newSize
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !inspectorCollapsed {
                        Divider()
                        CanvasInspectorView(document: document)
                            .frame(width: EditorTheme.inspectorWidth)
                            .transition(.move(edge: .trailing))
                    }
                }

                Divider()
                statusBar
                    .frame(height: EditorTheme.statusHeight)
                    .background(.thinMaterial)
            }
        }
        .frame(minWidth: 1060, minHeight: 700)
        .tint(EditorTheme.accent)
        .onExitCommand {
            document.clearSelection()
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let isDelete = event.keyCode == 51 || event.keyCode == 117
                let noMods = event.modifierFlags
                    .intersection([.command, .option, .shift, .control])
                    .isEmpty
                guard isDelete, noMods, !document.selectedItemIDs.isEmpty else { return event }
                document.deleteSelection()
                return nil
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
        .overlay(alignment: .topLeading) {
            shortcutLayer
                .frame(width: 0, height: 0)
                .opacity(0.001)
                .allowsHitTesting(false)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.png, .jpeg, .gif, .image],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            for (i, url) in urls.enumerated() {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let image = NSImage(contentsOf: url) else { continue }
                let offset = CGPoint(x: CGFloat(i) * 20, y: CGFloat(i) * 20)
                document.addImage(image, kind: .importedImage(sourceURL: url), positionOffset: offset)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(L10n.zoom(Int(document.zoomScale * 100)))
            Spacer(minLength: 0)
            Text(L10n.canvas(Int(document.canvasSize.width), Int(document.canvasSize.height)))
            Spacer(minLength: 0)
            Text(L10n.selected(document.selectedItemIDs.count))
            Spacer(minLength: 0)
            Text("\(document.items.count) \(L10n.canvasItems)")

            Button(inspectorCollapsed ? L10n.showInspector : L10n.hideInspector) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    inspectorCollapsed.toggle()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    // MARK: - Shortcuts

    private var shortcutLayer: some View {
        Group {
            Button("", action: { document.undo() })
                .keyboardShortcut("z", modifiers: [.command])
            Button("", action: { document.redo() })
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
            Button("", action: { pasteFromClipboard() })
                .keyboardShortcut("v", modifiers: [.command])
            Button("", action: { save() })
                .keyboardShortcut("s", modifiers: [.command])
            Button("", action: { document.duplicateSelection() })
                .keyboardShortcut("d", modifiers: [.command])
        }
    }

    // MARK: - Magnification

    private func applyMagnification(delta: CGFloat, hoverInView: CGPoint) {
        let oldZoom = document.zoomScale
        let newZoom = max(0.05, min(8.0, oldZoom * delta))
        guard oldZoom > 0, let scrollView = resolvedScrollView else {
            document.setZoomScale(newZoom)
            return
        }

        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let anchorInContent = CGPoint(
            x: currentOrigin.x + hoverInView.x,
            y: currentOrigin.y + hoverInView.y
        )

        let ratio = newZoom / oldZoom
        let proposedAnchor = CGPoint(x: anchorInContent.x * ratio, y: anchorInContent.y * ratio)
        document.setZoomScale(newZoom)

        let contentWidth = document.canvasSize.width * newZoom + 48
        let contentHeight = document.canvasSize.height * newZoom + 48
        let visibleSize = clipView.bounds.size
        let maxX = max(0, contentWidth - visibleSize.width)
        let maxY = max(0, contentHeight - visibleSize.height)

        let nextOrigin = CGPoint(
            x: min(max(0, proposedAnchor.x - hoverInView.x), maxX),
            y: min(max(0, proposedAnchor.y - hoverInView.y), maxY)
        )
        clipView.setBoundsOrigin(nextOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Clipboard

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let tiffData = pb.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            document.addImage(image, kind: .importedImage(sourceURL: nil))
        } else if let pngData = pb.data(forType: .png),
                  let image = NSImage(data: pngData) {
            document.addImage(image, kind: .importedImage(sourceURL: nil))
        }
    }

    // MARK: - Export

    private func save() {
        guard let composed = CanvasRenderer.render(document: document) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = document.selectedFormat == .png ? [.png] : [.jpeg]
        panel.nameFieldStringValue = "Picelf-Canvas-\(dateString()).\(document.selectedFormat == .png ? "png" : "jpg")"

        let savePath = AppPreferences.shared.savePath
        if !savePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: savePath)
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            AppPreferences.shared.savePath = url.deletingLastPathComponent().path
            let format: ImageExporter.Format = document.selectedFormat == .png
                ? .png
                : .jpeg(quality: document.jpegQuality)
            try? ImageExporter.export(composed, to: url, format: format)
        }
    }

    private func copyToClipboard() {
        guard let composed = CanvasRenderer.render(document: document) else { return }
        try? composed.copyToClipboard()
    }

    private func share() {
        guard let composed = CanvasRenderer.render(document: document) else { return }
        let picker = NSSharingServicePicker(items: [composed])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
