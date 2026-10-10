import AppKit
import SwiftUI

/// Ensures the first click after entering framing is delivered to SwiftUI gestures.
final class FirstMousePassthroughHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
