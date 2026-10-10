// VideoFrameExtractorTests.swift
// PicelfIOSTests — Unit tests for VideoFrameExtractor

import XCTest
@testable import Picelf

final class VideoFrameExtractorTests: XCTestCase {

    // MARK: - Initialization

    func test_init_defaultConfiguration() {
        let extractor = VideoFrameExtractor()
        XCTAssertEqual(extractor.configuration.sampleFPS, 5.0)
        XCTAssertEqual(extractor.configuration.maxWidth, 1080)
        XCTAssertEqual(extractor.configuration.duplicateMADThreshold, 2.0)
    }

    func test_init_customConfiguration() {
        let config = VideoFrameExtractor.Configuration(
            sampleFPS: 10.0,
            maxWidth: 720,
            duplicateMADThreshold: 3.0
        )
        let extractor = VideoFrameExtractor(configuration: config)
        XCTAssertEqual(extractor.configuration.sampleFPS, 10.0)
        XCTAssertEqual(extractor.configuration.maxWidth, 720)
        XCTAssertEqual(extractor.configuration.duplicateMADThreshold, 3.0)
    }

    // MARK: - Cancellation

    func test_cancel_setsIsCancelled() {
        let extractor = VideoFrameExtractor()
        XCTAssertFalse(extractor.isCancelled)

        extractor.cancel()
        XCTAssertTrue(extractor.isCancelled)
    }

    // MARK: - Error on missing video

    func test_extractFrames_nonexistentFile_throws() async {
        let extractor = VideoFrameExtractor()
        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-video-\(UUID().uuidString).mp4")

        do {
            _ = try await extractor.extractFrames(from: bogusURL)
            XCTFail("Expected an error for nonexistent video file")
        } catch {
            // Expected: AVAssetReader or track loading should fail
        }
    }

    // MARK: - Progress struct

    func test_progress_fraction() {
        let progress = VideoFrameExtractor.Progress(
            framesExtracted: 10,
            framesSkipped: 2,
            totalSamples: 50,
            fraction: 0.24
        )
        XCTAssertEqual(progress.framesExtracted, 10)
        XCTAssertEqual(progress.framesSkipped, 2)
        XCTAssertEqual(progress.totalSamples, 50)
        XCTAssertEqual(progress.fraction, 0.24, accuracy: 0.001)
    }

    // MARK: - Error descriptions

    func test_errorDescriptions_areNotNil() {
        let errors: [VideoFrameExtractorError] = [
            .noVideoTrack,
            .invalidDuration,
            .readerStartFailed(nil),
            .readingFailed(nil),
            .cancelled,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription,
                            "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty,
                           "Error \(error) description should not be empty")
        }
    }
}
