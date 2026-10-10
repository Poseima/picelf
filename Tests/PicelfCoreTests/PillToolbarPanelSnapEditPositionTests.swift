import XCTest
@testable import Picelf

final class PillToolbarPanelSnapEditPositionTests: XCTestCase {
    func test_snapEditToolbarOrigin_prefersBelowWhenSpaceAllows() {
        let frameRect = CGRect(x: 300, y: 280, width: 360, height: 220)
        let safeRect = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let toolbarSize = CGSize(width: 340, height: 52)

        let origin = PillToolbarPanel.snapEditToolbarOrigin(
            frameRect: frameRect,
            safeRect: safeRect,
            toolbarSize: toolbarSize
        )

        XCTAssertEqual(origin.y, 216, accuracy: 0.001) // 280 - 52 - 12
    }

    func test_snapEditToolbarOrigin_fallsBackAboveWhenDockBlocksBelow() {
        let frameRect = CGRect(x: 220, y: 104, width: 520, height: 240)
        let safeRect = CGRect(x: 0, y: 96, width: 1440, height: 780) // Dock eats bottom area
        let toolbarSize = CGSize(width: 340, height: 52)

        let origin = PillToolbarPanel.snapEditToolbarOrigin(
            frameRect: frameRect,
            safeRect: safeRect,
            toolbarSize: toolbarSize
        )

        XCTAssertEqual(origin.y, 356, accuracy: 0.001) // 104 + 240 + 12
    }

    func test_snapEditToolbarOrigin_alwaysStaysWithinVisibleFrame() {
        let frameRect = CGRect(x: -200, y: 60, width: 2200, height: 980)
        let safeRect = CGRect(x: 80, y: 70, width: 1260, height: 730)
        let toolbarSize = CGSize(width: 460, height: 60)

        let origin = PillToolbarPanel.snapEditToolbarOrigin(
            frameRect: frameRect,
            safeRect: safeRect,
            toolbarSize: toolbarSize
        )

        XCTAssertGreaterThanOrEqual(origin.x, safeRect.minX + 8 - 0.001)
        XCTAssertLessThanOrEqual(origin.x + toolbarSize.width, safeRect.maxX - 8 + 0.001)
        XCTAssertGreaterThanOrEqual(origin.y, safeRect.minY + 8 - 0.001)
        XCTAssertLessThanOrEqual(origin.y + toolbarSize.height, safeRect.maxY - 8 + 0.001)
    }

    @MainActor
    func test_panelAcceptsMouseMovedEventsForHoverTooltips() {
        let panel = PillToolbarPanel()
        XCTAssertTrue(panel.acceptsMouseMovedEvents)
    }
}
