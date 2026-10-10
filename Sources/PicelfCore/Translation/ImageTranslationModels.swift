import Foundation
import CoreGraphics

enum TranslationOverlayMode: String, Codable, CaseIterable, Identifiable {
    case off
    case hover
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return L10n.translationOverlayOff
        case .hover:
            return L10n.translationOverlayHover
        case .replace:
            return L10n.translationOverlayReplace
        }
    }
}

enum TranslationTargetPreference: String, Codable, CaseIterable, Identifiable {
    case followAppLanguage
    case english
    case chineseSimplified
    case lastUsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followAppLanguage:
            return L10n.translationTargetFollowApp
        case .english:
            return TranslationLanguageOption.english.localizedName
        case .chineseSimplified:
            return TranslationLanguageOption.chineseSimplified.localizedName
        case .lastUsed:
            return L10n.translationTargetLastUsed
        }
    }
}

enum TranslationExportFormatPreference: String, Codable, CaseIterable, Identifiable {
    case matchSource
    case png

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matchSource:
            return L10n.translationExportMatchSource
        case .png:
            return "PNG"
        }
    }
}

enum TranslationLanguageOption: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"

    var id: String { rawValue }

    static func normalized(raw: String?) -> TranslationLanguageOption {
        guard let raw else { return .english }
        if let exact = TranslationLanguageOption(rawValue: raw) {
            return exact
        }
        let lowercased = raw.lowercased()
        if lowercased.hasPrefix("zh-hans") || lowercased == "zh-cn" || lowercased == "zh-sg" {
            return .chineseSimplified
        }
        if lowercased.hasPrefix("zh-hant") || lowercased == "zh-tw" || lowercased == "zh-hk" {
            return .chineseTraditional
        }
        let prefix = lowercased.split(separator: "-").first.map(String.init)
        return TranslationLanguageOption.allCases.first { option in
            option.rawValue.lowercased().split(separator: "-").first.map(String.init) == prefix
        } ?? .english
    }

    static func defaultForAppLanguage(_ appLanguage: AppLanguageOption) -> TranslationLanguageOption {
        switch appLanguage {
        case .zh:
            return .chineseSimplified
        case .en, .system:
            if L10n.zh {
                return .chineseSimplified
            }
            return .english
        }
    }

    static func fallbackOpposite(for source: TranslationLanguageOption) -> TranslationLanguageOption {
        switch source {
        case .english:
            return .chineseSimplified
        case .chineseSimplified, .chineseTraditional:
            return .english
        default:
            return .english
        }
    }

    var localizedName: String {
        switch self {
        case .english:
            return L10n.zh ? "英语" : "English"
        case .chineseSimplified:
            return L10n.zh ? "简体中文" : "Chinese (Simplified)"
        case .chineseTraditional:
            return L10n.zh ? "繁体中文" : "Chinese (Traditional)"
        case .japanese:
            return L10n.zh ? "日语" : "Japanese"
        case .korean:
            return L10n.zh ? "韩语" : "Korean"
        case .french:
            return L10n.zh ? "法语" : "French"
        case .german:
            return L10n.zh ? "德语" : "German"
        case .spanish:
            return L10n.zh ? "西班牙语" : "Spanish"
        case .italian:
            return L10n.zh ? "意大利语" : "Italian"
        case .portuguese:
            return L10n.zh ? "葡萄牙语" : "Portuguese"
        }
    }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
}

struct NormalizedTextRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func rect(in canvasSize: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(x) * canvasSize.width,
            y: CGFloat(y) * canvasSize.height,
            width: CGFloat(width) * canvasSize.width,
            height: CGFloat(height) * canvasSize.height
        )
    }
}

struct RecognizedTextBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var normalizedBounds: NormalizedTextRect
    var dominantLanguageCode: String?

    init(
        id: UUID = UUID(),
        text: String,
        normalizedBounds: NormalizedTextRect,
        dominantLanguageCode: String? = nil
    ) {
        self.id = id
        self.text = text
        self.normalizedBounds = normalizedBounds
        self.dominantLanguageCode = dominantLanguageCode
    }

    var bounds: CGRect { normalizedBounds.cgRect }
}

struct RecognizedTextDocument: Codable, Equatable {
    var blocks: [RecognizedTextBlock]
    var dominantLanguageCode: String?

    var fullText: String {
        blocks
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var hasContent: Bool {
        !fullText.isEmpty
    }
}

struct TranslationSegment: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceText: String
    var translatedText: String
    var normalizedBounds: NormalizedTextRect
    var sourceLanguageCode: String?
    var targetLanguageCode: String

    init(
        id: UUID,
        sourceText: String,
        translatedText: String,
        normalizedBounds: NormalizedTextRect,
        sourceLanguageCode: String?,
        targetLanguageCode: String
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.normalizedBounds = normalizedBounds
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }

    var bounds: CGRect { normalizedBounds.cgRect }

    func rect(in canvasSize: CGSize) -> CGRect {
        normalizedBounds.rect(in: canvasSize)
    }
}

enum TranslationRuntimeState: Equatable {
    case idle
    case extractingText
    case translating
    case ready
    case unsupported
    case failed
}

struct TranslationRequestToken: Equatable {
    let id: UUID
    let sourceLanguageCode: String?
    let targetLanguageCode: String
}

struct TranslationCachePayload: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var imageHash: String
    var targetLanguageCode: String
    var ocrDocument: RecognizedTextDocument
    var segments: [TranslationSegment]
    var cachedAt: Date

    init(
        version: Int = currentVersion,
        imageHash: String,
        targetLanguageCode: String,
        ocrDocument: RecognizedTextDocument,
        segments: [TranslationSegment],
        cachedAt: Date = Date()
    ) {
        self.version = version
        self.imageHash = imageHash
        self.targetLanguageCode = targetLanguageCode
        self.ocrDocument = ocrDocument
        self.segments = segments
        self.cachedAt = cachedAt
    }
}
