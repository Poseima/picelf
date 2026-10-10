import SwiftUI
import AppKit

struct ScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let scroll = view.enclosingScrollView {
                onResolve(scroll)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scroll = nsView.enclosingScrollView {
                onResolve(scroll)
            }
        }
    }
}
