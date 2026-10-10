import XCTest
@testable import Picelf

final class DimmingOverlayWindowTests: XCTestCase {
    func test_localHoleRect_translatesByWindowOrigin() {
        let hole = CGRect(x: 1560, y: 420, width: 480, height: 320)
        let windowFrame = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        let contentBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let local = DimmingOverlayWindow.localHoleRect(
            holeInScreen: hole,
            windowFrameInScreen: windowFrame,
            contentBounds: contentBounds
        )

        XCTAssertEqual(local.origin.x, 120, accuracy: 0.001)
        XCTAssertEqual(local.origin.y, 420, accuracy: 0.001)
        XCTAssertEqual(local.width, 480, accuracy: 0.001)
        XCTAssertEqual(local.height, 320, accuracy: 0.001)
    }

    func test_localHoleRect_clipsToContentBounds() {
        let hole = CGRect(x: 1300, y: -80, width: 400, height: 300)
        let windowFrame = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        let contentBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let local = DimmingOverlayWindow.localHoleRect(
            holeInScreen: hole,
            windowFrameInScreen: windowFrame,
            contentBounds: contentBounds
        )

        XCTAssertEqual(local.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(local.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(local.width, 260, accuracy: 0.001)
        XCTAssertEqual(local.height, 220, accuracy: 0.001)
    }
}
