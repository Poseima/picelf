import AppKit

/// Dedicated panel for in-frame snap editing.
/// Becomes key window so canvas gestures are reliable across app activation states.
final class SnapEditImagePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // Keep snap-edit canvas interactive even when Picelf is not the active app
            // (common in fullscreen and cross-app capture flows).
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isMovableByWindowBackground = false
        self.becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Canvas container used by snap edit so we can render a non-interactive border
/// while routing all pointer events directly to the canvas.
final class SnapEditCanvasContainerView: NSView {
    private let staticBorderLayer = CAShapeLayer()

    var showsStaticBorder: Bool = false {
        didSet { updateStaticBorderVisibility() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        updateStaticBorderPath()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        staticBorderLayer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.9).cgColor
        staticBorderLayer.fillColor = NSColor.clear.cgColor
        staticBorderLayer.lineWidth = 2
        staticBorderLayer.isHidden = true
        layer?.addSublayer(staticBorderLayer)
    }

    private func updateStaticBorderVisibility() {
        staticBorderLayer.isHidden = !showsStaticBorder
        updateStaticBorderPath()
    }

    private func updateStaticBorderPath() {
        guard let layer else { return }
        staticBorderLayer.frame = layer.bounds
        let inset: CGFloat = 1
        let borderRect = layer.bounds.insetBy(dx: inset, dy: inset)
        staticBorderLayer.path = CGPath(
            roundedRect: borderRect,
            cornerWidth: 3,
            cornerHeight: 3,
            transform: nil
        )
    }
}
