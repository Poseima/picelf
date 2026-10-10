import SwiftUI
import UniformTypeIdentifiers

struct CanvasInspectorView: View {
    @ObservedObject var document: CanvasDocument
    @ObservedObject private var library = StickerLibrary.shared
    @State private var inspectorTab: InspectorTab = .properties
    @State private var canvasWidth: Int = 1920
    @State private var canvasHeight: Int = 1080

    private enum InspectorTab: String, CaseIterable {
        case properties, stickers
        var label: String {
            switch self {
            case .properties: return L10n.canvasProperties
            case .stickers: return L10n.canvasStickers
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView {
                switch inspectorTab {
                case .properties:
                    propertiesSection
                case .stickers:
                    stickerSection
                }
            }
        }
        .background(EditorTheme.panelBackground)
        .tint(EditorTheme.accent)
    }

    // MARK: - Properties

    @ViewBuilder
    private var propertiesSection: some View {
        if let item = document.primarySelectedItem {
            VStack(alignment: .leading, spacing: 16) {
                // Canvas size
                canvasSizeSection

                Divider()

                // Item info
                sectionHeader(L10n.canvasItemInfo)

                HStack {
                    Text("X")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(Int(item.position.x))")
                        .monospacedDigit()
                    Spacer()
                    Text("Y")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(Int(item.position.y))")
                        .monospacedDigit()
                }
                .font(.system(size: 12, design: .rounded))

                HStack {
                    Text("W")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(Int(item.size.width))")
                        .monospacedDigit()
                    Spacer()
                    Text("H")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(Int(item.size.height))")
                        .monospacedDigit()
                }
                .font(.system(size: 12, design: .rounded))

                Divider()

                // Opacity
                sectionHeader(L10n.stickerOpacity)
                HStack {
                    Slider(value: Binding(
                        get: { item.opacity },
                        set: { document.updateSelectedOpacity($0) }
                    ), in: 0.1...1.0)
                    Text("\(Int(item.opacity * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                Divider()

                // Corner radius
                sectionHeader(L10n.canvasCornerRadius)
                HStack {
                    Slider(value: Binding(
                        get: { item.cornerRadius },
                        set: { document.updateSelectedCornerRadius($0) }
                    ), in: 0...60)
                    Text("\(Int(item.cornerRadius))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }

                Divider()

                // Toggles
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { item.hasShadow },
                        set: { _ in document.toggleSelectedShadow() }
                    )) {
                        Label(L10n.stickerShadow, systemImage: "shadow")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)

                    Toggle(isOn: Binding(
                        get: { item.flipH },
                        set: { _ in document.flipSelectedHorizontally() }
                    )) {
                        Label(L10n.stickerFlipH, systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)

                    Toggle(isOn: Binding(
                        get: { item.flipV },
                        set: { _ in document.flipSelectedVertically() }
                    )) {
                        Label(L10n.stickerFlipV, systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                }

                Divider()

                // Layer controls
                sectionHeader(L10n.canvasLayer)
                HStack(spacing: 8) {
                    Button(L10n.stickerBringForward) {
                        document.reorder(item.id, direction: .up)
                    }
                    .buttonStyle(.borderless)

                    Button(L10n.stickerSendBack) {
                        document.reorder(item.id, direction: .down)
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(action: { document.duplicateSelection() }) {
                        Image(systemName: "plus.square.on.square")
                    }
                    .buttonStyle(.borderless)
                    .iconTip(.duplicate)

                    Button(action: { document.toggleLock(item.id) }) {
                        Image(systemName: item.isLocked ? "lock.fill" : "lock.open")
                    }
                    .buttonStyle(.borderless)
                    .iconTip(item.isLocked ? .unlock : .lock)

                    Button(action: { document.toggleVisibility(item.id) }) {
                        Image(systemName: item.isHidden ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .iconTip(item.isHidden ? .showLayer : .hideLayer)
                }
            }
            .padding(12)
        } else {
            canvasSizeSection
                .padding(12)

            Spacer()

            Text(L10n.canvasNoSelection)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()

            Spacer()
        }
    }

    // MARK: - Canvas Size Section

    private var canvasSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.canvasSize)

            HStack(spacing: 8) {
                TextField("W", value: $canvasWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("×")
                    .foregroundStyle(.secondary)
                TextField("H", value: $canvasHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Spacer()
                Button(L10n.canvasApplySize) {
                    document.canvasSize = CGSize(width: max(1, canvasWidth), height: max(1, canvasHeight))
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                Button(L10n.canvasFitContent) {
                    document.fitToContent()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .font(.system(size: 12, design: .rounded))
            .monospacedDigit()

            Divider()

            // Background
            sectionHeader(L10n.canvasBackground)
            HStack(spacing: 10) {
                backgroundButton(.white, label: L10n.canvasWhite, color: .white)
                backgroundButton(.transparent, label: L10n.canvasTransparent, color: nil)
                colorPickerButton
                imageBackgroundButton
            }
        }
        .onAppear {
            canvasWidth = Int(document.canvasSize.width)
            canvasHeight = Int(document.canvasSize.height)
        }
        .onChange(of: document.canvasSize) { _, newSize in
            canvasWidth = Int(newSize.width)
            canvasHeight = Int(newSize.height)
        }
    }

    private var imageBackgroundButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let url = panel.url,
               let image = NSImage(contentsOf: url) {
                document.background = .customImage(image)
                document.canvasSize = image.size
            }
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isImageBackground ? EditorTheme.selectionStroke : Color.gray.opacity(0.3), lineWidth: isImageBackground ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .iconTip(.chooseImageBackground)
    }

    private var isImageBackground: Bool {
        if case .customImage = document.background { return true }
        return false
    }

    private var isSolidColor: Bool {
        if case .solidColor = document.background { return true }
        return false
    }

    private var colorPickerButton: some View {
        ColorPicker("", selection: backgroundColorBinding)
            .labelsHidden()
            .scaleEffect(1.4)
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSolidColor ? EditorTheme.selectionStroke : Color.gray.opacity(0.3), lineWidth: isSolidColor ? 2 : 1)
            )
            .iconTip(.customBackgroundColor)
    }

    private func backgroundButton(_ bg: CanvasBackground, label: String, color: Color?) -> some View {
        Button {
            document.background = bg
        } label: {
            if let color {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isActiveBackground(bg) ? EditorTheme.selectionStroke : Color.gray.opacity(0.3), lineWidth: isActiveBackground(bg) ? 2 : 1)
                    )
            } else {
                CheckerboardView()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isActiveBackground(bg) ? EditorTheme.selectionStroke : Color.gray.opacity(0.3), lineWidth: isActiveBackground(bg) ? 2 : 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func isActiveBackground(_ bg: CanvasBackground) -> Bool {
        switch (document.background, bg) {
        case (.white, .white): return true
        case (.transparent, .transparent): return true
        case (.solidColor, .solidColor): return true
        default: return false
        }
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                if case .solidColor(let c) = document.background { return c }
                return .gray
            },
            set: { document.background = .solidColor($0) }
        )
    }

    // MARK: - Sticker Section

    private var stickerSection: some View {
        CanvasStickerSection(
            onStickerSelected: { stickerID in
                document.addSticker(id: stickerID)
            }
        )
        .padding(12)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Sticker Section (callback-based, decoupled from EditorDocument)

struct CanvasStickerSection: View {
    let onStickerSelected: (String) -> Void
    @ObservedObject private var library = StickerLibrary.shared
    @EnvironmentObject private var workbenchStore: WorkbenchStore
    @State private var selectedTab: StickerTab = .pinned

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

                Button(action: { openStickerImportPanel() }) {
                    Image(systemName: "plus")
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
                    if library.favorites.isEmpty { emptyState } else { imageGrid(items: library.favorites) }
                case .recents:
                    if library.recents.isEmpty { emptyState } else { imageGrid(items: library.recents) }
                case .emoji:
                    emojiGrid
                }
            }
        }
    }

    private func openStickerImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = library.importFromURL(url) {
                onStickerSelected(id)
            }
        }
    }

    private var emptyState: some View {
        Text(L10n.canvasNoStickers)
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
    }

    // MARK: - Pinned Grid

    private var pinnedGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(pinnedJobs) { job in
                pinnedCell(job)
            }
        }
    }

    private func pinnedCell(_ job: WorkbenchJob) -> some View {
        Group {
            if let url = job.outputURL, let img = NSImage(contentsOf: url) {
                Button {
                    placePinnedImage(job)
                } label: {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipped()
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(Text("?").foregroundStyle(.secondary))
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
        let stickerID = library.importImage(image, originalFilename: url.lastPathComponent)
        onStickerSelected(stickerID)
    }

    // MARK: - Sticker Library Grid

    private func imageGrid(items: [StickerLibrary.StickerItem]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(items) { item in
                if let image = library.image(for: item.id) {
                    Button {
                        onStickerSelected(item.id)
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(item.isFavorite ? L10n.stickerUnfavorite : L10n.stickerFavorite) {
                            library.toggleFavorite(item.id)
                        }
                        Button(L10n.stickerDelete, role: .destructive) {
                            library.deleteSticker(item.id)
                        }
                    }
                }
            }
        }
    }

    private var emojiGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 40, maximum: 52), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(emojiList, id: \.self) { emoji in
                Button {
                    onStickerSelected(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
