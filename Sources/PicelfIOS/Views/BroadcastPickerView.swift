// BroadcastPickerView.swift
// PicelfIOS — UIViewRepresentable wrapping RPSystemBroadcastPickerView
//
// Presents the system broadcast picker that lets users start a broadcast
// upload extension for cross-app screen recording.
//
// Target: iOS 16+, Swift 5.9+

import SwiftUI
import ReplayKit

/// SwiftUI wrapper for RPSystemBroadcastPickerView.
///
/// When tapped, this shows the system broadcast picker UI that lets the user
/// start/stop the PicelfBroadcastUpload extension for cross-app recording.
struct BroadcastPickerView: UIViewRepresentable {

    /// Width and height of the picker view.
    var size: CGFloat = 44

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        picker.preferredExtension = "com.picelf.open.ios.broadcast-upload"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        // No dynamic updates needed
    }
}

extension BroadcastPickerView {
    func withAccessibility() -> some View {
        self.accessibilityIdentifier("capture.broadcast.picker")
            .accessibilityLabel(L10n.localized("开始广播录屏", "Start broadcast recording"))
    }
}
