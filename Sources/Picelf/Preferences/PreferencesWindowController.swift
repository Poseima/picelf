import AppKit
import Combine
import SwiftUI

@MainActor
enum PreferencesWindowAppearance {
    static let defaultSize = CGSize(width: 900, height: 620)
    static let minimumSize = CGSize(width: 820, height: 540)

    /// Applies to both the AppKit window and SwiftUI's Settings scene. Never
    /// resize here: SwiftUI updates this bridge during navigation and editing.
    static func apply(to window: NSWindow) {
        let title = L10n.preferences.replacingOccurrences(of: "...", with: "")
        if window.title != title { window.title = title }
        if window.contentMinSize != minimumSize { window.contentMinSize = minimumSize }
        let style = window.styleMask.union([.resizable, .fullSizeContentView])
        if window.styleMask != style { window.styleMask = style }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if window.appearance?.name != .darkAqua { window.appearance = NSAppearance(named: .darkAqua) }
        if window.toolbarStyle != .unifiedCompact { window.toolbarStyle = .unifiedCompact }
        if window.isOpaque { window.isOpaque = false }
        if window.backgroundColor != .clear { window.backgroundColor = .clear }
        if window.tabbingMode != .disallowed { window.tabbingMode = .disallowed }
    }
}

/// Configures the window supplied by SwiftUI without changing its frame or
/// replacing its content view. Also keeps its title in sync with app language.
struct PreferencesWindowAppearanceBridge: NSViewRepresentable {
    final class WindowView: NSView {
        private var configurationScheduled = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            guard window != nil, !configurationScheduled else { return }
            configurationScheduled = true
            // AppKit window styling can invalidate SwiftUI layout. Apply it
            // after the current update rather than from inside that layout.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configurationScheduled = false
                if let window = self.window { PreferencesWindowAppearance.apply(to: window) }
            }
        }
    }

    func makeNSView(context: Context) -> WindowView { WindowView() }

    func updateNSView(_ view: WindowView, context: Context) {
        view.scheduleConfiguration()
    }
}

@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?
    private let navigationState = PreferencesNavigationState()
    private var languageObservation: AnyCancellable?

    init() {
        languageObservation = AppPreferences.shared.$appLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let window = self?.window else { return }
                PreferencesWindowAppearance.apply(to: window)
            }
    }

    func show() {
        let win = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func show(tab: PreferencesTab) {
        navigationState.selectedTab = tab
        show()
    }

    private func ensureWindow() -> NSWindow {
        if let existing = window { return existing }

        let hosting = NSHostingView(rootView: PreferencesView(navigation: navigationState))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PreferencesWindowAppearance.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        PreferencesWindowAppearance.apply(to: window)
        window.identifier = NSUserInterfaceItemIdentifier("preferences.window")
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        self.window = window
        return window
    }
}
