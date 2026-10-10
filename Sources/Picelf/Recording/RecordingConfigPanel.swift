import AppKit
import SwiftUI

final class RecordingConfigPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = false
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func positionBelow(rect: CGRect, on screen: NSScreen) {
        let safe = screen.visibleFrame
        let x = rect.midX - frame.width / 2
        let y = rect.maxY - frame.height - 8
        let clamped = NSRect(
            x: max(safe.minX + 8, min(x, safe.maxX - frame.width - 8)),
            y: max(safe.minY + 8, y),
            width: frame.width,
            height: frame.height
        )
        setFrame(clamped, display: true)
    }
}
