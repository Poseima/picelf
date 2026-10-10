import AppKit
import Foundation
import os

private let stickerLibraryLog = Logger(subsystem: "com.picelf", category: "StickerLibrary")

@MainActor
final class StickerLibrary: ObservableObject {
    static let shared = StickerLibrary()

    struct StickerItem: Identifiable, Codable {
        let id: String
        var filename: String
        var isFavorite: Bool
        var lastUsed: Date?
        var dateAdded: Date
    }

    @Published private(set) var items: [StickerItem] = []
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 32 * 1024 * 1024  // 32 MB
        return cache
    }()
    /// Thread-safe CGImage cache for use in AnnotationRenderer (non-main-actor context)
    private let cgImageCache = NSCache<NSString, CGImageBox>()

    private let stickersDir: URL
    private let manifestURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        stickersDir = appSupport.appendingPathComponent("com.picelf.open.app/Stickers", isDirectory: true)
        manifestURL = stickersDir.appendingPathComponent("manifest.json")

        try? FileManager.default.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        loadManifest()
    }

    // MARK: - Public API

    func image(for id: String) -> NSImage? {
        let key = id as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let url = stickersDir.appendingPathComponent("\(id).png")
        guard let img = NSImage(contentsOf: url) else { return nil }
        let cost = Int(img.size.width * img.size.height * 4)
        imageCache.setObject(img, forKey: key, cost: cost)
        // Also populate cgImage cache
        if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            cgImageCache.setObject(CGImageBox(cg), forKey: key)
        }
        return img
    }

    func cgImage(for id: String) -> CGImage? {
        guard let nsImage = image(for: id) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Main-actor accessor for CGImage, with cache + disk fallback.
    func cgImageSync(for id: String) -> CGImage? {
        if let box = cgImageCache.object(forKey: id as NSString) {
            return box.image
        }
        // Fallback: load from disk
        let url = stickersDir.appendingPathComponent("\(id).png")
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        cgImageCache.setObject(CGImageBox(cg), forKey: id as NSString)
        return cg
    }

    /// Synchronous bridge for non-main rendering code paths.
    /// Draw code in this app runs on the main thread; if not, this traps in debug.
    nonisolated static func cgImageSyncShared(for id: String) -> CGImage? {
        MainActor.assumeIsolated {
            shared.cgImageSync(for: id)
        }
    }

    @discardableResult
    func importImage(_ image: NSImage, originalFilename: String) -> String {
        let id = UUID().uuidString
        let resized = resizeToMax(image, maxDimension: 1024)
        let url = stickersDir.appendingPathComponent("\(id).png")

        if let tiff = resized.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }

        let cost = Int(resized.size.width * resized.size.height * 4)
        imageCache.setObject(resized, forKey: id as NSString, cost: cost)

        let item = StickerItem(
            id: id,
            filename: originalFilename,
            isFavorite: false,
            lastUsed: nil,
            dateAdded: Date()
        )
        items.append(item)
        saveManifest()
        return id
    }

    @discardableResult
    func importFromURL(_ url: URL) -> String? {
        guard url.isFileURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            stickerLibraryLog.debug("Import skipped for missing file URL: \(url.path, privacy: .public)")
            return nil
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        return importImage(image, originalFilename: url.lastPathComponent)
    }

    func deleteSticker(_ id: String) {
        items.removeAll { $0.id == id }
        imageCache.removeObject(forKey: id as NSString)
        let url = stickersDir.appendingPathComponent("\(id).png")
        try? FileManager.default.removeItem(at: url)
        saveManifest()
    }

    func toggleFavorite(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
        saveManifest()
    }

    func markUsed(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastUsed = Date()
        saveManifest()
    }

    var favorites: [StickerItem] {
        items.filter { $0.isFavorite }
    }

    var recents: [StickerItem] {
        items.filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
            .prefix(12)
            .map { $0 }
    }

    // MARK: - Private

    private func resizeToMax(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scale: CGFloat
        if size.width >= size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([StickerItem].self, from: data) else { return }
        items = decoded
    }

    private func saveManifest() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}

private final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
