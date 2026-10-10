import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum SubjectExtractor {

    #if canImport(AppKit)
    @available(macOS 14.0, *)
    static func extractSubject(from image: NSImage) async throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SubjectExtractorError.noImage
        }
        let outputCG = try await extractSubjectCG(from: cgImage)
        return NSImage(cgImage: outputCG, size: image.size)
    }
    #elseif canImport(UIKit)
    @available(iOS 17.0, *)
    static func extractSubject(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw SubjectExtractorError.noImage
        }
        let outputCG = try await extractSubjectCG(from: cgImage)
        return UIImage(cgImage: outputCG)
    }
    #endif

    @available(macOS 14.0, iOS 17.0, *)
    static func extractSubjectCG(from cgImage: CGImage) async throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw SubjectExtractorError.noMask
        }

        let mask = try result.generateScaledMaskForImage(
            forInstances: result.allInstances, from: handler
        )

        let ciImage = CIImage(cgImage: cgImage)
        let maskCI = CIImage(cvPixelBuffer: mask)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = ciImage
        filter.maskImage = maskCI
        filter.backgroundImage = CIImage.empty()

        guard let outputCI = filter.outputImage else {
            throw SubjectExtractorError.filterFailed
        }

        let context = CIContext()
        guard let outputCG = context.createCGImage(outputCI, from: ciImage.extent) else {
            throw SubjectExtractorError.renderFailed
        }

        return outputCG
    }
}

enum SubjectExtractorError: LocalizedError {
    case noImage
    case noMask
    case filterFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noImage: return "Could not get CGImage from source"
        case .noMask: return "No foreground subject detected"
        case .filterFailed: return "Mask blend filter failed"
        case .renderFailed: return "Failed to render final image"
        }
    }
}
