import SwiftUI

struct RecordingToolbarView: View {
    @ObservedObject var orchestrator: RecordingOrchestrator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Red recording dot
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(orchestrator.isPaused ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: !orchestrator.isPaused)

            // Elapsed time
            Text(L10n.elapsed(Int(orchestrator.elapsedSeconds)))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 52)

            Divider()
                .frame(height: 18)

            // Pause / Resume
            Button {
                if orchestrator.isPaused {
                    orchestrator.resumeRecording()
                } else {
                    orchestrator.pauseRecording()
                }
            } label: {
                Image(systemName: orchestrator.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .iconTip(orchestrator.isPaused ? .recordResume : .recordPause)

            // Stop
            Button {
                orchestrator.stopRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .iconTip(.recordStop)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.red.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}
