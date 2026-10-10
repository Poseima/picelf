import XCTest
@testable import Picelf

final class CaptureOrchestratorMenuStartPolicyTests: XCTestCase {
    func test_shouldForceRestartForMenuStart_whenCapturing() {
        XCTAssertTrue(
            CaptureMenuStartPolicy.shouldForceRestart(
                isCapturing: true,
                isSnapEditing: false,
                isStitching: false,
                hasOverlayPanels: false
            )
        )
    }

    func test_shouldForceRestartForMenuStart_whenSnapEditing() {
        XCTAssertTrue(
            CaptureMenuStartPolicy.shouldForceRestart(
                isCapturing: false,
                isSnapEditing: true,
                isStitching: false,
                hasOverlayPanels: false
            )
        )
    }

    func test_shouldForceRestartForMenuStart_whenStitching() {
        XCTAssertTrue(
            CaptureMenuStartPolicy.shouldForceRestart(
                isCapturing: false,
                isSnapEditing: false,
                isStitching: true,
                hasOverlayPanels: false
            )
        )
    }

    func test_shouldForceRestartForMenuStart_whenOverlayPanelsAreActive() {
        XCTAssertTrue(
            CaptureMenuStartPolicy.shouldForceRestart(
                isCapturing: false,
                isSnapEditing: false,
                isStitching: false,
                hasOverlayPanels: true
            )
        )
    }

    func test_shouldNotForceRestartForMenuStart_whenIdle() {
        XCTAssertFalse(
            CaptureMenuStartPolicy.shouldForceRestart(
                isCapturing: false,
                isSnapEditing: false,
                isStitching: false,
                hasOverlayPanels: false
            )
        )
    }
}
