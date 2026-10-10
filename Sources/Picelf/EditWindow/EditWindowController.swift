import AppKit
import SwiftUI

class EditWindowController {
    private var window: NSWindow?
    var onPinImage: ((NSImage) -> Void)?
    var workbenchStore: WorkbenchStore?

    func show(
        image: NSImage,
        sourceURL: URL? = nil,
        autoOCR: Bool = false,
        autoExtract: Bool = false,
        autoTranslate: Bool = false,
        applyWatermark: Bool = true,
        relayEditor: RelayMacLiveEditor? = nil
    ) {
        let editView = EditView(
            originalImage: image,
            sourceURL: sourceURL,
            autoOCR: autoOCR,
            autoExtract: autoExtract,
            autoTranslate: autoTranslate,
            applyWatermark: applyWatermark,
            onPinImage: onPinImage,
            relayEditor: relayEditor
        )
        let rootView: AnyView
        if let store = workbenchStore {
            rootView = AnyView(editView.environmentObject(store))
        } else {
            rootView = AnyView(editView)
        }
        let hostingView = NSHostingView(rootView: rootView)

        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 840)
            let initialWidth = min(1280, screenFrame.width * 0.85)
            let initialHeight = min(840, screenFrame.height * 0.85)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.toolbarStyle = .unifiedCompact
            window.isOpaque = false
            window.backgroundColor = .clear
            window.tabbingMode = .disallowed
            window.setFrameAutosaveName("Picelf.EditorWindow")
            if !window.setFrameUsingName("Picelf.EditorWindow") {
                window.center()
            }
            self.window = window
        }

        window.title = "Picelf — Editor"
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
