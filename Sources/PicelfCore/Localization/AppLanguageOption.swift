import Foundation

enum AppLanguageOption: String, CaseIterable, Identifiable {
    case system
    case en
    case zh

    var id: String { rawValue }

    static func normalized(raw: String?) -> AppLanguageOption {
        guard let raw else { return .system }
        let normalized = raw.lowercased()
        switch normalized {
        case "system":
            return .system
        case "zh", "zh-hans", "zh-hant":
            return .zh
        case "en":
            return .en
        default:
            if normalized.hasPrefix("zh") {
                return .zh
            }
            return .en
        }
    }
}
