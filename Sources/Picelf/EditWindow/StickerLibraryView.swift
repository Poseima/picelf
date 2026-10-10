import SwiftUI
import UniformTypeIdentifiers
import os

private let stickerLibraryLog = Logger(subsystem: "com.picelf", category: "StickerLibraryView")

struct StickerLibraryView: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject private var library = StickerLibrary.shared
    @EnvironmentObject private var workbenchStore: WorkbenchStore
    @State private var selectedTab: StickerTab = .pinned
    @State private var showingFileImporter = false

    private enum StickerTab: String, CaseIterable {
        case pinned, all, favorites, recents, emoji
        var label: String {
            switch self {
            case .pinned: return L10n.filterPinned
            case .all: return L10n.stickerAll
            case .favorites: return L10n.stickerFavorites
            case .recents: return L10n.stickerRecents
            case .emoji: return L10n.stickerEmoji
            }
        }
    }

    private let emojiList = ["★", "✅", "❗", "🔥", "💡", "📌", "🔒", "🙂"]

    private var pinnedJobs: [WorkbenchJob] {
        workbenchStore.jobs.filter { $0.isPinned && $0.status == .completed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(StickerTab.allCases, id: \.self) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button(action: { showingFileImporter = true }) {
                    Image(systemName: "plus")
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                .buttonStyle(.borderless)
                .iconTip(.importSticker)
            }

            Group {
                switch selectedTab {
                case .pinned:
                    if pinnedJobs.isEmpty {
                        emptyState
                    } else {
                        pinnedGrid
                    }
                case .all:
                    if library.items.isEmpty {
                        emptyState
                    } else {
                        imageGrid(items: library.items)
                    }
                case .favorites:
                    if library.favorites.isEmpty {
                        emptyState
                    } else {
                        imageGrid(items: library.favorites)
                    }
                case .recents:
                    if library.recents.isEmpty {
                        emptyState
                    } else {
                        imageGrid(items: library.recents)
                    }
                case .emoji:
                    emojiGrid
                }
            }
            .frame(minHeight: 80)
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .tint(EditorTheme.accent)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.png, .jpeg, .gif, .image],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                library.importFromURL(url)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(L10n.stickerNoItems)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EditorTheme.secondaryText)
            Text(L10n.stickerImportPrompt)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(EditorTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Pinned (Workbench) Grid

    private var pinnedGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 64))], spacing: 6) {
            ForEach(pinnedJobs) { job in
                pinnedCell(job)
            }
        }
    }

    private func pinnedCell(_ job: WorkbenchJob) -> some View {
        Group {
            if let url = job.outputURL, let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipped()
                    .cornerRadius(4)
                    .onTapGesture {
                        placePinnedImage(job)
                    }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(Text("?").foregroundStyle(EditorTheme.secondaryText))
            }
        }
        .contextMenu {
            Button(L10n.removeFromPinLibrary) {
                workbenchStore.unmarkPinned(jobID: job.id)
            }
        }
    }

    private func placePinnedImage(_ job: WorkbenchJob) {
        guard let url = job.outputURL, let image = NSImage(contentsOf: url) else { return }
        // Import into sticker library on first use, then place
        let stickerID = library.importImage(image, originalFilename: url.lastPathComponent)
        placeImageSticker(stickerID)
    }

    // MARK: - Sticker Library Grid

    private func imageGrid(items: [StickerLibrary.StickerItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 64))], spacing: 6) {
            ForEach(items) { item in
                stickerCell(item)
            }
        }
    }

    private func stickerCell(_ item: StickerLibrary.StickerItem) -> some View {
        ZStack(alignment: .topTrailing) {
            if let img = library.image(for: item.id) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .cornerRadius(4)
                    .onTapGesture {
                        placeImageSticker(item.id)
                    }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(Text("?").foregroundStyle(EditorTheme.secondaryText))
            }

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .padding(2)
            }
        }
        .contextMenu {
            Button(item.isFavorite ? L10n.stickerUnfavorite : L10n.stickerFavorite) {
                library.toggleFavorite(item.id)
            }
            Button(L10n.stickerDelete, role: .destructive) {
                library.deleteSticker(item.id)
            }
        }
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 56))], spacing: 6) {
            ForEach(emojiList, id: \.self) { emoji in
                Text(emoji)
                    .font(.system(size: 28))
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(document.selectedSticker == emoji ? EditorTheme.selectedFill : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(document.selectedSticker == emoji ? EditorTheme.selectedStroke : Color.clear, lineWidth: 1)
                    )
                    .onTapGesture {
                        document.selectedSticker = emoji
                        document.selectedTool = .sticker
                        // Place emoji at canvas center
                        let center = CGPoint(x: document.imageWidth / 2, y: document.imageHeight / 2)
                        document.beginAnnotation(at: center)
                    }
            }
        }
    }

    private func placeImageSticker(_ stickerID: String) {
        let center = CGPoint(x: document.imageWidth / 2, y: document.imageHeight / 2)
        document.addImageSticker(id: stickerID, at: center)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    Task { @MainActor in
                        library.importImage(image, originalFilename: "dropped-image.png")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let fileURL: URL?
                    if let url = item as? URL {
                        fileURL = url
                    } else if let data = item as? Data {
                        fileURL = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let string = item as? String {
                        fileURL = URL(string: string)
                    } else {
                        fileURL = nil
                    }
                    guard let url = fileURL, url.isFileURL else { return }
                    Task { @MainActor in
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            stickerLibraryLog.debug("Ignoring dropped missing file URL: \(url.path, privacy: .public)")
                            return
                        }
                        library.importFromURL(url)
                    }
                }
            }
        }
    }
}
