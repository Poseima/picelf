import AppKit
import SwiftUI

class StitchPreviewPanel: NSPanel {
    static let panelWidth: CGFloat = 220
    static let maxHeight: CGFloat = 600

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.panelWidth, height: 300)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        self.isFloatingPanel = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Position the preview panel to the right of the capture frame,
    /// clamped within the screen's visible area (excludes Dock and menu bar).
    func positionBeside(rect: CGRect, screen: NSScreen) {
        let gap: CGFloat = 12
        let safe = screen.visibleFrame
        var x = rect.maxX + gap
        let panelWidth = frame.width

        // If it would overflow the right edge, position to the left instead
        if x + panelWidth > safe.maxX - 8 {
            x = rect.minX - panelWidth - gap
        }
        x = max(safe.minX + 8, x)

        // Vertically align to the top of the capture frame
        var y = rect.maxY - frame.height
        y = max(safe.minY + 8, min(y, safe.maxY - frame.height - 8))

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func fitToContent() {
        guard let contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let fitting = contentView.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }

        let width = max(180, ceil(fitting.width))
        let height = min(Self.maxHeight, max(100, ceil(fitting.height)))
        setContentSize(NSSize(width: width, height: height))
    }
}
