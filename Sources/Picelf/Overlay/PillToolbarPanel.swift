import AppKit
import SwiftUI

class PillToolbarPanel: NSPanel {
    static let preferredSize = NSSize(width: 340, height: 52)
    static let minSize = NSSize(width: 150, height: 44)
    nonisolated(unsafe) private static let edgeInset: CGFloat = 8
    nonisolated(unsafe) private static let anchorGap: CGFloat = 12

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.preferredSize),
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
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentMinSize = Self.minSize
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Position the toolbar centered above the given frame rect,
    /// clamped within the screen's visible area (excludes Dock and menu bar).
    func positionAbove(rect: CGRect, screen: NSScreen) {
        let toolbarWidth = frame.width
        let safe = screen.visibleFrame

        var x = rect.midX - toolbarWidth / 2
        x = min(max(safe.minX + Self.edgeInset, x), safe.maxX - toolbarWidth - Self.edgeInset)

        var y = rect.maxY + Self.anchorGap
        if y + frame.height > safe.maxY - Self.edgeInset {
            y = rect.minY - frame.height - Self.anchorGap
        }
        if y < safe.minY + Self.edgeInset {
            // Below-frame position overlaps Dock → force above, clamp to visible area
            y = max(rect.maxY + Self.anchorGap, safe.minY + Self.edgeInset)
        }
        y = min(y, safe.maxY - frame.height - Self.edgeInset)
        y = max(safe.minY + Self.edgeInset, y)

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Position used by snap-edit mode:
    /// prefer below-frame; if blocked by Dock/visibleFrame, fallback above-frame.
    func positionForSnapEdit(rect: CGRect, screen: NSScreen) {
        let origin = Self.snapEditToolbarOrigin(
            frameRect: rect,
            safeRect: screen.visibleFrame,
            toolbarSize: frame.size
        )
        setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
    }

    nonisolated static func snapEditToolbarOrigin(
        frameRect: CGRect,
        safeRect: CGRect,
        toolbarSize: CGSize
    ) -> CGPoint {
        let minX = safeRect.minX + edgeInset
        let maxX = safeRect.maxX - toolbarSize.width - edgeInset
        let x: CGFloat
        if maxX >= minX {
            let centeredX = frameRect.midX - toolbarSize.width / 2
            x = min(max(minX, centeredX), maxX)
        } else {
            x = safeRect.minX
        }

        let minY = safeRect.minY + edgeInset
        let maxY = safeRect.maxY - toolbarSize.height - edgeInset
        guard maxY >= minY else {
            return CGPoint(x: x, y: safeRect.minY)
        }

        let belowY = frameRect.minY - toolbarSize.height - anchorGap
        let aboveY = frameRect.maxY + anchorGap
        let canPlaceBelow = belowY >= minY
        let canPlaceAbove = aboveY <= maxY

        let preferredY: CGFloat
        if canPlaceBelow {
            preferredY = belowY
        } else if canPlaceAbove {
            preferredY = aboveY
        } else {
            // Both sides are constrained: keep as close as possible to the frame.
            let clampedBelow = min(max(minY, belowY), maxY)
            let clampedAbove = min(max(minY, aboveY), maxY)
            let distanceBelow = abs((clampedBelow + toolbarSize.height + anchorGap) - frameRect.minY)
            let distanceAbove = abs(clampedAbove - (frameRect.maxY + anchorGap))
            preferredY = distanceBelow <= distanceAbove ? clampedBelow : clampedAbove
        }

        return CGPoint(x: x, y: min(max(minY, preferredY), maxY))
    }

    /// Position the toolbar centered below the given frame rect.
    func positionBelow(rect: CGRect, screen: NSScreen) {
        let safe = screen.visibleFrame
        var x = rect.midX - frame.width / 2
        x = min(max(safe.minX + Self.edgeInset, x), safe.maxX - frame.width - Self.edgeInset)
        var y = rect.minY - frame.height - Self.anchorGap
        y = max(safe.minY + Self.edgeInset, y)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func fitToContent() {
        guard let contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let fitting = contentView.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }

        let width = max(Self.minSize.width, ceil(fitting.width))
        let height = max(Self.minSize.height, ceil(fitting.height))
        setContentSize(NSSize(width: width, height: height))
    }
}
