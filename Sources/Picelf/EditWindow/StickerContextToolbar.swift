import SwiftUI

struct StickerContextToolbar: View {
    @ObservedObject var document: EditorDocument

    private var selectedAnnotation: EditorAnnotation? {
        document.primarySelectedAnnotation
    }

    var body: some View {
        HStack(spacing: 10) {
            // Opacity
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 12))
                .foregroundStyle(EditorTheme.secondaryText)
                .iconTipText(L10n.stickerOpacity)
            Slider(
                value: Binding(
                    get: { selectedAnnotation?.opacity ?? 1.0 },
                    set: { document.updateSelectedOpacity($0) }
                ),
                in: 0.1...1.0
            )
            .frame(width: 80)
            Text("\(Int((selectedAnnotation?.opacity ?? 1.0) * 100))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 34, alignment: .trailing)

            Divider().frame(height: 20)

            // Shadow toggle
            Button(action: { document.toggleSelectedShadow() }) {
                Image(systemName: selectedAnnotation?.hasShadow == true ? "shadow" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.primaryText)
            }
            .buttonStyle(.borderless)
            .iconTip(.stickerShadow)

            Divider().frame(height: 20)

            // Flip H/V
            Button(action: { document.flipSelectedHorizontally() }) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.primaryText)
            }
            .buttonStyle(.borderless)
            .iconTip(.stickerFlipHorizontal)

            Button(action: { document.flipSelectedVertically() }) {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.primaryText)
            }
            .buttonStyle(.borderless)
            .iconTip(.stickerFlipVertical)

            Divider().frame(height: 20)

            // Layer order
            Button(action: {
                if let id = document.selectedAnnotationIDs.first {
                    document.reorder(id, direction: .up)
                }
            }) {
                Image(systemName: "square.2.layers.3d.top.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.primaryText)
            }
            .buttonStyle(.borderless)
            .iconTip(.bringForward)

            Button(action: {
                if let id = document.selectedAnnotationIDs.first {
                    document.reorder(id, direction: .down)
                }
            }) {
                Image(systemName: "square.2.layers.3d.bottom.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.primaryText)
            }
            .buttonStyle(.borderless)
            .iconTip(.sendBackward)

            Divider().frame(height: 20)

            // Duplicate
            Button(action: { document.duplicateSelection() }) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.primaryText)
            }
            .buttonStyle(.borderless)
            .iconTip(.duplicate)

            // Delete
            Button(action: { document.deleteSelection() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .iconTip(.delete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
