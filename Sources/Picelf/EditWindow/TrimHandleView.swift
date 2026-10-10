import SwiftUI

struct TrimHandleView: View {
    let position: CGFloat
    let isTop: Bool
    let onDrag: (CGFloat) -> Void

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(EditorTheme.selectedFill.opacity(isDragging ? 1.0 : 0.78))
            .frame(height: 4)
            .overlay(
                Capsule()
                    .fill(isDragging ? EditorTheme.accentStrong : EditorTheme.accent)
                    .frame(width: 40, height: 6)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        onDrag(value.translation.height)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
