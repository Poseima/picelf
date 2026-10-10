import XCTest
@testable import Picelf

final class WindowEnumeratorTests: XCTestCase {
    func test_windowInfoModel() {
        let info = WindowInfo(id: 123, title: "Test", appName: "Safari", appBundleID: "com.apple.Safari",
                              frame: CGRect(x: 0, y: 0, width: 1200, height: 800), isOnScreen: true)
        XCTAssertEqual(info.id, 123)
        XCTAssertEqual(info.appName, "Safari")
    }

    @MainActor
    func test_windowSnapping_containsPoint() {
        let windows = [
            WindowInfo(id: 1, title: "A", appName: "App1", appBundleID: "com.a",
                       frame: CGRect(x: 100, y: 100, width: 800, height: 600), isOnScreen: true),
            WindowInfo(id: 2, title: "B", appName: "App2", appBundleID: "com.b",
                       frame: CGRect(x: 500, y: 200, width: 600, height: 400), isOnScreen: true),
        ]
        let snapped = WindowEnumerator.findClosestWindow(to: CGPoint(x: 150, y: 150), in: windows)
        XCTAssertEqual(snapped?.id, 1)
    }

    @MainActor
    func test_windowSnapping_closestCenter() {
        let windows = [
            WindowInfo(id: 1, title: "A", appName: "App1", appBundleID: "com.a",
                       frame: CGRect(x: 100, y: 100, width: 200, height: 200), isOnScreen: true),
            WindowInfo(id: 2, title: "B", appName: "App2", appBundleID: "com.b",
                       frame: CGRect(x: 500, y: 500, width: 200, height: 200), isOnScreen: true),
        ]
        let snapped = WindowEnumerator.findClosestWindow(to: CGPoint(x: 550, y: 550), in: windows)
        XCTAssertEqual(snapped?.id, 2)
    }

    @MainActor
    func test_emptyWindowList() {
        let snapped = WindowEnumerator.findClosestWindow(to: CGPoint(x: 100, y: 100), in: [])
        XCTAssertNil(snapped)
    }

    @MainActor
    func test_findTopmostWindow_prefersFrontMostID() {
        let windows = [
            WindowInfo(
                id: 1,
                title: "Back",
                appName: "App1",
                appBundleID: "com.a",
                frame: CGRect(x: 100, y: 100, width: 500, height: 400),
                isOnScreen: true
            ),
            WindowInfo(
                id: 2,
                title: "Front",
                appName: "App2",
                appBundleID: "com.b",
                frame: CGRect(x: 120, y: 120, width: 500, height: 400),
                isOnScreen: true
            )
        ]

        let point = CGPoint(x: 200, y: 200)
        let front = WindowEnumerator.findTopmostWindow(
            containing: point,
            in: windows,
            orderedFrontToBackBy: [2, 1]
        )
        XCTAssertEqual(front?.id, 2)
    }

    @MainActor
    func test_findTopmostWindow_returnsNilWhenPointOutside() {
        let windows = [
            WindowInfo(
                id: 1,
                title: "A",
                appName: "App1",
                appBundleID: "com.a",
                frame: CGRect(x: 100, y: 100, width: 200, height: 200),
                isOnScreen: true
            )
        ]

        let result = WindowEnumerator.findTopmostWindow(
            containing: CGPoint(x: 10, y: 10),
            in: windows,
            orderedFrontToBackBy: [1]
        )
        XCTAssertNil(result)
    }
}
