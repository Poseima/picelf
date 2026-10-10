import AppKit
import SwiftUI

@MainActor
final class CanvasWindowController {
    private var window: NSWindow?
    private var document: CanvasDocument?
    var workbenchStore: WorkbenchStore?

    func show(images: [NSImage] = []) {
        let doc: CanvasDocument
        if let existing = document {
            doc = existing
        } else {
            doc = CanvasDocument()
            document = doc
        }

        for (i, image) in images.enumerated() {
            let offset = CGPoint(x: CGFloat(i) * 20, y: CGFloat(i) * 20)
            doc.addImage(image, kind: .importedImage(sourceURL: nil), positionOffset: offset)
        }

        let root = CanvasView(document: doc)
        let rootView: AnyView
        if let store = workbenchStore {
            rootView = AnyView(root.environmentObject(store))
        } else {
            rootView = AnyView(root)
        }
        let hostingView = NSHostingView(rootView: rootView)

        let win: NSWindow
        if let existing = self.window {
            win = existing
        } else {
            win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.isReleasedWhenClosed = false
            win.titlebarAppearsTransparent = true
            win.appearance = NSAppearance(named: .darkAqua)
            win.toolbarStyle = .unifiedCompact
            win.isOpaque = false
            win.backgroundColor = .clear
            win.tabbingMode = .disallowed
            win.setFrameAutosaveName("Picelf.CanvasWindow")
            if !win.setFrameUsingName("Picelf.CanvasWindow") {
                win.center()
            }
            self.window = win
        }

        win.title = "Picelf — Canvas"
        win.contentView = hostingView
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func addItem(image: NSImage) {
        show() // ensure window is visible
        document?.addImage(image, kind: .importedImage(sourceURL: nil))
    }

    func newCanvas() {
        document = nil
        show()
    }
}
