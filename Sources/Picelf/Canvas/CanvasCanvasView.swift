import SwiftUI
import AppKit

struct CanvasCanvasView: View {
    @ObservedObject var document: CanvasDocument
    var onMagnify: ((CGFloat, CGPoint) -> Void)? = nil

    @State private var interactionMode: InteractionMode = .none
    @State private var lastPoint: CGPoint?
    @State private var lastMagnificationValue: CGFloat = 1.0
    @State private var hoverLocation: CGPoint = .zero
    @State private var marqueeStart: CGPoint?
    @State private var marqueeEnd: CGPoint?

    private enum InteractionMode {
        case none
        case moving
        case resizing(ResizeCorner)
        case rotating
        case marqueeSelect
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            canvasBackground
                .frame(
                    width: document.canvasSize.width * document.zoomScale,
                    height: document.canvasSize.height * document.zoomScale
                )

            // Items rendered via SwiftUI Canvas
            Canvas { context, _ in
                for item in document.visibleItems {
                    drawItem(item, in: context)
                }
                
                // 实时水印预览
                let watermarkConfig = AppPreferences.shared.watermarkConfig
                if watermarkConfig.isEnabled && !watermarkConfig.text.isEmpty {
                    let canvasSize = CGSize(
                        width: document.canvasSize.width * document.zoomScale,
                        height: document.canvasSize.height * document.zoomScale
                    )
                    drawWatermark(config: watermarkConfig, in: context, canvasSize: canvasSize)
                }
            }
            .frame(
                width: document.canvasSize.width * document.zoomScale,
                height: document.canvasSize.height * document.zoomScale
            )

            // Selection overlay
            SelectionOverlayView(
                selectionRect: scaledSelectionRect,
                showsResizeHandle: document.selectedItemIDs.count == 1,
                showsRotationHandle: document.selectedItemIDs.count == 1
            )

            // Marquee selection rectangle
            if let start = marqueeStart, let end = marqueeEnd {
                let rect = normalizedRect(start: start, end: end)
                Rectangle()
                    .stroke(EditorTheme.selectionStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .background(EditorTheme.subtleAccentFill)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(
            width: document.canvasSize.width * document.zoomScale,
            height: document.canvasSize.height * document.zoomScale,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(singleTapGesture)
        .simultaneousGesture(magnificationGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
            case .ended:
                hoverLocation = CGPoint(
                    x: (document.canvasSize.width * document.zoomScale) / 2,
                    y: (document.canvasSize.height * document.zoomScale) / 2
                )
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var canvasBackground: some View {
        switch document.background {
        case .white:
            Color.white
        case .transparent:
            CheckerboardView()
        case .solidColor(let color):
            color
        case .customImage(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    // MARK: - Scaled Selection

    private var scaledSelectionRect: CGRect? {
        guard let rect = document.selectionBounds() else { return nil }
        return CGRect(
            x: rect.origin.x * document.zoomScale,
            y: rect.origin.y * document.zoomScale,
            width: rect.width * document.zoomScale,
            height: rect.height * document.zoomScale
        )
    }

    // MARK: - Gestures

    private var singleTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = toCanvasPoint(value.location)
                let additive = NSEvent.modifierFlags.contains(.shift)
                document.selectItem(at: point, additive: additive)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let point = toCanvasPoint(value.location)
                handleDragChanged(point, viewLocation: value.location)
            }
            .onEnded { value in
                let point = toCanvasPoint(value.location)
                defer {
                    interactionMode = .none
                    lastPoint = nil
                    marqueeStart = nil
                    marqueeEnd = nil
                }

                switch interactionMode {
                case .resizing(let corner):
                    document.resizePrimarySelection(to: point, corner: corner)
                    document.finalizeInteractionChange()
                case .rotating:
                    if let bounds = document.selectionBounds() {
                        let center = CGPoint(x: bounds.midX, y: bounds.midY)
                        let angle = atan2(point.y - center.y, point.x - center.x) + .pi / 2
                        document.rotatePrimarySelection(angle: angle)
                    }
                    document.finalizeInteractionChange()
                case .moving:
                    document.finalizeInteractionChange()
                case .marqueeSelect:
                    selectItemsInMarquee()
                case .none:
                    document.cancelInteractionChange()
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnificationValue
                if let onMagnify {
                    onMagnify(delta, hoverLocation)
                } else {
                    document.setZoomScale(document.zoomScale * delta)
                }
                lastMagnificationValue = value.magnification
            }
            .onEnded { _ in
                lastMagnificationValue = 1.0
            }
    }

    // MARK: - Drag Logic

    private func handleDragChanged(_ point: CGPoint, viewLocation: CGPoint) {
        switch interactionMode {
        case .none:
            if isNearRotationHandle(point) {
                interactionMode = .rotating
                lastPoint = point
            } else if let corner = hitResizeCorner(point) {
                interactionMode = .resizing(corner)
                lastPoint = point
            } else if let hit = document.hitTest(at: point) {
                if !document.selectedItemIDs.contains(hit) {
                    document.selectedItemIDs = [hit]
                }
                interactionMode = .moving
                lastPoint = point
            } else {
                interactionMode = .marqueeSelect
                marqueeStart = viewLocation
                marqueeEnd = viewLocation
            }
        case .moving:
            guard let lastPoint else { return }
            let delta = CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y)
            document.moveSelection(by: delta)
            self.lastPoint = point
        case .resizing(let corner):
            document.resizePrimarySelection(to: point, corner: corner)
        case .rotating:
            if let bounds = document.selectionBounds() {
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                let angle = atan2(point.y - center.y, point.x - center.x) + .pi / 2
                document.rotatePrimarySelection(angle: angle)
            }
        case .marqueeSelect:
            marqueeEnd = viewLocation
        }
    }

    private func selectItemsInMarquee() {
        guard let start = marqueeStart, let end = marqueeEnd else { return }
        let rect = normalizedRect(
            start: toCanvasPoint(start),
            end: toCanvasPoint(end)
        )
        guard rect.width > 4, rect.height > 4 else { return }
        var selected: Set<UUID> = []
        for item in document.visibleItems {
            if rect.intersects(item.bounds) && !item.isLocked {
                selected.insert(item.id)
            }
        }
        document.selectedItemIDs = selected
    }

    // MARK: - Hit Testing

    private func hitResizeCorner(_ point: CGPoint) -> ResizeCorner? {
        guard let bounds = document.selectionBounds(), document.selectedItemIDs.count == 1 else { return nil }
        let threshold: CGFloat = 12
        let corners: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: bounds.minX, y: bounds.minY), .topLeft),
            (CGPoint(x: bounds.maxX, y: bounds.minY), .topRight),
            (CGPoint(x: bounds.minX, y: bounds.maxY), .bottomLeft),
            (CGPoint(x: bounds.maxX, y: bounds.maxY), .bottomRight),
        ]
        for (corner, resizeCorner) in corners {
            if hypot(point.x - corner.x, point.y - corner.y) <= threshold {
                return resizeCorner
            }
        }
        return nil
    }

    private func isNearRotationHandle(_ point: CGPoint) -> Bool {
        guard document.selectedItemIDs.count == 1, let bounds = document.selectionBounds() else { return false }
        let handlePoint = CGPoint(x: bounds.midX, y: bounds.minY - 24)
        return hypot(point.x - handlePoint.x, point.y - handlePoint.y) <= 12
    }

    // MARK: - Coordinate Conversion

    private func toCanvasPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x / document.zoomScale, y: location.y / document.zoomScale)
    }

    private func normalizedRect(start: CGPoint, end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // MARK: - Item Drawing

    private func drawItem(_ item: CanvasItem, in context: GraphicsContext) {
        guard let image = document.resolveImage(for: item) else { return }
        let bounds = scaledBounds(item)

        var ctx = context
        ctx.opacity = item.opacity

        if item.hasShadow {
            ctx.addFilter(.shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2))
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CGAffineTransform.identity
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: item.rotation)
        if item.flipH { transform = transform.scaledBy(x: -1, y: 1) }
        if item.flipV { transform = transform.scaledBy(x: 1, y: -1) }
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        ctx.concatenate(transform)

        if item.cornerRadius > 0 {
            let clippedPath = Path(roundedRect: bounds, cornerRadius: item.cornerRadius * document.zoomScale)
            ctx.clip(to: clippedPath)
        }

        ctx.draw(Image(nsImage: image), in: bounds)

        if item.borderWidth > 0 {
            ctx.stroke(
                Path(roundedRect: bounds, cornerRadius: item.cornerRadius * document.zoomScale),
                with: .color(item.borderColor),
                lineWidth: item.borderWidth * document.zoomScale
            )
        }
    }

    private func scaledBounds(_ item: CanvasItem) -> CGRect {
        let b = item.bounds
        return CGRect(
            x: b.origin.x * document.zoomScale,
            y: b.origin.y * document.zoomScale,
            width: b.width * document.zoomScale,
            height: b.height * document.zoomScale
        )
    }
    
    // MARK: - Watermark Drawing
    
    private func drawWatermark(config: WatermarkConfig, in context: GraphicsContext, canvasSize: CGSize) {
        let padding: CGFloat = 16
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let reducedDensity: Bool
        switch interactionMode {
        case .none:
            reducedDensity = false
        default:
            reducedDensity = true
        }
        
        // 不再随 zoomScale 缩放，使用原始尺寸
        if config.tiledEnabled {
            drawTiledWatermark(
                config: config,
                in: context,
                canvasSize: canvasSize,
                reducedDensity: reducedDensity
            )
        } else {
            let position = config.position.anchorPoint(in: canvasRect, padding: padding)
            drawWatermarkText(config: config, in: context, at: position)
        }
    }
    
    private func drawWatermarkText(config: WatermarkConfig, in context: GraphicsContext, at position: CGPoint) {
        let textColor = config.color.color.opacity(config.opacity)
        
        var textContext = context
        if config.hasShadow {
            textContext.addFilter(.shadow(
                color: .black.opacity(0.5),
                radius: config.shadowRadius,
                x: 1,
                y: -1
            ))
        }
        
        var resolvedContext = textContext
        if config.rotation != 0 {
            let transform = CGAffineTransform.identity
                .translatedBy(x: position.x, y: position.y)
                .rotated(by: config.rotation * .pi / 180)
                .translatedBy(x: -position.x, y: -position.y)
            resolvedContext.concatenate(transform)
        }
        
        let text = Text(config.text)
            .font(.system(size: config.fontSize, weight: .semibold))
            .foregroundStyle(textColor)
        
        resolvedContext.draw(text, at: position, anchor: anchorForPosition(config.position))
    }
    
    private func drawTiledWatermark(
        config: WatermarkConfig,
        in context: GraphicsContext,
        canvasSize: CGSize,
        reducedDensity: Bool
    ) {
        let angle = config.tiledAngle * .pi / 180
        let spacingScale: CGFloat = reducedDensity ? 1.8 : 1.0
        let spacingX = max(40, config.tiledSpacingX * spacingScale)
        let spacingY = max(40, config.tiledSpacingY * spacingScale)
        let step = reducedDensity ? 2 : 1
        
        // 旋转30度后，需要更大的覆盖范围
        let diagonal = sqrt(canvasSize.width * canvasSize.width + canvasSize.height * canvasSize.height)
        let coverSize = diagonal * (reducedDensity ? 1.15 : 1.5)
        
        let cols = Int(coverSize / spacingX) + 2
        let rows = Int(coverSize / spacingY) + 2
        let cosA = cos(angle)
        let sinA = sin(angle)
        
        for row in stride(from: -rows, through: rows, by: step) {
            for col in stride(from: -cols, through: cols, by: step) {
                let baseX = canvasSize.width / 2 + CGFloat(col) * spacingX
                let baseY = canvasSize.height / 2 + CGFloat(row) * spacingY
                
                // 应用旋转
                let rotatedX = (baseX - canvasSize.width / 2) * cosA - (baseY - canvasSize.height / 2) * sinA + canvasSize.width / 2
                let rotatedY = (baseX - canvasSize.width / 2) * sinA + (baseY - canvasSize.height / 2) * cosA + canvasSize.height / 2
                
                let pos = CGPoint(x: rotatedX, y: rotatedY)
                
                // 只绘制在画布范围内的水印
                if pos.x > -50 && pos.x < canvasSize.width + 50 &&
                   pos.y > -50 && pos.y < canvasSize.height + 50 {
                    drawWatermarkText(config: config, in: context, at: pos)
                }
            }
        }
    }
    
    private func anchorForPosition(_ position: WatermarkPosition) -> UnitPoint {
        switch position {
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .middleLeft: return .leading
        case .middleCenter: return .center
        case .middleRight: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }
}

// MARK: - Checkerboard Background

struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 12
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            let light = Color(white: 0.95)
            let dark = Color(white: 0.82)

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(Path(rect), with: .color(isLight ? light : dark))
                }
            }
        }
    }
}
