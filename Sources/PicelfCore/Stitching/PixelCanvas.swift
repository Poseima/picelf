// PixelCanvas.swift
// Picelf — Raw Pixel Buffer Compositing
//
// Replaces CGContext-based compositeSlice with raw memcpy for ~30× faster compositing.
// Buffer uses RGBA (premultipliedLast) matching the capture pipeline.
//
// Target: macOS 14+, Swift 5.9+

import Foundation
import CoreGraphics

/// A growable raw-pixel buffer for incremental image stitching.
///
/// Instead of allocating a new CGContext + drawing two CGImages per frame
/// (30-50ms), PixelCanvas maintains a single RGBA buffer and appends rows
/// via `memcpy` (~1ms).
///
/// CGImage is only created on demand for preview (throttled) and final export.
final class PixelCanvas {

    private(set) var width: Int = 0
    private(set) var currentHeight: Int = 0
    private var allocatedHeight: Int = 0
    private var buffer: UnsafeMutablePointer<UInt8>?

    /// Bytes per row = width × 4 (RGBA).
    var bytesPerRow: Int { width * 4 }

    /// Total allocated bytes.
    var allocatedBytes: Int { allocatedHeight * bytesPerRow }

    deinit {
        buffer?.deallocate()
    }

    // MARK: - First Frame

    /// Initialize the canvas with the first frame's pixel data.
    /// Allocates buffer with 2× headroom for growth.
    func setFirstFrame(
        rgbaPtr: UnsafePointer<UInt8>, bpr: Int,
        w: Int, h: Int
    ) {
        width = w
        currentHeight = h
        allocatedHeight = h * 2  // 2× over-allocate

        let newBPR = w * 4
        buffer?.deallocate()
        buffer = .allocate(capacity: allocatedHeight * newBPR)

        // Copy row by row (source bpr may differ from our bpr)
        if bpr == newBPR {
            buffer!.update(from: rgbaPtr, count: h * newBPR)
        } else {
            for row in 0..<h {
                let dst = buffer! + row * newBPR
                let src = rgbaPtr + row * bpr
                dst.update(from: src, count: newBPR)
            }
        }
    }

    // MARK: - Trim

    /// Remove rows from the bottom of the canvas.
    /// Next appendRows() will overwrite the trimmed region.
    func trimBottom(_ rows: Int) {
        currentHeight = max(0, currentHeight - rows)
    }

    // MARK: - Append Rows

    /// Append new rows from a frame to the canvas.
    ///
    /// - Parameters:
    ///   - rgbaPtr: Source pixel data pointer.
    ///   - bpr: Source bytes per row.
    ///   - sourceStartRow: First row in the source to copy (image coords, y=0 at top).
    ///   - sourceRowCount: Number of rows to copy from the source.
    ///
    /// The new rows are appended at the bottom of the canvas (after `currentHeight`).
    func appendRows(
        from rgbaPtr: UnsafePointer<UInt8>, bpr: Int,
        sourceStartRow: Int, sourceRowCount: Int
    ) {
        guard let buf = buffer, sourceRowCount > 0 else { return }

        let newHeight = currentHeight + sourceRowCount
        let bprSelf = bytesPerRow

        // Grow buffer if needed (2× strategy)
        if newHeight > allocatedHeight {
            let newAllocated = max(newHeight * 2, allocatedHeight + sourceRowCount * 4)
            let newBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: newAllocated * bprSelf)
            // Copy existing content
            newBuf.update(from: buf, count: currentHeight * bprSelf)
            buf.deallocate()
            buffer = newBuf
            allocatedHeight = newAllocated
        }

        // Copy source rows to the end of the canvas
        let dst = buffer! + currentHeight * bprSelf
        if bpr == bprSelf {
            // Fast path: same row stride → single memcpy
            let src = rgbaPtr + sourceStartRow * bpr
            dst.update(from: src, count: sourceRowCount * bprSelf)
        } else {
            // Row-by-row copy (different stride)
            for i in 0..<sourceRowCount {
                let srcRow = rgbaPtr + (sourceStartRow + i) * bpr
                let dstRow = dst + i * bprSelf
                dstRow.update(from: srcRow, count: bprSelf)
            }
        }

        currentHeight = newHeight
    }

    /// Overwrite existing rows in the canvas (for overlap zone updates).
    ///
    /// - Parameters:
    ///   - rgbaPtr: Source pixel data pointer.
    ///   - bpr: Source bytes per row.
    ///   - sourceStartRow: First row in the source to copy.
    ///   - rowCount: Number of rows to copy.
    ///   - canvasStartRow: Destination row in the canvas.
    func overwriteRows(
        from rgbaPtr: UnsafePointer<UInt8>, bpr: Int,
        sourceStartRow: Int, rowCount: Int,
        canvasStartRow: Int
    ) {
        guard let buf = buffer, rowCount > 0 else { return }
        guard canvasStartRow >= 0, canvasStartRow + rowCount <= currentHeight else { return }

        let bprSelf = bytesPerRow

        if bpr == bprSelf {
            let src = rgbaPtr + sourceStartRow * bpr
            let dst = buf + canvasStartRow * bprSelf
            dst.update(from: src, count: rowCount * bprSelf)
        } else {
            for i in 0..<rowCount {
                let srcRow = rgbaPtr + (sourceStartRow + i) * bpr
                let dstRow = buf + (canvasStartRow + i) * bprSelf
                dstRow.update(from: srcRow, count: bprSelf)
            }
        }
    }

    // MARK: - CGImage Export

    /// Create a CGImage from the current canvas contents.
    /// This copies the buffer — safe to call while stitching continues.
    func makeCGImage() -> CGImage? {
        guard let buf = buffer, currentHeight > 0, width > 0 else { return nil }

        let bpr = bytesPerRow
        let totalBytes = currentHeight * bpr

        // Copy buffer to CFData (CGImage takes ownership of the data)
        let data = CFDataCreate(nil, buf, totalBytes)!
        let provider = CGDataProvider(data: data)!

        return CGImage(
            width: width,
            height: currentHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bpr,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Direct read-only access to the raw buffer (for pixel-level operations).
    /// Returns nil if the canvas is empty.
    var rawPointer: UnsafePointer<UInt8>? {
        guard let buf = buffer, currentHeight > 0 else { return nil }
        return UnsafePointer(buf)
    }
}
