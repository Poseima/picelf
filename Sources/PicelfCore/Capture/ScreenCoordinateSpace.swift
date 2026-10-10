import AppKit

enum ScreenCoordinateSpace {
    /// AppKit global space uses a virtual desktop coordinate system (y-up),
    /// while CG screen space uses y-down. We flip around the virtual desktop's maxY.
    static func desktopMaxY() -> CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? 0
    }

    static func cgRectToAppKit(_ rect: CGRect, desktopMaxY: CGFloat = desktopMaxY()) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: desktopMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitRectToCG(_ rect: CGRect, desktopMaxY: CGFloat = desktopMaxY()) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: desktopMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitPointToCG(_ point: CGPoint, desktopMaxY: CGFloat = desktopMaxY()) -> CGPoint {
        CGPoint(x: point.x, y: desktopMaxY - point.y)
    }
}
