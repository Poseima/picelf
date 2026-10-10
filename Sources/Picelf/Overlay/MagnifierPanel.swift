import AppKit

class MagnifierPanel: NSPanel {
    private var magnifierView: MagnifierNSView?
    
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 140, height: 170)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false // Shadow handled by MagnifierNSView
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true
        
        setupMagnifierView()
    }
    
    private func setupMagnifierView() {
        let view = MagnifierNSView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
        contentView = view
        magnifierView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    /// Update magnifier content with a single call (combines image + color).
    func update(cgImage: CGImage, hexColor: String) {
        magnifierView?.update(cgImage: cgImage, hexColor: hexColor)
    }

    func reposition(near point: CGPoint, on screen: NSScreen) {
        let offset: CGFloat = 20
        var origin = CGPoint(x: point.x + offset, y: point.y - frame.height - offset)

        if origin.x + frame.width > screen.visibleFrame.maxX {
            origin.x = point.x - frame.width - offset
        }
        if origin.y < screen.visibleFrame.minY {
            origin.y = point.y + offset
        }

        setFrameOrigin(origin)
    }
}
