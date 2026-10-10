import AppKit
import SwiftUI

/// A non-activating floating panel that shows the capture frame overlay.
/// Does not steal focus from the target application.
class CaptureFramePanel: NSPanel {
    /// Called when arrow keys are pressed. Vector is in screen coordinates.
    var onArrowKey: ((CGVector) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let step: CGFloat = shift ? 10 : 1

        switch event.keyCode {
        case 123: onArrowKey?(CGVector(dx: -step, dy: 0))    // left
        case 124: onArrowKey?(CGVector(dx: step, dy: 0))     // right
        case 125: onArrowKey?(CGVector(dx: 0, dy: -step))    // down (screen: -Y)
        case 126: onArrowKey?(CGVector(dx: 0, dy: step))     // up (screen: +Y)
        case 36, 76: onConfirm?()                            // return / enter
        case 53: onCancel?()                                 // escape
        default: super.keyDown(with: event)
        }
    }
}
