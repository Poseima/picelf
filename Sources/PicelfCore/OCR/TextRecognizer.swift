import Vision
import CoreGraphics
import NaturalLanguage

enum TextRecognizer {
    static func recognize(image: CGImage) async throws -> String {
        try await recognizeDocument(image: image).fullText
    }

    static func recognizeDocument(image: CGImage) async throws -> RecognizedTextDocument {
        if image.height > 4000 {
            return try await recognizeChunkedDocument(image: image)
        }
        return try recognizeSingleDocument(image: image)
    }

    // MARK: - Single image OCR

    private static func recognizeSingleDocument(image: CGImage) throws -> RecognizedTextDocument {
        let observations = try recognizeObservations(in: image)
        return buildDocument(from: observations)
    }

    private static func recognizeObservations(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "it", "pt"]
        try handler.perform([request])
        return request.results ?? []
    }

    private static func buildDocument(from observations: [VNRecognizedTextObservation]) -> RecognizedTextDocument {
        let blocks = observations
            .compactMap(makeTextBlock)
            .sorted(by: compareBlocks)
        return RecognizedTextDocument(
            blocks: blocks,
            dominantLanguageCode: dominantLanguageCode(for: blocks.map(\.text).joined(separator: "\n"))
        )
    }

    private static func makeTextBlock(from observation: VNRecognizedTextObservation) -> RecognizedTextBlock? {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let bounds = observation.boundingBox
        let topLeftRect = CGRect(
            x: bounds.minX,
            y: 1 - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
        return RecognizedTextBlock(
            text: text,
            normalizedBounds: NormalizedTextRect(rect: topLeftRect),
            dominantLanguageCode: dominantLanguageCode(for: text)
        )
    }

    // MARK: - Chunked OCR for tall images

    private struct OCRChunk {
        let top: Int
        let image: CGImage
    }

    private static func recognizeChunkedDocument(image: CGImage) async throws -> RecognizedTextDocument {
        let chunks = splitImage(image, maxChunkHeight: 3000, overlapPercent: 0.10)
        var allBlocks: [RecognizedTextBlock] = []

        for (index, chunk) in chunks.enumerated() {
            let chunkDocument = try recognizeSingleDocument(image: chunk.image)
            let remappedBlocks = chunkDocument.blocks
                .map { remapChunkBlock($0, chunkTop: chunk.top, chunkHeight: chunk.image.height, fullHeight: image.height) }
                .sorted(by: compareBlocks)

            if index > 0 {
                allBlocks.append(contentsOf: deduplicateOverlap(previous: allBlocks, current: remappedBlocks))
            } else {
                allBlocks.append(contentsOf: remappedBlocks)
            }
        }

        allBlocks.sort(by: compareBlocks)
        return RecognizedTextDocument(
            blocks: allBlocks,
            dominantLanguageCode: dominantLanguageCode(for: allBlocks.map(\.text).joined(separator: "\n"))
        )
    }

    // MARK: - Image splitting

    private static func splitImage(_ image: CGImage, maxChunkHeight: Int, overlapPercent: Double) -> [OCRChunk] {
        let fullHeight = image.height
        let fullWidth = image.width

        guard fullHeight > maxChunkHeight else {
            return [OCRChunk(top: 0, image: image)]
        }

        let overlap = Int(Double(maxChunkHeight) * overlapPercent)
        let effectiveStep = maxChunkHeight - overlap
        let numChunks = max(1, Int(ceil(Double(fullHeight - overlap) / Double(effectiveStep))))

        var chunks: [OCRChunk] = []

        for i in 0..<numChunks {
            let top: Int
            let bottom: Int

            if i == 0 {
                top = 0
                bottom = min(maxChunkHeight, fullHeight)
            } else if i == numChunks - 1 {
                top = max(0, i * effectiveStep)
                bottom = fullHeight
            } else {
                top = max(0, i * effectiveStep)
                bottom = min(top + maxChunkHeight, fullHeight)
            }

            let rect = CGRect(x: 0, y: top, width: fullWidth, height: bottom - top)
            if let cropped = image.cropping(to: rect) {
                chunks.append(OCRChunk(top: top, image: cropped))
            }
        }

        return chunks
    }

    // MARK: - Overlap deduplication

    private static func deduplicateOverlap(previous: [RecognizedTextBlock], current: [RecognizedTextBlock]) -> [RecognizedTextBlock] {
        guard !previous.isEmpty, !current.isEmpty else { return current }

        let tail = Array(previous.suffix(8))
        var deduped = current
        while let first = deduped.first,
              tail.contains(where: { blocksEquivalent($0, first) }) {
            deduped.removeFirst()
        }
        return deduped
    }

    private static func remapChunkBlock(
        _ block: RecognizedTextBlock,
        chunkTop: Int,
        chunkHeight: Int,
        fullHeight: Int
    ) -> RecognizedTextBlock {
        let bounds = block.bounds
        let topPixels = CGFloat(chunkTop) + bounds.minY * CGFloat(chunkHeight)
        let heightPixels = bounds.height * CGFloat(chunkHeight)
        let remapped = CGRect(
            x: bounds.minX,
            y: topPixels / CGFloat(fullHeight),
            width: bounds.width,
            height: heightPixels / CGFloat(fullHeight)
        ).standardized

        return RecognizedTextBlock(
            id: block.id,
            text: block.text,
            normalizedBounds: NormalizedTextRect(rect: clamped(rect: remapped)),
            dominantLanguageCode: block.dominantLanguageCode
        )
    }

    private static func compareBlocks(_ lhs: RecognizedTextBlock, _ rhs: RecognizedTextBlock) -> Bool {
        let left = lhs.bounds
        let right = rhs.bounds
        if abs(left.minY - right.minY) > 0.004 {
            return left.minY < right.minY
        }
        return left.minX < right.minX
    }

    private static func blocksEquivalent(_ lhs: RecognizedTextBlock, _ rhs: RecognizedTextBlock) -> Bool {
        normalizedText(lhs.text) == normalizedText(rhs.text)
            && abs(lhs.bounds.minY - rhs.bounds.minY) <= 0.015
            && abs(lhs.bounds.minX - rhs.bounds.minX) <= 0.05
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private static func dominantLanguageCode(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        return recognizer.dominantLanguage?.rawValue
    }

    private static func clamped(rect: CGRect) -> CGRect {
        let minX = max(0, min(rect.minX, 1))
        let minY = max(0, min(rect.minY, 1))
        let maxX = max(minX, min(rect.maxX, 1))
        let maxY = max(minY, min(rect.maxY, 1))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
