// ResultStore.swift
// PicelfIOS — Persistence for stitch results
//
// Saves full-resolution PNGs and thumbnails to the app documents directory.
// Metadata is persisted as JSON, sorted by date descending.
//
// Target: iOS 16+, Swift 5.9+

import UIKit
import os

private let log = Logger(subsystem: "com.picelf.ios", category: "ResultStore")

@MainActor
final class ResultStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var results: [StitchResult] = []

    // MARK: - Constants

    private static let metadataFileName = "stitch-results.json"
    private static let thumbnailMaxWidth: CGFloat = 200
    private static let rootOverrideEnvironmentKey = "UITEST_RESULT_STORE_ROOT"

    // MARK: - Directories

    private let baseDirectory: URL

    private var documentsDirectory: URL {
        baseDirectory
    }

    private var imagesDirectory: URL {
        documentsDirectory.appendingPathComponent("StitchImages", isDirectory: true)
    }

    private var thumbnailsDirectory: URL {
        documentsDirectory.appendingPathComponent("StitchThumbnails", isDirectory: true)
    }

    private var metadataURL: URL {
        documentsDirectory.appendingPathComponent(Self.metadataFileName)
    }

    // MARK: - Init

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let overridePath = ProcessInfo.processInfo.environment[Self.rootOverrideEnvironmentKey],
                  !overridePath.isEmpty {
            self.baseDirectory = URL(fileURLWithPath: overridePath, isDirectory: true)
        } else {
            self.baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        ensureDirectoriesExist()
        loadMetadata()
    }

    // MARK: - Public API

    /// Save a stitched image and return the result metadata.
    ///
    /// - Parameter image: The full-resolution stitched UIImage.
    /// - Returns: The saved `StitchResult`.
    @discardableResult
    func save(image: UIImage) -> StitchResult? {
        guard let cgImage = image.cgImage else {
            log.error("Cannot save: UIImage has no CGImage backing")
            return nil
        }

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let thumbnailFileName = "\(id.uuidString)-thumb.png"

        // Save full-resolution PNG
        let imageURL = imagesDirectory.appendingPathComponent(fileName)
        guard let pngData = image.pngData() else {
            log.error("Failed to create PNG data")
            return nil
        }
        do {
            try pngData.write(to: imageURL, options: .atomic)
        } catch {
            log.error("Failed to write image: \(error.localizedDescription)")
            return nil
        }

        // Generate and save thumbnail
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)
        if let thumbnail = generateThumbnail(from: image) {
            if let thumbData = thumbnail.pngData() {
                try? thumbData.write(to: thumbnailURL, options: .atomic)
            }
        }

        let result = StitchResult(
            id: id,
            date: Date(),
            width: cgImage.width,
            height: cgImage.height,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName
        )

        results.insert(result, at: 0)
        saveMetadata()

        log.notice("Saved result: \(id.uuidString) (\(cgImage.width)x\(cgImage.height))")
        return result
    }

    /// Load the thumbnail image for a result.
    func loadThumbnail(for result: StitchResult) -> UIImage? {
        let url = thumbnailsDirectory.appendingPathComponent(result.thumbnailFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Load the full-resolution image for a result.
    func loadFullImage(for result: StitchResult) -> UIImage? {
        let url = imagesDirectory.appendingPathComponent(result.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Delete a result and its associated files.
    func delete(_ result: StitchResult) {
        // Remove files
        let imageURL = imagesDirectory.appendingPathComponent(result.fileName)
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(result.thumbnailFileName)
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: thumbnailURL)

        // Remove from list
        results.removeAll { $0.id == result.id }
        saveMetadata()

        log.notice("Deleted result: \(result.id.uuidString)")
    }

    /// Delete multiple results.
    func delete(_ resultsToDelete: Set<UUID>) {
        for id in resultsToDelete {
            if let result = results.first(where: { $0.id == id }) {
                let imageURL = imagesDirectory.appendingPathComponent(result.fileName)
                let thumbnailURL = thumbnailsDirectory.appendingPathComponent(result.thumbnailFileName)
                try? FileManager.default.removeItem(at: imageURL)
                try? FileManager.default.removeItem(at: thumbnailURL)
            }
        }
        results.removeAll { resultsToDelete.contains($0.id) }
        saveMetadata()
    }

    // MARK: - Private Helpers

    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        for dir in [documentsDirectory, imagesDirectory, thumbnailsDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL) else {
            results = []
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([StitchResult].self, from: data)
            results = decoded.sorted { $0.date > $1.date }
        } catch {
            log.error("Failed to decode metadata: \(error.localizedDescription)")
            results = []
        }
    }

    private func saveMetadata() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(results)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            log.error("Failed to save metadata: \(error.localizedDescription)")
        }
    }

    private func generateThumbnail(from image: UIImage) -> UIImage? {
        let maxWidth = Self.thumbnailMaxWidth
        guard image.size.width > 0 else { return nil }

        let scale = maxWidth / image.size.width
        let newSize = CGSize(
            width: maxWidth,
            height: (image.size.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
