import XCTest
@testable import Picelf

final class CaptureOrchestratorAutoSnapClickTests: XCTestCase {
    private var originalSharedPreferences: AppPreferences?
    private var suiteName: String = ""

    override func setUp() {
        super.setUp()
        suiteName = "com.picelf.tests.auto-snap-click.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        originalSharedPreferences = AppPreferences.shared
        AppPreferences.shared = AppPreferences(defaults: defaults)
    }

    override func tearDown() {
        if let originalSharedPreferences {
            AppPreferences.shared = originalSharedPreferences
        }
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func test_clickInsideAutoSnappedFrameCommitsSelection() {
        let orchestrator = CaptureOrchestrator()
        orchestrator.framePanel = CaptureFramePanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        orchestrator.captureState.mode = .idleSelecting
        orchestrator.captureState.frameRect = CGRect(x: 100, y: 120, width: 300, height: 220)
        orchestrator.captureState.selectedWindowID = 42
        AppPreferences.shared.autoSnapToWindows = true

        let committed = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 150, y: 150),
            timestamp: 1.0,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertTrue(committed)
        XCTAssertEqual(orchestrator.captureState.mode, .selectionReady)
    }

    @MainActor
    func test_clickDoesNotCommitWhenAutoSnapDisabled() {
        let orchestrator = CaptureOrchestrator()
        orchestrator.framePanel = CaptureFramePanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        orchestrator.captureState.mode = .idleSelecting
        orchestrator.captureState.frameRect = CGRect(x: 100, y: 120, width: 300, height: 220)
        orchestrator.captureState.selectedWindowID = 42
        AppPreferences.shared.autoSnapToWindows = false

        let committed = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 150, y: 150),
            timestamp: 1.0,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertFalse(committed)
        XCTAssertEqual(orchestrator.captureState.mode, .idleSelecting)
    }

    @MainActor
    func test_clickOutsideFrameDoesNotCommit() {
        let orchestrator = CaptureOrchestrator()
        orchestrator.framePanel = CaptureFramePanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        orchestrator.captureState.mode = .idleSelecting
        orchestrator.captureState.frameRect = CGRect(x: 100, y: 120, width: 300, height: 220)
        orchestrator.captureState.selectedWindowID = 42
        AppPreferences.shared.autoSnapToWindows = true

        let committed = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 50, y: 50),
            timestamp: 1.0,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertFalse(committed)
        XCTAssertEqual(orchestrator.captureState.mode, .idleSelecting)
    }

    @MainActor
    func test_clickDoesNotCommitWhenSnapEditing() {
        let orchestrator = CaptureOrchestrator()
        orchestrator.framePanel = CaptureFramePanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        orchestrator.captureState.mode = .idleSelecting
        orchestrator.captureState.frameRect = CGRect(x: 100, y: 120, width: 300, height: 220)
        orchestrator.captureState.selectedWindowID = 42
        orchestrator.captureState.isSnapEditing = true
        AppPreferences.shared.autoSnapToWindows = true

        let committed = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 150, y: 150),
            timestamp: 1.0,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertFalse(committed)
        XCTAssertEqual(orchestrator.captureState.mode, .idleSelecting)
    }

    @MainActor
    func test_duplicateTimestampClickIsIgnored() {
        let orchestrator = CaptureOrchestrator()
        orchestrator.framePanel = CaptureFramePanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        orchestrator.captureState.mode = .idleSelecting
        orchestrator.captureState.frameRect = CGRect(x: 100, y: 120, width: 300, height: 220)
        orchestrator.captureState.selectedWindowID = 42
        AppPreferences.shared.autoSnapToWindows = true

        let firstCommit = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 150, y: 150),
            timestamp: 123.456,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        // Reset mode to isolate dedupe behavior from state-machine guard.
        orchestrator.captureState.mode = .idleSelecting

        let secondCommit = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 150, y: 150),
            timestamp: 123.456,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertTrue(firstCommit)
        XCTAssertFalse(secondCommit)
    }

    @MainActor
    func test_pointerUpDoesNotCommitWhenDragIsInProgress() {
        let orchestrator = CaptureOrchestrator()
        orchestrator.framePanel = CaptureFramePanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        orchestrator.captureState.mode = .dragSelecting
        orchestrator.captureState.frameRect = CGRect(x: 100, y: 120, width: 300, height: 220)
        orchestrator.captureState.selectedWindowID = 42
        AppPreferences.shared.autoSnapToWindows = true

        let committed = orchestrator.tryCommitAutoSnapOnPointerUp(
            at: CGPoint(x: 150, y: 150),
            timestamp: 10.0,
            screenFrameOverride: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        XCTAssertFalse(committed)
        XCTAssertEqual(orchestrator.captureState.mode, .dragSelecting)
    }
}
