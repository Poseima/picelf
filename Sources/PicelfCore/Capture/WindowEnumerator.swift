import Foundation
import ScreenCaptureKit
import AppKit
import os

private let log = Logger(subsystem: "com.picelf", category: "WindowEnumerator")

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appBundleID: String
    let frame: CGRect
    let isOnScreen: Bool

    init(id: CGWindowID, title: String, appName: String, appBundleID: String,
         frame: CGRect, isOnScreen: Bool) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appBundleID = appBundleID
        self.frame = frame
        self.isOnScreen = isOnScreen
    }

    init(from scWindow: SCWindow) {
        self.id = scWindow.windowID
        self.title = scWindow.title ?? "(untitled)"
        self.appName = scWindow.owningApplication?.applicationName ?? "(unknown)"
        self.appBundleID = scWindow.owningApplication?.bundleIdentifier ?? ""
        // SCWindow.frame uses CG coords (y-down); convert to AppKit (y-up) for UI use.
        self.frame = Self.cgToAppKit(scWindow.frame)
        self.isOnScreen = scWindow.isOnScreen
    }

    /// Convert CG screen coordinates (y-down) to AppKit screen coordinates (y-up).
    static func cgToAppKit(_ rect: CGRect) -> CGRect {
        ScreenCoordinateSpace.cgRectToAppKit(rect)
    }

    /// Convert AppKit screen coordinates (y-up) to CG screen coordinates (y-down).
    static func appKitToCG(_ rect: CGRect) -> CGRect {
        ScreenCoordinateSpace.appKitRectToCG(rect)
    }
}

@MainActor
class WindowEnumerator: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var error: Error?

    func refreshAvailableContent() async {
        log.info("refreshAvailableContent() called")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let allWindows = content.windows
            log.info("SCShareableContent returned \(allWindows.count) raw windows")

            self.windows = allWindows
                .filter { $0.frame.width > 50 && $0.frame.height > 50 }
                .filter { $0.windowLayer == 0 }
                .map { WindowInfo(from: $0) }

            log.info("After filtering: \(self.windows.count) eligible windows")
            for (i, w) in self.windows.prefix(5).enumerated() {
                log.debug("  window[\(i)]: id=\(w.id) '\(w.title)' app='\(w.appName)' frame=\(w.frame.debugDescription)")
            }

            if self.windows.isEmpty && !allWindows.isEmpty {
                log.warning("All \(allWindows.count) windows were filtered out (too small or wrong layer)")
            } else if self.windows.isEmpty {
                log.error("0 windows returned — screen recording permission likely denied. Check System Settings > Privacy & Security > Screen Recording")
            }

            self.error = nil
        } catch {
            log.error("SCShareableContent.excludingDesktopWindows threw: \(error.localizedDescription)")
            self.error = error
        }
    }

    func scWindow(for info: WindowInfo) async -> SCWindow? {
        log.debug("scWindow(for: id=\(info.id)) looking up SCWindow")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let result = content.windows.first { $0.windowID == info.id }
            if result == nil {
                log.error("scWindow lookup FAILED — windowID \(info.id) not found in \(content.windows.count) windows")
            }
            return result
        } catch {
            log.error("scWindow lookup threw: \(error.localizedDescription)")
            return nil
        }
    }

    func scDisplay(for displayID: CGDirectDisplayID) async -> SCDisplay? {
        log.debug("scDisplay(for: id=\(displayID)) looking up SCDisplay")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let result = content.displays.first { $0.displayID == displayID }
            if result == nil {
                log.error("scDisplay lookup FAILED — displayID \(displayID) not found in \(content.displays.count) displays")
            }
            return result
        } catch {
            log.error("scDisplay lookup threw: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func findClosestWindow(to point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        if let containing = windows.first(where: { $0.frame.contains(point) }) {
            return containing
        }
        return windows.min(by: {
            let c0 = CGPoint(x: $0.frame.midX, y: $0.frame.midY)
            let c1 = CGPoint(x: $1.frame.midX, y: $1.frame.midY)
            return hypot(point.x - c0.x, point.y - c0.y) < hypot(point.x - c1.x, point.y - c1.y)
        })
    }

    /// Find the top-most window that contains the point using a front-to-back
    /// window id ordering. Returns nil when no window contains the point.
    nonisolated static func findTopmostWindow(
        containing point: CGPoint,
        in windows: [WindowInfo],
        orderedFrontToBackBy windowIDs: [CGWindowID]
    ) -> WindowInfo? {
        let containing = windows.filter { $0.frame.contains(point) }
        guard !containing.isEmpty else { return nil }

        guard !windowIDs.isEmpty else { return containing.first }
        let byID = Dictionary(uniqueKeysWithValues: containing.map { ($0.id, $0) })
        for id in windowIDs {
            if let window = byID[id] {
                return window
            }
        }
        return containing.first
    }
}
