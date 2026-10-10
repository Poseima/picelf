import SwiftUI

struct ProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var orchestrator: IOSCaptureOrchestrator

    private var progress: Double {
        switch orchestrator.state {
        case .extracting(let p, _, _): return p
        case .stitching(let p): return p
        default: return 0
        }
    }

    private var statusText: String {
        switch orchestrator.state {
        case .extracting(_, let framesExtracted, let totalSamples):
            if totalSamples > 0 {
                return L10n.localized("提取帧中... \(framesExtracted)/\(totalSamples)", "Extracting frames... \(framesExtracted)/\(totalSamples)")
            }
            return L10n.localized("提取帧中...", "Extracting frames...")
        case .stitching(let p):
            return L10n.localized("拼接中... \(Int(p * 100))%", "Stitching... \(Int(p * 100))%")
        case .completed:
            return L10n.done
        case .failed(let msg):
            return L10n.localized("失败: \(msg)", "Failed: \(msg)")
        default:
            return L10n.localized("准备中...", "Preparing...")
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(IOSTheme.accent.opacity(0.15), lineWidth: 6)
                    .frame(width: 120, height: 120)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        IOSTheme.emeraldGradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)

                // Percentage text
                Text("\(Int(progress * 100))%")
                    .font(IOSTheme.title(24))
                    .foregroundStyle(IOSTheme.textPrimary)
            }
            .accessibilityIdentifier("processing.progress.ring")

            // Status text
            VStack(spacing: IOSTheme.spacing8) {
                Text(statusText)
                    .font(IOSTheme.headline(16))
                    .foregroundStyle(IOSTheme.textPrimary)

                // Linear progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(IOSTheme.accent.opacity(0.15))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(IOSTheme.emeraldGradient)
                            .frame(width: geometry.size.width * progress, height: 6)
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            .accessibilityIdentifier("processing.status.text")

            Spacer()

            // Cancel button
            Button {
                IOSHaptics.light()
                orchestrator.cancel()
                dismiss()
            } label: {
                Text(L10n.cancel)
                    .font(IOSTheme.body())
                    .foregroundStyle(IOSTheme.textSecondary)
            }
            .padding(.bottom, 40)
            .accessibilityIdentifier("processing.cancel.button")
        }
        .background(IOSTheme.canvasBG.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
