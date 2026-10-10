import AppKit

/// A full-screen transparent window that dims everything outside the capture frame.
class DimmingOverlayWindow: NSWindow {
    private let backgroundLayer = CALayer()
    private let dimmingLayer = CAShapeLayer()
    private let holeRectProvider: () -> NSRect

    init(screen: NSScreen, backgroundImage: CGImage?, holeRect: @escaping () -> NSRect) {
        self.holeRectProvider = holeRect
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.frame = view.bounds
        view.layer = rootLayer
        self.contentView = view

        backgroundLayer.frame = view.bounds
        backgroundLayer.contentsGravity = .resize
        backgroundLayer.contents = backgroundImage
        rootLayer.addSublayer(backgroundLayer)

        dimmingLayer.frame = view.bounds
        rootLayer.addSublayer(dimmingLayer)

        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = NSColor.black.withAlphaComponent(0.15).cgColor
        updateHole()
    }

    func updateBackgroundImage(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.contents = image
        CATransaction.commit()
    }

    func setFrozenBackgroundVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.isHidden = !visible
        CATransaction.commit()
    }

    func updateHole() {
        guard let bounds = contentView?.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = bounds
        dimmingLayer.frame = bounds
        CATransaction.commit()

        let hole = holeRectProvider()
        let localHole = Self.localHoleRect(
            holeInScreen: hole,
            windowFrameInScreen: frame,
            contentBounds: bounds
        )

        let path = CGMutablePath()
        path.addRect(bounds)
        if !localHole.isNull, !localHole.isEmpty {
            path.addRect(localHole)
        }
        // Use CADisplayLink-friendly implicit animation (disabled for instant update)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimmingLayer.path = path
        CATransaction.commit()
    }

    static func localHoleRect(
        holeInScreen: CGRect,
        windowFrameInScreen: CGRect,
        contentBounds: CGRect
    ) -> CGRect {
        let translated = CGRect(
            x: holeInScreen.origin.x - windowFrameInScreen.origin.x,
            y: holeInScreen.origin.y - windowFrameInScreen.origin.y,
            width: holeInScreen.width,
            height: holeInScreen.height
        )
        return translated.intersection(contentBounds)
    }
}
