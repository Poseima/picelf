// RecordingGuideView.swift
// PicelfIOS — Control Center broadcast recording guide

import SwiftUI

struct RecordingGuideView: View {
    @Environment(\.dismiss) private var dismiss

    let onImportVideo: () -> Void
    #if DEBUG
    let onSimulateBroadcast: ((String) -> Void)?
    #endif

    #if DEBUG
    private var broadcastFixtureName: String? {
        IOSCaptureOrchestrator.fixtureName(for: IOSCaptureOrchestrator.uiTestBroadcastFixtureEnvKey)
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(IOSTheme.textSecondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 24)

                Text(L10n.localized("录屏拼接", "Stitch a Recording"))
                    .font(IOSTheme.title(24))
                    .foregroundStyle(IOSTheme.textPrimary)
                    .padding(.bottom, 6)

                Text(L10n.localized("请从控制中心启动 Picelf 广播录屏", "Start a Picelf broadcast from Control Center"))
                    .font(IOSTheme.body(14))
                    .foregroundStyle(IOSTheme.textSecondary)
                    .padding(.bottom, 20)

                broadcastStartSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                VStack(spacing: 0) {
                    stepRow(number: 1, icon: "hand.point.up.left.fill", title: L10n.localized("打开控制中心", "Open Control Center"), subtitle: L10n.localized("从屏幕右上角下滑", "Swipe down from the top-right corner"), isLast: false)
                    stepRow(number: 2, icon: "record.circle", title: L10n.localized("长按录屏按钮", "Touch and hold Screen Recording"), subtitle: L10n.localized("选择 Picelf 开始录制", "Choose Picelf to start recording"), isLast: false)
                    stepRow(number: 3, icon: "scroll.fill", title: L10n.localized("滚动目标页面", "Scroll the page"), subtitle: L10n.localized("保持均匀速度，效果更佳", "Keep a steady pace for better results"), isLast: false)
                    stepRow(number: 4, icon: "stop.circle.fill", title: L10n.localized("停止录屏", "Stop Recording"), subtitle: L10n.localized("回到 Picelf 后会自动处理", "Return to Picelf to process it automatically"), isLast: true)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            importActionBar
        }
        .background(IOSTheme.canvasBG.ignoresSafeArea())
    }

    private var importActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(IOSTheme.panelBorder)
                .frame(height: 1)

            Button {
                IOSHaptics.light()
                onImportVideo()
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                    Text(L10n.localized("或直接导入已有录屏视频", "Or import an existing screen recording"))
                        .font(IOSTheme.body(15))
                }
                .foregroundStyle(IOSTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .accessibilityIdentifier("recording.guide.import.button")
        }
        .padding(.horizontal, 24)
        .background(IOSTheme.canvasBG)
    }

    private var broadcastStartSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(IOSTheme.emeraldGradient)
                        .frame(width: 64, height: 64)
                    BroadcastPickerView(size: 52)
                        .withAccessibility()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localized("控制中心开始广播", "Start from Control Center"))
                        .font(IOSTheme.headline(16))
                        .foregroundStyle(IOSTheme.textPrimary)
                    Text(L10n.localized("点按左侧按钮，然后在系统面板里选择 Picelf。", "Tap the button on the left, then choose Picelf in the system panel."))
                        .font(IOSTheme.body(13))
                        .foregroundStyle(IOSTheme.textSecondary)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(IOSTheme.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(IOSTheme.panelBorder, lineWidth: 1)
            )

            #if DEBUG
            if let broadcastFixtureName {
                Button {
                    IOSHaptics.medium()
                    onSimulateBroadcast?(broadcastFixtureName)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text(L10n.localized("模拟广播返回", "Simulate Broadcast Return"))
                    }
                }
                .buttonStyle(IOSPrimaryButtonStyle())
                .accessibilityIdentifier("recording.guide.simulate.button")
            }
            #endif
        }
    }

    // MARK: - Step Row

    private func stepRow(number: Int, icon: String, title: String, subtitle: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(IOSTheme.emeraldGradient)
                        .frame(width: 32, height: 32)
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                if !isLast {
                    Rectangle()
                        .fill(IOSTheme.accent.opacity(0.15))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(IOSTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(IOSTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(IOSTheme.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(IOSTheme.panelBG)
            )
        }
        .padding(.horizontal, 16)
    }
}
