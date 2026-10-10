import XCTest
@testable import Picelf

@MainActor
final class SnapEditImagePanelInteractionTests: XCTestCase {
    func test_panelIsNonActivating_forCrossAppEditing() {
        let panel = SnapEditImagePanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120))

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    func test_panelCanBecomeKey_forCanvasFocus() {
        let panel = SnapEditImagePanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120))

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }
}
