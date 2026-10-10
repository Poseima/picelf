import AppKit
import SwiftUI
import ImageIO

@MainActor
class PinnedImagePanel: NSPanel {

    let pinID: UUID
    var sourceImageURL: URL?
    var zoomScale: CGFloat = 1.0
    var pinOpacity: CGFloat = 1.0
    var originalImageSize: CGSize

    private var dragStart: NSPoint?
    private var currentImage: NSImage

    var onEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onClose: (() -> Void)?
    var onExtractSubject: (() -> Void)?
    var onBindingChanged: ((PinBinding) -> Void)?
    var currentBinding: PinBinding = .allDesktops

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(pinID: UUID, image: NSImage, originalImageSize: CGSize) {
        self.pinID = pinID
        self.originalImageSize = originalImageSize
        self.currentImage = image // temporary, will be downscaled below

        // Cap initial display size to 600x600 points while preserving aspect ratio
        let maxDim: CGFloat = 600
        let scale = min(1.0, maxDim / max(originalImageSize.width, originalImageSize.height))
        let displaySize = NSSize(
            width: round(originalImageSize.width * scale),
            height: round(originalImageSize.height * scale)
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: displaySize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = false

        // If the initial display required down-scaling, record that as zoomScale
        if scale < 1.0 {
            self.zoomScale = scale
        }

        // Downscale to display resolution to avoid holding huge images in memory
        self.currentImage = Self.downsampleForDisplay(image, targetSize: displaySize)

        let hostingView = NSHostingView(
            rootView: PinnedImageView(image: currentImage)
        )
        hostingView.frame = NSRect(origin: .zero, size: displaySize)
        self.contentView = hostingView
    }

    // MARK: - Public

    func updateImage(_ image: NSImage) {
        let displaySize = frame.size
        currentImage = Self.downsampleForDisplay(image, targetSize: displaySize)
        rebuildHostingView()
    }

    func applyZoom() {
        let newSize = NSSize(
            width: round(originalImageSize.width * zoomScale),
            height: round(originalImageSize.height * zoomScale)
        )
        setContentSize(newSize)
        rebuildHostingView()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        if event.clickCount == 2 {
            onClose?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = event.locationInWindow
        let delta = CGPoint(
            x: current.x - start.x,
            y: current.y - start.y
        )
        setFrameOrigin(CGPoint(
            x: frame.origin.x + delta.x,
            y: frame.origin.y + delta.y
        ))
    }

    override func scrollWheel(with event: NSEvent) {
        let factor = 1 + event.deltaY * 0.03
        let newScale = max(0.1, min(5.0, zoomScale * factor))
        applyZoomAnchored(newScale: newScale, anchorInScreen: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        let factor = 1 + event.magnification
        let newScale = max(0.1, min(5.0, zoomScale * factor))
        applyZoomAnchored(newScale: newScale, anchorInScreen: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contentView = self.contentView else { return }

        let menu = NSMenu()

        // Edit
        let editItem = NSMenuItem(title: L10n.pinEdit, action: #selector(menuEdit), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        // Copy
        let copyItem = NSMenuItem(title: L10n.copy, action: #selector(menuCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        // Save As...
        let saveItem = NSMenuItem(title: L10n.pinSaveAs, action: #selector(menuSaveAs), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        // Remove Background
        let extractItem = NSMenuItem(title: L10n.removeBackground, action: #selector(menuExtractSubject), keyEquivalent: "")
        extractItem.target = self
        menu.addItem(extractItem)

        menu.addItem(.separator())

        // Opacity submenu
        let opacityItem = NSMenuItem(title: L10n.pinOpacity, action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()

        for pct in [100, 75, 50, 25] {
            let item = NSMenuItem(
                title: "\(pct)%",
                action: #selector(menuSetOpacity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = pct
            if Int(round(pinOpacity * 100)) == pct {
                item.state = .on
            }
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        // Bind to... submenu
        let bindItem = NSMenuItem(title: L10n.pinBindTo, action: nil, keyEquivalent: "")
        bindItem.submenu = buildBindingSubmenu()
        menu.addItem(bindItem)

        menu.addItem(.separator())

        // Close
        let closeItem = NSMenuItem(title: L10n.pinClose, action: #selector(menuClose), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    // MARK: - Menu Actions

    @objc private func menuEdit() {
        onEdit?()
    }

    @objc private func menuCopy() {
        onCopy?()
    }

    @objc private func menuSaveAs() {
        onSaveAs?()
    }

    @objc private func menuExtractSubject() {
        onExtractSubject?()
    }

    @objc private func menuSetOpacity(_ sender: NSMenuItem) {
        let pct = CGFloat(sender.tag) / 100.0
        pinOpacity = pct
        alphaValue = pct
    }

    @objc private func menuClose() {
        onClose?()
    }

    // MARK: - Binding Menu

    private func buildBindingSubmenu() -> NSMenu {
        let sub = NSMenu()

        // All Desktops
        let allItem = NSMenuItem(title: L10n.pinAllDesktops, action: #selector(menuBindAllDesktops), keyEquivalent: "")
        allItem.target = self
        if case .allDesktops = currentBinding { allItem.state = .on }
        sub.addItem(allItem)

        // Current Desktop Only
        let curItem = NSMenuItem(title: L10n.pinCurrentDesktop, action: #selector(menuBindCurrentDesktop), keyEquivalent: "")
        curItem.target = self
        if case .currentDesktopOnly = currentBinding { curItem.state = .on }
        sub.addItem(curItem)

        // Desktop (like desktop icons)
        let desktopItem = NSMenuItem(title: L10n.pinDesktop, action: #selector(menuBindDesktop), keyEquivalent: "")
        desktopItem.target = self
        if case .desktop = currentBinding { desktopItem.state = .on }
        sub.addItem(desktopItem)

        // Screens
        let screens = PinBindingMonitor.availableScreens()
        if !screens.isEmpty {
            sub.addItem(.separator())
            for screen in screens {
                let item = NSMenuItem(
                    title: L10n.pinScreen(screen.name),
                    action: #selector(menuBindScreen(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = Int(screen.displayID)
                item.representedObject = screen.name
                if case .screen(let id, _) = currentBinding, id == screen.displayID {
                    item.state = .on
                }
                sub.addItem(item)
            }
        }

        // Windows
        let windows = PinBindingMonitor.availableWindows()
        if !windows.isEmpty {
            sub.addItem(.separator())
            for win in windows {
                let item = NSMenuItem(
                    title: L10n.pinWindow(win.appName, win.title),
                    action: #selector(menuBindWindow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = win
                if case .window(let bid, _, let t) = currentBinding, bid == win.bundleID && t == win.title {
                    item.state = .on
                }
                sub.addItem(item)
            }
        }

        return sub
    }

    @objc private func menuBindAllDesktops() {
        currentBinding = .allDesktops
        onBindingChanged?(.allDesktops)
    }

    @objc private func menuBindCurrentDesktop() {
        currentBinding = .currentDesktopOnly
        onBindingChanged?(.currentDesktopOnly)
    }

    @objc private func menuBindDesktop() {
        currentBinding = .desktop
        onBindingChanged?(.desktop)
    }

    @objc private func menuBindScreen(_ sender: NSMenuItem) {
        let displayID = UInt32(sender.tag)
        let name = sender.representedObject as? String ?? ""
        let binding = PinBinding.screen(displayID: displayID, displayName: name)
        currentBinding = binding
        onBindingChanged?(binding)
    }

    @objc private func menuBindWindow(_ sender: NSMenuItem) {
        guard let win = sender.representedObject as? (bundleID: String, appName: String, title: String) else { return }
        let binding = PinBinding.window(appBundleID: win.bundleID, appName: win.appName, windowTitle: win.title)
        currentBinding = binding
        onBindingChanged?(binding)
    }

    // MARK: - Private

    private func applyZoomAnchored(newScale: CGFloat, anchorInScreen: NSPoint) {
        let anchorInPanel = CGPoint(
            x: anchorInScreen.x - frame.origin.x,
            y: anchorInScreen.y - frame.origin.y
        )
        let anchorFractionX = anchorInPanel.x / frame.width
        let anchorFractionY = anchorInPanel.y / frame.height

        zoomScale = newScale

        let newSize = NSSize(
            width: round(originalImageSize.width * zoomScale),
            height: round(originalImageSize.height * zoomScale)
        )

        let newOrigin = CGPoint(
            x: anchorInScreen.x - newSize.width * anchorFractionX,
            y: anchorInScreen.y - newSize.height * anchorFractionY
        )

        setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        rebuildHostingView()
    }

    private func rebuildHostingView() {
        // Reload from disk at current display resolution on zoom
        if let url = sourceImageURL, let fullImage = NSImage(contentsOf: url) {
            currentImage = Self.downsampleForDisplay(fullImage, targetSize: frame.size)
        }
        let hostingView = NSHostingView(
            rootView: PinnedImageView(image: currentImage)
        )
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        self.contentView = hostingView
    }

    /// Downsample image to fit target display size (in points × screen scale).
    /// Returns original if already small enough.
    private static func downsampleForDisplay(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let targetPixelW = targetSize.width * backingScale
        let targetPixelH = targetSize.height * backingScale

        // No need to downsample if image is already small
        guard image.size.width > targetPixelW * 1.5 || image.size.height > targetPixelH * 1.5 else {
            return image
        }

        let newSize = NSSize(width: targetPixelW, height: targetPixelH)
        let downscaled = NSImage(size: newSize)
        downscaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        downscaled.unlockFocus()
        return downscaled
    }
}
