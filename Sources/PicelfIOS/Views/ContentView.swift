import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var preferences = AppPreferences.shared

    @ObservedObject var orchestrator: IOSCaptureOrchestrator
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--uitest-open-relay")
        && UIDevice.current.userInterfaceIdiom == .pad ? 3 : 0
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var navigateToPreview = false
    @State private var completedImage: UIImage?
    @State private var isProcessingSheetPresented = false
    @State private var shouldPresentPreviewAfterProcessingDismiss = false

    var body: some View {
        // Keep the tab bar in sync when the language changes in Settings.
        let _ = preferences.appLanguage
        TabView(selection: $selectedTab) {
            CaptureView(orchestrator: orchestrator)
                .tabItem {
                    Label(L10n.localized("捕获", "Capture"), systemImage: "camera.fill")
                }
                .tag(0)
                .accessibilityIdentifier("tab.capture")

            if UIDevice.current.userInterfaceIdiom == .pad {
                RelayPadView()
                    .tabItem { Label(L10n.localized("接力画板", "Relay Canvas"), systemImage: "pencil.and.outline") }
                    .tag(3)
                    .accessibilityIdentifier("tab.relay")
            }

            LibraryView()
                .tabItem {
                    Label(L10n.localized("资料库", "Library"), systemImage: "folder.fill")
                }
                .tag(1)
                .accessibilityIdentifier("tab.library")

            SettingsView()
                .tabItem {
                    Label(L10n.localized("设置", "Settings"), systemImage: "gearshape.fill")
                }
                .tag(2)
                .accessibilityIdentifier("tab.settings")
        }
        .environment(\.locale, Locale(identifier: L10n.zh ? "zh-Hans" : "en"))
        .tint(IOSTheme.accent)
        .accessibilityIdentifier("app.tabview")
        .sheet(isPresented: showProcessingBinding, onDismiss: handleProcessingDismiss) {
            ProcessingView(orchestrator: orchestrator)
        }
        .fullScreenCover(isPresented: $navigateToPreview) {
            if let image = completedImage {
                PreviewView(image: image)
            }
        }
        .alert(L10n.localized("错误", "Error"), isPresented: $showErrorAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: orchestrator.state) { newState in
            handleStateChange(newState)
        }
        .task {
            await orchestrator.processPendingBroadcastIfNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await orchestrator.processPendingBroadcastIfNeeded()
            }
        }
    }

    private var showProcessingBinding: Binding<Bool> {
        Binding(
            get: {
                switch orchestrator.state {
                case .extracting, .stitching: return true
                default: return false
                }
            },
            set: { newValue in
                if !newValue {
                    orchestrator.cancel()
                }
            }
        )
    }

    private func handleStateChange(_ state: IOSCaptureOrchestrator.State) {
        switch state {
        case .extracting, .stitching:
            isProcessingSheetPresented = true
        case .completed:
            if let image = orchestrator.resultImage {
                completedImage = image
                if isProcessingSheetPresented {
                    shouldPresentPreviewAfterProcessingDismiss = true
                } else {
                    navigateToPreview = true
                }
            }
        case .failed(let message):
            errorMessage = message
            showErrorAlert = true
        default:
            break
        }
    }

    private func handleProcessingDismiss() {
        isProcessingSheetPresented = false
        guard shouldPresentPreviewAfterProcessingDismiss, completedImage != nil else { return }
        shouldPresentPreviewAfterProcessingDismiss = false
        navigateToPreview = true
    }
}
