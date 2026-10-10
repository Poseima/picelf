import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum WatermarkPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft = "左上"
    case topCenter = "中上"
    case topRight = "右上"
    case middleLeft = "左中"
    case middleCenter = "居中"
    case middleRight = "右中"
    case bottomLeft = "左下"
    case bottomCenter = "中下"
    case bottomRight = "右下"
    
    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .topLeft: return L10n.localized("左上", "Top Left")
        case .topCenter: return L10n.localized("中上", "Top Center")
        case .topRight: return L10n.localized("右上", "Top Right")
        case .middleLeft: return L10n.localized("左中", "Middle Left")
        case .middleCenter: return L10n.localized("居中", "Center")
        case .middleRight: return L10n.localized("右中", "Middle Right")
        case .bottomLeft: return L10n.localized("左下", "Bottom Left")
        case .bottomCenter: return L10n.localized("中下", "Bottom Center")
        case .bottomRight: return L10n.localized("右下", "Bottom Right")
        }
    }
    
    /// Calculate the anchor point for the watermark text
    func anchorPoint(in rect: CGRect, padding: CGFloat = 16) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX + padding, y: rect.minY + padding)
        case .topCenter:
            return CGPoint(x: rect.midX, y: rect.minY + padding)
        case .topRight:
            return CGPoint(x: rect.maxX - padding, y: rect.minY + padding)
        case .middleLeft:
            return CGPoint(x: rect.minX + padding, y: rect.midY)
        case .middleCenter:
            return CGPoint(x: rect.midX, y: rect.midY)
        case .middleRight:
            return CGPoint(x: rect.maxX - padding, y: rect.midY)
        case .bottomLeft:
            return CGPoint(x: rect.minX + padding, y: rect.maxY - padding)
        case .bottomCenter:
            return CGPoint(x: rect.midX, y: rect.maxY - padding)
        case .bottomRight:
            return CGPoint(x: rect.maxX - padding, y: rect.maxY - padding)
        }
    }
    
    /// Text alignment for the position
    var textAlignment: NSTextAlignment {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft:
            return .left
        case .topCenter, .middleCenter, .bottomCenter:
            return .center
        case .topRight, .middleRight, .bottomRight:
            return .right
        }
    }
}

struct WatermarkConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var text: String = ""  // 可留空
    var position: WatermarkPosition = .bottomRight
    var fontSize: CGFloat = 12
    var fontName: String = "Arial"
    var color: CodableColor = CodableColor(color: .white)
    var opacity: CGFloat = 0.5
    var hasShadow: Bool = true
    var shadowRadius: CGFloat = 0
    var rotation: CGFloat = 40
    
    // 平铺模式
    var tiledEnabled: Bool = true
    var tiledAngle: CGFloat = 30
    var tiledSpacingX: CGFloat = 180
    var tiledSpacingY: CGFloat = 100
    
    init() {
        self.isEnabled = false
        self.text = ""
        self.position = .bottomRight
        self.fontSize = 12
        self.fontName = "Arial"
        self.color = CodableColor(color: .white)
        self.opacity = 0.5
        self.hasShadow = true
        self.shadowRadius = 0
        self.rotation = 40
        self.tiledEnabled = true
        self.tiledAngle = 30
        self.tiledSpacingX = 180
        self.tiledSpacingY = 100
    }
}

/// Wrapper for Color to make it Codable
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(color: Color) {
        #if canImport(AppKit)
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            self.red = 1
            self.green = 1
            self.blue = 1
            self.alpha = 1
            return
        }
        self.red = rgb.redComponent
        self.green = rgb.greenComponent
        self.blue = rgb.blueComponent
        self.alpha = rgb.alphaComponent
        #elseif canImport(UIKit)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
        #endif
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    #if canImport(AppKit)
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    #elseif canImport(UIKit)
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    #endif

    var brightnessComponent: CGFloat {
        #if canImport(AppKit)
        return nsColor.brightnessComponent
        #elseif canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return b
        #endif
    }
}
