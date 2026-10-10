import XCTest
@testable import Picelf

final class CaptureOrchestratorInputPolicyTests: XCTestCase {
    func test_shouldIgnoreFramePanelMouseEvents_whenCapturing() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldIgnoreFramePanelMouseEvents(
                isCapturing: true,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: false,
                selectedTool: nil
            )
        )
    }

    func test_shouldIgnoreFramePanelMouseEvents_whenRecording() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldIgnoreFramePanelMouseEvents(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: true,
                isSnapEditing: false,
                selectedTool: nil
            )
        )
    }

    func test_shouldIgnoreFramePanelMouseEvents_whenPreparingRecording() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldIgnoreFramePanelMouseEvents(
                isCapturing: false,
                isPreparingRecording: true,
                isRecording: false,
                isSnapEditing: false,
                selectedTool: nil
            )
        )
    }

    func test_shouldIgnoreFramePanelMouseEvents_whenSnapEditingWithTool() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldIgnoreFramePanelMouseEvents(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: true,
                selectedTool: .pencil
            )
        )
    }

    func test_shouldNotIgnoreFramePanelMouseEvents_whenSnapEditingWithoutTool() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldIgnoreFramePanelMouseEvents(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: true,
                selectedTool: nil
            )
        )
    }

    func test_shouldNotIgnoreFramePanelMouseEvents_whenIdle() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldIgnoreFramePanelMouseEvents(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: false,
                selectedTool: .pencil
            )
        )
    }

    func test_shouldIgnoreSnapEditImagePanelMouseEvents_whenSnapEditingWithoutTool() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldIgnoreSnapEditImagePanelMouseEvents(
                isSnapEditing: true,
                selectedTool: nil
            )
        )
    }

    func test_shouldNotIgnoreSnapEditImagePanelMouseEvents_whenSnapEditingWithTool() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldIgnoreSnapEditImagePanelMouseEvents(
                isSnapEditing: true,
                selectedTool: .pencil
            )
        )
    }

    func test_shouldNotIgnoreSnapEditImagePanelMouseEvents_whenNotSnapEditing() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldIgnoreSnapEditImagePanelMouseEvents(
                isSnapEditing: false,
                selectedTool: nil
            )
        )
    }

    func test_shouldShowFrozenBackground_whenIdle() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldShowFrozenBackground(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: false,
                showsLiveContentInFrame: false
            )
        )
    }

    func test_shouldShowFrozenBackground_whenPreparingRecording() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldShowFrozenBackground(
                isCapturing: false,
                isPreparingRecording: true,
                isRecording: false,
                isSnapEditing: false,
                showsLiveContentInFrame: false
            )
        )
    }

    func test_shouldHideFrozenBackground_whenRecording() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldShowFrozenBackground(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: true,
                isSnapEditing: false,
                showsLiveContentInFrame: true
            )
        )
    }

    func test_shouldShowFrozenBackground_whenCaptureHasNotStartedStreaming() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldShowFrozenBackground(
                isCapturing: true,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: false,
                showsLiveContentInFrame: false
            )
        )
    }

    func test_shouldHideFrozenBackground_whenCaptureStreamIsLive() {
        XCTAssertFalse(
            CaptureOrchestrator.shouldShowFrozenBackground(
                isCapturing: true,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: false,
                showsLiveContentInFrame: true
            )
        )
    }

    func test_shouldShowFrozenBackground_whenSnapEditing() {
        XCTAssertTrue(
            CaptureOrchestrator.shouldShowFrozenBackground(
                isCapturing: false,
                isPreparingRecording: false,
                isRecording: false,
                isSnapEditing: true,
                showsLiveContentInFrame: false
            )
        )
    }
}
