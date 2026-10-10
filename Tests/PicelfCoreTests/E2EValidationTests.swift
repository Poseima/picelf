import XCTest
import CoreGraphics
@testable import Picelf

final class E2EValidationTests: XCTestCase {

    func test_cleanStitch_passes() {
        let image = makePatternImage(width: 640, height: 5000)
        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image)
        )

        XCTAssertTrue(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
    }

    func test_largeDuplicateBand_fails() {
        var bytes = makePatternBytes(width: 640, height: 5000)
        // Align to detector stride to exercise artifact checks deterministically.
        copyBand(bytes: &bytes, width: 640, fromY: 1152, toY: 2944, bandHeight: 384)
        let image = makeImage(fromRGBA: bytes, width: 640, height: 5000)

        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image)
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertTrue(report.issues.contains { $0.category == "duplication" || $0.category == "repeated-section" }, report.formattedSummary(prefix: "[ValidationTest]"))
    }

    func test_seamArtifact_fails() {
        var bytes = makePatternBytes(width: 640, height: 5000)
        injectSeam(bytes: &bytes, width: 640, startY: 3000, offsetPx: 128, seamHeight: 256)
        let image = makeImage(fromRGBA: bytes, width: 640, height: 5000)

        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image)
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertTrue(report.issues.contains { $0.category == "seam" || $0.category == "duplication" }, report.formattedSummary(prefix: "[ValidationTest]"))
    }

    func test_repeatedFooter_fails() {
        var bytes = makePatternBytes(width: 640, height: 5000)
        // Align to detector stride to exercise artifact checks deterministically.
        copyBand(bytes: &bytes, width: 640, fromY: 3520, toY: 4448, bandHeight: 416)
        let image = makeImage(fromRGBA: bytes, width: 640, height: 5000)

        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image)
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertTrue(report.issues.contains { $0.category == "repeated-section" || $0.category == "duplication" }, report.formattedSummary(prefix: "[ValidationTest]"))
    }

    func test_rightEdgeFloatingOverlay_fails() {
        let width = 640
        let height = 5000
        var bytes = makePatternBytes(width: width, height: height)
        let panelWidth = 72
        let panelHeight = 132
        let marginRight = 8
        let sourceY = 720

        drawRightEdgeOverlay(
            bytes: &bytes,
            width: width,
            height: height,
            topY: sourceY,
            panelWidth: panelWidth,
            panelHeight: panelHeight,
            marginRight: marginRight
        )

        for targetY in stride(from: sourceY + 640, through: 4560, by: 640) {
            copyRightEdgeOverlay(
                bytes: &bytes,
                width: width,
                height: height,
                fromY: sourceY,
                toY: targetY,
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                marginRight: marginRight
            )
        }

        let image = makeImage(fromRGBA: bytes, width: width, height: height)
        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image),
            profile: .highRecall,
            policy: .strictWarnings
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertTrue(
            report.issues.contains { $0.category == "edge-overlay" },
            report.formattedSummary(prefix: "[ValidationTest]")
        )
    }

    func test_plainRightMargin_notFlaggedAsEdgeOverlay() {
        let width = 640
        let height = 5000
        var bytes = makePatternBytes(width: width, height: height)
        flattenRightMargin(bytes: &bytes, width: width, height: height, marginWidth: 72)
        let image = makeImage(fromRGBA: bytes, width: width, height: height)

        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image),
            profile: .highRecall,
            policy: .strictWarnings
        )

        XCTAssertTrue(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertFalse(
            report.issues.contains { $0.category == "edge-overlay" },
            report.formattedSummary(prefix: "[ValidationTest]")
        )
    }

    func test_naturalSimilarity_notOverFlagged() {
        let image = makeNaturalSimilarityImage(width: 640, sectionHeight: 600, sectionCount: 8)
        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: makeContext(for: image)
        )

        XCTAssertTrue(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
    }

    func test_referenceVscodeLongScreenshot_reportOnly() throws {
        guard let referencePath = ProcessInfo.processInfo.environment["PICELF_REFERENCE_SCREENSHOT"] else {
            throw XCTSkip("Set PICELF_REFERENCE_SCREENSHOT to an optional local reference image")
        }
        guard FileManager.default.fileExists(atPath: referencePath) else {
            throw XCTSkip("Reference screenshot not found at \(referencePath)")
        }
        let url = URL(fileURLWithPath: referencePath)
        guard let provider = CGDataProvider(url: url as CFURL),
              let image = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            XCTFail("Could not load reference screenshot")
            return
        }

        let context = E2EValidationContext(
            acceptedFrameCount: nil,
            windowPixelWidth: image.width,
            windowPixelHeight: min(1200, image.height),
            contrastSampleRect: CGRect(
                x: 40,
                y: min(max(0, image.height / 3), max(0, image.height - 260)),
                width: max(1, min(1000, image.width - 80)),
                height: 200
            )
        )
        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: context,
            profile: .highRecall,
            policy: .criticalOnly
        )

        print(report.formattedSummary(prefix: "[ReferenceVscode]"))
    }

    func test_bilibiliDuplicatedSectionFixture_failsInStrictMode() throws {
        let image = try loadFixtureImage("duplicated-section.png")
        let sampleY = min(image.height / 3, max(0, image.height - 220))
        let context = E2EValidationContext(
            contrastSampleRect: CGRect(
                x: 40,
                y: sampleY,
                width: min(900, max(1, image.width - 80)),
                height: 180
            )
        )

        let report = E2EStitchValidator.validateStitchedImage(
            image,
            context: context,
            profile: .highRecall,
            policy: .strictWarnings
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertTrue(
            report.issues.contains {
                $0.category == "duplication" || $0.category == "repeated-section"
            },
            report.formattedSummary(prefix: "[ValidationTest]")
        )
    }

    func test_ocrBenchmarkValidator_detectsMissingLowerRightContent() {
        let benchmark = RecognizedTextDocument(
            blocks: [
                RecognizedTextBlock(
                    text: "Main article",
                    normalizedBounds: NormalizedTextRect(x: 0.24, y: 0.20, width: 0.22, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar item one",
                    normalizedBounds: NormalizedTextRect(x: 0.70, y: 0.38, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar item two",
                    normalizedBounds: NormalizedTextRect(x: 0.72, y: 0.52, width: 0.18, height: 0.03)
                )
            ],
            dominantLanguageCode: "en"
        )
        let output = RecognizedTextDocument(
            blocks: [
                RecognizedTextBlock(
                    text: "Main article",
                    normalizedBounds: NormalizedTextRect(x: 0.24, y: 0.20, width: 0.22, height: 0.03)
                )
            ],
            dominantLanguageCode: "en"
        )

        let report = E2EOCRBenchmarkValidator.compare(
            output: output,
            benchmark: benchmark,
            thresholds: .a218Zhihu
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertLessThan(report.lowerRightBlockRatio, OCRBenchmarkThresholds.a218Zhihu.minLowerRightBlockRatio)
        XCTAssertLessThan(report.lowerRightCharRatio, OCRBenchmarkThresholds.a218Zhihu.minLowerRightCharRatio)
        XCTAssertLessThan(report.midRightBlockRatio, OCRBenchmarkThresholds.a218Zhihu.minMidRightBlockRatio)
    }

    func test_ocrBenchmarkValidator_detectsLowerRightDuplication() {
        let benchmark = RecognizedTextDocument(
            blocks: [
                RecognizedTextBlock(
                    text: "Main article",
                    normalizedBounds: NormalizedTextRect(x: 0.24, y: 0.20, width: 0.22, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar item",
                    normalizedBounds: NormalizedTextRect(x: 0.70, y: 0.38, width: 0.18, height: 0.03)
                )
            ],
            dominantLanguageCode: "en"
        )
        let output = RecognizedTextDocument(
            blocks: [
                RecognizedTextBlock(
                    text: "Main article",
                    normalizedBounds: NormalizedTextRect(x: 0.24, y: 0.20, width: 0.22, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar item",
                    normalizedBounds: NormalizedTextRect(x: 0.70, y: 0.38, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar item duplicated",
                    normalizedBounds: NormalizedTextRect(x: 0.72, y: 0.60, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar item duplicated again",
                    normalizedBounds: NormalizedTextRect(x: 0.74, y: 0.72, width: 0.18, height: 0.03)
                )
            ],
            dominantLanguageCode: "en"
        )

        let report = E2EOCRBenchmarkValidator.compare(
            output: output,
            benchmark: benchmark,
            thresholds: .a218Zhihu
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertGreaterThan(report.lowerRightBlockRatio, OCRBenchmarkThresholds.a218Zhihu.maxLowerRightBlockRatio)
        XCTAssertGreaterThan(report.lowerRightCharRatio, OCRBenchmarkThresholds.a218Zhihu.maxLowerRightCharRatio)
        XCTAssertGreaterThan(report.midRightBlockRatio, OCRBenchmarkThresholds.a218Zhihu.maxMidRightBlockRatio)
    }

    func test_ocrBenchmarkValidator_detectsRightRailDistributionMismatch() {
        let benchmark = RecognizedTextDocument(
            blocks: [
                RecognizedTextBlock(
                    text: "Main article",
                    normalizedBounds: NormalizedTextRect(x: 0.24, y: 0.20, width: 0.22, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar upper",
                    normalizedBounds: NormalizedTextRect(x: 0.70, y: 0.24, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar middle",
                    normalizedBounds: NormalizedTextRect(x: 0.72, y: 0.50, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar lower",
                    normalizedBounds: NormalizedTextRect(x: 0.74, y: 0.80, width: 0.18, height: 0.03)
                )
            ],
            dominantLanguageCode: "en"
        )
        let output = RecognizedTextDocument(
            blocks: [
                RecognizedTextBlock(
                    text: "Main article",
                    normalizedBounds: NormalizedTextRect(x: 0.24, y: 0.20, width: 0.22, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar clustered one",
                    normalizedBounds: NormalizedTextRect(x: 0.70, y: 0.24, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar clustered two",
                    normalizedBounds: NormalizedTextRect(x: 0.72, y: 0.29, width: 0.18, height: 0.03)
                ),
                RecognizedTextBlock(
                    text: "Sidebar clustered three",
                    normalizedBounds: NormalizedTextRect(x: 0.74, y: 0.34, width: 0.18, height: 0.03)
                )
            ],
            dominantLanguageCode: "en"
        )

        let report = E2EOCRBenchmarkValidator.compare(
            output: output,
            benchmark: benchmark,
            thresholds: .a218Zhihu
        )

        XCTAssertFalse(report.passed, report.formattedSummary(prefix: "[ValidationTest]"))
        XCTAssertGreaterThan(
            report.rightRailBlockDistributionDistance,
            OCRBenchmarkThresholds.a218Zhihu.maxRightRailBlockDistributionDistance
        )
        XCTAssertGreaterThan(
            report.rightRailCharDistributionDistance,
            OCRBenchmarkThresholds.a218Zhihu.maxRightRailCharDistributionDistance
        )
    }

    private func makeContext(for image: CGImage) -> E2EValidationContext {
        E2EValidationContext(
            acceptedFrameCount: 7,
            windowPixelWidth: 640,
            windowPixelHeight: 900,
            contrastSampleRect: CGRect(x: 40, y: 320, width: min(520, image.width - 80), height: 220)
        )
    }

    private func loadFixtureImage(_ fileName: String) throws -> CGImage {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/BilibiliDuplicationCase")
            .appendingPathComponent(fileName)
        guard let provider = CGDataProvider(url: fixtureURL as CFURL),
              let image = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw XCTSkip("Fixture not found or unreadable at \(fixtureURL.path)")
        }
        return image
    }

    private func makePatternImage(width: Int, height: Int) -> CGImage {
        makeImage(fromRGBA: makePatternBytes(width: width, height: height), width: width, height: height)
    }

    private func makePatternBytes(width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        func clampToByte(_ value: Int) -> UInt8 {
            UInt8(min(255, max(0, value)))
        }

        for row in 0..<height {
            let low = row & 0xFF
            let high = (row >> 8) & 0xFF
            for col in 0..<width {
                let idx = (row * width + col) * 4
                let seedA = (low * 73 + high * 97 + col * 11) & 0xFF
                let seedB = (low * 61 + high * 89 + col * 7) & 0xFF
                let seedC = (low * 47 + high * 83 + col * 5) & 0xFF

                let base = 208 + ((col / 19 + low / 7 + high * 3) % 28)

                var r = base + (seedA % 18)
                var g = base + (seedB % 18) - 6
                var b = base + (seedC % 18) - 10

                let isTextBand = (row % 36) < 6
                    && col > 20
                    && col < width - 20
                    && ((col / 8 + row / 9) % 3 != 0)
                if isTextBand {
                    r = 16 + (seedA % 36)
                    g = 20 + (seedB % 36)
                    b = 24 + (seedC % 36)
                }

                bytes[idx] = clampToByte(r)
                bytes[idx + 1] = clampToByte(g)
                bytes[idx + 2] = clampToByte(b)
                bytes[idx + 3] = 255
            }
        }
        return bytes
    }

    private func makeNaturalSimilarityImage(width: Int, sectionHeight: Int, sectionCount: Int) -> CGImage {
        let height = sectionHeight * sectionCount
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        func clampToByte(_ value: Int) -> UInt8 {
            UInt8(min(255, max(0, value)))
        }

        for section in 0..<sectionCount {
            for localRow in 0..<sectionHeight {
                let row = section * sectionHeight + localRow

                for col in 0..<width {
                    let idx = (row * width + col) * 4
                    let base = 205 + ((section * 13 + localRow * 3) % 32)
                    let layout = ((localRow / 24) % 2 == 0) ? -18 : 0
                    let shape = ((col / 64) % 3 == 0) ? -22 : 0
                    let grain = (row * 7 + col * 13 + section * 17) % 35

                    var gray = base + layout + shape - grain

                    let isTextLine = (localRow % 29) < 4
                        && col > 24
                        && col < width - 24
                        && ((col + section * 17) % 21 < 15)
                    if isTextLine {
                        gray = 28 + ((col * 5 + localRow * 7 + section * 11) % 35)
                    }

                    let tint = (section * 17 + col / 18) % 28
                    bytes[idx] = clampToByte(gray + tint)
                    bytes[idx + 1] = clampToByte(gray)
                    bytes[idx + 2] = clampToByte(gray - tint)
                    bytes[idx + 3] = 255
                }
            }
        }

        return makeImage(fromRGBA: bytes, width: width, height: height)
    }

    private func copyBand(bytes: inout [UInt8], width: Int, fromY: Int, toY: Int, bandHeight: Int) {
        let bytesPerRow = width * 4
        let totalRows = bytes.count / bytesPerRow
        guard fromY >= 0, toY >= 0, bandHeight > 0 else { return }

        let maxCopy = min(bandHeight, totalRows - max(fromY, toY))
        guard maxCopy > 0 else { return }

        var sourceRows = [UInt8]()
        sourceRows.reserveCapacity(maxCopy * bytesPerRow)
        for row in 0..<maxCopy {
            let srcStart = (fromY + row) * bytesPerRow
            sourceRows.append(contentsOf: bytes[srcStart..<(srcStart + bytesPerRow)])
        }

        for row in 0..<maxCopy {
            let dstStart = (toY + row) * bytesPerRow
            let srcStart = row * bytesPerRow
            for offset in 0..<bytesPerRow {
                bytes[dstStart + offset] = sourceRows[srcStart + offset]
            }
        }
    }

    private func injectSeam(bytes: inout [UInt8], width: Int, startY: Int, offsetPx: Int, seamHeight: Int) {
        let bytesPerRow = width * 4
        let totalRows = bytes.count / bytesPerRow
        guard startY > offsetPx, seamHeight > 0 else { return }

        let maxCopy = min(seamHeight, totalRows - startY)
        guard maxCopy > 0 else { return }

        var sourceRows = [UInt8]()
        sourceRows.reserveCapacity(maxCopy * bytesPerRow)
        for row in 0..<maxCopy {
            let srcRow = startY + row - offsetPx
            guard srcRow >= 0 else { continue }
            let srcStart = srcRow * bytesPerRow
            sourceRows.append(contentsOf: bytes[srcStart..<(srcStart + bytesPerRow)])
        }

        for row in 0..<maxCopy {
            let dstStart = (startY + row) * bytesPerRow
            let srcStart = row * bytesPerRow
            guard srcStart + bytesPerRow <= sourceRows.count else { break }
            for offset in 0..<bytesPerRow {
                bytes[dstStart + offset] = sourceRows[srcStart + offset]
            }
        }
    }

    private func makeImage(fromRGBA bytes: [UInt8], width: Int, height: Int) -> CGImage {
        var mutable = bytes
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: &mutable,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func drawRightEdgeOverlay(
        bytes: inout [UInt8],
        width: Int,
        height: Int,
        topY: Int,
        panelWidth: Int,
        panelHeight: Int,
        marginRight: Int
    ) {
        let xStart = max(0, width - marginRight - panelWidth)
        let xEnd = min(width, xStart + panelWidth)
        guard xStart < xEnd else { return }

        let yStart = max(0, topY)
        let yEnd = min(height, topY + panelHeight)
        guard yStart < yEnd else { return }

        for y in yStart..<yEnd {
            let localY = y - yStart
            for x in xStart..<xEnd {
                let localX = x - xStart
                let idx = (y * width + x) * 4

                let border = localX < 2
                    || localX >= panelWidth - 2
                    || localY < 2
                    || localY >= panelHeight - 2
                let centerX = panelWidth / 2
                let arrowBand = localY > 12 && localY < 44 && abs(localX - centerX) < 2
                let circleDX = localX - centerX
                let upperCircleDY = localY - 72
                let lowerCircleDY = localY - 106
                let upperCircle = circleDX * circleDX + upperCircleDY * upperCircleDY <= 16 * 16
                let lowerCircle = circleDX * circleDX + lowerCircleDY * lowerCircleDY <= 12 * 12
                let glyph = ((localX / 4) + (localY / 5)) % 2 == 0

                let gray: UInt8
                if border || arrowBand || upperCircle || lowerCircle {
                    gray = glyph ? 34 : 52
                } else {
                    gray = glyph ? 208 : 226
                }

                bytes[idx] = gray
                bytes[idx + 1] = gray
                bytes[idx + 2] = gray
                bytes[idx + 3] = 255
            }
        }
    }

    private func copyRightEdgeOverlay(
        bytes: inout [UInt8],
        width: Int,
        height: Int,
        fromY: Int,
        toY: Int,
        panelWidth: Int,
        panelHeight: Int,
        marginRight: Int
    ) {
        let xStart = max(0, width - marginRight - panelWidth)
        let xEnd = min(width, xStart + panelWidth)
        guard xStart < xEnd else { return }
        guard fromY >= 0, toY >= 0, fromY + panelHeight <= height, toY + panelHeight <= height else { return }

        for row in 0..<panelHeight {
            let sourceY = fromY + row
            let targetY = toY + row
            for x in xStart..<xEnd {
                let src = (sourceY * width + x) * 4
                let dst = (targetY * width + x) * 4
                bytes[dst] = bytes[src]
                bytes[dst + 1] = bytes[src + 1]
                bytes[dst + 2] = bytes[src + 2]
                bytes[dst + 3] = bytes[src + 3]
            }
        }
    }

    private func flattenRightMargin(
        bytes: inout [UInt8],
        width: Int,
        height: Int,
        marginWidth: Int
    ) {
        let startX = max(0, width - marginWidth)
        guard startX < width else { return }

        for y in 0..<height {
            for x in startX..<width {
                let idx = (y * width + x) * 4
                bytes[idx] = 236
                bytes[idx + 1] = 236
                bytes[idx + 2] = 236
                bytes[idx + 3] = 255
            }
        }
    }
}
