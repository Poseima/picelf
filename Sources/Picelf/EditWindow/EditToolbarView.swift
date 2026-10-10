import SwiftUI
import AppKit

struct EditToolbarView: View {
    let image: NSImage
    let trimTop: Int
    let trimBottom: Int
    @Binding var selectedFormat: ImageFormat
    @Binding var jpegQuality: Double
    let dimensions: String

    @State private var showWatermarkPopover = false
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        HStack {
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)

            Button("Copy") { copyToClipboard() }
                .keyboardShortcut("c", modifiers: .command)

            Button("Share") { share() }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            // Watermark button
            ZStack(alignment: .topTrailing) {
                Button(L10n.watermark) { showWatermarkPopover = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                
                if prefs.watermarkConfig.isEnabled {
                    Circle()
                        .fill(EditorTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -2)
                }
            }
            .popover(isPresented: $showWatermarkPopover, arrowEdge: .bottom) {
                WatermarkSettingsView(isPresented: $showWatermarkPopover)
            }

            Spacer()

            Picker("Format", selection: $selectedFormat) {
                Text("PNG").tag(ImageFormat.png)
                Text("JPEG").tag(ImageFormat.jpeg)
            }
            .frame(width: 80)

            if selectedFormat == .jpeg {
                Slider(value: $jpegQuality, in: 0.1...1.0) {
                    Text("Quality")
                }
                .frame(width: 100)
            }

            Text(dimensions)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .tint(EditorTheme.accent)
    }

    private func trimmedImage() -> NSImage? {
        guard let trimmed = image.trimmed(top: trimTop, bottom: trimBottom) else { return nil }
        // Apply watermark
        let config = prefs.watermarkConfig
        return WatermarkRenderer.apply(to: trimmed, config: config)
    }

    private func save() {
        guard let trimmed = trimmedImage() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = selectedFormat == .png
            ? [.png]
            : [.jpeg]
        panel.nameFieldStringValue = "Picelf-\(dateString()).\(selectedFormat == .png ? "png" : "jpg")"

        let savePath = AppPreferences.shared.savePath
        if !savePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: savePath)
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            AppPreferences.shared.savePath = url.deletingLastPathComponent().path

            let format: ImageExporter.Format = self.selectedFormat == .png
                ? .png
                : .jpeg(quality: self.jpegQuality)

            try? ImageExporter.export(trimmed, to: url, format: format)
        }
    }

    private func copyToClipboard() {
        guard let trimmed = trimmedImage() else { return }
        try? trimmed.copyToClipboard()
    }

    private func share() {
        guard let trimmed = trimmedImage() else { return }
        let picker = NSSharingServicePicker(items: [trimmed])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
