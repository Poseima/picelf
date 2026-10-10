import SwiftUI
import UniformTypeIdentifiers

struct CanvasToolbarView: View {
    @ObservedObject var document: CanvasDocument
    let viewportSize: CGSize
    let onSave: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let onAddImage: () -> Void

    @State private var showWatermarkPopover = false

    var body: some View {
        HStack(spacing: 12) {
            // Add image button
            Button(action: onAddImage) {
                Label(L10n.canvasAddImage, systemImage: EditToolbarSymbol.addImage)
            }
            .buttonStyle(.borderless)
            .iconTip(.addImage)

            Divider().frame(height: 20)

            // Undo / Redo
            Button(action: { document.undo() }) {
                Image(systemName: EditToolbarSymbol.undo)
            }
            .buttonStyle(.borderless)
            .disabled(!document.canUndo)
            .iconTip(.undo)

            Button(action: { document.redo() }) {
                Image(systemName: EditToolbarSymbol.redo)
            }
            .buttonStyle(.borderless)
            .disabled(!document.canRedo)
            .iconTip(.redo)

            Divider().frame(height: 20)

            // Zoom controls
            Button(action: { document.zoomOut() }) {
                Image(systemName: EditToolbarSymbol.zoomOut)
            }
            .buttonStyle(.borderless)
            .iconTip(.zoomOut)

            Text(L10n.zoom(Int(document.zoomScale * 100)))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 50)

            Button(action: { document.zoomIn() }) {
                Image(systemName: EditToolbarSymbol.zoomIn)
            }
            .buttonStyle(.borderless)
            .iconTip(.zoomIn)

            Button(action: { document.fitToWindow(viewport: viewportSize) }) {
                Image(systemName: EditToolbarSymbol.fit)
            }
            .buttonStyle(.borderless)
            .iconTip(.fitToWindow)

            Button(action: { document.actualSize() }) {
                Text("1:1")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.borderless)
            .iconTip(.actualSize)

            Spacer()

            // Delete
            Button(action: { document.deleteSelection() }) {
                Image(systemName: EditToolbarSymbol.delete)
            }
            .buttonStyle(.borderless)
            .disabled(document.selectedItemIDs.isEmpty)
            .iconTip(.delete)

            Divider().frame(height: 20)

            // Watermark
            ZStack(alignment: .topTrailing) {
                Button(action: { showWatermarkPopover = true }) {
                    Label(
                        L10n.watermark,
                        systemImage: AppPreferences.shared.watermarkConfig.isEnabled ? EditToolbarSymbol.watermarkOn : EditToolbarSymbol.watermarkOff
                    )
                }
                .buttonStyle(.borderless)
                .iconTip(.watermark)
                
                if AppPreferences.shared.watermarkConfig.isEnabled {
                    Circle()
                        .fill(EditorTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -2)
                }
            }
            .popover(isPresented: $showWatermarkPopover, arrowEdge: .bottom) {
                WatermarkSettingsView(isPresented: $showWatermarkPopover)
            }

            Divider().frame(height: 20)

            // Export
            Button(action: onCopy) {
                Label(L10n.copy, systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .iconTip(.copy)

            Button(action: onSave) {
                Label(L10n.save, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .iconTip(.save)

            Button(action: onShare) {
                Label(L10n.share, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .iconTip(.share)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: EditorTheme.toolbarHeight)
        .background(.thinMaterial)
        .tint(EditorTheme.accent)
    }
}
