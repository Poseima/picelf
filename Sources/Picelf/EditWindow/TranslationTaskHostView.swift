import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
@available(macOS 15.0, *)
struct TranslationTaskHostView: View {
    @ObservedObject var document: EditorDocument
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: document.pendingTranslationRequest) {
                syncConfiguration()
            }
            .translationTask(configuration) { session in
                guard let request = document.pendingTranslationRequest else { return }
                await document.handleTranslationSession(session, request: request)
            }
    }

    private func syncConfiguration() {
        guard let request = document.pendingTranslationRequest else {
            configuration = nil
            return
        }

        let source = request.sourceLanguageCode.map(Locale.Language.init(identifier:))
        let target = Locale.Language(identifier: request.targetLanguageCode)

        if var current = configuration,
           current.source == source,
           current.target == target {
            current.invalidate()
            configuration = current
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}
#endif
