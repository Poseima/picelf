import XCTest
@testable import Picelf

final class ScreenCoordinateSpaceTests: XCTestCase {
    func test_rectRoundTrip_preservesGeometry() {
        let desktopMaxY: CGFloat = 1440
        let cgRect = CGRect(x: -900, y: 220, width: 1280, height: 720)

        let appKitRect = ScreenCoordinateSpace.cgRectToAppKit(cgRect, desktopMaxY: desktopMaxY)
        let restored = ScreenCoordinateSpace.appKitRectToCG(appKitRect, desktopMaxY: desktopMaxY)

        XCTAssertEqual(restored.origin.x, cgRect.origin.x, accuracy: 0.001)
        XCTAssertEqual(restored.origin.y, cgRect.origin.y, accuracy: 0.001)
        XCTAssertEqual(restored.size.width, cgRect.size.width, accuracy: 0.001)
        XCTAssertEqual(restored.size.height, cgRect.size.height, accuracy: 0.001)
    }

    func test_pointConversion_usesVirtualDesktopMaxY() {
        let desktopMaxY: CGFloat = 1800
        let appKitPoint = CGPoint(x: -320, y: 250)

        let cgPoint = ScreenCoordinateSpace.appKitPointToCG(appKitPoint, desktopMaxY: desktopMaxY)

        XCTAssertEqual(cgPoint.x, -320, accuracy: 0.001)
        XCTAssertEqual(cgPoint.y, 1550, accuracy: 0.001)
    }
}
