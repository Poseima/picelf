import AppKit
import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import Picelf

/// Opt-in: records only the separate anonymous marker windows, never the whole desktop.
@MainActor
final class RecordingLiveTests: XCTestCase {
    private func requireLiveAccess() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PICELF_RUN_RECORDING_TESTS"] == "1", "Requires PICELF_RUN_RECORDING_TESTS=1 and recording-marker.swift")
        let signature = MicrophonePermissionRuntimeDiagnostics.current()
        try XCTSkipUnless(signature.isSigned && signature.teamIdentifier != nil, "Use a developer-signed Debug test host")
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "Screen Recording access is required for the signed test host")
    }

    private func markerSelections() async throws -> [RecordingSelection] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [RecordingSelection] = []
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
            guard let marker = content.windows.first(where: { $0.title == "Picelf Recording Marker \(id)" }) else { continue }
            let context = try await RecordingDisplayContext.resolve(displayID: id)
            result.append(try RecordingSelection(display: context.snapshot, desktopRegion: DesktopRecordingRect(rect: marker.frame)))
        }
        try XCTSkipIf(result.isEmpty, "Launch the separate recording marker fixture first")
        return result
    }

    private var outputDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("picelf-recording-validation", isDirectory: true)
    }

    private func verifyVideo(_ result: RecordingResult, selection: RecordingSelection, name: String) async throws {
        let asset = AVURLAsset(url: result.url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let expected = try XCTUnwrap(ScreenRecorder.resolveGeometry(contentRect: selection.display.cgFrame, requestedSourceRect: selection.desktopRegion.rect, scaleFactor: selection.display.pointPixelScale, resolution: .original))
        XCTAssertEqual(size.width, CGFloat(expected.outputWidth))
        XCTAssertEqual(size.height, CGFloat(expected.outputHeight))
        XCTAssertGreaterThan(result.duration, 0)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let (image, _) = try await generator.image(at: CMTime(seconds: 0.25, preferredTimescale: 600))
        let bitmap = NSBitmapImageRep(cgImage: image)
        try verifyMarkers(bitmap, name: name)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: outputDirectory.appendingPathComponent("\(name).png"))
        let destination = outputDirectory.appendingPathComponent("\(name).mp4")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: result.url, to: destination)
        print("[Recording E2E] \(name) display=\(selection.display.displayID) scale=\(selection.display.pointPixelScale) size=\(size) output=\(destination.path)")
    }

    private func verifyMarkers(_ bitmap: NSBitmapImageRep, name: String) throws {
        let samples: [(CGFloat, CGFloat, [Bool])] = [
            (0.05, 0.05, [true, false, false]), (0.95, 0.05, [false, true, false]),
            (0.05, 0.95, [false, false, true]), (0.95, 0.95, [true, true, false]),
            (0.5, 0.5, [true, false, true]), (0.25, 0.25, [true, true, true])
        ]
        for (x, y, channels) in samples {
            let actual = try XCTUnwrap(bitmap.colorAt(x: Int(CGFloat(bitmap.pixelsWide) * x), y: Int(CGFloat(bitmap.pixelsHigh) * y))?.usingColorSpace(.sRGB))
            // Display profiles and video color conversion change channel values.
            // Verify the saturated marker colors and their positions, rather than exact RGB.
            for (value, isHigh) in zip([actual.redComponent, actual.greenComponent, actual.blueComponent], channels) {
                if isHigh {
                    XCTAssertGreaterThan(value, 0.75, "\(name) x=\(x) y=\(y)")
                } else {
                    XCTAssertLessThan(value, 0.6, "\(name) x=\(x) y=\(y)")
                }
            }
        }
    }

    func test_savedMarkerVideosHaveExpectedPositions() async throws {
        let directory = ProcessInfo.processInfo.environment["PICELF_RECORDING_SAVED_VIDEO_DIRECTORY"]
        try XCTSkipIf(directory == nil, "Set PICELF_RECORDING_SAVED_VIDEO_DIRECTORY to previously captured anonymous marker videos")
        let videos = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: try XCTUnwrap(directory)), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("display-") && $0.pathExtension == "mp4" }
        XCTAssertFalse(videos.isEmpty)
        for url in videos {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            let (image, _) = try await generator.image(at: CMTime(seconds: 0.25, preferredTimescale: 600))
            try verifyMarkers(NSBitmapImageRep(cgImage: image), name: url.lastPathComponent)
        }
    }

    func test_recordsMarkersOnEveryAttachedDisplay() async throws {
        try requireLiveAccess()
        for selection in try await markerSelections() {
            let recorder = ScreenRecorder(configuration: RecordingConfiguration(captureSystemAudio: false, showsCursor: false))
            try await recorder.startRecording(target: selection)
            try await Task.sleep(for: .seconds(1))
            let result = try await recorder.stopRecording()
            try await verifyVideo(result, selection: selection, name: "display-\(selection.display.displayID)")
        }
    }

    func test_displayChangeDuringPauseSavesVideoOnceDespiteConcurrentStop() async throws {
        try requireLiveAccess()
        let selections = try await markerSelections()
        let selection = try XCTUnwrap(selections.last)
        var changed = false
        let detected = expectation(description: "Display change detected")
        let recorder = ScreenRecorder(configuration: RecordingConfiguration(captureSystemAudio: false, showsCursor: false), displayContextProvider: { id in
            let context = try await RecordingDisplayContext.resolve(displayID: id)
            if changed { detected.fulfill(); throw RecordingError.displayConfigurationChanged }
            return context
        })
        let stopped = expectation(description: "Display change completes recording")
        stopped.assertForOverFulfill = true
        var automaticResult: RecordingResult?
        recorder.onAutomaticStop = { result, reason in
            if case .displayChanged = reason {} else { XCTFail("Expected display-change reason") }
            switch result {
            case .success(let saved): automaticResult = saved
            case .failure(let error): XCTFail("Could not save recording: \(error)")
            }
            stopped.fulfill()
        }
        try await recorder.startRecording(target: selection)
        try await Task.sleep(for: .seconds(1))
        recorder.pauseRecording()
        // An unrelated change keeps exactly the same target snapshot.
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(automaticResult)
        changed = true
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await fulfillment(of: [detected], timeout: 10)
        let userStop = Task { try await recorder.stopRecording() }
        let duplicateStop = Task { try await recorder.stopRecording() }
        await fulfillment(of: [stopped], timeout: 10)
        let saved = try XCTUnwrap(automaticResult)
        let userResult = try await userStop.value
        let duplicateResult = try await duplicateStop.value
        XCTAssertEqual(userResult.url, saved.url)
        XCTAssertEqual(duplicateResult.url, saved.url)
        XCTAssertLessThan(saved.duration, 1.5, "Paused wall time must not count toward video duration")
        try await verifyVideo(saved, selection: selection, name: "display-change-paused")
    }
}
