import SwiftUI

@main
struct PicelfIOSApp: App {
    @StateObject private var resultStore: ResultStore
    @StateObject private var orchestrator: IOSCaptureOrchestrator

    init() {
        let store = ResultStore()
        _resultStore = StateObject(wrappedValue: store)
        _orchestrator = StateObject(wrappedValue: IOSCaptureOrchestrator(resultStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(orchestrator: orchestrator)
                .environmentObject(resultStore)
        }
    }
}
