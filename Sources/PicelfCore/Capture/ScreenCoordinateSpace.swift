import AppKit

enum ScreenCoordinateSpace {
    /// Both global coordinate systems are anchored to the primary display.
    /// NSScreen.main follows keyboard focus and is not necessarily that display.
    static func primaryScreenMaxY() -> CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func cgRectToAppKit(_ rect: CGRect, primaryScreenMaxY: CGFloat = primaryScreenMaxY()) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitRectToCG(_ rect: CGRect, primaryScreenMaxY: CGFloat = primaryScreenMaxY()) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitPointToCG(_ point: CGPoint, primaryScreenMaxY: CGFloat = primaryScreenMaxY()) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }
}
