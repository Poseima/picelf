import SwiftUI
import Photos

struct PreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let originalImage: UIImage

    @State private var showExportSheet = false
    @State private var showShareSheet = false
    @State private var selectedTool: PreviewTool?
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var topTrim: CGFloat = 0
    @State private var bottomTrim: CGFloat = 0
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showCopyConfirmation = false
    @State private var showAnnotationEditor = false
    @State private var currentImage: UIImage

    init(image: UIImage) {
        self.originalImage = image
        _currentImage = State(initialValue: image)
    }

    /// The active image used for display and export (may be annotated).
    private var image: UIImage { currentImage }

    enum PreviewTool: String, CaseIterable, Identifiable {
        case crop = "裁剪"
        case ocr = "OCR"
        case annotate = "标注"
        case watermark = "水印"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .crop: return L10n.localized("裁剪", "Crop")
            case .ocr: return "OCR"
            case .annotate: return L10n.localized("标注", "Annotate")
            case .watermark: return L10n.watermark
            }
        }

        var icon: String {
            switch self {
            case .crop: return "crop"
            case .ocr: return "doc.text.viewfinder"
            case .annotate: return "pencil.tip.crop.circle"
            case .watermark: return "drop.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.opacity(0.95).ignoresSafeArea()

                // Zoomable image area
                imageArea

                // Floating bottom toolbar
                VStack {
                    Spacer()
                    floatingToolbar
                        .padding(.bottom, IOSTheme.spacing16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("preview.back.button")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        IOSHaptics.medium()
                        showExportSheet = true
                    } label: {
                        HStack(spacing: IOSTheme.spacing4) {
                            Image(systemName: "square.and.arrow.up")
                            Text(L10n.export)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: IOSTheme.radiusCard, style: .continuous)
                                .fill(IOSTheme.emeraldGradient)
                        )
                    }
                    .accessibilityIdentifier("preview.export.button")
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ExportView(
                    image: image,
                    onSave: saveToPhotos,
                    onCopy: copyToClipboard,
                    onShare: { showShareSheet = true }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewRepresentable(activityItems: [image])
            }
            .alert(L10n.localized("已保存到相册", "Saved to Photos"), isPresented: $showSaveSuccess) {
                Button(L10n.localized("好的", "OK"), role: .cancel) {}
            }
            .alert(L10n.localized("保存失败", "Save Failed"), isPresented: $showSaveError) {
                Button(L10n.localized("好的", "OK"), role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .alert(L10n.localized("已复制到剪贴板", "Copied to Clipboard"), isPresented: $showCopyConfirmation) {
                Button(L10n.localized("好的", "OK"), role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showAnnotationEditor) {
                IOSEditorView(image: currentImage) { annotatedImage in
                    currentImage = annotatedImage
                }
            }
        }
    }

    // MARK: - Image Area

    private var imageArea: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: min(geometry.size.width, image.size.width) * zoomScale,
                        height: min(geometry.size.width, image.size.width)
                            / max(image.size.width, 1) * image.size.height * zoomScale
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastZoomScale
                                lastZoomScale = value
                                zoomScale = min(max(zoomScale * delta, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                lastZoomScale = 1.0
                            }
                    )
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height
                    )
            }
        }
        .accessibilityIdentifier("preview.image.area")
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        HStack(spacing: 20) {
            ForEach(PreviewTool.allCases) { tool in
                Button {
                    IOSHaptics.selection()
                    if tool == .annotate {
                        showAnnotationEditor = true
                    } else {
                        withAnimation(.spring(duration: 0.2)) {
                            selectedTool = selectedTool == tool ? nil : tool
                        }
                    }
                } label: {
                    VStack(spacing: IOSTheme.spacing4) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tool.title)
                            .font(IOSTheme.caption(11))
                    }
                    .foregroundStyle(selectedTool == tool ? IOSTheme.accent : .white.opacity(0.8))
                    .frame(width: 56, height: 48)
                }
                .accessibilityIdentifier("preview.tool.\(tool.rawValue)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, IOSTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: IOSTheme.radiusFloating, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IOSTheme.radiusFloating, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityIdentifier("preview.toolbar")
    }

    // MARK: - Actions

    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    saveErrorMessage = L10n.localized("需要相册写入权限，请在设置中授权。", "Photo Library access is required. Allow it in Settings.")
                    showSaveError = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                guard let pngData = image.pngData() else { return }
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: pngData, options: nil)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        IOSHaptics.medium()
                        showSaveSuccess = true
                    } else {
                        saveErrorMessage = error?.localizedDescription ?? "Unknown error"
                        showSaveError = true
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        image.copyToClipboard()
        IOSHaptics.light()
        showCopyConfirmation = true
    }
}

// MARK: - Trim Handle

private struct TrimHandle: View {
    enum Edge { case top, bottom }
    let edge: Edge

    var body: some View {
        VStack(spacing: 0) {
            if edge == .bottom {
                Rectangle()
                    .fill(IOSTheme.accent.opacity(0.3))
                    .frame(height: 1)
            }

            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(IOSTheme.accent)
                    .frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.vertical, 6)
            .background(IOSTheme.accent.opacity(0.08))

            if edge == .top {
                Rectangle()
                    .fill(IOSTheme.accent.opacity(0.3))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityViewRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
