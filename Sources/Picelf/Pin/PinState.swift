import Foundation
import CoreGraphics

/// Describes what a pinned image is bound to for visibility.
enum PinBinding: Codable, Equatable {
    case allDesktops
    case currentDesktopOnly
    case desktop
    case screen(displayID: UInt32, displayName: String)
    case window(appBundleID: String, appName: String, windowTitle: String)
}

/// Represents the persisted state of a single pinned image on the desktop.
struct PinnedState: Codable, Identifiable {
    let id: UUID
    let imageURL: URL           // Absolute path to image on disk
    var frameX: CGFloat         // Screen position (AppKit coords)
    var frameY: CGFloat
    var frameW: CGFloat
    var frameH: CGFloat
    var zoomScale: CGFloat
    var opacity: CGFloat
    var sourceJobID: UUID?
    var originalImageW: CGFloat
    var originalImageH: CGFloat
    var binding: PinBinding

    var frame: CGRect {
        get { CGRect(x: frameX, y: frameY, width: frameW, height: frameH) }
        set {
            frameX = newValue.origin.x
            frameY = newValue.origin.y
            frameW = newValue.size.width
            frameH = newValue.size.height
        }
    }

    var originalImageSize: CGSize {
        CGSize(width: originalImageW, height: originalImageH)
    }

    init(id: UUID, imageURL: URL, frame: CGRect, zoomScale: CGFloat, opacity: CGFloat, sourceJobID: UUID?, originalImageSize: CGSize, binding: PinBinding = .allDesktops) {
        self.id = id
        self.imageURL = imageURL
        self.frameX = frame.origin.x
        self.frameY = frame.origin.y
        self.frameW = frame.size.width
        self.frameH = frame.size.height
        self.zoomScale = zoomScale
        self.opacity = opacity
        self.sourceJobID = sourceJobID
        self.originalImageW = originalImageSize.width
        self.originalImageH = originalImageSize.height
        self.binding = binding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageURL = try container.decode(URL.self, forKey: .imageURL)
        frameX = try container.decode(CGFloat.self, forKey: .frameX)
        frameY = try container.decode(CGFloat.self, forKey: .frameY)
        frameW = try container.decode(CGFloat.self, forKey: .frameW)
        frameH = try container.decode(CGFloat.self, forKey: .frameH)
        zoomScale = try container.decode(CGFloat.self, forKey: .zoomScale)
        opacity = try container.decode(CGFloat.self, forKey: .opacity)
        sourceJobID = try container.decodeIfPresent(UUID.self, forKey: .sourceJobID)
        originalImageW = try container.decode(CGFloat.self, forKey: .originalImageW)
        originalImageH = try container.decode(CGFloat.self, forKey: .originalImageH)
        binding = try container.decodeIfPresent(PinBinding.self, forKey: .binding) ?? .allDesktops
    }
}

/// Manages persistence of pin states to disk.
enum PinStateStore {
    private static let fileURL: URL = {
        let dir = AppDataPaths.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AppDataPaths.pinnedStateFileURL
    }()

    static func load() -> [PinnedState] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([PinnedState].self, from: data)
        } catch {
            return []
        }
    }

    static func save(_ states: [PinnedState]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(states)
            try data.write(to: fileURL, options: .atomic)
        } catch {}
    }

    static func append(_ state: PinnedState) {
        var states = load()
        states.append(state)
        save(states)
    }

    static func remove(id: UUID) {
        var states = load()
        states.removeAll { $0.id == id }
        save(states)
    }

    static func update(id: UUID, frame: CGRect? = nil, zoomScale: CGFloat? = nil, opacity: CGFloat? = nil, binding: PinBinding? = nil) {
        var states = load()
        guard let idx = states.firstIndex(where: { $0.id == id }) else { return }
        if let frame { states[idx].frame = frame }
        if let zoomScale { states[idx].zoomScale = zoomScale }
        if let opacity { states[idx].opacity = opacity }
        if let binding { states[idx].binding = binding }
        save(states)
    }
}
