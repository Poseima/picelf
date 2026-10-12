// Run this separate fixture app while running RecordingLiveTests from a signed test host.
import AppKit

final class RecordingMarkerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let size: CGFloat = 100
        let markers: [(CGRect, NSColor)] = [
            (CGRect(x: 0, y: bounds.height - size, width: size, height: size), .red),
            (CGRect(x: bounds.width - size, y: bounds.height - size, width: size, height: size), .green),
            (CGRect(x: 0, y: 0, width: size, height: size), .blue),
            (CGRect(x: bounds.width - size, y: 0, width: size, height: size), .yellow),
            (CGRect(x: bounds.midX - 50, y: bounds.midY - 50, width: size, height: size), .magenta)
        ]
        for (rect, color) in markers { color.setFill(); rect.fill() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var windows: [NSWindow] = []
for screen in NSScreen.screens {
    let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
    let frame = CGRect(x: screen.frame.midX - 400, y: screen.frame.midY - 300, width: 800, height: 600)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.title = "Picelf Recording Marker \(id)"
    window.isReleasedWhenClosed = false
    window.hasShadow = false
    window.level = .floating
    window.contentView = RecordingMarkerView(frame: CGRect(origin: .zero, size: frame.size))
    window.orderFrontRegardless()
    windows.append(window)
}
app.run()
