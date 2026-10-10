import XCTest
@testable import Picelf

final class IconTipHUDGeometryResolverTests: XCTestCase {
    func test_prefersAboveWhenSpaceIsAvailable() {
        let origin = IconTipHUDGeometryResolver.resolve(
            mouseLocation: CGPoint(x: 400, y: 300),
            tipSize: CGSize(width: 120, height: 30),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 700)
        )

        XCTAssertEqual(origin.x, 412, accuracy: 0.001)
        XCTAssertEqual(origin.y, 312, accuracy: 0.001)
    }

    func test_flipsBelowWhenTopSpaceInsufficient() {
        let origin = IconTipHUDGeometryResolver.resolve(
            mouseLocation: CGPoint(x: 400, y: 690),
            tipSize: CGSize(width: 120, height: 30),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 700)
        )

        XCTAssertEqual(origin.y, 648, accuracy: 0.001)
    }

    func test_flipsLeftWhenRightSpaceInsufficient() {
        let origin = IconTipHUDGeometryResolver.resolve(
            mouseLocation: CGPoint(x: 990, y: 300),
            tipSize: CGSize(width: 120, height: 30),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 700)
        )

        XCTAssertEqual(origin.x, 858, accuracy: 0.001)
    }

    func test_clampsInsideVisibleFrame() {
        let frame = CGRect(x: 100, y: 50, width: 300, height: 200)
        let origin = IconTipHUDGeometryResolver.resolve(
            mouseLocation: CGPoint(x: 105, y: 245),
            tipSize: CGSize(width: 280, height: 120),
            screenVisibleFrame: frame
        )

        XCTAssertGreaterThanOrEqual(origin.x, frame.minX + 4)
        XCTAssertLessThanOrEqual(origin.x + 280, frame.maxX - 4)
        XCTAssertGreaterThanOrEqual(origin.y, frame.minY + 4)
        XCTAssertLessThanOrEqual(origin.y + 120, frame.maxY - 4)
    }

    func test_tipLargerThanVisibleFrameCentersWithinFrame() {
        let frame = CGRect(x: 0, y: 0, width: 120, height: 70)
        let origin = IconTipHUDGeometryResolver.resolve(
            mouseLocation: CGPoint(x: 60, y: 35),
            tipSize: CGSize(width: 240, height: 140),
            screenVisibleFrame: frame
        )

        XCTAssertEqual(origin.x, frame.midX - 120, accuracy: 0.001)
        XCTAssertEqual(origin.y, frame.midY - 70, accuracy: 0.001)
    }
}

final class IconTipHUDLevelResolverTests: XCTestCase {
    func test_fallbackLevelWhenOwnerWindowMissing() {
        let resolved = IconTipHUDLevelResolver.resolveRawLevel(ownerWindowRawLevel: nil)
        XCTAssertEqual(resolved, IconTipHUDLevelResolver.fallbackLevel.rawValue)
    }

    func test_levelIsRaisedAboveOwnerWindow() {
        let resolved = IconTipHUDLevelResolver.resolveRawLevel(
            ownerWindowRawLevel: NSWindow.Level.screenSaver.rawValue + 2
        )
        XCTAssertEqual(resolved, NSWindow.Level.screenSaver.rawValue + 3)
    }

    func test_lowOwnerLevelStillUsesFallback() {
        let resolved = IconTipHUDLevelResolver.resolveRawLevel(ownerWindowRawLevel: NSWindow.Level.normal.rawValue)
        XCTAssertEqual(resolved, IconTipHUDLevelResolver.fallbackLevel.rawValue)
    }
}
