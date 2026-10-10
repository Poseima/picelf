import Foundation
import SwiftUI

enum EditorToolContext: String, Codable, CaseIterable {
    case fullEditor
    case snapEdit
    case canvasExportOnly
}

struct EditorToolState: Codable, Equatable {
    static let currentSchemaVersion = 2

    static let knownToolRawValues: [String] = [
        "Rect", "Ellipse", "Line", "Arrow", "Pencil", "Mosaic", "Text", "Step", "Highlight", "Sticker"
    ]

    static let lineWidthRange: ClosedRange<Double> = 1...24
    static let textFontSizeRange: ClosedRange<Double> = 12...64
    static let textBoxWidthRange: ClosedRange<Double> = 160...1200
    static let mosaicBlockSizeRange: ClosedRange<Double> = 6...40
    static let jpegQualityRange: ClosedRange<Double> = 0.1...1.0

    static let defaultLineWidth: Double = 3
    static let defaultTextFontSize: Double = 18
    static let defaultTextBoxWidth: Double = 320
    static let defaultMosaicBlockSize: Double = 14
    static let defaultSticker: String = "★"
    static let defaultStrokeColor = CodableColor(color: Color(red: 0.00, green: 0.55, blue: 0.40))
    static let defaultFillColor = CodableColor(color: .clear)

    var schemaVersion: Int
    var selectedToolRaw: String?
    var toolRecencyRaw: [String]

    var strokeColor: CodableColor
    var fillColor: CodableColor
    var lineWidth: Double
    var textFontSize: Double
    var textBoxWidth: Double
    var mosaicBlockSize: Double
    var selectedSticker: String

    var exportFormat: ImageFormat
    var jpegQuality: Double

    static func defaultState(
        exportFormat: ImageFormat = .png,
        jpegQuality: Double = 0.9
    ) -> EditorToolState {
        EditorToolState(
            schemaVersion: currentSchemaVersion,
            selectedToolRaw: nil,
            toolRecencyRaw: [],
            strokeColor: defaultStrokeColor,
            fillColor: defaultFillColor,
            lineWidth: defaultLineWidth,
            textFontSize: defaultTextFontSize,
            textBoxWidth: defaultTextBoxWidth,
            mosaicBlockSize: defaultMosaicBlockSize,
            selectedSticker: defaultSticker,
            exportFormat: exportFormat,
            jpegQuality: jpegQuality
        )
        .sanitized()
    }

    mutating func recordToolSelection(rawValue: String?) {
        selectedToolRaw = rawValue
        guard let rawValue else { return }
        toolRecencyRaw.removeAll { $0 == rawValue }
        toolRecencyRaw.insert(rawValue, at: 0)
        if toolRecencyRaw.count > 20 {
            toolRecencyRaw.removeLast(toolRecencyRaw.count - 20)
        }
    }

    /// Entering any editor context should start with no active tool selected.
    /// We still persist tool recency for analytics/future preference usage.
    func resolvedSelectedToolRaw(for _: EditorToolContext) -> String? {
        nil
    }

    func sanitized() -> EditorToolState {
        var copy = self
        let originalSchemaVersion = copy.schemaVersion

        let knownTools = Set(Self.knownToolRawValues)

        if let raw = copy.selectedToolRaw, !knownTools.contains(raw) {
            copy.selectedToolRaw = nil
        }

        var dedupedRecency: [String] = []
        var seen: Set<String> = []
        for raw in copy.toolRecencyRaw {
            guard knownTools.contains(raw), !seen.contains(raw) else { continue }
            dedupedRecency.append(raw)
            seen.insert(raw)
            if dedupedRecency.count >= 20 {
                break
            }
        }
        copy.toolRecencyRaw = dedupedRecency

        if let selected = copy.selectedToolRaw {
            copy.toolRecencyRaw.removeAll { $0 == selected }
            copy.toolRecencyRaw.insert(selected, at: 0)
            if copy.toolRecencyRaw.count > 20 {
                copy.toolRecencyRaw.removeLast(copy.toolRecencyRaw.count - 20)
            }
        }

        copy.strokeColor = copy.strokeColor.clamped()
        copy.fillColor = copy.fillColor.clamped()
        copy.migrateLegacyDefaultsIfNeeded(from: originalSchemaVersion)
        copy.lineWidth = Self.clamp(copy.lineWidth, to: Self.lineWidthRange)
        copy.textFontSize = Self.clamp(copy.textFontSize, to: Self.textFontSizeRange)
        copy.textBoxWidth = Self.clamp(copy.textBoxWidth, to: Self.textBoxWidthRange)
        copy.mosaicBlockSize = Self.clamp(copy.mosaicBlockSize, to: Self.mosaicBlockSizeRange)
        copy.jpegQuality = Self.clampJPEGQuality(copy.jpegQuality)

        if copy.selectedSticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.selectedSticker = Self.defaultSticker
        }

        copy.schemaVersion = Self.currentSchemaVersion
        return copy
    }

    static func clampJPEGQuality(_ value: Double) -> Double {
        clamp(value, to: jpegQualityRange)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case selectedToolRaw
        case toolRecencyRaw
        case strokeColor
        case fillColor
        case lineWidth
        case textFontSize
        case textBoxWidth
        case mosaicBlockSize
        case selectedSticker
        case exportFormat
        case jpegQuality
    }

    init(
        schemaVersion: Int,
        selectedToolRaw: String?,
        toolRecencyRaw: [String],
        strokeColor: CodableColor,
        fillColor: CodableColor,
        lineWidth: Double,
        textFontSize: Double,
        textBoxWidth: Double = Self.defaultTextBoxWidth,
        mosaicBlockSize: Double,
        selectedSticker: String,
        exportFormat: ImageFormat,
        jpegQuality: Double
    ) {
        self.schemaVersion = schemaVersion
        self.selectedToolRaw = selectedToolRaw
        self.toolRecencyRaw = toolRecencyRaw
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.textFontSize = textFontSize
        self.textBoxWidth = textBoxWidth
        self.mosaicBlockSize = mosaicBlockSize
        self.selectedSticker = selectedSticker
        self.exportFormat = exportFormat
        self.jpegQuality = jpegQuality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        selectedToolRaw = try container.decodeIfPresent(String.self, forKey: .selectedToolRaw)
        toolRecencyRaw = try container.decodeIfPresent([String].self, forKey: .toolRecencyRaw) ?? []
        strokeColor = try container.decodeIfPresent(CodableColor.self, forKey: .strokeColor) ?? Self.defaultStrokeColor
        fillColor = try container.decodeIfPresent(CodableColor.self, forKey: .fillColor) ?? Self.defaultFillColor
        lineWidth = try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? Self.defaultLineWidth
        textFontSize = try container.decodeIfPresent(Double.self, forKey: .textFontSize) ?? Self.defaultTextFontSize
        textBoxWidth = try container.decodeIfPresent(Double.self, forKey: .textBoxWidth) ?? Self.defaultTextBoxWidth
        mosaicBlockSize = try container.decodeIfPresent(Double.self, forKey: .mosaicBlockSize) ?? Self.defaultMosaicBlockSize
        selectedSticker = try container.decodeIfPresent(String.self, forKey: .selectedSticker) ?? Self.defaultSticker
        exportFormat = try container.decodeIfPresent(ImageFormat.self, forKey: .exportFormat) ?? .png
        jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.9
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(selectedToolRaw, forKey: .selectedToolRaw)
        try container.encode(toolRecencyRaw, forKey: .toolRecencyRaw)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(fillColor, forKey: .fillColor)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(textFontSize, forKey: .textFontSize)
        try container.encode(textBoxWidth, forKey: .textBoxWidth)
        try container.encode(mosaicBlockSize, forKey: .mosaicBlockSize)
        try container.encode(selectedSticker, forKey: .selectedSticker)
        try container.encode(exportFormat, forKey: .exportFormat)
        try container.encode(jpegQuality, forKey: .jpegQuality)
    }

    private mutating func migrateLegacyDefaultsIfNeeded(from schemaVersion: Int) {
        guard schemaVersion < 2 else { return }
        if Self.matchesLegacyDefaultStrokeColor(strokeColor) {
            strokeColor = Self.defaultStrokeColor
        }
    }

    private static func matchesLegacyDefaultStrokeColor(_ color: CodableColor) -> Bool {
        let legacyDefaults = [
            CodableColor(color: .cyan)
        ]
        return legacyDefaults.contains { color.approximatelyEquals($0) }
    }
}

extension CodableColor {
    func clamped() -> CodableColor {
        CodableColor(
            color: Color(
                red: min(max(red, 0), 1),
                green: min(max(green, 0), 1),
                blue: min(max(blue, 0), 1),
                opacity: min(max(alpha, 0), 1)
            )
        )
    }

    func approximatelyEquals(_ other: CodableColor, tolerance: Double = 0.015) -> Bool {
        abs(red - other.red) <= tolerance &&
        abs(green - other.green) <= tolerance &&
        abs(blue - other.blue) <= tolerance &&
        abs(alpha - other.alpha) <= tolerance
    }
}
