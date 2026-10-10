// RealVideoStitchTests.swift
// PicelfIOSTests — E2E test using a real Settings app screen recording

import XCTest
import UIKit
import CoreGraphics
@testable import Picelf

final class RealVideoStitchTests: XCTestCase {

    private static let externalVideoPathEnvKey = "PICELF_EXTERNAL_VIDEO_PATH"
    private static let externalSampleFPSEnvKey = "PICELF_EXTERNAL_SAMPLE_FPS"

    private struct VideoStitchOutcome {
        let stitchedCG: CGImage
        let firstFrameSize: CGSize
        let metrics: StitchRunMetrics?
        let resultURL: URL
    }

    @MainActor
    func test_realSettingsRecording_extractsAndStitches() async throws {
        try await runVideoStitchTest(videoName: "settings-scroll", resultName: "settings")
    }

    @MainActor
    func test_realSafariRecording_extractsAndStitches() async throws {
        try await runVideoStitchTest(videoName: "safari-scroll", resultName: "safari")
    }

    @MainActor
    func test_realWikipediaArticle_extractsAndStitches() async throws {
        try await runVideoStitchTest(videoName: "wiki-photo-scroll", resultName: "wiki-photo")
    }

    @MainActor
    func test_realYouTube_extractsAndStitches() async throws {
        try await runVideoStitchTest(videoName: "youtube-scroll", resultName: "youtube")
    }

    @MainActor
    func test_realHealth_extractsAndStitches() async throws {
        try await runVideoStitchTest(videoName: "health-scroll", resultName: "health")
    }

    @MainActor
    func test_realMaps_extractsAndStitches() async throws {
        try await runVideoStitchTest(videoName: "maps-scroll", resultName: "maps")
    }

    @MainActor
    func test_externalVideoFixture_extractsAndStitches() async throws {
        let videoURL = try externalVideoURL()

        _ = try await runVideoStitchTest(
            videoURL: videoURL,
            resultName: "external-video",
            sampleFPS: externalSampleFPS()
        )
    }

    // MARK: - Shared Test Logic

    @MainActor
    private func runVideoStitchTest(videoName: String, resultName: String) async throws {
        let bundle = Bundle(for: type(of: self))
        let videoURL: URL
        if let bundledURL = bundle.url(forResource: videoName, withExtension: "mp4") {
            videoURL = bundledURL
        } else {
            let fixturesPath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/\(videoName).mp4")
            guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
                throw XCTSkip("Test video fixture not found: \(videoName).mp4")
            }
            videoURL = fixturesPath
        }

        _ = try await runVideoStitchTest(videoURL: videoURL, resultName: resultName)
    }

    @MainActor
    private func runVideoStitchTest(
        videoURL: URL,
        resultName: String,
        sampleFPS: Double = 5.0,
        attachResult: Bool = true
    ) async throws -> VideoStitchOutcome {

        print("[\(resultName)] Using video: \(videoURL.path)")

        let extractor = VideoFrameExtractor(configuration: .init(
            sampleFPS: sampleFPS, maxWidth: 1080, duplicateMADThreshold: 2.0
        ))

        let frames = try await extractor.extractFrames(from: videoURL) { progress in
            if progress.framesExtracted % 10 == 0 {
                print("[\(resultName)] Extracting: \(progress.framesExtracted)/\(progress.totalSamples)")
            }
        }

        print("[\(resultName)] Extracted \(frames.count) unique frames")
        XCTAssertGreaterThan(frames.count, 0, "Should extract at least 1 frame")

        let coordinator = StitchingCoordinator()
        for frame in frames {
            coordinator.appendFrame(frame)
        }

        let stitchedImage = try await coordinator.stitch()
        guard let stitchedCG = stitchedImage.cgImage else {
            XCTFail("Failed to get CGImage from stitched result")
            throw StitchingError.pixelDataUnavailable
        }

        print("[\(resultName)] Stitched: \(stitchedCG.width)×\(stitchedCG.height), frame: \(frames[0].width)×\(frames[0].height), ratio: \(String(format: "%.2f", Double(stitchedCG.height) / Double(frames[0].height)))x")
        XCTAssertGreaterThanOrEqual(stitchedCG.height, frames[0].height)
        let widthDiff = abs(stitchedCG.width - frames[0].width)
        XCTAssertLessThan(widthDiff, frames[0].width / 10)

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("picelf-real-e2e")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let resultURL = outputDir.appendingPathComponent("\(resultName)-stitch-result.png")
        if let dest = CGImageDestinationCreateWithURL(resultURL as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, stitchedCG, nil)
            CGImageDestinationFinalize(dest)
        }
        print("[\(resultName)] Result saved to: \(resultURL.path)")

        if attachResult {
            let attachment = XCTAttachment(contentsOfFile: resultURL)
            attachment.name = "\(resultName)-stitch-result"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        return VideoStitchOutcome(
            stitchedCG: stitchedCG,
            firstFrameSize: CGSize(width: frames[0].width, height: frames[0].height),
            metrics: coordinator.lastRunMetrics,
            resultURL: resultURL
        )
    }

    private func externalSampleFPS() -> Double {
        guard let rawValue = ProcessInfo.processInfo.environment[Self.externalSampleFPSEnvKey],
              let sampleFPS = Double(rawValue),
              sampleFPS > 0 else {
            return 5.0
        }
        return sampleFPS
    }

    private func externalVideoURL() throws -> URL {
        if let rawPath = ProcessInfo.processInfo.environment[Self.externalVideoPathEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty {
            let url = URL(fileURLWithPath: rawPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("External fixture not found: \(url.path)")
            }
            return url
        }

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/external-video.mp4")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip(
                "Provide an external video via \(Self.externalVideoPathEnvKey) or place it at \(fixtureURL.path)"
            )
        }
        return fixtureURL
    }

}
