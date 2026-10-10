import XCTest
import Foundation

final class SimulatorSafariScrollCollectorUITests: XCTestCase {

    private struct Configuration {
        let steps: Int
        let settleMS: UInt32
        let initialSettleMS: UInt32
        let profile: String

        static let defaults = Configuration(
            steps: 8,
            settleMS: 1100,
            initialSettleMS: 4500,
            profile: "generic"
        )
    }

    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let configURL = URL(fileURLWithPath: "/tmp/picelf-safari-collector-config.json")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_collectSafariScrollingSession() throws {
        let configuration = loadConfiguration()

        safari.activate()
        sleepMilliseconds(configuration.initialSettleMS)

        dismissStartupPrompts(maxPasses: 10)

        let scrollSurface = try waitForScrollSurface(timeout: 30)
        for step in 0..<configuration.steps {
            dismissInlinePromptsIfNeeded()
            performScroll(on: scrollSurface, profile: configuration.profile)
            print("[SafariCollector] step \(step + 1)/\(configuration.steps)")
            sleepMilliseconds(configuration.settleMS)
        }

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "safari-collector-final-frame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func loadConfiguration() -> Configuration {
        guard let data = try? Data(contentsOf: configURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .defaults
        }

        let steps = (raw["steps"] as? NSNumber)?.intValue ?? Configuration.defaults.steps
        let settleMS = (raw["settleMS"] as? NSNumber)?.uint32Value ?? Configuration.defaults.settleMS
        let initialSettleMS = (raw["initialSettleMS"] as? NSNumber)?.uint32Value ?? Configuration.defaults.initialSettleMS
        let profile = (raw["profile"] as? String) ?? Configuration.defaults.profile

        return Configuration(
            steps: max(1, steps),
            settleMS: max(100, settleMS),
            initialSettleMS: max(500, initialSettleMS),
            profile: profile
        )
    }

    private func waitForScrollSurface(timeout: TimeInterval) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let candidates = [
                safari.webViews.firstMatch,
                safari.scrollViews.firstMatch,
                safari.collectionViews.firstMatch,
                safari.tables.firstMatch,
                safari.windows.firstMatch
            ]
            if let surface = candidates.first(where: { $0.exists && $0.isHittable }) {
                return surface
            }

            dismissStartupPrompts(maxPasses: 2)
            sleepMilliseconds(300)
        } while Date() < deadline

        XCTFail("No scrollable Safari surface became available within \(timeout)s")
        throw NSError(domain: "SimulatorSafariScrollCollectorUITests", code: 2)
    }

    private func dismissStartupPrompts(maxPasses: Int) {
        for _ in 0..<maxPasses {
            if tapFirstMatching(in: safari, labels: [
                "Continue",
                "继续",
                "下一步",
                "Not Now",
                "现在不要",
                "以后",
                "稍后",
                "Keep Browsing",
                "继续浏览",
                "Accept",
                "Accept All",
                "Accept all",
                "同意",
                "我知道了",
                "知道了",
                "Stay Here",
                "Keep in Browser",
                "Continue in browser",
                "继续在浏览器中",
                "Open",
                "关闭",
                "Close",
                "Cancel",
                "取消"
            ], includeStaticTexts: true) {
                sleepMilliseconds(400)
                continue
            }

            if tapFirstMatching(in: springboard, labels: [
                "Allow",
                "允许",
                "Don’t Allow",
                "不允许",
                "OK",
                "好",
                "Not Now",
                "现在不要"
            ], includeStaticTexts: true) {
                sleepMilliseconds(400)
                continue
            }

            if dismissBilibiliPromptIfNeeded() {
                sleepMilliseconds(400)
                continue
            }

            break
        }
    }

    private func dismissInlinePromptsIfNeeded() {
        for _ in 0..<2 {
            if tapFirstMatching(in: safari, labels: [
                "Close",
                "关闭",
                "Not Now",
                "现在不要",
                "Keep Browsing",
                "继续浏览",
                "Stay Here",
                "Keep in Browser",
                "Continue in browser",
                "继续在浏览器中",
                "以后",
                "稍后",
                "取消"
            ], includeStaticTexts: false) {
                sleepMilliseconds(250)
                continue
            }

            if dismissBilibiliPromptIfNeeded() {
                sleepMilliseconds(250)
                continue
            }

            break
        }
    }

    private func tapFirstMatching(
        in app: XCUIApplication,
        labels: [String],
        includeStaticTexts: Bool
    ) -> Bool {
        for label in labels {
            let button = app.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                return true
            }

            if includeStaticTexts {
                let staticText = app.staticTexts[label]
                if staticText.exists && staticText.isHittable {
                    staticText.tap()
                    return true
                }
            }
        }
        return false
    }

    private func dismissBilibiliPromptIfNeeded() -> Bool {
        let genericCloseButtons = safari.buttons.matching(NSPredicate(
            format: "label ==[c] 'close' OR label == '关闭'"
        ))
        if genericCloseButtons.firstMatch.exists && genericCloseButtons.firstMatch.isHittable {
            genericCloseButtons.firstMatch.tap()
            return true
        }

        let maybeCancel = safari.buttons.matching(NSPredicate(
            format: "label == '取消' OR label == '稍后' OR label == '稍后再说'"
        ))
        if maybeCancel.firstMatch.exists && maybeCancel.firstMatch.isHittable {
            maybeCancel.firstMatch.tap()
            return true
        }

        return false
    }

    private func performScroll(on element: XCUIElement, profile: String) {
        let normalizedRange = dragRange(for: profile)
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedRange.start))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedRange.end))
        start.press(forDuration: 0.03, thenDragTo: end)
    }

    private func dragRange(for profile: String) -> (start: CGFloat, end: CGFloat) {
        switch profile {
        case "youtube-watch":
            return (0.82, 0.24)
        case "youtube-search":
            return (0.80, 0.26)
        case "bilibili-video":
            return (0.80, 0.28)
        case "bilibili-search":
            return (0.78, 0.30)
        default:
            return (0.80, 0.27)
        }
    }

    private func sleepMilliseconds(_ milliseconds: UInt32) {
        usleep(milliseconds * 1000)
    }
}
