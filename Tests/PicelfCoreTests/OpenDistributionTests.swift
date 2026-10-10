import XCTest
@testable import Picelf

final class OpenDistributionTests: XCTestCase {
    func testAppUsesIndependentIdentityAndStorage() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.picelf.open.app")
        XCTAssertEqual(AppDataPaths.appSupportDirectory.lastPathComponent, "com.picelf.open.app")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Picelf")
    }

    func testMicrophonePermissionsAcceptAnyDeveloperTeam() {
        for team in ["FIRSTTEAM1", "OTHERTEAM2"] {
            XCTAssertTrue(diagnostics(signed: true, team: team).isSuitableForPrivacyPermissionTesting)
        }
    }

    func testMicrophonePermissionsRejectUnsignedOrUnentitledBuilds() {
        XCTAssertFalse(diagnostics(signed: false, team: nil).isSuitableForPrivacyPermissionTesting)
        XCTAssertFalse(diagnostics(signed: true, team: nil).isSuitableForPrivacyPermissionTesting)
        XCTAssertFalse(diagnostics(signed: true, team: "FIRSTTEAM1", audio: false).isSuitableForPrivacyPermissionTesting)
        XCTAssertFalse(diagnostics(signed: true, team: "FIRSTTEAM1", sandbox: false).isSuitableForPrivacyPermissionTesting)
    }

    private func diagnostics(signed: Bool, team: String?, audio: Bool = true, sandbox: Bool = true) -> MicrophonePermissionRuntimeDiagnostics {
        MicrophonePermissionRuntimeDiagnostics(
            bundleIdentifier: "com.picelf.open.app", bundlePath: "/Applications/Picelf.app",
            isSigned: signed, teamIdentifier: team, hasAppSandbox: sandbox,
            hasAudioInputEntitlement: audio, hasLegacyMicrophoneEntitlement: false
        )
    }
}
