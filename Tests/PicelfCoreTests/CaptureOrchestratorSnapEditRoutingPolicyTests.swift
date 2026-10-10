import XCTest
@testable import Picelf

final class CaptureOrchestratorSnapEditRoutingPolicyTests: XCTestCase {
    func test_routingMode_isInactive_whenNotSnapEditing() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditRoutingMode(
                isSnapEditing: false,
                selectedTool: .pencil
            ),
            .inactive
        )
    }

    func test_routingMode_isFrameAdjust_whenSnapEditingWithoutTool() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditRoutingMode(
                isSnapEditing: true,
                selectedTool: nil
            ),
            .frameAdjust
        )
    }

    func test_routingMode_isCanvasEdit_whenSnapEditingWithTool() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditRoutingMode(
                isSnapEditing: true,
                selectedTool: .rectangle
            ),
            .canvasEdit
        )
    }

    func test_panelPresentation_hidesFrame_andShowsStaticBorder_whenCanvasEdit() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditPanelPresentation(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: true,
                selectedTool: .rectangle
            ),
            SnapEditPanelPresentation(
                framePanelVisible: false,
                framePanelIgnoresMouseEvents: true,
                snapEditPanelIgnoresMouseEvents: false,
                showsStaticBorder: true,
                isToolActive: true
            )
        )
    }

    func test_panelPresentation_showsInteractiveFrame_whenFrameAdjust() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditPanelPresentation(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: true,
                selectedTool: nil
            ),
            SnapEditPanelPresentation(
                framePanelVisible: true,
                framePanelIgnoresMouseEvents: false,
                snapEditPanelIgnoresMouseEvents: true,
                showsStaticBorder: false,
                isToolActive: false
            )
        )
    }

    func test_panelPresentation_inactive_state_respectsCaptureInputPolicy() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditPanelPresentation(
                isCapturing: true,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: false,
                selectedTool: nil
            ),
            SnapEditPanelPresentation(
                framePanelVisible: true,
                framePanelIgnoresMouseEvents: true,
                snapEditPanelIgnoresMouseEvents: false,
                showsStaticBorder: false,
                isToolActive: false
            )
        )
    }

    func test_panelPresentation_inactive_state_respectsRecordingInputPolicy() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditPanelPresentation(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: true,
                isSnapEditing: false,
                selectedTool: nil
            ),
            SnapEditPanelPresentation(
                framePanelVisible: false,
                framePanelIgnoresMouseEvents: true,
                snapEditPanelIgnoresMouseEvents: true,
                showsStaticBorder: false,
                isToolActive: false
            )
        )
    }

    func test_panelPresentation_inactive_state_respectsPreparingRecordingInputPolicy() {
        XCTAssertEqual(
            CaptureOrchestrator.snapEditPanelPresentation(
                isCapturing: false,
                isPreparingRecording: true,
                isRecording: false,
                isSnapEditing: false,
                selectedTool: nil
            ),
            SnapEditPanelPresentation(
                framePanelVisible: false,
                framePanelIgnoresMouseEvents: true,
                snapEditPanelIgnoresMouseEvents: true,
                showsStaticBorder: false,
                isToolActive: false
            )
        )
    }
}
