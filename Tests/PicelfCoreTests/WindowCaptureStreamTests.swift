import XCTest
@testable import Picelf

final class WindowCaptureStreamTests: XCTestCase {
    @MainActor
    func test_initialState() {
        let stream = WindowCaptureStream()
        XCTAssertFalse(stream.isCapturing)
        XCTAssertEqual(stream.capturedFrameCount, 0)
        XCTAssertNil(stream.error)
    }

    @MainActor
    func test_configurationDefaults() {
        let stream = WindowCaptureStream()
        XCTAssertEqual(stream.framesPerSecond, 10)
        XCTAssertFalse(stream.showsCursor)
    }

    func test_makeCaptureRegion_fullWindow() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let selected = window

        let region = WindowCaptureStream.makeCaptureRegion(
            selectedFrameInScreen: selected,
            windowFrameInScreen: window
        )

        XCTAssertEqual(region?.xPoints, 0)
        XCTAssertEqual(region?.yPointsFromTop, 0)
        XCTAssertEqual(region?.widthPoints, 800)
        XCTAssertEqual(region?.heightPoints, 600)
    }

    func test_makeCaptureRegion_topHalf() {
        // CG coordinates (y-down): top half starts at window's minY
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let selectedTopHalf = CGRect(x: 100, y: 200, width: 800, height: 300)

        let region = WindowCaptureStream.makeCaptureRegion(
            selectedFrameInScreen: selectedTopHalf,
            windowFrameInScreen: window
        )

        XCTAssertEqual(region?.xPoints, 0)
        XCTAssertEqual(region?.yPointsFromTop, 0)
        XCTAssertEqual(region?.widthPoints, 800)
        XCTAssertEqual(region?.heightPoints, 300)
    }

    func test_makeCaptureRegion_partiallyOutsideWindow_clampsToIntersection() {
        // CG coordinates (y-down): window y=100..400, selected y=250..550
        // Intersection: x=100..350, y=250..400 → yPointsFromTop = 250-100 = 150
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        let selected = CGRect(x: 50, y: 250, width: 300, height: 300)

        let region = WindowCaptureStream.makeCaptureRegion(
            selectedFrameInScreen: selected,
            windowFrameInScreen: window
        )

        XCTAssertEqual(region?.xPoints, 0)
        XCTAssertEqual(region?.yPointsFromTop, 150)
        XCTAssertEqual(region?.widthPoints, 250)
        XCTAssertEqual(region?.heightPoints, 150)
    }

    func test_makeCaptureRegion_noIntersection_returnsNil() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        let selected = CGRect(x: 0, y: 0, width: 50, height: 50)

        let region = WindowCaptureStream.makeCaptureRegion(
            selectedFrameInScreen: selected,
            windowFrameInScreen: window
        )

        XCTAssertNil(region)
    }

    func test_pixelCropRect_scalesAndRounds() {
        let region = WindowCaptureRegion(
            xPoints: 10.25,
            yPointsFromTop: 20.5,
            widthPoints: 100.2,
            heightPoints: 50.1
        )

        let rect = WindowCaptureStream.pixelCropRect(
            for: region,
            scaleFactor: 2,
            imageWidth: 300,
            imageHeight: 200
        )

        XCTAssertEqual(rect, CGRect(x: 20, y: 41, width: 201, height: 101))
    }

    func test_pixelCropRect_clampsToFrameBounds() {
        let region = WindowCaptureRegion(
            xPoints: 90,
            yPointsFromTop: 70,
            widthPoints: 20,
            heightPoints: 20
        )

        let rect = WindowCaptureStream.pixelCropRect(
            for: region,
            scaleFactor: 2,
            imageWidth: 200,
            imageHeight: 150
        )

        XCTAssertEqual(rect, CGRect(x: 180, y: 140, width: 20, height: 10))
    }

    func test_pixelCropRect_invalidAfterClamp_returnsNil() {
        let region = WindowCaptureRegion(
            xPoints: 200,
            yPointsFromTop: 200,
            widthPoints: 10,
            heightPoints: 10
        )

        let rect = WindowCaptureStream.pixelCropRect(
            for: region,
            scaleFactor: 1,
            imageWidth: 100,
            imageHeight: 100
        )

        XCTAssertNil(rect)
    }

    func test_recordingGeometry_trimsOddOriginalRegionOnTrailingEdges() {
        let geometry = ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: 100, y: 200, width: 300, height: 200),
            requestedSourceRect: CGRect(x: 105, y: 207, width: 81, height: 41),
            scaleFactor: 1.0,
            resolution: .original
        )

        XCTAssertEqual(
            geometry,
            ScreenRecorder.ResolvedRecordingGeometry(
                sourceRect: CGRect(x: 105, y: 207, width: 80, height: 40),
                outputWidth: 80,
                outputHeight: 40
            )
        )
    }

    func test_recordingGeometry_preservesRetinaOriginalRegionWhenAlreadyEvenInPixels() {
        let geometry = ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: 200, y: 300, width: 800, height: 600),
            requestedSourceRect: CGRect(x: 210, y: 312, width: 101, height: 51),
            scaleFactor: 2.0,
            resolution: .original
        )

        XCTAssertEqual(
            geometry,
            ScreenRecorder.ResolvedRecordingGeometry(
                sourceRect: CGRect(x: 210, y: 312, width: 101, height: 51),
                outputWidth: 202,
                outputHeight: 102
            )
        )
    }

    func test_recordingGeometry_downscalesToEvenFHDOutput() {
        let geometry = ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: -1728, y: 100, width: 4000, height: 3000),
            requestedSourceRect: CGRect(x: -1728, y: 100, width: 3000, height: 2000),
            scaleFactor: 1.0,
            resolution: .fhd
        )

        XCTAssertEqual(
            geometry,
            ScreenRecorder.ResolvedRecordingGeometry(
                sourceRect: CGRect(x: -1728, y: 100, width: 3000, height: 2000),
                outputWidth: 1920,
                outputHeight: 1280
            )
        )
    }

    func test_recordingGeometry_negativeDisplayRegionPreservesDisplayCoordinates() {
        let geometry = ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: -1728, y: 0, width: 1728, height: 1117),
            requestedSourceRect: CGRect(x: -1400, y: 90, width: 600, height: 500),
            scaleFactor: 2.0,
            resolution: .original
        )

        XCTAssertEqual(
            geometry,
            ScreenRecorder.ResolvedRecordingGeometry(
                sourceRect: CGRect(x: -1400, y: 90, width: 600, height: 500),
                outputWidth: 1200,
                outputHeight: 1000
            )
        )
    }

    func test_recordingGeometry_fullEvenWholeSurfaceDoesNotSetSourceRect() {
        let geometry = ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: 50, y: 70, width: 100, height: 50),
            requestedSourceRect: nil,
            scaleFactor: 1.0,
            resolution: .original
        )

        XCTAssertEqual(
            geometry,
            ScreenRecorder.ResolvedRecordingGeometry(
                sourceRect: nil,
                outputWidth: 100,
                outputHeight: 50
            )
        )
    }

    func test_recordingGeometry_fullCaptureTrimsOddWholeSurfaceAndSetsSourceRect() {
        let geometry = ScreenRecorder.resolveGeometry(
            contentRect: CGRect(x: 50, y: 70, width: 101, height: 51),
            requestedSourceRect: nil,
            scaleFactor: 1.0,
            resolution: .original
        )

        XCTAssertEqual(
            geometry,
            ScreenRecorder.ResolvedRecordingGeometry(
                sourceRect: CGRect(x: 50, y: 70, width: 100, height: 50),
                outputWidth: 100,
                outputHeight: 50
            )
        )
    }
}
