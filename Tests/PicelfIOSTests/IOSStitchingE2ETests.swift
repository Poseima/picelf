// IOSStitchingE2ETests.swift
// PicelfIOSTests — End-to-end test: synthetic scrolling video → extract frames → stitch → validate

import XCTest
import AVFoundation
import CoreGraphics
import UIKit
@testable import Picelf

final class IOSStitchingE2ETests: XCTestCase {

    private let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("picelf-ios-e2e")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    // MARK: - Full Pipeline: Video → Extract → Stitch

    @MainActor
    func test_syntheticScrollVideo_extractsAndStitchesCorrectly() async throws {
        // Step 1: Generate a tall synthetic image with numbered sections
        let sourceImage = try generateTallSyntheticImage(width: 390, height: 3000, sectionHeight: 200)
        let sourceURL = outputDir.appendingPathComponent("source-image.png")
        try writePNG(sourceImage, to: sourceURL)

        // Step 2: Create a scrolling video
        let videoURL = outputDir.appendingPathComponent("scroll-recording.mp4")
        try await createScrollingVideo(from: sourceImage, to: videoURL, viewportHeight: 844, scrollSpeed: 300, fps: 30)

        // Step 3: Extract frames
        let extractor = VideoFrameExtractor(configuration: .init(sampleFPS: 5.0, maxWidth: 390, duplicateMADThreshold: 2.0))
        let frames = try await extractor.extractFrames(from: videoURL) { progress in
            print("Extracting: \(progress.framesExtracted)/\(progress.totalSamples) (\(Int(progress.fraction * 100))%)")
        }

        print("Extracted \(frames.count) frames from video")
        XCTAssertGreaterThan(frames.count, 3, "Should extract multiple frames")

        // Step 4: Stitch
        let coordinator = StitchingCoordinator()
        for frame in frames {
            coordinator.appendFrame(frame)
        }

        let stitchedImage = try await coordinator.stitch()
        guard let stitchedCG = stitchedImage.cgImage else {
            XCTFail("Failed to get CGImage from stitched result")
            return
        }

        print("Stitched result: \(stitchedCG.width) × \(stitchedCG.height)")

        // Step 5: Save output
        let resultURL = outputDir.appendingPathComponent("stitched-result.png")
        try writePNG(stitchedCG, to: resultURL)
        print("Result saved to: \(resultURL.path)")

        // Step 6: Validate
        let heightRatio = Double(stitchedCG.height) / Double(sourceImage.height)
        XCTAssertGreaterThan(heightRatio, 0.5, "Stitched height should be at least 50% of source")
        XCTAssertLessThan(heightRatio, 1.5, "Stitched height should not exceed 150% of source")
        // Width may change slightly due to frame downsampling
        let widthDiff = abs(stitchedCG.width - sourceImage.width)
        XCTAssertLessThan(widthDiff, sourceImage.width / 4, "Width should be within 25% of source")

        let attachment = XCTAttachment(image: stitchedImage)
        attachment.name = "stitched-result"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Direct Frame Stitch (no video)

    @MainActor
    func test_syntheticFrames_stitchCorrectly() async throws {
        let fullImage = try generateTallSyntheticImage(width: 390, height: 2000, sectionHeight: 200)
        let viewportHeight = 844
        let scrollStep = 600

        var frames: [CGImage] = []
        var y = 0
        while y < fullImage.height - viewportHeight {
            let cropRect = CGRect(x: 0, y: y, width: fullImage.width, height: viewportHeight)
            guard let frame = fullImage.cropping(to: cropRect) else { break }
            frames.append(frame)
            y += scrollStep
        }
        if y < fullImage.height {
            let lastY = max(0, fullImage.height - viewportHeight)
            if let frame = fullImage.cropping(to: CGRect(x: 0, y: lastY, width: fullImage.width, height: viewportHeight)) {
                frames.append(frame)
            }
        }

        print("Generated \(frames.count) synthetic frames")
        XCTAssertGreaterThan(frames.count, 2)

        let coordinator = StitchingCoordinator()
        for frame in frames {
            coordinator.appendFrame(frame)
        }

        let stitchedImage = try await coordinator.stitch()
        guard let stitchedCG = stitchedImage.cgImage else {
            XCTFail("Failed to get CGImage from stitched result")
            return
        }

        print("Stitched: \(stitchedCG.width)×\(stitchedCG.height) from source \(fullImage.width)×\(fullImage.height)")

        let resultURL = outputDir.appendingPathComponent("direct-stitch-result.png")
        try writePNG(stitchedCG, to: resultURL)
        print("Direct stitch result saved to: \(resultURL.path)")

        // With 3 frames (844px viewport, 600px scroll step), expected overlap removal is significant
        // Stitched height should be between 40%-120% of source
        XCTAssertGreaterThan(stitchedCG.height, fullImage.height / 3,
            "Stitched height \(stitchedCG.height) should be at least 1/3 of source \(fullImage.height)")
        XCTAssertLessThanOrEqual(stitchedCG.height, fullImage.height,
            "Stitched height \(stitchedCG.height) should not exceed source \(fullImage.height)")

        let attachment = XCTAttachment(image: stitchedImage)
        attachment.name = "direct-stitch-result"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func test_stitchAfterRapidFrameAppend_doesNotCrashOnIOS() async throws {
        let fullImage = try generateTallSyntheticImage(width: 390, height: 2400, sectionHeight: 180)
        let viewportHeight = 844
        let scrollStep = 320

        var frames: [CGImage] = []
        for originY in stride(from: 0, through: fullImage.height - viewportHeight, by: scrollStep) {
            guard let frame = fullImage.cropping(to: CGRect(x: 0, y: originY, width: fullImage.width, height: viewportHeight)) else {
                continue
            }
            frames.append(frame)
        }

        XCTAssertGreaterThan(frames.count, 3)

        let coordinator = StitchingCoordinator()
        for frame in frames {
            coordinator.appendFrame(frame)
        }

        let stitchedImage = try await coordinator.stitch()
        XCTAssertNotNil(stitchedImage.cgImage)
        XCTAssertGreaterThanOrEqual(Int(stitchedImage.size.height), viewportHeight)
    }

    @MainActor
    func test_processPendingBroadcast_importsPersistsAndCleansSession() async throws {
        let broadcastRoot = outputDir.appendingPathComponent("broadcast-session-\(UUID().uuidString)", isDirectory: true)
        let resultStoreRoot = outputDir.appendingPathComponent("result-store-\(UUID().uuidString)", isDirectory: true)
        let resultStore = ResultStore(baseDirectory: resultStoreRoot)
        let orchestrator = IOSCaptureOrchestrator(resultStore: resultStore)
        let viewportHeight = 844
        let scrollStep = 320
        let fullImage = try generateTallSyntheticImage(width: 390, height: 2600, sectionHeight: 190)

        defer {
            try? FileManager.default.removeItem(at: broadcastRoot)
            try? FileManager.default.removeItem(at: resultStoreRoot)
        }

        guard let framesDirectory = BroadcastFrameRelay.framesDirectoryURL(rootURL: broadcastRoot) else {
            XCTFail("Failed to create broadcast relay directory")
            return
        }

        var frameIndex = 0
        for originY in stride(from: 0, through: fullImage.height - viewportHeight, by: scrollStep) {
            guard let frame = fullImage.cropping(to: CGRect(x: 0, y: originY, width: fullImage.width, height: viewportHeight)) else {
                continue
            }
            let frameURL = framesDirectory.appendingPathComponent(BroadcastFrameRelay.frameFileName(index: frameIndex))
            try writeJPEG(frame, to: frameURL)
            frameIndex += 1
        }
        BroadcastFrameRelay.writeStopMarker(rootURL: broadcastRoot)

        let processed = await orchestrator.processPendingBroadcastIfNeeded(rootURL: broadcastRoot)

        XCTAssertTrue(processed)
        XCTAssertNotNil(orchestrator.resultImage)
        XCTAssertEqual(resultStore.results.count, 1, "Processed broadcast should be persisted immediately")
        XCTAssertTrue(BroadcastFrameRelay.sortedFrameFileURLs(rootURL: broadcastRoot).isEmpty)
        XCTAssertFalse(BroadcastFrameRelay.hasStopMarker(rootURL: broadcastRoot))
    }

    // MARK: - Helpers

    private func generateTallSyntheticImage(width: Int, height: Int, sectionHeight: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw NSError(domain: "TestError", code: 1)
        }

        let sectionColors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.95, 0.95, 0.98), (0.92, 0.97, 0.93), (0.98, 0.95, 0.90),
            (0.93, 0.93, 0.98), (0.97, 0.93, 0.93), (0.93, 0.97, 0.97),
        ]

        var sectionIndex = 0
        var y = 0

        while y < height {
            let sectionH = min(sectionHeight, height - y)
            let color = sectionColors[sectionIndex % sectionColors.count]

            ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: height - y - sectionH, width: width, height: sectionH))

            ctx.setStrokeColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 0, y: CGFloat(height - y)))
            ctx.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(height - y)))
            ctx.strokePath()

            let text = "Section \(sectionIndex + 1)" as NSString
            let font = UIFont.boldSystemFont(ofSize: 24)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]

            UIGraphicsPushContext(ctx)
            let textY = CGFloat(height - y - sectionH / 2 - 12)
            text.draw(at: CGPoint(x: 20, y: textY), withAttributes: attrs)

            let contentFont = UIFont.systemFont(ofSize: 14)
            let contentAttrs: [NSAttributedString.Key: Any] = [.font: contentFont, .foregroundColor: UIColor.gray]
            for line in 0..<4 {
                let lineText = "Content line \(line + 1) in section \(sectionIndex + 1)" as NSString
                let contentY = textY + 30 + CGFloat(line * 20)
                if contentY < CGFloat(height - y) {
                    lineText.draw(at: CGPoint(x: 40, y: contentY), withAttributes: contentAttrs)
                }
            }
            UIGraphicsPopContext()

            y += sectionHeight
            sectionIndex += 1
        }

        guard let image = ctx.makeImage() else {
            throw NSError(domain: "TestError", code: 2)
        }
        return image
    }

    private func createScrollingVideo(from image: CGImage, to url: URL, viewportHeight: Int, scrollSpeed: Int, fps: Int) async throws {
        try? FileManager.default.removeItem(at: url)

        let width = image.width
        let totalScroll = image.height - viewportHeight
        guard totalScroll > 0 else { return }

        let duration = Double(totalScroll) / Double(scrollSpeed)
        let totalFrames = Int(duration * Double(fps))

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: viewportHeight
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: viewportHeight
        ])

        writer.add(writerInput)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "VideoError", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            let scrollY = Int(Double(frameIndex) / Double(totalFrames) * Double(totalScroll))
            guard let cropped = image.cropping(to: CGRect(x: 0, y: scrollY, width: width, height: viewportHeight)) else { continue }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, viewportHeight, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width, height: viewportHeight,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: viewportHeight))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frameIndex), timescale: Int32(fps)))
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        print("Video created: \(totalFrames) frames, \(String(format: "%.1f", duration))s at \(fps)fps")
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "ExportError", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ExportError", code: 2)
        }
    }

    private func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: BroadcastFrameRelay.jpegQuality) else {
            throw NSError(domain: "ExportError", code: 3)
        }
        try data.write(to: url, options: .atomic)
    }
}
