import SwiftUI

// MARK: - LibraryView

struct LibraryView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @EnvironmentObject private var resultStore: ResultStore

    @State private var isSelecting = false
    @State private var selectedItems = Set<UUID>()
    @State private var selectedResult: StitchResult?
    @State private var previewImage: UIImage?
    @State private var showPreview = false
    @State private var showDeleteConfirmation = false

    private let columns = [
        GridItem(.flexible(), spacing: IOSTheme.spacing8),
        GridItem(.flexible(), spacing: IOSTheme.spacing8),
        GridItem(.flexible(), spacing: IOSTheme.spacing8),
    ]

    var body: some View {
        let _ = preferences.appLanguage
        NavigationStack {
            Group {
                if resultStore.results.isEmpty {
                    emptyState
                } else {
                    gridContent
                }
            }
            .background(IOSTheme.canvasBG.ignoresSafeArea())
            .navigationTitle(L10n.localized("资料库", "Library"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !resultStore.results.isEmpty {
                        Button(isSelecting ? L10n.done : L10n.choose) {
                            withAnimation(.spring(duration: 0.2)) {
                                isSelecting.toggle()
                                if !isSelecting {
                                    selectedItems.removeAll()
                                }
                            }
                        }
                        .font(IOSTheme.body(15))
                        .foregroundStyle(IOSTheme.accent)
                        .accessibilityIdentifier("library.select.button")
                    }
                }

                if isSelecting && !selectedItems.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(L10n.localized("删除 (\(selectedItems.count))", "Delete (\(selectedItems.count))"), systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showPreview) {
                if let image = previewImage {
                    PreviewView(image: image)
                        .environmentObject(resultStore)
                }
            }
            .alert(
                L10n.localized("确定删除 \(selectedItems.count) 项？", "Delete \(selectedItems.count) items?"),
                isPresented: $showDeleteConfirmation
            ) {
                Button(L10n.stickerDelete, role: .destructive) {
                    resultStore.delete(selectedItems)
                    selectedItems.removeAll()
                    isSelecting = false
                }
                Button(L10n.cancel, role: .cancel) {}
            }
        }
        .accessibilityIdentifier("library.grid")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: IOSTheme.spacing16) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(IOSTheme.textSecondary.opacity(0.5))
            Text(L10n.localized("还没有拼接结果", "No stitched results yet"))
                .font(IOSTheme.headline())
                .foregroundStyle(IOSTheme.textSecondary)
            Text(L10n.localized("导入视频并拼接后，结果会显示在这里", "Imported and stitched videos will appear here"))
                .font(IOSTheme.body(14))
                .foregroundStyle(IOSTheme.textSecondary.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groupedItems, id: \.title) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: IOSTheme.spacing8) {
                            ForEach(group.items) { result in
                                LibraryItemCard(
                                    result: result,
                                    resultStore: resultStore,
                                    isSelecting: isSelecting,
                                    isSelected: selectedItems.contains(result.id)
                                ) {
                                    if isSelecting {
                                        IOSHaptics.selection()
                                        toggleSelection(result.id)
                                    } else {
                                        IOSHaptics.light()
                                        if let image = resultStore.loadFullImage(for: result) {
                                            previewImage = image
                                            showPreview = true
                                        }
                                    }
                                } onDelete: {
                                    resultStore.delete(result)
                                } onCopy: {
                                    if let image = resultStore.loadFullImage(for: result) {
                                        image.copyToClipboard()
                                        IOSHaptics.light()
                                    }
                                } onShare: {
                                    if let image = resultStore.loadFullImage(for: result) {
                                        previewImage = image
                                        showPreview = true
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(IOSTheme.headline(15))
                            .foregroundStyle(IOSTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, IOSTheme.spacing16)
            .padding(.top, IOSTheme.spacing8)
        }
    }

    // MARK: - Grouping

    private struct ItemGroup {
        let title: String
        let items: [StitchResult]
    }

    private var groupedItems: [ItemGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var todayItems: [StitchResult] = []
        var yesterdayItems: [StitchResult] = []
        var earlierItems: [StitchResult] = []

        for result in resultStore.results {
            let itemDay = calendar.startOfDay(for: result.date)
            if itemDay == today {
                todayItems.append(result)
            } else if itemDay == yesterday {
                yesterdayItems.append(result)
            } else {
                earlierItems.append(result)
            }
        }

        var groups: [ItemGroup] = []
        if !todayItems.isEmpty { groups.append(ItemGroup(title: L10n.localized("今天", "Today"), items: todayItems)) }
        if !yesterdayItems.isEmpty { groups.append(ItemGroup(title: L10n.localized("昨天", "Yesterday"), items: yesterdayItems)) }
        if !earlierItems.isEmpty { groups.append(ItemGroup(title: L10n.localized("更早", "Earlier"), items: earlierItems)) }
        return groups
    }

    private func toggleSelection(_ id: UUID) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }
}

// MARK: - Library Item Card

private struct LibraryItemCard: View {
    let result: StitchResult
    let resultStore: ResultStore
    let isSelecting: Bool
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: result.date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: IOSTheme.spacing4) {
                ZStack(alignment: .topTrailing) {
                    thumbnailView

                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? IOSTheme.accent : .white.opacity(0.7))
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(timeText)
                    .font(IOSTheme.caption(11))
                    .foregroundStyle(IOSTheme.textSecondary)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.stickerDelete, systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onShare) {
                Label(L10n.share, systemImage: "square.and.arrow.up")
            }
            Button(action: onCopy) {
                Label(L10n.copy, systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label(L10n.stickerDelete, systemImage: "trash")
            }
        }
        .accessibilityIdentifier("library.item.card")
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnail = resultStore.loadThumbnail(for: result) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(IOSTheme.panelBG)
                    .aspectRatio(0.6, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(IOSTheme.accent.opacity(0.4))
                    )
            }
        }
    }
}
