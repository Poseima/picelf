import AppKit
import os

private let log = Logger(subsystem: "com.picelf", category: "PinBindingMonitor")

/// Monitors window/screen visibility and manages pin z-ordering based on their binding.
@MainActor
final class PinBindingMonitor {

    var onShowPin: ((UUID) -> Void)?
    var onHidePin: ((UUID) -> Void)?
    /// Order pin just above the given window number in the z-order.
    var onOrderPinAbove: ((UUID, Int) -> Void)?

    private var trackedPins: [UUID: PinBinding] = [:]
    private var visiblePins: Set<UUID> = []
    private var pollTimer: Timer?
    private var screenObserver: Any?

    func reconfigure(panels: [UUID: PinnedImagePanel]) {
        trackedPins.removeAll()
        for (id, panel) in panels {
            let binding = panel.currentBinding
            switch binding {
            case .window, .screen:
                trackedPins[id] = binding
            default:
                break
            }
        }

        if trackedPins.isEmpty {
            stopTimer()
        } else {
            startTimerIfNeeded()
            evaluateNow()
        }
    }

    func evaluateNow() {
        let onScreenWindows = queryOnScreenWindows()
        let connectedDisplayIDs = Set(NSScreen.screens.compactMap { displayID(for: $0) })

        for (pinID, binding) in trackedPins {
            switch binding {
            case .window(let bundleID, _, let title):
                // Find matching window and its CGWindowID for z-ordering
                if let match = onScreenWindows.first(where: { $0.bundleID == bundleID && matchTitle($0.title, against: title) }) {
                    let wasVisible = visiblePins.contains(pinID)
                    if !wasVisible {
                        visiblePins.insert(pinID)
                        onShowPin?(pinID)
                    }
                    onOrderPinAbove?(pinID, match.windowNumber)
                } else {
                    if visiblePins.contains(pinID) {
                        visiblePins.remove(pinID)
                        onHidePin?(pinID)
                    }
                }

            case .screen(let displayID, _):
                let shouldShow = connectedDisplayIDs.contains(displayID)
                let wasVisible = visiblePins.contains(pinID)
                if shouldShow && !wasVisible {
                    visiblePins.insert(pinID)
                    onShowPin?(pinID)
                } else if !shouldShow && wasVisible {
                    visiblePins.remove(pinID)
                    onHidePin?(pinID)
                }

            default:
                break
            }
        }
    }

    func startTrackingIfNeeded(pinID: UUID, binding: PinBinding) {
        switch binding {
        case .window, .screen:
            trackedPins[pinID] = binding
            startTimerIfNeeded()
            evaluateNow()
        default:
            stopTracking(pinID: pinID)
            if !visiblePins.contains(pinID) {
                visiblePins.insert(pinID)
                onShowPin?(pinID)
            }
        }
    }

    func stopTracking(pinID: UUID) {
        trackedPins.removeValue(forKey: pinID)
        visiblePins.remove(pinID)
        if trackedPins.isEmpty { stopTimer() }
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateNow()
            }
        }
        setupScreenObserver()
        log.info("Binding monitor started")
    }

    private func stopTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        log.info("Binding monitor stopped")
    }

    private func setupScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateNow()
            }
        }
    }

    // MARK: - Window Query

    private struct WindowEntry {
        let bundleID: String
        let title: String
        let windowNumber: Int
    }

    private func queryOnScreenWindows() -> [WindowEntry] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var entries: [WindowEntry] = []
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let windowNumber = info[kCGWindowNumber as String] as? Int else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 50 && h > 50 else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            guard let bundleID = app?.bundleIdentifier else { continue }
            if bundleID == Bundle.main.bundleIdentifier { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            entries.append(WindowEntry(bundleID: bundleID, title: title, windowNumber: windowNumber))
        }
        return entries
    }

    private func matchTitle(_ windowTitle: String, against bindingTitle: String) -> Bool {
        if bindingTitle.isEmpty { return true }
        if windowTitle == bindingTitle { return true }
        if windowTitle.hasPrefix(bindingTitle) { return true }
        if bindingTitle.count > 10 && windowTitle.hasPrefix(String(bindingTitle.prefix(30))) { return true }
        return false
    }

    // MARK: - Menu Helpers

    static func availableScreens() -> [(displayID: UInt32, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen) else { return nil }
            return (id, screen.localizedName)
        }
    }

    static func availableWindows() -> [(bundleID: String, appName: String, title: String)] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var result: [(bundleID: String, appName: String, title: String)] = []
        var seen = Set<String>()

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 50 && h > 50 else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            guard let bundleID = app?.bundleIdentifier else { continue }
            if bundleID == Bundle.main.bundleIdentifier { continue }

            let appName = app?.localizedName ?? (info[kCGWindowOwnerName as String] as? String ?? "")
            let title = info[kCGWindowName as String] as? String ?? ""
            let key = "\(bundleID)|\(title)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append((bundleID, appName, title))
        }
        return Array(result.prefix(15))
    }
}

private func displayID(for screen: NSScreen) -> UInt32? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
}
