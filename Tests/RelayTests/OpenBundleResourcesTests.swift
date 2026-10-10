import XCTest

final class OpenBundleResourcesTests: XCTestCase {
    func testApplicationIncludesOpenSourceLicenseNotices() throws {
        let license = try XCTUnwrap(Bundle.main.url(forResource: "LICENSE", withExtension: nil))
        XCTAssertTrue(try String(contentsOf: license, encoding: .utf8).contains("MIT License"))
        for project in ["KeyboardShortcuts", "SnapshotTesting"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: project, withExtension: "txt", subdirectory: "licenses"))
            XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("Permission is hereby granted"))
        }
    }
}
