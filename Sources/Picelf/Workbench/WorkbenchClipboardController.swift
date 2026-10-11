import AppKit
import Combine

/// Immutable per-command snapshot: queued pastes never read a newer clipboard.
struct WorkbenchPasteboardSnapshot {
    let fileURLs: [URL]
    let imageData: [Data]

    init(_ pasteboard: NSPasteboard) {
        fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self],
                     options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []).map { $0 as URL }
        imageData = [NSPasteboard.PasteboardType.png, .tiff].compactMap { pasteboard.data(forType: $0) }
    }
    var hasContent: Bool { !fileURLs.isEmpty || !imageData.isEmpty }
}

@MainActor
final class WorkbenchClipboardController: ObservableObject {
    @Published var selectedJobID: UUID?
    @Published private(set) var importedJobID: UUID?
    @Published private(set) var savedURL: URL?
    @Published var errorMessage: String?
    private(set) var displayedIDs: Set<UUID> = []
    private let store: WorkbenchStore
    private var pasteTail: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    var focusGallery: (() -> Void)?

    init(store: WorkbenchStore) { self.store = store }

    func reconcileSelection(displayedIDs: [UUID]) {
        self.displayedIDs = Set(displayedIDs)
        if let id = selectedJobID, self.displayedIDs.contains(id) { return }
        selectedJobID = displayedIDs.first
    }

    var canCopy: Bool {
        guard let id = selectedJobID, displayedIDs.contains(id) else { return false }
        return store.jobs.first { $0.id == id }?.canCopyToClipboard == true
    }

    func select(_ id: UUID) {
        selectedJobID = id
        focusGallery?()
    }

    func copy(to pasteboard: NSPasteboard = .general) {
        guard canCopy, let id = selectedJobID else { return }
        if !store.copyResultToClipboard(jobID: id, pasteboard: pasteboard) {
            errorMessage = L10n.clipboardCopyFailed
        }
    }

    @discardableResult
    func paste(from pasteboard: NSPasteboard = .general) -> Task<Void, Never>? {
        let snapshot = WorkbenchPasteboardSnapshot(pasteboard)
        guard snapshot.hasContent else { return nil }
        let previous = pasteTail
        store.beginTransfer() // Includes time waiting behind earlier paste commands.
        let task = Task { [self] in
            await previous?.value
            defer { store.endTransfer() }
            let ids = await store.importSnapshot(snapshot)
            if let id = ids.last {
                importedJobID = id
            } else {
                errorMessage = L10n.clipboardImportFailed
            }
        }
        pasteTail = task
        return task
    }

    func saveToDownloads(_ id: UUID) {
        store.beginTransfer()
        Task {
            defer { store.endTransfer() }
            do {
                let url = try await store.saveResultToDownloads(jobID: id)
                feedbackTask?.cancel()
                savedURL = url
                feedbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    self?.savedURL = nil
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

/// Only the Workbench window owns this responder. Field editors earlier in the
/// chain retain standard text operations; attached sheets do not fall through.
@MainActor
final class WorkbenchClipboardResponder: NSResponder, NSMenuItemValidation {
    weak var window: NSWindow?
    let clipboard: WorkbenchClipboardController

    init(clipboard: WorkbenchClipboardController) {
        self.clipboard = clipboard
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var acceptsCommands: Bool {
        guard let window else { return false }
        return window.isKeyWindow && window.attachedSheet == nil && !(window.firstResponder is NSTextView)
    }
    @objc func copy(_ sender: Any?) {
        guard acceptsCommands else { return }
        clipboard.copy()
    }
    @objc func paste(_ sender: Any?) {
        guard acceptsCommands else { return }
        clipboard.paste()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard acceptsCommands else { return false }
        switch menuItem.action {
        case #selector(copy(_:)): return clipboard.canCopy
        case #selector(paste(_:)): return WorkbenchPasteboardSnapshot(.general).hasContent
        default: return false
        }
    }
}
