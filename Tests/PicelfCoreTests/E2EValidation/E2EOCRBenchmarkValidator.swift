import CoreGraphics
import Foundation
@testable import Picelf

struct OCRBenchmarkSpec {
    let benchmarkImageURL: URL
    var thresholds: OCRBenchmarkThresholds = .a218Zhihu
}

struct OCRBenchmarkThresholds {
    var minTotalBlockRatio: Double
    var minCenterCharRatio: Double
    var minLowerRightBlockRatio: Double
    var minLowerRightCharRatio: Double
    var minMidRightBlockRatio: Double
    var minRightRailBinBlockRatio: Double = 0
    var minRightRailBinCharRatio: Double = 0
    var minPassingRightRailBins: Int = 0
    var rightRailBinCount: Int = 0
    var maxTotalBlockRatio: Double = .greatestFiniteMagnitude
    var maxLowerRightBlockRatio: Double = .greatestFiniteMagnitude
    var maxLowerRightCharRatio: Double = .greatestFiniteMagnitude
    var maxMidRightBlockRatio: Double = .greatestFiniteMagnitude
    var maxRightRailBinBlockRatio: Double = .greatestFiniteMagnitude
    var maxRightRailBinCharRatio: Double = .greatestFiniteMagnitude
    var hardMaxRightRailBinBlockRatio: Double = .greatestFiniteMagnitude
    var hardMaxRightRailBinCharRatio: Double = .greatestFiniteMagnitude
    var maxRightRailBlockDistributionDistance: Double = .greatestFiniteMagnitude
    var maxRightRailCharDistributionDistance: Double = .greatestFiniteMagnitude

    static let a218Zhihu = OCRBenchmarkThresholds(
        minTotalBlockRatio: 0.75,
        minCenterCharRatio: 0.60,
        minLowerRightBlockRatio: 0.55,
        minLowerRightCharRatio: 0.50,
        minMidRightBlockRatio: 0.55,
        minRightRailBinBlockRatio: 0.40,
        minRightRailBinCharRatio: 0.35,
        minPassingRightRailBins: 5,
        rightRailBinCount: 6,
        maxTotalBlockRatio: 1.30,
        maxLowerRightBlockRatio: 1.35,
        maxLowerRightCharRatio: 1.45,
        maxMidRightBlockRatio: 1.35,
        maxRightRailBinBlockRatio: 1.25,
        maxRightRailBinCharRatio: 1.25,
        hardMaxRightRailBinBlockRatio: 1.35,
        hardMaxRightRailBinCharRatio: 1.35,
        maxRightRailBlockDistributionDistance: 0.40,
        maxRightRailCharDistributionDistance: 0.35
    )
}

struct OCRRightRailBinComparison {
    let index: Int
    let outputBlocks: Int
    let benchmarkBlocks: Int
    let blockRatio: Double
    let outputChars: Int
    let benchmarkChars: Int
    let charRatio: Double

    var benchmarkNonEmpty: Bool {
        benchmarkBlocks > 0 || benchmarkChars > 0
    }

    func passed(thresholds: OCRBenchmarkThresholds) -> Bool {
        guard benchmarkNonEmpty else { return true }
        return blockRatio >= thresholds.minRightRailBinBlockRatio &&
            blockRatio <= thresholds.maxRightRailBinBlockRatio &&
            charRatio >= thresholds.minRightRailBinCharRatio &&
            charRatio <= thresholds.maxRightRailBinCharRatio
    }

    func exceedsHardLimit(thresholds: OCRBenchmarkThresholds) -> Bool {
        benchmarkNonEmpty &&
        (blockRatio > thresholds.hardMaxRightRailBinBlockRatio ||
         charRatio > thresholds.hardMaxRightRailBinCharRatio)
    }
}

struct OCRBenchmarkComparisonReport {
    let totalBlocks: Int
    let benchmarkTotalBlocks: Int
    let totalBlockRatio: Double
    let centerChars: Int
    let benchmarkCenterChars: Int
    let centerCharRatio: Double
    let lowerRightBlocks: Int
    let benchmarkLowerRightBlocks: Int
    let lowerRightBlockRatio: Double
    let lowerRightChars: Int
    let benchmarkLowerRightChars: Int
    let lowerRightCharRatio: Double
    let midRightBlocks: Int
    let benchmarkMidRightBlocks: Int
    let midRightBlockRatio: Double
    let rightRailBins: [OCRRightRailBinComparison]
    let rightRailBlockDistributionDistance: Double
    let rightRailCharDistributionDistance: Double
    let thresholds: OCRBenchmarkThresholds

    var benchmarkNonEmptyRightRailBins: Int {
        rightRailBins.filter(\.benchmarkNonEmpty).count
    }

    var passingRightRailBins: Int {
        rightRailBins.reduce(into: 0) { total, bin in
            if bin.benchmarkNonEmpty && bin.passed(thresholds: thresholds) {
                total += 1
            }
        }
    }

    var hasHardRightRailOverflow: Bool {
        rightRailBins.contains { $0.exceedsHardLimit(thresholds: thresholds) }
    }

    var passed: Bool {
        let requiredRightRailBins = min(
            thresholds.minPassingRightRailBins,
            benchmarkNonEmptyRightRailBins
        )
        return totalBlockRatio >= thresholds.minTotalBlockRatio &&
            totalBlockRatio <= thresholds.maxTotalBlockRatio &&
            centerCharRatio >= thresholds.minCenterCharRatio &&
            lowerRightBlockRatio >= thresholds.minLowerRightBlockRatio &&
            lowerRightBlockRatio <= thresholds.maxLowerRightBlockRatio &&
            lowerRightCharRatio >= thresholds.minLowerRightCharRatio &&
            lowerRightCharRatio <= thresholds.maxLowerRightCharRatio &&
            midRightBlockRatio >= thresholds.minMidRightBlockRatio &&
            midRightBlockRatio <= thresholds.maxMidRightBlockRatio &&
            rightRailBlockDistributionDistance <= thresholds.maxRightRailBlockDistributionDistance &&
            rightRailCharDistributionDistance <= thresholds.maxRightRailCharDistributionDistance &&
            !hasHardRightRailOverflow &&
            (requiredRightRailBins == 0 || passingRightRailBins >= requiredRightRailBins)
    }

    func formattedSummary(prefix: String) -> String {
        "\(prefix) OCR benchmark: \(passed ? "PASS" : "FAIL") " +
        "totalBlocks=\(totalBlocks)/\(benchmarkTotalBlocks) (\(format(totalBlockRatio))), " +
        "centerChars=\(centerChars)/\(benchmarkCenterChars) (\(format(centerCharRatio))), " +
        "lowerRightBlocks=\(lowerRightBlocks)/\(benchmarkLowerRightBlocks) (\(format(lowerRightBlockRatio))), " +
        "lowerRightChars=\(lowerRightChars)/\(benchmarkLowerRightChars) (\(format(lowerRightCharRatio))), " +
        "midRightBlocks=\(midRightBlocks)/\(benchmarkMidRightBlocks) (\(format(midRightBlockRatio))), " +
        "rightRailBins=\(passingRightRailBins)/\(benchmarkNonEmptyRightRailBins), " +
        "rightRailBlockDist=\(format(rightRailBlockDistributionDistance)), " +
        "rightRailCharDist=\(format(rightRailCharDistributionDistance))"
    }

    func failureSummary(prefix: String) -> String {
        guard !passed else { return "" }

        var failures: [String] = []
        if totalBlockRatio < thresholds.minTotalBlockRatio {
            failures.append("totalBlocks \(format(totalBlockRatio)) < \(format(thresholds.minTotalBlockRatio))")
        }
        if totalBlockRatio > thresholds.maxTotalBlockRatio {
            failures.append("totalBlocks \(format(totalBlockRatio)) > \(format(thresholds.maxTotalBlockRatio))")
        }
        if centerCharRatio < thresholds.minCenterCharRatio {
            failures.append("centerChars \(format(centerCharRatio)) < \(format(thresholds.minCenterCharRatio))")
        }
        if lowerRightBlockRatio < thresholds.minLowerRightBlockRatio {
            failures.append("lowerRightBlocks \(format(lowerRightBlockRatio)) < \(format(thresholds.minLowerRightBlockRatio))")
        }
        if lowerRightBlockRatio > thresholds.maxLowerRightBlockRatio {
            failures.append("lowerRightBlocks \(format(lowerRightBlockRatio)) > \(format(thresholds.maxLowerRightBlockRatio))")
        }
        if lowerRightCharRatio < thresholds.minLowerRightCharRatio {
            failures.append("lowerRightChars \(format(lowerRightCharRatio)) < \(format(thresholds.minLowerRightCharRatio))")
        }
        if lowerRightCharRatio > thresholds.maxLowerRightCharRatio {
            failures.append("lowerRightChars \(format(lowerRightCharRatio)) > \(format(thresholds.maxLowerRightCharRatio))")
        }
        if midRightBlockRatio < thresholds.minMidRightBlockRatio {
            failures.append("midRightBlocks \(format(midRightBlockRatio)) < \(format(thresholds.minMidRightBlockRatio))")
        }
        if midRightBlockRatio > thresholds.maxMidRightBlockRatio {
            failures.append("midRightBlocks \(format(midRightBlockRatio)) > \(format(thresholds.maxMidRightBlockRatio))")
        }
        if rightRailBlockDistributionDistance > thresholds.maxRightRailBlockDistributionDistance {
            failures.append(
                "rightRailBlockDist \(format(rightRailBlockDistributionDistance)) > \(format(thresholds.maxRightRailBlockDistributionDistance))"
            )
        }
        if rightRailCharDistributionDistance > thresholds.maxRightRailCharDistributionDistance {
            failures.append(
                "rightRailCharDist \(format(rightRailCharDistributionDistance)) > \(format(thresholds.maxRightRailCharDistributionDistance))"
            )
        }
        let requiredRightRailBins = min(
            thresholds.minPassingRightRailBins,
            benchmarkNonEmptyRightRailBins
        )
        if requiredRightRailBins > 0, passingRightRailBins < requiredRightRailBins {
            failures.append("rightRailBins \(passingRightRailBins)/\(benchmarkNonEmptyRightRailBins) < \(requiredRightRailBins)")
        }
        for bin in rightRailBins where bin.exceedsHardLimit(thresholds: thresholds) {
            if bin.blockRatio > thresholds.hardMaxRightRailBinBlockRatio {
                failures.append("rightRailBin[\(bin.index)] blocks \(format(bin.blockRatio)) > \(format(thresholds.hardMaxRightRailBinBlockRatio))")
            }
            if bin.charRatio > thresholds.hardMaxRightRailBinCharRatio {
                failures.append("rightRailBin[\(bin.index)] chars \(format(bin.charRatio)) > \(format(thresholds.hardMaxRightRailBinCharRatio))")
            }
        }
        return "\(prefix) OCR benchmark failed: " + failures.joined(separator: " | ")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct OCRFixturePayload: Codable {
    let blockCount: Int
    let blocks: [RecognizedTextBlock]
    let dominantLanguageCode: String?
    let fullText: String
    let height: Int
    let sourceImage: String
    let width: Int
}

private struct LegacyOCRFixturePayload: Codable {
    let blockCount: Int
    let blocks: [LegacyRecognizedTextBlock]
    let dominantLanguageCode: String?
    let fullText: String
    let height: Int
    let sourceImage: String
    let width: Int
}

private struct LegacyRecognizedTextBlock: Codable {
    var text: String
    var normalizedBounds: NormalizedTextRect
    var dominantLanguageCode: String?

    func upgraded() -> RecognizedTextBlock {
        RecognizedTextBlock(
            text: text,
            normalizedBounds: normalizedBounds,
            dominantLanguageCode: dominantLanguageCode
        )
    }
}

enum E2EOCRBenchmarkValidator {
    static func validate(
        outputImage: CGImage,
        outputImageURL: URL,
        benchmarkImageURL: URL,
        thresholds: OCRBenchmarkThresholds
    ) async throws -> OCRBenchmarkComparisonReport {
        let outputDocument = try await OCRFixtureStore.recognizeAndWrite(
            image: outputImage,
            imageURL: outputImageURL
        )
        let benchmarkDocument = try await OCRFixtureStore.loadOrRecognize(
            imageURL: benchmarkImageURL
        )
        return compare(
            output: outputDocument,
            benchmark: benchmarkDocument,
            thresholds: thresholds
        )
    }

    static func compare(
        output: RecognizedTextDocument,
        benchmark: RecognizedTextDocument,
        thresholds: OCRBenchmarkThresholds
    ) -> OCRBenchmarkComparisonReport {
        let totalBlocks = output.blocks.count
        let benchmarkTotalBlocks = benchmark.blocks.count
        let totalBlockRatio = ratio(totalBlocks, benchmarkTotalBlocks)

        let centerChars = regionCharCount(document: output) { bounds in
            bounds.x >= 0.18 && bounds.x < 0.62
        }
        let benchmarkCenterChars = regionCharCount(document: benchmark) { bounds in
            bounds.x >= 0.18 && bounds.x < 0.62
        }
        let centerCharRatio = ratio(centerChars, benchmarkCenterChars)

        let lowerRightBlocks = regionBlockCount(document: output) { bounds in
            bounds.x >= 0.62 && bounds.y >= 0.25
        }
        let benchmarkLowerRightBlocks = regionBlockCount(document: benchmark) { bounds in
            bounds.x >= 0.62 && bounds.y >= 0.25
        }
        let lowerRightBlockRatio = ratio(lowerRightBlocks, benchmarkLowerRightBlocks)

        let lowerRightChars = regionCharCount(document: output) { bounds in
            bounds.x >= 0.62 && bounds.y >= 0.25
        }
        let benchmarkLowerRightChars = regionCharCount(document: benchmark) { bounds in
            bounds.x >= 0.62 && bounds.y >= 0.25
        }
        let lowerRightCharRatio = ratio(lowerRightChars, benchmarkLowerRightChars)

        let midRightBlocks = regionBlockCount(document: output) { bounds in
            bounds.x >= 0.62 && bounds.y >= 0.35 && bounds.y < 0.75
        }
        let benchmarkMidRightBlocks = regionBlockCount(document: benchmark) { bounds in
            bounds.x >= 0.62 && bounds.y >= 0.35 && bounds.y < 0.75
        }
        let midRightBlockRatio = ratio(midRightBlocks, benchmarkMidRightBlocks)
        let rightRailBins = rightRailBinComparisons(
            output: output,
            benchmark: benchmark,
            thresholds: thresholds
        )
        let rightRailBlockDistributionDistance = distributionDistance(
            outputValues: rightRailBins.map(\.outputBlocks),
            benchmarkValues: rightRailBins.map(\.benchmarkBlocks)
        )
        let rightRailCharDistributionDistance = distributionDistance(
            outputValues: rightRailBins.map(\.outputChars),
            benchmarkValues: rightRailBins.map(\.benchmarkChars)
        )

        return OCRBenchmarkComparisonReport(
            totalBlocks: totalBlocks,
            benchmarkTotalBlocks: benchmarkTotalBlocks,
            totalBlockRatio: totalBlockRatio,
            centerChars: centerChars,
            benchmarkCenterChars: benchmarkCenterChars,
            centerCharRatio: centerCharRatio,
            lowerRightBlocks: lowerRightBlocks,
            benchmarkLowerRightBlocks: benchmarkLowerRightBlocks,
            lowerRightBlockRatio: lowerRightBlockRatio,
            lowerRightChars: lowerRightChars,
            benchmarkLowerRightChars: benchmarkLowerRightChars,
            lowerRightCharRatio: lowerRightCharRatio,
            midRightBlocks: midRightBlocks,
            benchmarkMidRightBlocks: benchmarkMidRightBlocks,
            midRightBlockRatio: midRightBlockRatio,
            rightRailBins: rightRailBins,
            rightRailBlockDistributionDistance: rightRailBlockDistributionDistance,
            rightRailCharDistributionDistance: rightRailCharDistributionDistance,
            thresholds: thresholds
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return numerator > 0 ? 1.0 : 0.0 }
        return Double(numerator) / Double(denominator)
    }

    private static func distributionDistance(
        outputValues: [Int],
        benchmarkValues: [Int]
    ) -> Double {
        guard outputValues.count == benchmarkValues.count, !outputValues.isEmpty else {
            return 0
        }
        let outputTotal = outputValues.reduce(0, +)
        let benchmarkTotal = benchmarkValues.reduce(0, +)
        guard outputTotal > 0, benchmarkTotal > 0 else {
            return outputTotal == benchmarkTotal ? 0 : 1
        }

        var distance = 0.0
        for (output, benchmark) in zip(outputValues, benchmarkValues) {
            let normalizedOutput = Double(output) / Double(outputTotal)
            let normalizedBenchmark = Double(benchmark) / Double(benchmarkTotal)
            distance += abs(normalizedOutput - normalizedBenchmark)
        }
        return distance / 2.0
    }

    private static func regionBlockCount(
        document: RecognizedTextDocument,
        where predicate: (NormalizedTextRect) -> Bool
    ) -> Int {
        document.blocks.reduce(into: 0) { total, block in
            if predicate(block.normalizedBounds) {
                total += 1
            }
        }
    }

    private static func regionCharCount(
        document: RecognizedTextDocument,
        where predicate: (NormalizedTextRect) -> Bool
    ) -> Int {
        document.blocks.reduce(into: 0) { total, block in
            if predicate(block.normalizedBounds) {
                total += block.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            }
        }
    }

    private static func rightRailBinComparisons(
        output: RecognizedTextDocument,
        benchmark: RecognizedTextDocument,
        thresholds: OCRBenchmarkThresholds
    ) -> [OCRRightRailBinComparison] {
        guard thresholds.rightRailBinCount > 0 else { return [] }

        let yLower = 0.20
        let yUpper = 1.0
        let binHeight = (yUpper - yLower) / Double(thresholds.rightRailBinCount)
        return (0..<thresholds.rightRailBinCount).map { index in
            let binLower = yLower + Double(index) * binHeight
            let binUpper = index == thresholds.rightRailBinCount - 1 ? yUpper : (binLower + binHeight)
            let predicate: (NormalizedTextRect) -> Bool = { bounds in
                Double(bounds.x) >= 0.62 &&
                Double(bounds.y) >= binLower &&
                Double(bounds.y) < binUpper
            }
            let outputBlocks = regionBlockCount(document: output, where: predicate)
            let benchmarkBlocks = regionBlockCount(document: benchmark, where: predicate)
            let outputChars = regionCharCount(document: output, where: predicate)
            let benchmarkChars = regionCharCount(document: benchmark, where: predicate)
            return OCRRightRailBinComparison(
                index: index,
                outputBlocks: outputBlocks,
                benchmarkBlocks: benchmarkBlocks,
                blockRatio: ratio(outputBlocks, benchmarkBlocks),
                outputChars: outputChars,
                benchmarkChars: benchmarkChars,
                charRatio: ratio(outputChars, benchmarkChars)
            )
        }
    }
}

private enum OCRFixtureStore {
    static func loadOrRecognize(imageURL: URL) async throws -> RecognizedTextDocument {
        let jsonURL = ocrJSONURL(for: imageURL)
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return try loadDocument(from: jsonURL)
        }
        let image = try loadImage(from: imageURL)
        return try await recognizeAndWrite(image: image, imageURL: imageURL)
    }

    static func recognizeAndWrite(
        image: CGImage,
        imageURL: URL
    ) async throws -> RecognizedTextDocument {
        let document = try await TextRecognizer.recognizeDocument(image: image)
        try write(document: document, image: image, imageURL: imageURL)
        return document
    }

    private static func write(
        document: RecognizedTextDocument,
        image: CGImage,
        imageURL: URL
    ) throws {
        let payload = OCRFixturePayload(
            blockCount: document.blocks.count,
            blocks: document.blocks,
            dominantLanguageCode: document.dominantLanguageCode,
            fullText: document.fullText,
            height: image.height,
            sourceImage: imageURL.path,
            width: image.width
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: ocrJSONURL(for: imageURL))
        try document.fullText.write(
            to: ocrTextURL(for: imageURL),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func loadDocument(from jsonURL: URL) throws -> RecognizedTextDocument {
        let data = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        let payload: OCRFixturePayload
        do {
            payload = try decoder.decode(OCRFixturePayload.self, from: data)
        } catch let decodeError as DecodingError {
            guard case .keyNotFound(let key, _) = decodeError, key.stringValue == "id" else {
                throw decodeError
            }
            let legacyPayload = try decoder.decode(LegacyOCRFixturePayload.self, from: data)
            payload = OCRFixturePayload(
                blockCount: legacyPayload.blockCount,
                blocks: legacyPayload.blocks.map { $0.upgraded() },
                dominantLanguageCode: legacyPayload.dominantLanguageCode,
                fullText: legacyPayload.fullText,
                height: legacyPayload.height,
                sourceImage: legacyPayload.sourceImage,
                width: legacyPayload.width
            )
        }
        return RecognizedTextDocument(
            blocks: payload.blocks,
            dominantLanguageCode: payload.dominantLanguageCode
        )
    }

    private static func loadImage(from imageURL: URL) throws -> CGImage {
        guard let provider = CGDataProvider(url: imageURL as CFURL),
              let image = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw NSError(
                domain: "E2EOCRBenchmarkValidator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not load image at \(imageURL.path)"]
            )
        }
        return image
    }

    private static func ocrJSONURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("ocr.json")
    }

    private static func ocrTextURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("ocr.txt")
    }
}
