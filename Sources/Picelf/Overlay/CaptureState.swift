import Foundation
import SwiftUI
import AppKit

enum CaptureInteractionMode {
    case idleSelecting
    case dragSelecting
    case selectionReady
}

@MainActor
class CaptureState: ObservableObject {
    @Published var isCapturing = false
    @Published var isStitching = false
    @Published var frameCount = 0
    @Published var stitchProgress: Double = 0
    @Published var selectedWindowID: CGWindowID?
    @Published var frameRect: CGRect = .zero
    @Published var mode: CaptureInteractionMode = .idleSelecting
    @Published var previewImage: NSImage?
    @Published var isSnapEditing = false
    /// True when snap edit has an active tool selected; frame interactions should be locked.
    @Published var isSnapEditingToolActive = false
    @Published var frozenBackgroundImage: NSImage?
    @Published var frozenScreenFrame: CGRect = .zero
    @Published var frozenPixelScaleX: CGFloat = 1
    @Published var frozenPixelScaleY: CGFloat = 1
}
