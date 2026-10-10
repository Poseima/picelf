// StitchResult.swift
// PicelfIOS — Codable model for a completed stitch result
//
// Target: iOS 16+, Swift 5.9+

import Foundation

/// Represents a saved stitch result with metadata.
struct StitchResult: Codable, Identifiable, Equatable {
    /// Unique identifier for this result.
    let id: UUID
    /// Date the stitch was completed.
    let date: Date
    /// Width of the stitched image in pixels.
    let width: Int
    /// Height of the stitched image in pixels.
    let height: Int
    /// File name of the full-resolution PNG in the documents directory.
    let fileName: String
    /// File name of the 200px-wide thumbnail PNG.
    let thumbnailFileName: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        width: Int,
        height: Int,
        fileName: String,
        thumbnailFileName: String
    ) {
        self.id = id
        self.date = date
        self.width = width
        self.height = height
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
    }
}
