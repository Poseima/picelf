// TestHelpers.swift
// PicelfIOSTests — Shared test utilities

import UIKit
@testable import Picelf

enum TestHelpers {

    /// Create a solid-color CGImage for testing.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - color: Fill color (defaults to red).
    /// - Returns: A CGImage, or nil if context creation fails.
    static func makeSolidColorImage(
        width: Int,
        height: Int,
        color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Create a solid-color UIImage for testing.
    static func makeSolidColorUIImage(
        width: Int,
        height: Int,
        color: CGColor = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
    ) -> UIImage? {
        guard let cgImage = makeSolidColorImage(width: width, height: height, color: color) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Create a temporary directory for test isolation.
    /// The caller is responsible for cleanup.
    static func makeTemporaryDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicelfIOSTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Remove a temporary directory.
    static func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
