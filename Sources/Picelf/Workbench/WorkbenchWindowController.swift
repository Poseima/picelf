import AppKit
import SwiftUI

@MainActor
final class WorkbenchWindowController {
    private let store: WorkbenchStore
    private var window: NSWindow?
    private var clipboardResponder: WorkbenchClipboardResponder?

    init(store: WorkbenchStore) {
        self.store = store
    }

    func show(activate: Bool) {
        let win = ensureWindow()
        win.collectionBehavior.insert(.moveToActiveSpace)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        } else {
            win.orderFrontRegardless()
        }
    }

    private func ensureWindow() -> NSWindow {
        if let existing = window {
            return existing
        }

        let clipboard = WorkbenchClipboardController(store: store)
        let root = WorkbenchView(store: store, clipboard: clipboard)
        let hosting = NSHostingView(rootView: root)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 820)
        let initialWidth = min(1280, screenFrame.width * 0.85)
        let initialHeight = min(820, screenFrame.height * 0.85)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Picelf Workbench"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unifiedCompact
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Picelf.WorkbenchWindow")
        if !window.setFrameUsingName("Picelf.WorkbenchWindow") {
            window.center()
        }
        window.contentView = hosting
        let responder = WorkbenchClipboardResponder(clipboard: clipboard)
        responder.window = window
        responder.nextResponder = window.nextResponder
        window.nextResponder = responder
        clipboard.focusGallery = { [weak window] in
            window?.makeFirstResponder(nil)
        }
        clipboardResponder = responder
        window.setAccessibilityIdentifier("workbench.window")
        self.window = window
        return window
    }
}
