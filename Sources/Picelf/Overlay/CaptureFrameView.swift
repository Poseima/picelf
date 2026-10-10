import SwiftUI
import os

private let log = Logger(subsystem: "com.picelf", category: "UserAction")

struct CaptureFrameView: View {
    @ObservedObject var captureState: CaptureState
    let screenFrame: CGRect
    let onCancel: () -> Void
    let onManualSelectionCommitted: () -> Void
    let onRestartFramingRequested: () -> Void
    let onTapWithoutDrag: ((CGPoint) -> Void)?
    
    @State private var dragStartLocal: CGPoint?
    @State private var dragStartFrame: CGRect?
    @State private var activeInteraction: Interaction = .none
    @State private var pushedCrosshairCursor = false
    @State private var hasCrossedManualDragThreshold = false

    private let minSelectionSize: CGFloat = 24
    private let handleHitRadius: CGFloat = 14
    private let borderHitThickness: CGFloat = 12
    private let manualDragThreshold: CGFloat = 3

    private enum Interaction {
        case none
        case newSelection
        case move
        case resize(ResizeAnchor)
    }

    var body: some View {
        GeometryReader { geo in
            let localSelection = localRect(from: captureState.frameRect)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(selectionGesture(in: geo.size))

                if localSelection.width > 0, localSelection.height > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            borderColor(for: captureState.mode),
                            lineWidth: 2
                        )
                        .frame(width: localSelection.width, height: localSelection.height)
                        .position(x: localSelection.midX, y: localSelection.midY)
                        .allowsHitTesting(false)

                    if !captureState.isCapturing {
                        // Corner handles - frame set externally for proper position tracking
                        ResizeHandle()
                            .frame(width: 12, height: 12)
                            .position(x: localSelection.minX, y: localSelection.minY)
                            .allowsHitTesting(false)
                        ResizeHandle()
                            .frame(width: 12, height: 12)
                            .position(x: localSelection.maxX, y: localSelection.minY)
                            .allowsHitTesting(false)
                        ResizeHandle()
                            .frame(width: 12, height: 12)
                            .position(x: localSelection.minX, y: localSelection.maxY)
                            .allowsHitTesting(false)
                        ResizeHandle()
                            .frame(width: 12, height: 12)
                            .position(x: localSelection.maxX, y: localSelection.maxY)
                            .allowsHitTesting(false)
                    }

                } else {
                    Text(L10n.dragHint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.35), in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                if !pushedCrosshairCursor {
                    NSCursor.crosshair.push()
                    pushedCrosshairCursor = true
                }
            }
            .onDisappear {
                if pushedCrosshairCursor {
                    NSCursor.pop()
                    pushedCrosshairCursor = false
                }
            }
        }
    }

    private func selectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !captureState.isCapturing else { return }
                guard !captureState.isSnapEditingToolActive else { return }

                let location = clamped(value.location, in: size)
                if dragStartLocal == nil {
                    let start = clamped(value.startLocation, in: size)
                    dragStartLocal = start
                    dragStartFrame = captureState.frameRect
                    activeInteraction = resolveInteraction(
                        at: start,
                        selectionRect: localRect(from: captureState.frameRect),
                        forceNewSelection: captureState.mode == .idleSelecting
                    )
                }

                guard let start = dragStartLocal else { return }
                let dragDistance = hypot(value.translation.width, value.translation.height)
                if dragDistance >= manualDragThreshold, !hasCrossedManualDragThreshold {
                    if shouldRestartFramingForAutoSnapDrag() {
                        onRestartFramingRequested()
                        // Restart framing, then continue this same gesture as a fresh selection.
                        activeInteraction = .newSelection
                        dragStartFrame = nil
                    }
                    hasCrossedManualDragThreshold = true
                    captureState.mode = .dragSelecting
                }

                switch activeInteraction {
                case .none:
                    break
                case .newSelection:
                    guard hasCrossedManualDragThreshold else { break }
                    let rect = normalizedRect(from: start, to: location)
                    captureState.frameRect = rounded(clampToScreen(screenRect(from: rect)))
                case .move:
                    guard hasCrossedManualDragThreshold else { break }
                    guard let startFrame = dragStartFrame else { return }
                    let moved = CGRect(
                        x: startFrame.origin.x + value.translation.width,
                        y: startFrame.origin.y - value.translation.height,
                        width: startFrame.width,
                        height: startFrame.height
                    )
                    captureState.frameRect = rounded(clampToScreen(moved))
                case .resize(let anchor):
                    guard hasCrossedManualDragThreshold else { break }
                    guard let startFrame = dragStartFrame else { return }
                    let resized = anchor.adjustedRect(
                        from: startFrame,
                        deltaX: value.translation.width,
                        deltaY: value.translation.height
                    )
                    captureState.frameRect = rounded(clampToScreen(resized))
                }
            }
            .onEnded { value in
                defer {
                    dragStartLocal = nil
                    dragStartFrame = nil
                    activeInteraction = .none
                    hasCrossedManualDragThreshold = false
                }

                guard !captureState.isCapturing else { return }
                guard !captureState.isSnapEditingToolActive else { return }
                guard hasCrossedManualDragThreshold else {
                    let tapLocal = clamped(value.location, in: size)
                    onTapWithoutDrag?(screenPoint(from: tapLocal))
                    return
                }
                if captureState.frameRect.width < minSelectionSize || captureState.frameRect.height < minSelectionSize {
                    captureState.frameRect = .zero
                    captureState.mode = .idleSelecting
                    return
                }
                onManualSelectionCommitted()
                captureState.mode = .selectionReady
                log.debug("[USER] Selection updated -> \(self.captureState.frameRect.debugDescription)")
            }
    }

    private func shouldRestartFramingForAutoSnapDrag() -> Bool {
        let isMoveInteraction: Bool
        if case .move = activeInteraction {
            isMoveInteraction = true
        } else {
            isMoveInteraction = false
        }
        return Self.shouldRestartFramingForAutoSnapDrag(
            autoSnapEnabled: AppPreferences.shared.autoSnapToWindows,
            isSnapEditing: captureState.isSnapEditing,
            isSnapEditingToolActive: captureState.isSnapEditingToolActive,
            isStitching: captureState.isStitching,
            hasSelectedWindow: captureState.selectedWindowID != nil,
            hasFrame: captureState.frameRect.width > 0 && captureState.frameRect.height > 0,
            frameRect: captureState.frameRect,
            screenFrame: screenFrame,
            mode: captureState.mode,
            isMoveInteraction: isMoveInteraction
        )
    }

    nonisolated static func shouldRestartFramingForAutoSnapDrag(
        autoSnapEnabled: Bool,
        isSnapEditing: Bool,
        isSnapEditingToolActive: Bool,
        isStitching: Bool,
        hasSelectedWindow: Bool,
        hasFrame: Bool,
        frameRect: CGRect,
        screenFrame: CGRect,
        mode: CaptureInteractionMode,
        isMoveInteraction: Bool
    ) -> Bool {
        guard autoSnapEnabled else { return false }
        guard mode == .selectionReady else { return false }
        guard isMoveInteraction else { return false }
        guard !isStitching else { return false }
        guard hasSelectedWindow else { return false }
        guard hasFrame else { return false }

        if isSnapEditing {
            guard !isSnapEditingToolActive else { return false }
            return frameApproximatelyCoversScreen(
                frameRect: frameRect,
                screenFrame: screenFrame
            )
        }

        return true
    }

    nonisolated static func frameApproximatelyCoversScreen(
        frameRect: CGRect,
        screenFrame: CGRect,
        edgeTolerance: CGFloat = 18
    ) -> Bool {
        guard frameRect.width > 0, frameRect.height > 0 else { return false }
        guard screenFrame.width > 0, screenFrame.height > 0 else { return false }

        let leftAligned = abs(frameRect.minX - screenFrame.minX) <= edgeTolerance
        let rightAligned = abs(frameRect.maxX - screenFrame.maxX) <= edgeTolerance
        let bottomAligned = abs(frameRect.minY - screenFrame.minY) <= edgeTolerance
        let topAligned = abs(frameRect.maxY - screenFrame.maxY) <= edgeTolerance
        return leftAligned && rightAligned && bottomAligned && topAligned
    }

    private func resolveInteraction(
        at point: CGPoint,
        selectionRect: CGRect,
        forceNewSelection: Bool
    ) -> Interaction {
        if captureState.isSnapEditingToolActive {
            return .none
        }

        if forceNewSelection {
            return .newSelection
        }

        guard selectionRect.width > 0, selectionRect.height > 0 else {
            return .newSelection
        }

        for corner in ResizeAnchor.corners {
            let handleCenter = corner.position(in: selectionRect)
            if distance(point, handleCenter) <= handleHitRadius {
                return .resize(corner)
            }
        }

        if !selectionRect.contains(point) {
            return .newSelection
        }

        if let edgeAnchor = edgeAnchor(at: point, in: selectionRect) {
            return .resize(edgeAnchor)
        }

        if selectionRect.contains(point) {
            return .move
        }

        return .newSelection
    }

    private func edgeAnchor(at point: CGPoint, in rect: CGRect) -> ResizeAnchor? {
        let nearLeft = abs(point.x - rect.minX) <= borderHitThickness
        let nearRight = abs(point.x - rect.maxX) <= borderHitThickness
        let nearTop = abs(point.y - rect.minY) <= borderHitThickness
        let nearBottom = abs(point.y - rect.maxY) <= borderHitThickness

        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        if nearRight { return .right }

        return nil
    }

    private func borderColor(for mode: CaptureInteractionMode) -> Color {
        switch mode {
        case .idleSelecting:
            return Color.white.opacity(0.75)
        case .dragSelecting:
            return EditorTheme.selectionStroke
        case .selectionReady:
            return EditorTheme.accent
        }
    }

    private func localRect(from screenRect: CGRect) -> CGRect {
        guard screenRect.width > 0, screenRect.height > 0 else { return .zero }

        let x = screenRect.minX - screenFrame.minX
        let y = screenFrame.maxY - screenRect.maxY
        return CGRect(x: x, y: y, width: screenRect.width, height: screenRect.height)
    }

    private func screenPoint(from localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + localPoint.x,
            y: screenFrame.maxY - localPoint.y
        )
    }

    private func screenRect(from localRect: CGRect) -> CGRect {
        let x = screenFrame.minX + localRect.minX
        let topY = screenFrame.maxY - localRect.minY
        let y = topY - localRect.height
        return CGRect(x: x, y: y, width: localRect.width, height: localRect.height)
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func rounded(_ rect: CGRect) -> CGRect {
        CGRect(
            x: round(rect.origin.x),
            y: round(rect.origin.y),
            width: round(rect.width),
            height: round(rect.height)
        )
    }

    private func clampToScreen(_ rect: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(max(minSelectionSize, r.width), screenFrame.width)
        r.size.height = min(max(minSelectionSize, r.height), screenFrame.height)
        r.origin.x = min(max(screenFrame.minX, r.origin.x), screenFrame.maxX - r.width)
        r.origin.y = min(max(screenFrame.minY, r.origin.y), screenFrame.maxY - r.height)
        return r
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), size.width),
            y: min(max(0, point.y), size.height)
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

enum ResizeAnchor: CaseIterable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static var corners: [ResizeAnchor] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// deltaX/deltaY are in SwiftUI coordinate space (right=+x, down=+y).
    /// The returned rect is in screen coordinates (origin at bottom-left).
    func adjustedRect(from rect: CGRect, deltaX: CGFloat, deltaY: CGFloat, minSize: CGFloat = 50) -> CGRect {
        switch self {
        case .left:
            let newWidth = max(minSize, rect.width - deltaX)
            return CGRect(
                x: rect.maxX - newWidth,
                y: rect.origin.y,
                width: newWidth,
                height: rect.height
            )
        case .right:
            let newWidth = max(minSize, rect.width + deltaX)
            return CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: newWidth,
                height: rect.height
            )
        case .top:
            let newHeight = max(minSize, rect.height - deltaY)
            return CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: newHeight
            )
        case .bottom:
            let newHeight = max(minSize, rect.height + deltaY)
            return CGRect(
                x: rect.origin.x,
                y: rect.maxY - newHeight,
                width: rect.width,
                height: newHeight
            )
        case .topLeft:
            let newWidth = max(minSize, rect.width - deltaX)
            let newHeight = max(minSize, rect.height - deltaY)
            return CGRect(
                x: rect.maxX - newWidth,
                y: rect.origin.y,
                width: newWidth,
                height: newHeight
            )
        case .topRight:
            let newWidth = max(minSize, rect.width + deltaX)
            let newHeight = max(minSize, rect.height - deltaY)
            return CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: newWidth,
                height: newHeight
            )
        case .bottomLeft:
            let newWidth = max(minSize, rect.width - deltaX)
            let newHeight = max(minSize, rect.height + deltaY)
            return CGRect(
                x: rect.maxX - newWidth,
                y: rect.maxY - newHeight,
                width: newWidth,
                height: newHeight
            )
        case .bottomRight:
            let newWidth = max(minSize, rect.width + deltaX)
            let newHeight = max(minSize, rect.height + deltaY)
            return CGRect(
                x: rect.origin.x,
                y: rect.maxY - newHeight,
                width: newWidth,
                height: newHeight
            )
        }
    }
}

private struct ResizeHandle: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.94))
            .overlay(
                Circle()
                    .stroke(EditorTheme.selectionStroke.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 2)
        // Frame size set externally for proper position tracking
    }
}
