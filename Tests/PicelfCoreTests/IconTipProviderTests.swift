import XCTest
@testable import Picelf

final class IconTipProviderTests: XCTestCase {
    func test_allIconTipKeysProduceNonEmptyTextAndAccessibility() {
        for key in IconTipKey.allCases {
            let text = IconTipProvider.text(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
            let label = IconTipProvider.accessibilityLabel(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = IconTipProvider.accessibilityHint(for: key).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(text.isEmpty, "Missing tip text for \(key.rawValue)")
            XCTAssertFalse(label.isEmpty, "Missing accessibility label for \(key.rawValue)")
            XCTAssertFalse(hint.isEmpty, "Missing accessibility hint for \(key.rawValue)")
        }
    }

    func test_nonChineseLanguageFallsBackToEnglishTips() {
        let original = AppPreferences.shared.appLanguage
        defer { AppPreferences.shared.appLanguage = original }

        AppPreferences.shared.appLanguage = "fr"
        let undo = IconTipProvider.text(for: .undo)
        XCTAssertTrue(undo.contains("Undo"), "Expected English fallback, got: \(undo)")
    }
}
