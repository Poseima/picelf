import SwiftUI
import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

private enum WorkbenchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pinned = "Pinned"
    case failed = "Failed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return L10n.filterAll
        case .pinned: return L10n.filterPinned
        case .failed: return L10n.filterFailed
        }
    }
}

private typealias BrandColor = PicelfBrandColor

private enum TimeFilter: String, CaseIterable, Identifiable {
    case all, today, thisWeek, thisMonth
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .all: return L10n.filterAllTime
        case .today: return L10n.filterToday
        case .thisWeek: return L10n.filterThisWeek
        case .thisMonth: return L10n.filterThisMonth
        }
    }
}

struct WorkbenchView: View {
    private struct MosaicAutoLoadTriggerKey: Equatable {
        let visibleCount: Int
        let totalCount: Int
    }

    private let mosaicPageSize = 12
    @ObservedObject var store: WorkbenchStore
    @ObservedObject private var prefs = AppPreferences.shared

    @State private var filter: WorkbenchFilter = .all
    @ObservedObject var clipboard: WorkbenchClipboardController
    @State private var inspectorCollapsed = true
    @State private var mosaicVisibleCount = 12
    @State private var lastAutoLoadTriggerKey: MosaicAutoLoadTriggerKey?
    @State private var searchText = ""
    @State private var showAppDropdown = false
    @State private var typeFilter: CaptureType? = nil
    @State private var timeFilter: TimeFilter = .all
    @State private var trackedOutputPaths: Set<String> = []
    @State private var isImportDropTargeted = false
    @StateObject private var thumbnailCache = WorkbenchThumbnailCache()

    private var liveJobs: [WorkbenchJob] {
        store.jobs.filter { $0.status == .queued || $0.status == .processing }
    }

    private var terminalJobs: [WorkbenchJob] {
        store.jobs.filter { $0.status.isTerminal }
    }

    private var filteredGalleryJobs: [WorkbenchJob] {
        var jobs: [WorkbenchJob]
        switch filter {
        case .all:
            jobs = terminalJobs
        case .pinned:
            jobs = terminalJobs.filter { $0.isPinned && $0.status == .completed }
        case .failed:
            jobs = terminalJobs.filter { $0.status == .failed || $0.status == .cancelled }
        }
        if !searchText.isEmpty {
            jobs = jobs.filter {
                $0.sourceAppName.localizedCaseInsensitiveContains(searchText) ||
                $0.sourceWindowTitle.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let typeFilter {
            jobs = jobs.filter { $0.captureType == typeFilter }
        }
        switch timeFilter {
        case .all: break
        case .today:
            jobs = jobs.filter { Calendar.current.isDateInToday($0.createdAt) }
        case .thisWeek:
            jobs = jobs.filter { Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear) }
        case .thisMonth:
            jobs = jobs.filter { Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
        }
        return jobs
    }

    private var uniqueApps: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: terminalJobs, by: appFacetName(for:))
            .mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }
    }

    private var mosaicJobsPaged: [WorkbenchJob] {
        Array(filteredGalleryJobs.prefix(mosaicVisibleCount))
    }

    private var hasMoreMosaicJobs: Bool {
        filteredGalleryJobs.count > mosaicVisibleCount
    }

    private var outputPathsSnapshot: Set<String> {
        Set(store.jobs.compactMap { $0.outputURL?.path })
    }

    private var selectedJob: WorkbenchJob? {
        if let id = clipboard.selectedJobID {
            return store.jobs.first(where: { $0.id == id && displayedIDs.contains(id) })
        }
        return liveJobs.first ?? filteredGalleryJobs.first
    }

    var body: some View {
        ZStack {
            studioBackdrop

            VStack(spacing: 0) {
                studioHeader
                content
            }
        }
        .frame(minWidth: 1120, minHeight: 700)
        .overlay {
            if isImportDropTargeted {
                importDropOverlay
            }
        }
        .overlay(alignment: .bottom) { saveFeedback }
        .alert(L10n.transferFailed, isPresented: Binding(
            get: { clipboard.errorMessage != nil },
            set: { if !$0 { clipboard.errorMessage = nil } }
        )) { Button(L10n.localized("好", "OK")) { clipboard.errorMessage = nil } }
          message: { Text(clipboard.errorMessage ?? "") }
        .onChange(of: clipboard.importedJobID) { _, id in
            if let id { showImportedImage(id) }
        }
        .onChange(of: displayedIDs) { _, _ in syncSelection() }
        .onDrop(of: [UTType.image, UTType.movie, UTType.fileURL], isTargeted: $isImportDropTargeted, perform: handleDrop)
        .onAppear {
            syncSelection()
            trackedOutputPaths = outputPathsSnapshot
        }
        .onChange(of: store.jobs.count) {
            syncSelection()
        }
        .onChange(of: outputPathsSnapshot) { _, paths in
            reconcileThumbnailCache(with: paths)
        }
        .onChange(of: filter) {
            clipboard.focusGallery?()
            resetMosaicPagination()
            syncSelection()
        }
        .onChange(of: searchText) {
            resetMosaicPagination()
            syncSelection()
        }
        .onChange(of: typeFilter) {
            resetMosaicPagination()
            syncSelection()
        }
        .onChange(of: timeFilter) {
            resetMosaicPagination()
            syncSelection()
        }
    }

    private var studioBackdrop: some View {
        StudioBackdrop()
    }

    private var studioHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.captureStudio)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text(summaryText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer()

                Button {
                    store.onOpenCanvas?([])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                        Text(L10n.pinCanvasLabel)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandColor.green.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(BrandColor.green.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .iconTip(.openCanvas)

                Button(inspectorCollapsed ? L10n.showInspector : L10n.hideInspector) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        inspectorCollapsed.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
            }

            WorkbenchSearchBar(
                searchText: $searchText,
                showAppDropdown: $showAppDropdown,
                uniqueApps: uniqueApps
            )

            HStack(spacing: 8) {
                ForEach(WorkbenchFilter.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter = option
                        }
                    } label: {
                        Text(option.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(filter == option ? Color.black : Color.white.opacity(0.9))
                            .background(
                                Capsule()
                                    .fill(filter == option ? Color.white : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 20)
                    .overlay(Color.white.opacity(0.2))

                FilterDropdownChip(
                    label: typeFilter.map { typeDisplayName($0) } ?? L10n.filterType,
                    isActive: typeFilter != nil
                ) {
                    Button { typeFilter = nil } label: {
                        chipRow(L10n.filterAllTypes, active: typeFilter == nil)
                    }
                    Button { typeFilter = .snap } label: {
                        chipRow(L10n.snap, active: typeFilter == .snap)
                    }
                    Button { typeFilter = .scroll } label: {
                        chipRow(L10n.scroll, active: typeFilter == .scroll)
                    }
                    Button { typeFilter = .recording } label: {
                        chipRow(L10n.record, active: typeFilter == .recording)
                    }
                    Button { typeFilter = .custom } label: {
                        chipRow(L10n.custom, active: typeFilter == .custom)
                    }
                }

                FilterDropdownChip(
                    label: timeFilter == .all ? L10n.filterTime : timeFilter.displayName,
                    isActive: timeFilter != .all
                ) {
                    ForEach(TimeFilter.allCases) { option in
                        Button { timeFilter = option } label: {
                            chipRow(option.displayName, active: timeFilter == option)
                        }
                    }
                }

                Spacer()

                if store.completedCount + store.failedCount > 0 {
                    Button(L10n.clearFinished) {
                        store.clearCompleted()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func typeDisplayName(_ type: CaptureType) -> String {
        switch type {
        case .snap: return L10n.snap
        case .scroll: return L10n.scroll
        case .recording: return L10n.record
        case .custom: return L10n.custom
        }
    }

    private func chipRow(_ text: String, active: Bool) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: active ? .semibold : .medium, design: .rounded))
                .foregroundStyle(active ? .white : Color.white.opacity(0.7))
            Spacer()
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BrandColor.green)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        LiveStageSection(jobs: liveJobs, store: store, selectedJobID: $clipboard.selectedJobID)
                            .zIndex(0)

                        GalleryMosaicSection(
                            jobs: mosaicJobsPaged,
                            store: store,
                            filter: filter,
                            selectedJobID: $clipboard.selectedJobID,
                            thumbnailCache: thumbnailCache,
                            hasMore: hasMoreMosaicJobs,
                            onPrefetchIfNeeded: requestMosaicAutoLoadIfNeeded,
                            clipboard: clipboard
                        )
                        .id("gallery-start")
                        .zIndex(1)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { clipboard.focusGallery?() })
                .onChange(of: clipboard.importedJobID) { _, id in
                    if id != nil { proxy.scrollTo("gallery-start", anchor: .top) }
                }
            }

            if !inspectorCollapsed {
                InspectorPanel(job: selectedJob, store: store, filter: filter)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var summaryText: String {
        if store.runningCount > 0 || store.queuedCount > 0 {
            return L10n.summaryRunning(store.runningCount, store.queuedCount)
        }
        return L10n.summaryIdle(store.jobs.count)
    }

    private var displayedIDs: [UUID] { (liveJobs + mosaicJobsPaged).map(\.id) }

    private func syncSelection() {
        clipboard.reconcileSelection(displayedIDs: displayedIDs)
    }

    private func showImportedImage(_ id: UUID) {
        filter = .all
        searchText = ""
        typeFilter = nil
        timeFilter = .all
        resetMosaicPagination()
        clipboard.selectedJobID = id
        syncSelection()
        clipboard.focusGallery?()
    }

    @ViewBuilder private var saveFeedback: some View {
        if let url = clipboard.savedURL {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColor.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.savedToDownloads)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(url.lastPathComponent)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 250, alignment: .leading)
                        .help(url.lastPathComponent)
                }
                .fixedSize(horizontal: true, vertical: false)
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Finder")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(L10n.showInFinder)
                .accessibilityLabel(L10n.showInFinder)
                .accessibilityIdentifier("workbench.showSavedInFinder")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BrandColor.green.opacity(0.5)))
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workbench.saveFeedback")
        }
    }

    private func resetMosaicPagination() {
        mosaicVisibleCount = mosaicPageSize
        lastAutoLoadTriggerKey = nil
    }

    private func requestMosaicAutoLoadIfNeeded() {
        guard hasMoreMosaicJobs else { return }

        let key = MosaicAutoLoadTriggerKey(
            visibleCount: mosaicVisibleCount,
            totalCount: filteredGalleryJobs.count
        )
        guard lastAutoLoadTriggerKey != key else { return }

        lastAutoLoadTriggerKey = key
        mosaicVisibleCount += mosaicPageSize
    }

    private func reconcileThumbnailCache(with latestPaths: Set<String>) {
        let removedPaths = trackedOutputPaths.subtracting(latestPaths)
        guard !removedPaths.isEmpty else {
            trackedOutputPaths = latestPaths
            return
        }

        for path in removedPaths {
            thumbnailCache.invalidate(path: path)
        }
        trackedOutputPaths = latestPaths
    }

    private var importDropOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BrandColor.green.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
            )
            .padding(24)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L10n.dropToImport)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(L10n.dropToImportSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.06, green: 0.09, blue: 0.11).opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(BrandColor.green.opacity(0.45), lineWidth: 1)
                        )
                )
            }
            .transition(.opacity)
    }

    private func appFacetName(for job: WorkbenchJob) -> String {
        job.isCustomImport ? L10n.custom : job.sourceAppName
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
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
                        let importedIDs = await store.importFiles([url])
                        if let selectedImportID = importedIDs.last {
                            showImportedImage(selectedImportID)
                        }
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    Task { @MainActor in
                        if let importedID = await store.importImage(image, sourceName: L10n.droppedImage) {
                            showImportedImage(importedID)
                        }
                    }
                }
            }
        }

        return accepted
    }
}

private struct LiveStageSection: View {
    let jobs: [WorkbenchJob]
    let store: WorkbenchStore
    @Binding var selectedJobID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.liveStage)

            if jobs.isEmpty {
                emptyPanel(title: L10n.noActiveSessions, subtitle: L10n.noActiveSessionsSubtitle)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(jobs) { job in
                            LiveStageCard(job: job, store: store)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(selectedJobID == job.id ? Color.white.opacity(0.9) : Color.clear, lineWidth: 1.5)
                                )
                                .onTapGesture { selectedJobID = job.id }
                                .frame(width: 350)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct GalleryMosaicSection: View {
    let jobs: [WorkbenchJob]
    let store: WorkbenchStore
    let filter: WorkbenchFilter
    @Binding var selectedJobID: UUID?
    let thumbnailCache: WorkbenchThumbnailCache
    let hasMore: Bool
    let onPrefetchIfNeeded: () -> Void
    let clipboard: WorkbenchClipboardController

    private let prefetchThreshold = 3
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.gallery)

            if jobs.isEmpty {
                emptyPanel(title: L10n.noGalleryItems, subtitle: L10n.noGalleryItemsSubtitle)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        GalleryTile(
                            job: job,
                            store: store,
                            filter: filter,
                            selected: selectedJobID == job.id,
                            thumbnailCache: thumbnailCache,
                            onSelect: { clipboard.select(job.id) },
                            onSaveToDownloads: { clipboard.saveToDownloads(job.id) }
                        )
                        .id(job.id)
                        .onAppear {
                            guard hasMore else { return }
                            guard shouldPrefetch(index: index, totalCount: jobs.count) else { return }
                            onPrefetchIfNeeded()
                        }
                    }
                }
            }
        }
    }

    private func shouldPrefetch(index: Int, totalCount: Int) -> Bool {
        index >= max(0, totalCount - prefetchThreshold)
    }
}

private struct LiveStageCard: View {
    let job: WorkbenchJob
    let store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(job.sourceAppName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()

                Text(job.status == .queued ? L10n.statusQueued : L10n.stitchingLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BrandColor.green.opacity(0.92)))
            }

            Text(job.sourceWindowTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let value = max(0, min(1, job.progress))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(
                                LinearGradient(colors: [BrandColor.green, BrandColor.teal], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(10, geo.size.width * value))
                            .animation(.easeOut(duration: 0.25), value: value)
                    }
                }
                .frame(height: 9)

                Text(job.phase)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                metricPill(L10n.frames, "\(job.captureFrameCount)")
                metricPill(L10n.rect, "\(Int(job.captureRect.width))×\(Int(job.captureRect.height))")
            }

            HStack {
                Button(L10n.cancel) {
                    store.cancel(jobID: job.id)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.white)

                Spacer()

                if let startedAt = job.startedAt {
                    Text(durationText(from: startedAt, to: Date()))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandColor.green.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.22)))
    }

    private func durationText(from start: Date, to end: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.pad]
        return "\(L10n.livePrefix) · \(formatter.string(from: start, to: end) ?? "0s")"
    }
}

private struct GalleryTile: View {
    let job: WorkbenchJob
    let store: WorkbenchStore
    let filter: WorkbenchFilter
    let selected: Bool
    let thumbnailCache: WorkbenchThumbnailCache
    let onSelect: () -> Void
    let onSaveToDownloads: () -> Void
    private let titleSlotHeight: CGFloat = 38
    private let metadataRowHeight: CGFloat = 14
    private let actionRowHeight: CGFloat = 28
    private let tileHeight: CGFloat = 284

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                ThumbnailSurface(job: job, cache: thumbnailCache)
                    .frame(height: 150)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.60)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack {
                    Spacer()
                    HStack {
                        CaptureTypeBadge(captureType: job.captureType)
                        Spacer()
                    }
                }
                .padding(8)
                .allowsHitTesting(false)

                if job.isPinned {
                    HStack {
                        Spacer()
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.black.opacity(0.45))
                            )
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }

            Text(job.sourceWindowTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: titleSlotHeight, alignment: .topLeading)

            HStack(spacing: 8) {
                Text(job.sourceAppName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("·")
                Text(relativeDate(job.createdAt))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(1)
            .frame(height: metadataRowHeight, alignment: .leading)

            HStack(spacing: 6) {
                if job.canOpenResult {
                    tileIconButton(job.isVideoOutput ? "play.fill" : "arrow.up.right.square",
                                   tint: job.isVideoOutput ? .red : BrandColor.green,
                                   prominent: true,
                                   tipKey: .openResult) {
                        store.open(jobID: job.id)
                    }
                    if job.canPinToDesktop {
                        tileIconButton("pin", tint: .white, tipKey: .pinToDesktop) { pinToDesktop() }
                    }
                    tileIconButton("folder", tint: .white, tipKey: .revealInFinder) { store.revealInFinder(jobID: job.id) }
                } else if job.canRetry {
                    tileIconButton("arrow.counterclockwise", tint: .orange, prominent: true, tipKey: .retry) {
                        store.retry(jobID: job.id)
                    }
                }

                Spacer()

                if job.status == .completed {
                    tileIconButton(job.isPinned ? "bookmark.fill" : "bookmark",
                                   tint: job.isPinned ? .yellow : .white,
                                   tipKey: job.isPinned ? .unkeepCapture : .keepCapture) {
                        toggleKeep()
                    }
                }
                tileIconButton("trash", tint: Color.white.opacity(0.5), tipKey: .remove) {
                    store.remove(jobID: job.id)
                }
            }
            .frame(height: actionRowHeight)
        }
        .frame(height: tileHeight, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Color.white.opacity(0.85) : Color.white.opacity(0.14), lineWidth: selected ? 1.5 : 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: selected ? 14 : 8, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.image.\(job.id.uuidString)")
        .accessibilityLabel(job.sourceAppName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(.default) { onSelect() }
        .contextMenu {
            if job.canCopyToClipboard {
                Button(action: onSaveToDownloads) {
                    Label(L10n.saveToDownloads, systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("workbench.saveToDownloads")
            }
            if job.status == .completed {
                Button {
                    toggleKeep()
                } label: {
                    Label(job.isPinned ? L10n.unkeepCapture : L10n.keepCapture,
                          systemImage: job.isPinned ? "bookmark.fill" : "bookmark")
                }
                if job.canPinToDesktop {
                    Button { pinToDesktop() } label: {
                        Label(L10n.pinToDesktop, systemImage: "pin")
                    }
                }
                if job.canAddToCanvas {
                    Button {
                        if let image = store.image(for: job.id) {
                            store.onAddToCanvas?(image)
                        }
                    } label: {
                        Label(L10n.addToCanvas, systemImage: "rectangle.on.rectangle.angled")
                    }
                }
            }
        }
    }

    private func tileIconButton(
        _ systemName: String,
        tint: Color,
        prominent: Bool = false,
        tipKey: IconTipKey,
        action: @escaping () -> Void
    ) -> some View {
        Button { action() } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? .white : tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prominent ? tint.opacity(0.85) : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .iconTip(tipKey)
    }

    private func pinToDesktop() {
        if let image = store.image(for: job.id) {
            store.markPinned(jobID: job.id)
            store.onPinImage?(image, job.id)
        }
    }

    private func toggleKeep() {
        if job.isPinned {
            store.unmarkPinned(jobID: job.id)
        } else {
            store.markPinned(jobID: job.id)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct InspectorPanel: View {
    let job: WorkbenchJob?
    let store: WorkbenchStore
    let filter: WorkbenchFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.inspector)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(job.sourceWindowTitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        inspectorRow(job.isCustomImport ? L10n.source : L10n.app, value: job.sourceAppName)
                        inspectorRow(L10n.captureTypeLabel, value: {
                            switch job.captureType {
                            case .snap: return L10n.snap
                            case .recording: return L10n.record
                            case .scroll: return L10n.scroll
                            case .custom: return L10n.custom
                            }
                        }())
                        inspectorRow(L10n.frames, value: "\(job.captureFrameCount)")
                        inspectorRow(L10n.captureLabel, value: "\(Int(job.captureRect.width))×\(Int(job.captureRect.height))")

                        if let output = job.outputSize {
                            inspectorRow(L10n.output, value: "\(Int(output.width))×\(Int(output.height))")
                        }

                        if let duration = job.videoDurationSeconds {
                            inspectorRow(L10n.durationLimit, value: formatDuration(duration))
                        }

                        if let error = job.errorDescription, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.red)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.13)))
                        }

                        HStack(spacing: 6) {
                            if job.canOpenResult {
                                inspectorIconButton(job.isVideoOutput ? "play.fill" : "arrow.up.right.square",
                                                    tint: job.isVideoOutput ? .red : BrandColor.green,
                                                    prominent: true,
                                                    tipKey: .openResult) {
                                    store.open(jobID: job.id)
                                }
                                if job.canPinToDesktop {
                                    inspectorIconButton("pin", tint: .white, tipKey: .pinToDesktop) {
                                        pinToDesktop(job: job)
                                    }
                                }
                                inspectorIconButton("folder", tint: .white, tipKey: .revealInFinder) {
                                    store.revealInFinder(jobID: job.id)
                                }
                            } else if job.canRetry {
                                inspectorIconButton("arrow.counterclockwise", tint: .orange, prominent: true, tipKey: .retry) {
                                    store.retry(jobID: job.id)
                                }
                            } else if job.status != .completed {
                                inspectorIconButton("xmark", tint: .white, tipKey: .cancel) {
                                    store.cancel(jobID: job.id)
                                }
                            }

                            Spacer()

                            if job.status == .completed {
                                inspectorIconButton(job.isPinned ? "bookmark.fill" : "bookmark",
                                                    tint: job.isPinned ? .yellow : .white,
                                                    tipKey: job.isPinned ? .unkeepCapture : .keepCapture) {
                                    toggleKeep(job: job)
                                }
                            }
                            inspectorIconButton("trash", tint: Color.white.opacity(0.5), tipKey: .remove) {
                                store.remove(jobID: job.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                emptyPanel(title: L10n.noSelection, subtitle: L10n.noSelectionSubtitle)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func inspectorIconButton(
        _ systemName: String,
        tint: Color,
        prominent: Bool = false,
        tipKey: IconTipKey,
        action: @escaping () -> Void
    ) -> some View {
        Button { action() } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? .white : tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prominent ? tint.opacity(0.85) : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .iconTip(tipKey)
    }

    private func pinToDesktop(job: WorkbenchJob) {
        if let image = store.image(for: job.id) {
            store.markPinned(jobID: job.id)
            store.onPinImage?(image, job.id)
        }
    }

    private func toggleKeep(job: WorkbenchJob) {
        if job.isPinned {
            store.unmarkPinned(jobID: job.id)
        } else {
            store.markPinned(jobID: job.id)
        }
    }

    private func inspectorRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct WorkbenchSearchBar: View {
    @Binding var searchText: String
    @Binding var showAppDropdown: Bool
    let uniqueApps: [(name: String, count: Int)]

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))

                TextField(L10n.searchPlaceholder, text: $searchText)
                    .accessibilityIdentifier("workbench.search")
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($isFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .iconTip(.clearSearch)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAppDropdown.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .rotationEffect(.degrees(showAppDropdown ? 180 : 0))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(showAppDropdown ? 0.16 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .iconTip(.appFilter)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isFocused ? BrandColor.green.opacity(0.5) : Color.white.opacity(0.14), lineWidth: 1)
                    )
            )

            if showAppDropdown && !uniqueApps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        searchText = ""
                        showAppDropdown = false
                    } label: {
                        HStack {
                            Text(L10n.allApps)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(searchText.isEmpty ? .white : Color.white.opacity(0.7))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(searchText.isEmpty ? Color.white.opacity(0.08) : Color.clear)
                    }
                    .buttonStyle(.plain)

                    ForEach(Array(uniqueApps.prefix(6).enumerated()), id: \.offset) { _, app in
                        Button {
                            searchText = app.name
                            showAppDropdown = false
                        } label: {
                            HStack {
                                Text(app.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(app.count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(searchText == app.name ? Color.white.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.10, blue: 0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct FilterDropdownChip<Content: View>: View {
    let label: String
    let isActive: Bool
    @ViewBuilder let content: Content
    @State private var showDropdown = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showDropdown.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(showDropdown ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? .white : Color.white.opacity(0.8))
            .background(
                Capsule()
                    .fill(isActive ? BrandColor.green.opacity(0.25) : Color.white.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? BrandColor.green.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDropdown, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.vertical, 6)
            .frame(minWidth: 140)
            .buttonStyle(.plain)
        }
    }
}

private struct CaptureTypeBadge: View {
    let captureType: CaptureType
    private var symbolName: String {
        switch captureType {
        case .snap: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .scroll: return "arrow.up.and.down.text.horizontal"
        case .custom: return "square.and.arrow.down"
        }
    }
    private var label: String {
        switch captureType {
        case .snap: return L10n.snap
        case .recording: return L10n.record
        case .scroll: return L10n.scroll
        case .custom: return L10n.custom
        }
    }
    private var color: Color {
        switch captureType {
        case .snap: return BrandColor.blue
        case .recording: return .red
        case .scroll: return BrandColor.teal
        case .custom: return BrandColor.green
        }
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.85)))
    }
}

private struct ThumbnailSurface: View {
    let job: WorkbenchJob
    let cache: WorkbenchThumbnailCache
    @State private var thumbnail: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.black.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text(job.status == .processing || job.status == .queued ? L10n.renderingPreview : L10n.noPreview)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: cacheKey) {
            guard let url = job.outputURL else {
                thumbnail = nil
                return
            }
            let pixelSize = job.status == .completed ? 560 : 420
            thumbnail = await cache.thumbnail(for: url, maxPixelSize: pixelSize)
        }
        .onDisappear {
            thumbnail = nil
        }
    }

    private var cacheKey: String {
        job.outputURL?.path ?? "no-output-\(job.id.uuidString)"
    }
}

private func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
}

private func emptyPanel(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
        Text(subtitle)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.62))
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    )
}

@MainActor
final class WorkbenchThumbnailCache: ObservableObject {
    struct DebugStats {
        let cacheEntryCountEstimate: Int
        let inflightCount: Int
        let trackedPathCount: Int
        let trackedKeyCount: Int
    }

    private let cache = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private var keysByPath: [String: Set<String>] = [:]

    init() {
        cache.countLimit = 96
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        if let existingTask = inflight[key] {
            return await existingTask.value
        }

        let task = Task.detached(priority: .utility) {
            Self.loadThumbnail(from: url, maxPixelSize: maxPixelSize)
        }
        inflight[key] = task
        let image = await task.value
        inflight.removeValue(forKey: key)

        guard let image else {
            invalidate(path: url.path)
            return nil
        }

        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
        replacePathKeys(url.path, with: key)
        return image
    }

    func invalidate(for url: URL) {
        invalidate(path: url.path)
    }

    func invalidate(path: String) {
        guard let keys = keysByPath.removeValue(forKey: path) else {
            return
        }
        for key in keys {
            removeCachedEntry(for: key)
        }
    }

    #if DEBUG
    func debugStats() -> DebugStats {
        let trackedKeyCount = keysByPath.values.reduce(0) { $0 + $1.count }
        return DebugStats(
            cacheEntryCountEstimate: trackedKeyCount,
            inflightCount: inflight.count,
            trackedPathCount: keysByPath.count,
            trackedKeyCount: trackedKeyCount
        )
    }
    #endif

    private func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        let modifiedAt = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0)
        return "\(url.path)|\(Int(modifiedAt))|\(maxPixelSize)"
    }

    private func replacePathKeys(_ path: String, with key: String) {
        if let existingKeys = keysByPath[path] {
            for staleKey in existingKeys where staleKey != key {
                removeCachedEntry(for: staleKey)
            }
        }
        keysByPath[path] = [key]
    }

    private func removeCachedEntry(for key: String) {
        cache.removeObject(forKey: key as NSString)
        inflight[key]?.cancel()
        inflight.removeValue(forKey: key)
    }

    nonisolated private static func loadThumbnail(from url: URL, maxPixelSize: Int) -> NSImage? {
        // Video files → AVAssetImageGenerator
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v"].contains(ext) {
            return loadVideoThumbnail(from: url, maxPixelSize: maxPixelSize)
        }

        // Image files → CGImageSource
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(128, maxPixelSize),
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    nonisolated private static func loadVideoThumbnail(from url: URL, maxPixelSize: Int) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
