import AppKit
import XCTest
@testable import Picelf

final class RecordingDisplayGeometryTests: XCTestCase {
    private func snapshot(
        frame: CGRect = CGRect(x: 1728, y: 0, width: 2560, height: 1440),
        scale: CGFloat = 1,
        rotation: Double = 0,
        pixels: RecordingPixelSize = RecordingPixelSize(width: 2560, height: 1440),
        primaryID: CGDirectDisplayID = 1,
        primaryFrame: CGRect = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    ) -> RecordingDisplaySnapshot {
        RecordingDisplaySnapshot(
            displayID: 3,
            appKitFrame: ScreenCoordinateSpace.cgRectToAppKit(frame, primaryScreenMaxY: primaryFrame.maxY),
            cgFrame: frame, pointPixelScale: scale, rotation: rotation,
            modePixelSize: pixels, primaryDisplayID: primaryID, primaryFrame: primaryFrame
        )
    }

    func test_geometryUsesLocalPointsForAllDisplayPositionsAndScales() throws {
        let frames = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 1728, y: 0, width: 2560, height: 1440),
            CGRect(x: -2560, y: 250, width: 2560, height: 1440),
            CGRect(x: 200, y: -1920, width: 1080, height: 1920),
            CGRect(x: -100, y: 1117, width: 3440, height: 1440)
        ]
        for frame in frames {
            for scale: CGFloat in [1, 1.25, 1.5, 2, 3] {
                let region = CGRect(x: frame.minX + 80, y: frame.minY + 120, width: 400, height: 240)
                let selection = try RecordingSelection(display: snapshot(frame: frame, scale: scale), desktopRegion: DesktopRecordingRect(rect: region))
                XCTAssertEqual(selection.region.rect, CGRect(x: 80, y: 120, width: 400, height: 240))
                let geometry = try XCTUnwrap(ScreenRecorder.resolveGeometry(contentRect: frame, requestedSourceRect: selection.desktopRegion.rect, scaleFactor: scale, resolution: .original))
                XCTAssertEqual(geometry.sourceRect, selection.region.rect)
                XCTAssertEqual(geometry.outputWidth, Int(400 * scale))
                XCTAssertEqual(geometry.outputHeight, Int(240 * scale))
            }
        }
    }

    func test_crossScreenSelectionIsClampedToChosenDisplay() throws {
        let selected = try RecordingSelection(display: snapshot(), desktopRegion: DesktopRecordingRect(rect: CGRect(x: 1600, y: -20, width: 500, height: 400)))
        XCTAssertEqual(selected.region.rect, CGRect(x: 0, y: 0, width: 372, height: 380))
        XCTAssertEqual(selected.desktopRegion.rect, CGRect(x: 1728, y: 0, width: 372, height: 380))
    }

    func test_primaryAnchoredConversionHasKnownExpectedPositions() {
        let cases: [(CGRect, CGRect)] = [
            (CGRect(x: 1728, y: 0, width: 2560, height: 1440), CGRect(x: 1728, y: -323, width: 2560, height: 1440)),
            (CGRect(x: 0, y: -1440, width: 2560, height: 1440), CGRect(x: 0, y: 1117, width: 2560, height: 1440)),
            (CGRect(x: -1080, y: 100, width: 1080, height: 1920), CGRect(x: -1080, y: -903, width: 1080, height: 1920))
        ]
        for (cg, appKit) in cases {
            XCTAssertEqual(ScreenCoordinateSpace.cgRectToAppKit(cg, primaryScreenMaxY: 1117), appKit)
            XCTAssertEqual(ScreenCoordinateSpace.appKitRectToCG(appKit, primaryScreenMaxY: 1117), cg)
        }
        // An upper monitor's maxY is 2557; it must not become the conversion baseline.
        XCTAssertEqual(ScreenCoordinateSpace.appKitPointToCG(CGPoint(x: 50, y: 1200), primaryScreenMaxY: 1117), CGPoint(x: 50, y: -83))
    }

    func test_invalidRegionsAndScalesAreRejectedWithoutIntegerOverflow() {
        let valid = CGRect(x: 0, y: 0, width: 100, height: 100)
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(ScreenRecorder.resolveGeometry(contentRect: valid, requestedSourceRect: nil, scaleFactor: scale, resolution: .original))
        }
        for rect in [CGRect.zero, CGRect.null, CGRect.infinite, CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 20)] {
            XCTAssertNil(ScreenRecorder.resolveGeometry(contentRect: rect, requestedSourceRect: nil, scaleFactor: 2, resolution: .original))
        }
        for rect in [CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 101, y: 0, width: 10, height: 10), CGRect.infinite, CGRect(x: 0, y: CGFloat.nan, width: 10, height: 10)] {
            XCTAssertNil(ScreenRecorder.resolveGeometry(contentRect: valid, requestedSourceRect: rect, scaleFactor: 1, resolution: .original))
        }
    }

    func test_fractionalCropRoundsOutwardsAndTrimsOnlyTrailingOddPixels() throws {
        let geometry = try XCTUnwrap(ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: -500, y: -200, width: 100, height: 100),
            requestedSourceRect: CGRect(x: -499.7, y: -199.7, width: 10, height: 12),
            scaleFactor: 1.5, resolution: .original
        ))
        XCTAssertEqual(geometry.sourceRect, CGRect(x: 0, y: 0, width: 16.0 / 1.5, height: 18.0 / 1.5))
        XCTAssertEqual(geometry.outputWidth, 16)
        XCTAssertEqual(geometry.outputHeight, 18)
    }

    func test_allResolutionsStayEvenAndNeverUpscale() throws {
        for resolution in [RecordingResolution.original, .fhd, .hd] {
            for size in [CGSize(width: 101, height: 53), CGSize(width: 8000, height: 1441), CGSize(width: 1080, height: 3840)] {
                let geometry = try XCTUnwrap(ScreenRecorder.resolveGeometry(contentRect: CGRect(origin: .zero, size: size), requestedSourceRect: nil, scaleFactor: 1, resolution: resolution))
                XCTAssertEqual(geometry.outputWidth % 2, 0)
                XCTAssertEqual(geometry.outputHeight % 2, 0)
                XCTAssertLessThanOrEqual(CGFloat(geometry.outputWidth), size.width)
                XCTAssertLessThanOrEqual(CGFloat(geometry.outputHeight), size.height)
                let limit = resolution == .original ? 8000 : resolution == .fhd ? 1920 : 1280
                XCTAssertLessThanOrEqual(max(geometry.outputWidth, geometry.outputHeight), limit)
                XCTAssertEqual(Double(geometry.outputWidth) / Double(geometry.outputHeight), Double(Int(size.width) & ~1) / Double(Int(size.height) & ~1), accuracy: 0.04)
            }
        }
    }

    func test_selectionRejectsDisconnectAndAllRelevantConfigurationChanges() throws {
        let original = snapshot()
        let selected = try RecordingSelection(display: original, desktopRegion: DesktopRecordingRect(rect: CGRect(x: 1800, y: 100, width: 400, height: 300)))
        XCTAssertNoThrow(try selected.validate(current: original))
        let changed: [RecordingDisplaySnapshot?] = [
            nil,
            snapshot(frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440)),
            snapshot(frame: CGRect(x: 1728, y: 0, width: 1440, height: 2560), rotation: 90),
            snapshot(scale: 2),
            snapshot(pixels: RecordingPixelSize(width: 3840, height: 2160)),
            snapshot(primaryID: 3),
            snapshot(primaryFrame: CGRect(x: 0, y: 0, width: 1728, height: 1200))
        ]
        for current in changed { XCTAssertThrowsError(try selected.validate(current: current)) }
        // Unrelated screens are absent from the snapshot, so their changes do not stop capture.
    }

    @MainActor
    func test_startQueriesDisplayAgainBeforeCreatingWriter() async throws {
        var lookedUp = false
        let recorder = ScreenRecorder(configuration: RecordingConfiguration(), displayContextProvider: { id in
            lookedUp = true
            XCTAssertEqual(id, 3)
            throw RecordingError.displayConfigurationChanged
        })
        let selection = try RecordingSelection(display: snapshot(), desktopRegion: DesktopRecordingRect(rect: CGRect(x: 1800, y: 100, width: 400, height: 300)))
        do {
            try await recorder.startRecording(target: selection)
            XCTFail("A disconnected display must not start recording")
        } catch RecordingError.displayConfigurationChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(lookedUp)
    }

    @MainActor
    func test_simultaneousStopsFinalizeOnceAndShareTheResult() async throws {
        let finalization = RecordingFinalization()
        var calls = 0
        let url = URL(fileURLWithPath: "/tmp/recording-finalization-test.mp4")
        let operation: @MainActor () async throws -> RecordingResult = {
            calls += 1
            await Task.yield()
            return RecordingResult(url: url, duration: 5)
        }
        let userStop = Task { try await finalization.finish(operation) }
        let displayStop = Task { try await finalization.finish(operation) }
        let streamStop = Task { try await finalization.finish(operation) }
        let results = try await [userStop.value, displayStop.value, streamStop.value]
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(results.allSatisfy { $0.url == url && $0.duration == 5 })
    }

    @MainActor
    func test_failedFinalizationIsNotRetriedOrReportedAsSuccess() async {
        let finalization = RecordingFinalization()
        var calls = 0
        for _ in 0..<3 {
            do {
                _ = try await finalization.finish {
                    calls += 1
                    throw RecordingError.noFramesCaptured
                }
                XCTFail("An empty recording must fail")
            } catch RecordingError.noFramesCaptured {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(calls, 1)
    }
}
