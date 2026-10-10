import SwiftUI

struct TextInlineEditorView: View {
    let initialText: String
    let textColor: Color
    let fontSize: CGFloat
    let onTextChange: (String) -> Void
    let onCommit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool
    @State private var hasEverFocused = false
    @State private var didCommit = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(L10n.localized("输入文本", "Enter text"))
                    .font(.system(size: max(12, fontSize), weight: .medium, design: .rounded))
                    .foregroundStyle(textColor.opacity(0.45))
                    .padding(.leading, 10)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.system(size: max(12, fontSize), weight: .medium, design: .rounded))
                .foregroundStyle(textColor)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($focused)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(EditorTheme.cardBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(EditorTheme.selectionStroke.opacity(0.9), lineWidth: 1)
        )
        .onAppear {
            text = initialText
            onTextChange(text)
            DispatchQueue.main.async {
                focused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                if !focused {
                    focused = true
                }
            }
        }
        .onChange(of: text) { _, newText in
            onTextChange(newText)
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                hasEverFocused = true
            } else if hasEverFocused {
                commitIfNeeded()
            }
        }
        .onDisappear {
            if hasEverFocused {
                commitIfNeeded()
            }
        }
    }

    private func commitIfNeeded() {
        guard !didCommit else { return }
        didCommit = true
        onCommit(text)
    }
}
