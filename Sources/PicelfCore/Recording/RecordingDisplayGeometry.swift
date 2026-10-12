#if os(macOS)
import AppKit
import ScreenCaptureKit

/// Global desktop coordinates from Core Graphics (points, y-down).
struct DesktopRecordingRect: Equatable {
    let rect: CGRect
}

/// Coordinates relative to the captured display's top-left corner (points).
struct DisplayRecordingRect: Equatable {
    let rect: CGRect
}

struct RecordingPixelSize: Equatable {
    let width: Int
    let height: Int
}

struct RecordingDisplaySnapshot: Equatable {
    let displayID: CGDirectDisplayID
    let appKitFrame: CGRect
    let cgFrame: CGRect
    let pointPixelScale: CGFloat
    let rotation: Double
    let modePixelSize: RecordingPixelSize
    let primaryDisplayID: CGDirectDisplayID
    let primaryFrame: CGRect

    @MainActor
    static func capture(display: SCDisplay, filter: SCContentFilter) throws -> Self {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }), let primary = NSScreen.screens.first,
        CGDisplayIsActive(display.displayID) != 0,
        CGDisplayBounds(display.displayID) == display.frame,
        let mode = CGDisplayCopyDisplayMode(display.displayID) else {
            throw RecordingError.displayConfigurationChanged
        }
        let scale = CGFloat(filter.pointPixelScale)
        guard isValidRect(display.frame), isValidRect(screen.frame),
              scale.isFinite, scale > 0,
              filter.contentRect.size == display.frame.size,
              ScreenCoordinateSpace.appKitRectToCG(screen.frame, primaryScreenMaxY: primary.frame.maxY) == display.frame else {
            throw RecordingError.displayConfigurationChanged
        }
        return Self(
            displayID: display.displayID,
            appKitFrame: screen.frame,
            cgFrame: display.frame,
            pointPixelScale: scale,
            rotation: CGDisplayRotation(display.displayID),
            modePixelSize: RecordingPixelSize(width: mode.pixelWidth, height: mode.pixelHeight),
            primaryDisplayID: CGMainDisplayID(),
            primaryFrame: primary.frame
        )
    }

    static func isValidRect(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite &&
        rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite &&
        rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}

struct RecordingSelection: Equatable {
    let display: RecordingDisplaySnapshot
    let region: DisplayRecordingRect

    init(display: RecordingDisplaySnapshot, desktopRegion: DesktopRecordingRect) throws {
        guard RecordingDisplaySnapshot.isValidRect(desktopRegion.rect),
              RecordingDisplaySnapshot.isValidRect(display.cgFrame),
              display.pointPixelScale.isFinite, display.pointPixelScale > 0 else {
            throw RecordingError.invalidCaptureRegion
        }
        let clamped = desktopRegion.rect.intersection(display.cgFrame)
        guard RecordingDisplaySnapshot.isValidRect(clamped) else {
            throw RecordingError.invalidCaptureRegion
        }
        self.display = display
        self.region = DisplayRecordingRect(rect: clamped.offsetBy(dx: -display.cgFrame.minX, dy: -display.cgFrame.minY))
    }

    var desktopRegion: DesktopRecordingRect {
        DesktopRecordingRect(rect: region.rect.offsetBy(dx: display.cgFrame.minX, dy: display.cgFrame.minY))
    }

    func validate(current: RecordingDisplaySnapshot?) throws {
        guard current == display else { throw RecordingError.displayConfigurationChanged }
    }
}

/// SC objects live only for one lookup. Pending and running selections keep value snapshots.
struct RecordingDisplayContext {
    let filter: SCContentFilter
    let snapshot: RecordingDisplaySnapshot

    @MainActor
    static func resolve(displayID: CGDirectDisplayID) async throws -> Self {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecordingError.displayConfigurationChanged
        }
        let excluded = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        return Self(filter: filter, snapshot: try RecordingDisplaySnapshot.capture(display: display, filter: filter))
    }
}

enum RecordingStopReason {
    case user
    case durationLimit
    case displayChanged
    case streamError(Error)

    var notice: String? {
        switch self {
        case .user, .durationLimit: return nil
        case .displayChanged: return L10n.recordingDisplayChangedSaved
        case .streamError: return L10n.recordingInterruptedSaved
        }
    }
}

struct RecordingResult {
    let url: URL
    let duration: TimeInterval
}

/// All callers await the same file finalization, including simultaneous system/user stops.
@MainActor
final class RecordingFinalization {
    private var task: Task<RecordingResult, Error>?

    func finish(_ operation: @escaping @MainActor () async throws -> RecordingResult) async throws -> RecordingResult {
        if let task { return try await task.value }
        let task = Task { try await operation() }
        self.task = task
        return try await task.value
    }
}
#endif
