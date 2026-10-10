import SwiftUI

@main
struct PicelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesSettingsRootView()
        }
    }
}

@MainActor
private struct PreferencesSettingsRootView: View {
    @StateObject private var navigation = PreferencesNavigationState()

    var body: some View {
        PreferencesView(navigation: navigation)
            .frame(width: navigation.selectedTab.contentSize.width,
                   height: navigation.selectedTab.contentSize.height)
    }
}
