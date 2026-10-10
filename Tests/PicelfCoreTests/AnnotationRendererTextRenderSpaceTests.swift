import AppKit
import XCTest
@testable import Picelf

final class AnnotationRendererTextRenderSpaceTests: XCTestCase {
    func test_canvasTopLeftSpaceKeepsRectUnchanged() {
        let topLeftRect = CGRect(x: 24, y: 36, width: 180, height: 44)

        let resolved = AnnotationRenderer.resolvedWrappedTextDrawRect(
            fromTopLeftRect: topLeftRect,
            renderSpace: .canvasTopLeft
        )

        XCTAssertEqual(resolved.origin.x, topLeftRect.origin.x, accuracy: 0.001)
        XCTAssertEqual(resolved.origin.y, topLeftRect.origin.y, accuracy: 0.001)
        XCTAssertEqual(resolved.width, topLeftRect.width, accuracy: 0.001)
        XCTAssertEqual(resolved.height, topLeftRect.height, accuracy: 0.001)
    }

    func test_exportBottomLeftSpaceConvertsUsingCanvasHeight() {
        let topLeftRect = CGRect(x: 24, y: 36, width: 180, height: 44)
        let canvasHeight: CGFloat = 320

        let resolved = AnnotationRenderer.resolvedWrappedTextDrawRect(
            fromTopLeftRect: topLeftRect,
            renderSpace: .exportBottomLeft(canvasHeight: canvasHeight)
        )

        XCTAssertEqual(resolved.origin.x, 24, accuracy: 0.001)
        XCTAssertEqual(resolved.origin.y, 240, accuracy: 0.001) // 320 - (36 + 44)
        XCTAssertEqual(resolved.width, 180, accuracy: 0.001)
        XCTAssertEqual(resolved.height, 44, accuracy: 0.001)
    }

    func test_renderSpaceFlippedPolicyIsCanvasTrueAndExportFalse() {
        XCTAssertTrue(AnnotationRenderer.wrappedTextContextIsFlipped(for: .canvasTopLeft))
        XCTAssertFalse(AnnotationRenderer.wrappedTextContextIsFlipped(for: .exportBottomLeft(canvasHeight: 100)))
    }

    func test_resolveMosaicParameters_scalesCropRectForDownsampledSource() throws {
        let parameters = try XCTUnwrap(
            AnnotationRenderer.resolveMosaicParameters(
                documentRectTopLeft: CGRect(x: 120, y: 40, width: 100, height: 80),
                canvasSize: CGSize(width: 400, height: 200),
                sourcePixelSize: CGSize(width: 200, height: 100),
                block: 14
            )
        )

        XCTAssertEqual(parameters.documentRectTopLeft.origin.x, 120, accuracy: 0.001)
        XCTAssertEqual(parameters.documentRectTopLeft.origin.y, 40, accuracy: 0.001)
        XCTAssertEqual(parameters.documentRectTopLeft.width, 100, accuracy: 0.001)
        XCTAssertEqual(parameters.documentRectTopLeft.height, 80, accuracy: 0.001)

        XCTAssertEqual(parameters.sourceCropRect.origin.x, 60, accuracy: 0.001)
        XCTAssertEqual(parameters.sourceCropRect.origin.y, 20, accuracy: 0.001)
        XCTAssertEqual(parameters.sourceCropRect.width, 50, accuracy: 0.001)
        XCTAssertEqual(parameters.sourceCropRect.height, 40, accuracy: 0.001)
        XCTAssertEqual(parameters.effectiveBlockScale, 7, accuracy: 0.001)
    }

    func test_resolveMosaicParameters_clampsRectToCanvasBounds() throws {
        let parameters = try XCTUnwrap(
            AnnotationRenderer.resolveMosaicParameters(
                documentRectTopLeft: CGRect(x: 350, y: 170, width: 100, height: 80),
                canvasSize: CGSize(width: 400, height: 200),
                sourcePixelSize: CGSize(width: 200, height: 100),
                block: 14
            )
        )

        XCTAssertEqual(parameters.documentRectTopLeft.origin.x, 350, accuracy: 0.001)
        XCTAssertEqual(parameters.documentRectTopLeft.origin.y, 170, accuracy: 0.001)
        XCTAssertEqual(parameters.documentRectTopLeft.width, 50, accuracy: 0.001)
        XCTAssertEqual(parameters.documentRectTopLeft.height, 30, accuracy: 0.001)

        XCTAssertEqual(parameters.sourceCropRect.origin.x, 175, accuracy: 0.001)
        XCTAssertEqual(parameters.sourceCropRect.origin.y, 85, accuracy: 0.001)
        XCTAssertEqual(parameters.sourceCropRect.width, 25, accuracy: 0.001)
        XCTAssertEqual(parameters.sourceCropRect.height, 15, accuracy: 0.001)
    }

    func test_makeMosaicImage_samplesExpectedRegionFromDownsampledSource() throws {
        let preview = makeQuadrantImage(width: 200, height: 200)
        let previewCG = try XCTUnwrap(preview.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let parameters = try XCTUnwrap(
            AnnotationRenderer.resolveMosaicParameters(
                documentRectTopLeft: CGRect(x: 300, y: 300, width: 60, height: 60),
                canvasSize: CGSize(width: 400, height: 400),
                sourcePixelSize: CGSize(width: previewCG.width, height: previewCG.height),
                block: 20
            )
        )

        let mosaic = try XCTUnwrap(
            AnnotationRenderer.makeMosaicImage(from: previewCG, parameters: parameters)
        )
        let sample = try XCTUnwrap(
            sampleRGBAAtTopLeft(
                NSImage(cgImage: mosaic, size: NSSize(width: mosaic.width, height: mosaic.height)),
                point: CGPoint(x: 15, y: 15)
            )
        )

        XCTAssertGreaterThan(sample.r, 170)
        XCTAssertGreaterThan(sample.g, 170)
        XCTAssertGreaterThan(Int(sample.r) - Int(sample.b), 120)
        XCTAssertGreaterThan(Int(sample.g) - Int(sample.b), 120)
    }

    func test_compositorMosaic_usesSameRegionAsPreviewAndExport() throws {
        let fullRes = makeQuadrantImage(width: 400, height: 400)
        let annotation = EditorAnnotation(
            kind: .mosaic,
            start: CGPoint(x: 300, y: 300),
            end: CGPoint(x: 360, y: 360),
            color: .clear,
            lineWidth: 1
        )

        let composed = try XCTUnwrap(
            EditorCompositor.compose(
                baseImage: fullRes,
                imageSize: CGSize(width: 400, height: 400),
                annotations: [annotation],
                draft: nil
            )
        )
        let sample = try XCTUnwrap(
            sampleRGBAAtTopLeft(composed, point: CGPoint(x: 330, y: 330))
        )

        XCTAssertGreaterThan(sample.r, 170)
        XCTAssertGreaterThan(sample.g, 170)
        XCTAssertGreaterThan(Int(sample.r) - Int(sample.b), 120)
        XCTAssertGreaterThan(Int(sample.g) - Int(sample.b), 120)
    }

    private func makeQuadrantImage(width: Int, height: Int) -> NSImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight))
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight))
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.fill(CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight))

        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func sampleRGBAAtTopLeft(
        _ image: NSImage,
        point: CGPoint
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width
        let height = cg.height
        let scaleX = CGFloat(width) / max(1, image.size.width)
        let scaleY = CGFloat(height) / max(1, image.size.height)
        let x = Int((point.x * scaleX).rounded())
        let yTop = Int((point.y * scaleY).rounded())
        guard x >= 0, x < width, yTop >= 0, yTop < height else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let index = yTop * bytesPerRow + x * 4
        return (
            r: pixels[index],
            g: pixels[index + 1],
            b: pixels[index + 2],
            a: pixels[index + 3]
        )
    }
}
