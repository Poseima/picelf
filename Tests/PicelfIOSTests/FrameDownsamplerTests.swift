// FrameDownsamplerTests.swift
// PicelfIOSTests — Unit tests for FrameDownsampler

import XCTest
@testable import Picelf

final class FrameDownsamplerTests: XCTestCase {

    // MARK: - Downsample wider image

    func test_downsample_widerThanMaxWidth_reducesWidth() {
        let image = TestHelpers.makeSolidColorImage(width: 2000, height: 1000)!
        let result = FrameDownsampler.downsample(image, maxWidth: 1080)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 1080)
    }

    func test_downsample_widerThanMaxWidth_reducesHeight() {
        let image = TestHelpers.makeSolidColorImage(width: 2000, height: 1000)!
        let result = FrameDownsampler.downsample(image, maxWidth: 1080)
        XCTAssertNotNil(result)
        // Expected: 1000 * (1080/2000) = 540
        XCTAssertEqual(result!.height, 540)
    }

    // MARK: - No downsample when narrower

    func test_downsample_narrowerThanMaxWidth_returnsSameSize() {
        let image = TestHelpers.makeSolidColorImage(width: 800, height: 600)!
        let result = FrameDownsampler.downsample(image, maxWidth: 1080)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 800)
        XCTAssertEqual(result!.height, 600)
    }

    func test_downsample_exactlyMaxWidth_returnsSameSize() {
        let image = TestHelpers.makeSolidColorImage(width: 1080, height: 720)!
        let result = FrameDownsampler.downsample(image, maxWidth: 1080)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 1080)
        XCTAssertEqual(result!.height, 720)
    }

    // MARK: - Aspect ratio preservation

    func test_downsample_preservesAspectRatio() {
        let image = TestHelpers.makeSolidColorImage(width: 3000, height: 2000)!
        let result = FrameDownsampler.downsample(image, maxWidth: 1500)
        XCTAssertNotNil(result)

        let originalAspect = Double(3000) / Double(2000)
        let resultAspect = Double(result!.width) / Double(result!.height)
        XCTAssertEqual(originalAspect, resultAspect, accuracy: 0.01,
                       "Aspect ratio should be preserved after downsampling")
    }

    func test_downsample_tallImage_preservesAspectRatio() {
        // Tall image: 1200 x 6000 (scrolling screenshot aspect)
        let image = TestHelpers.makeSolidColorImage(width: 1200, height: 6000)!
        let result = FrameDownsampler.downsample(image, maxWidth: 600)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 600)
        // Expected: 6000 * (600/1200) = 3000
        XCTAssertEqual(result!.height, 3000)
    }
}
