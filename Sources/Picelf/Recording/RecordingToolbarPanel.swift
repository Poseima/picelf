import AppKit
import SwiftUI

final class RecordingToolbarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating + 1
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    func positionTopCenter(on screen: NSScreen) {
        let safe = screen.visibleFrame
        let x = safe.midX - frame.width / 2
        let y = safe.maxY - frame.height - 24
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
