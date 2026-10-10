import SwiftUI
import PhotosUI

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss

    let orchestrator: IOSCaptureOrchestrator
    let onImportVideo: (URL) -> Void
    #if DEBUG
    let onImportFixture: ((String) -> Void)?
    #endif

    @State private var selectedItem: PhotosPickerItem?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: IOSTheme.spacing16) {
                Spacer()

                Image(systemName: "film.stack")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(IOSTheme.accent)

                Text(L10n.localized("选择录屏视频", "Choose a Screen Recording"))
                    .font(IOSTheme.title())
                    .foregroundStyle(IOSTheme.textPrimary)

                Text(L10n.localized("从相册中选择一段滚动录屏视频，Picelf 会自动提取帧并拼接为长图。", "Choose a scrolling screen recording from Photos. Picelf will extract frames and stitch them into one long image."))
                    .font(IOSTheme.body(14))
                    .foregroundStyle(IOSTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                #if DEBUG
                if let fixtureName = orchestrator.uiTestImportFixtureName {
                    Button {
                        IOSHaptics.medium()
                        onImportFixture?(fixtureName)
                        dismiss()
                    } label: {
                        HStack(spacing: IOSTheme.spacing8) {
                            Image(systemName: "hammer.fill")
                            Text(L10n.localized("使用测试视频", "Use Test Video"))
                        }
                    }
                    .buttonStyle(IOSSecondaryButtonStyle())
                    .padding(.horizontal, 32)
                    .accessibilityIdentifier("import.fixture.button")
                }
                #endif

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos
                ) {
                    HStack(spacing: IOSTheme.spacing8) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(L10n.localized("从相册选择", "Choose from Photos"))
                    }
                }
                .buttonStyle(IOSPrimaryButtonStyle())
                .padding(.horizontal, 32)
                .accessibilityIdentifier("import.picker.button")

                Spacer()
                    .frame(height: 40)
            }
            .background(IOSTheme.canvasBG.ignoresSafeArea())
            .navigationTitle(L10n.localized("导入视频", "Import Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        dismiss()
                    }
                    .foregroundStyle(IOSTheme.accent)
                    .accessibilityIdentifier("import.cancel.button")
                }
            }
            .onChange(of: selectedItem) { newValue in
                guard let newValue else { return }
                IOSHaptics.medium()
                handleSelection(newValue)
            }
            .alert(L10n.localized("错误", "Error"), isPresented: $showErrorAlert) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func handleSelection(_ item: PhotosPickerItem) {
        Task {
            guard let videoData = try? await item.loadTransferable(type: VideoFileTransferable.self) else {
                errorMessage = L10n.localized("无法从相册加载视频，请重新选择。", "Could not load the video from Photos. Please choose it again.")
                showErrorAlert = true
                return
            }

            onImportVideo(videoData.url)
            dismiss()
        }
    }
}
