import SwiftUI

enum CanvasItemKind {
    case workbenchImage(jobID: UUID, imageURL: URL?)
    case importedImage(sourceURL: URL?)
    case sticker(stickerID: String)
}

struct CanvasItem: Identifiable {
    let id: UUID
    var kind: CanvasItemKind
    var position: CGPoint      // center point in canvas coordinates
    var size: CGSize           // display size
    var rotation: CGFloat      // radians
    var opacity: CGFloat       // 0.0...1.0
    var zIndex: Int
    var isLocked: Bool
    var isHidden: Bool
    var flipH: Bool
    var flipV: Bool
    var hasShadow: Bool
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var borderColor: Color
    var intrinsicAspectRatio: CGFloat?

    init(
        id: UUID = UUID(),
        kind: CanvasItemKind,
        position: CGPoint,
        size: CGSize,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1.0,
        zIndex: Int = 0,
        isLocked: Bool = false,
        isHidden: Bool = false,
        flipH: Bool = false,
        flipV: Bool = false,
        hasShadow: Bool = false,
        cornerRadius: CGFloat = 0,
        borderWidth: CGFloat = 0,
        borderColor: Color = .clear,
        intrinsicAspectRatio: CGFloat? = nil
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.size = size
        self.rotation = rotation
        self.opacity = opacity
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.isHidden = isHidden
        self.flipH = flipH
        self.flipV = flipV
        self.hasShadow = hasShadow
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.intrinsicAspectRatio = intrinsicAspectRatio
    }

    var bounds: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func duplicated(newID: UUID = UUID(), offset: CGFloat = 20, zIndex: Int) -> CanvasItem {
        CanvasItem(
            id: newID,
            kind: kind,
            position: CGPoint(x: position.x + offset, y: position.y + offset),
            size: size,
            rotation: rotation,
            opacity: opacity,
            zIndex: zIndex,
            isLocked: false,
            isHidden: isHidden,
            flipH: flipH,
            flipV: flipV,
            hasShadow: hasShadow,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            borderColor: borderColor,
            intrinsicAspectRatio: intrinsicAspectRatio
        )
    }
}

enum CanvasBackground {
    case white
    case transparent
    case solidColor(Color)
    case customImage(NSImage)
}
