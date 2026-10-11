import SwiftUI

@main
struct PicelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesSettingsRootView()
        }
        .defaultSize(width: PreferencesWindowAppearance.defaultSize.width,
                     height: PreferencesWindowAppearance.defaultSize.height)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands { PicelfCommands(openPreferences: appDelegate.openPreferences) }
    }
}

private struct PicelfCommands: Commands {
    let openPreferences: () -> Void
    @ObservedObject private var updates = UpdateController.shared
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some Commands {
        let _ = prefs.appLanguage
        // Route the system Settings command through the same AppKit window as
        // the status menu, preserving category, appearance and user resizing.
        CommandGroup(replacing: .appSettings) {
            Button(L10n.preferences) { openPreferences() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button(L10n.localized("检查更新…", "Check for Updates…")) { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
        }
    }
}

@MainActor
private struct PreferencesSettingsRootView: View {
    @StateObject private var navigation = PreferencesNavigationState()

    var body: some View {
        PreferencesView(navigation: navigation)
    }
}
