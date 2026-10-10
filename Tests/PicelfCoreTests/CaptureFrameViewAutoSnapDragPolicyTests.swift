import XCTest
@testable import Picelf

final class CaptureFrameViewAutoSnapDragPolicyTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let nonFullscreenFrame = CGRect(x: 220, y: 140, width: 1480, height: 860)

    func test_shouldRestart_whenAutoSnapSelectionReadyAndMoveInteraction() {
        XCTAssertTrue(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: false,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: nonFullscreenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldNotRestart_whenModeIsIdleSelecting() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: false,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: nonFullscreenFrame,
                screenFrame: screenFrame,
                mode: .idleSelecting,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldNotRestart_whenInteractionIsNotMove() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: false,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: nonFullscreenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: false
            )
        )
    }

    func test_shouldNotRestart_whenAutoSnapDisabled() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: false,
                isSnapEditing: false,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: nonFullscreenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldNotRestart_whenNoSelectedWindow() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: false,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: false,
                hasFrame: true,
                frameRect: nonFullscreenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldNotRestart_whenFrameIsEmpty() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: false,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: false,
                frameRect: .zero,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldRestart_whenSnapEditingAndFrameCoversScreenWithoutTool() {
        XCTAssertTrue(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: true,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: screenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldNotRestart_whenSnapEditingAndFrameDoesNotCoverScreen() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: true,
                isSnapEditingToolActive: false,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: nonFullscreenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }

    func test_shouldNotRestart_whenSnapEditingToolIsActiveEvenIfFullscreenFrame() {
        XCTAssertFalse(
            CaptureFrameView.shouldRestartFramingForAutoSnapDrag(
                autoSnapEnabled: true,
                isSnapEditing: true,
                isSnapEditingToolActive: true,
                isStitching: false,
                hasSelectedWindow: true,
                hasFrame: true,
                frameRect: screenFrame,
                screenFrame: screenFrame,
                mode: .selectionReady,
                isMoveInteraction: true
            )
        )
    }
}
