import SwiftUI

// MARK: - CaptureView

struct CaptureView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @EnvironmentObject private var resultStore: ResultStore

    @ObservedObject var orchestrator: IOSCaptureOrchestrator

    @State private var showImportView = false
    @State private var showRecentPreview = false
    @State private var selectedRecentImage: UIImage?
    @State private var pendingImportURL: URL?
    @State private var pendingImportFixtureName: String?

    var body: some View {
        let _ = preferences.appLanguage
        NavigationStack {
            ScrollView {
                VStack(spacing: IOSTheme.spacing16) {
                    actionCardsSection
                    recentResultsSection
                }
                .padding(.horizontal, IOSTheme.spacing16)
                .padding(.top, IOSTheme.spacing8)
            }
            .background(IOSTheme.canvasBG.ignoresSafeArea())
            .navigationTitle("Picelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("PicelfLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .sheet(isPresented: $showImportView, onDismiss: handleImportDismiss) {
                importSheet
            }
            .fullScreenCover(isPresented: $showRecentPreview) {
                if let selectedRecentImage {
                    PreviewView(image: selectedRecentImage)
                }
            }
        }
    }

    @ViewBuilder
    private var importSheet: some View {
        #if DEBUG
        ImportView(
            orchestrator: orchestrator,
            onImportVideo: { videoURL in
                pendingImportURL = videoURL
            },
            onImportFixture: { fixtureName in
                pendingImportFixtureName = fixtureName
            }
        )
        #else
        ImportView(
            orchestrator: orchestrator,
            onImportVideo: { videoURL in
                pendingImportURL = videoURL
            }
        )
        #endif
    }

    private func handleImportDismiss() {
        if let fixtureName = pendingImportFixtureName {
            pendingImportFixtureName = nil
            Task {
                await orchestrator.processUITestImportFixture(named: fixtureName)
            }
            return
        }

        guard let videoURL = pendingImportURL else { return }
        pendingImportURL = nil
        Task {
            await orchestrator.processVideo(from: videoURL)
        }
    }

    // MARK: Action Cards

    private var actionCardsSection: some View {
        VStack(spacing: IOSTheme.spacing12) {
            ActionCard(
                title: L10n.localized("导入视频", "Import Video"),
                subtitle: L10n.localized("导入录屏视频并生成长截图", "Turn a screen recording into a scrolling screenshot"),
                icon: "folder.badge.plus",
                style: .primary
            ) {
                IOSHaptics.medium()
                showImportView = true
            }
            .accessibilityIdentifier("capture.import.button")
        }
    }

    // MARK: Recent Results

    private var recentResultsSection: some View {
        VStack(alignment: .leading, spacing: IOSTheme.spacing10) {
            Text(L10n.localized("最近结果", "Recent Results"))
                .font(IOSTheme.headline())
                .foregroundStyle(IOSTheme.textPrimary)

            if resultStore.results.isEmpty {
                Text(L10n.localized("还没有拼接结果", "No stitched results yet"))
                    .font(IOSTheme.body(14))
                    .foregroundStyle(IOSTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: IOSTheme.spacing12) {
                        ForEach(resultStore.results.prefix(10)) { result in
                            RecentResultCard(result: result, resultStore: resultStore) {
                                IOSHaptics.light()
                                if let image = resultStore.loadFullImage(for: result) {
                                    selectedRecentImage = image
                                    showRecentPreview = true
                                }
                            }
                        }
                    }
                    .padding(.vertical, IOSTheme.spacing4)
                }
            }
        }
        .accessibilityIdentifier("capture.recent.section")
    }
}

// MARK: - Video File Transferable

/// Transferable wrapper that copies a video from PHPicker to a temp file.
struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { exportable in
            SentTransferredFile(exportable.url)
        } importing: { receivedFile in
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PicelfVideoImport", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let fileName = receivedFile.file.lastPathComponent
            let destURL = tempDir.appendingPathComponent(fileName)

            // Remove existing file if any
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: receivedFile.file, to: destURL)

            return VideoFileTransferable(url: destURL)
        }
    }
}

// MARK: - Action Card Style

enum ActionCardStyle {
    case primary, secondary
}

// MARK: - Action Card

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let style: ActionCardStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionCardLabel(title: title, subtitle: subtitle, icon: icon, style: style)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// Shared label used by both ActionCard and PhotosPicker.
struct ActionCardLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let style: ActionCardStyle

    var body: some View {
        VStack(spacing: IOSTheme.spacing10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(style == .primary ? .white : IOSTheme.accent)

            VStack(spacing: IOSTheme.spacing4) {
                Text(title)
                    .font(IOSTheme.headline(16))
                    .foregroundStyle(style == .primary ? .white : IOSTheme.textPrimary)

                Text(subtitle)
                    .font(IOSTheme.caption(12))
                    .foregroundStyle(style == .primary ? .white.opacity(0.85) : IOSTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, IOSTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                .fill(style == .primary ? AnyShapeStyle(IOSTheme.emeraldGradient) : AnyShapeStyle(IOSTheme.cardBG))
        )
        .overlay(
            RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                .stroke(
                    style == .primary ? Color.white.opacity(0.18) : IOSTheme.panelBorder,
                    lineWidth: 1
                )
        )
        .modifier(IOSTheme.cardShadow())
    }
}

// MARK: - Recent Result Card

private struct RecentResultCard: View {
    let result: StitchResult
    let resultStore: ResultStore
    let action: () -> Void

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: result.date)
    }

    private var dimensionText: String {
        "\(result.width) x \(result.height)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: IOSTheme.spacing8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(IOSTheme.panelBG)
                        .frame(width: 100, height: 140)

                    if let thumbnail = resultStore.loadThumbnail(for: result) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(IOSTheme.accent.opacity(0.5))
                    }
                }

                VStack(spacing: 2) {
                    Text(dateText)
                        .font(IOSTheme.caption(12))
                        .foregroundStyle(IOSTheme.textPrimary)
                    Text(dimensionText)
                        .font(IOSTheme.caption(10))
                        .foregroundStyle(IOSTheme.textSecondary)
                }
            }
            .padding(IOSTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .fill(IOSTheme.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                    .stroke(IOSTheme.panelBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier("capture.recent.card")
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
