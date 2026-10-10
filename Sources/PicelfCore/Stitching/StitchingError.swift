// StitchingError.swift
// Picelf — Stitching Error Types & Configuration

import Foundation
import CoreGraphics

/// Errors that can occur during the stitching pipeline.
enum StitchingError: LocalizedError {
    case noFrames
    case singleFrame
    case frameSizeMismatch(expected: CGSize, got: CGSize)
    case overlapDetectionFailed(frameIndex: Int)
    case contextCreationFailed(width: Int, height: Int)
    case pixelDataUnavailable
    case exportFailed(format: String, reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noFrames:
            return "No frames provided for stitching."
        case .singleFrame:
            return "Only one frame provided — nothing to stitch."
        case .frameSizeMismatch(let expected, let got):
            return "Frame size mismatch: expected \(Int(expected.width))×\(Int(expected.height)), got \(Int(got.width))×\(Int(got.height))."
        case .overlapDetectionFailed(let idx):
            return "Could not detect overlap between frame \(idx) and frame \(idx + 1). The content may have changed too much."
        case .contextCreationFailed(let w, let h):
            return "Failed to create bitmap context (\(w)×\(h))."
        case .pixelDataUnavailable:
            return "Could not access raw pixel data for the image."
        case .exportFailed(let fmt, let reason):
            return "Export to \(fmt) failed: \(reason)."
        case .cancelled:
            return "Stitching was cancelled."
        }
    }
}

/// Configuration for the stitching engine.
/// Placeholder retained for StitchingCoordinator API compatibility.
struct StitchingConfiguration {
    static let `default` = StitchingConfiguration()
}

/// Placeholder for API compatibility.
struct StitchRuntimePolicy {
    static let defaultBalanced = StitchRuntimePolicy()
}

struct StitchRunMetrics {
    let totalFrames: Int
    let skippedFrames: Int
    let downScrollFrames: Int
    let upScrollFrames: Int
    let duplicateRejects: Int
    let noMovementRejects: Int
    let finalPixelWidth: Int
    let finalPixelHeight: Int
    let elapsedMilliseconds: Int
}

enum StitchRuntimeEvent {
    case phaseStarted(name: String, mode: String)
}

/// Placeholder for API compatibility.
enum StitchExecutionMode: String, Codable {
    case balanced
    case safeFast
}
