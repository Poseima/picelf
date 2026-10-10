import AppKit
import Combine
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?
    private let navigationState = PreferencesNavigationState()
    private var navigationObservation: AnyCancellable?
    private var languageObservation: AnyCancellable?

    init() {
        navigationObservation = navigationState.$selectedTab
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] tab in
                self?.resizeWindow(for: tab, animated: true)
            }
        languageObservation = AppPreferences.shared.$appLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.window?.title = L10n.preferences.replacingOccurrences(of: "...", with: "")
            }
    }

    func show() {
        let win = ensureWindow()
        resizeWindow(for: navigationState.selectedTab, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func show(tab: PreferencesTab) {
        navigationState.selectedTab = tab
        show()
    }

    private func ensureWindow() -> NSWindow {
        if let existing = window {
            return existing
        }

        let hosting = NSHostingView(rootView: PreferencesView(navigation: navigationState))

        let contentSize = preferredContentSize(for: navigationState.selectedTab)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.preferences.replacingOccurrences(of: "...", with: "")
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        self.window = window
        return window
    }

    private func preferredContentSize(for tab: PreferencesTab) -> NSSize {
        tab.contentSize
    }

    private func resizeWindow(for tab: PreferencesTab, animated: Bool) {
        guard let window else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: preferredContentSize(for: tab))).size
        guard abs(window.frame.width - target.width) > 0.5 || abs(window.frame.height - target.height) > 0.5 else { return }

        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}
