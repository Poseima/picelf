import XCTest
import AppKit
import Sparkle
@testable import Picelf

@MainActor
final class UpdateControllerTests: XCTestCase {
    private final class Backend: UpdateBackend {
        var canCheckForUpdates = true
        var lastUpdateCheckDate: Date? = Date(timeIntervalSince1970: 123)
        var stateDidChange: (() -> Void)?
        var checks = 0
        var backgroundChecks = 0
        var starts = 0
        var startError: Error?
        let defaults: UserDefaults
        init(defaults: UserDefaults) { self.defaults = defaults }
        var automaticallyChecksForUpdates: Bool {
            get { defaults.object(forKey: "automatic") as? Bool ?? true }
            set { defaults.set(newValue, forKey: "automatic") }
        }
        func start() throws { starts += 1; if let startError { throw startError } }
        func checkForUpdates() { checks += 1 }
        func checkForUpdatesInBackground() { backgroundChecks += 1 }
    }

    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "com.picelf.update-tests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func controller(_ backend: Backend, activity: @escaping () -> UpdateActivity = { UpdateActivity() }) -> UpdateController {
        let controller = UpdateController(backend: backend,
                                          configuration: .init(enabled: true, testFeedURL: nil), activity: activity)
        controller.start()
        return controller
    }

    func test_debugAndTestHostsNeverStartWithoutExplicitLiveOptIn() {
        let live = ["PICELF_RUN_LIVE_UPDATE_TESTS": "1", "PICELF_UPDATE_TEST_FEED_URL": "https://example.com/test.xml"]
        XCTAssertFalse(UpdateRuntimeConfiguration.resolve(isDebug: true, isTestHost: false, environment: [:]).enabled)
        XCTAssertFalse(UpdateRuntimeConfiguration.resolve(isDebug: true, isTestHost: false,
            environment: ["PICELF_UPDATE_TEST_FEED_URL": "https://example.com/test.xml"]).enabled)
        for url in ["http://example.com/test.xml", "file:///tmp/test.xml", "not-a-url"] {
            var env = live; env["PICELF_UPDATE_TEST_FEED_URL"] = url
            XCTAssertFalse(UpdateRuntimeConfiguration.resolve(isDebug: true, isTestHost: false, environment: env).enabled)
        }
        let allowed = UpdateRuntimeConfiguration.resolve(isDebug: true, isTestHost: false, environment: live)
        XCTAssertTrue(allowed.enabled)
        XCTAssertEqual(allowed.testFeedURL?.host, "example.com")
        XCTAssertFalse(UpdateRuntimeConfiguration.resolve(isDebug: false, isTestHost: true, environment: live).enabled)
        let release = UpdateRuntimeConfiguration.resolve(isDebug: false, isTestHost: false, environment: live)
        XCTAssertTrue(release.enabled)
        XCTAssertNil(release.testFeedURL)
        let backend = Backend(defaults: defaults)
        let disabled = UpdateController(backend: backend, configuration: .init(enabled: false, testFeedURL: nil))
        disabled.start(); disabled.checkForUpdates()
        XCTAssertEqual(backend.starts, 0)
        XCTAssertEqual(backend.checks, 0)
        XCTAssertFalse(disabled.canCheckForUpdates)
    }

    func test_settingsAndMenuActionsShareOneBackendAndRespectAvailability() {
        let backend = Backend(defaults: defaults)
        let controller = controller(backend)
        controller.start()
        XCTAssertEqual(backend.starts, 1)
        let item = controller.makeMenuItem()
        XCTAssertTrue(item.target === controller)
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.checkForUpdates() // The settings and SwiftUI app menu action.
        controller.checkForUpdatesFromMenu(item) // Status menu selector.
        XCTAssertEqual(backend.checks, 2)
        XCTAssertEqual(controller.lastUpdateCheckDate, backend.lastUpdateCheckDate)
        backend.canCheckForUpdates = false; backend.stateDidChange?()
        controller.checkForUpdates()
        XCTAssertEqual(backend.checks, 2)
        XCTAssertFalse(controller.validateMenuItem(item))
    }

    func test_automaticCheckChoiceSurvivesControllerRecreation() {
        let first = controller(Backend(defaults: defaults))
        XCTAssertTrue(first.automaticallyChecksForUpdates)
        first.setAutomaticallyChecksForUpdates(false)
        let second = controller(Backend(defaults: defaults))
        XCTAssertFalse(second.automaticallyChecksForUpdates)
    }

    func test_eachBusyStateDefersInstallationAndDoesNotAutoResume() {
        for busy in [UpdateActivity(capture: true), UpdateActivity(recording: true), UpdateActivity(jobs: true),
                     UpdateActivity(relay: true), UpdateActivity(editor: true), UpdateActivity(canvas: true)] {
            var snapshot = busy
            let controller = controller(Backend(defaults: defaults), activity: { snapshot })
            var installs = 0
            XCTAssertTrue(controller.shouldAllowTermination()) // Ordinary quit stays unchanged.
            XCTAssertTrue(controller.postponeInstallation { installs += 1 })
            XCTAssertTrue(controller.waitingToInstall)
            XCTAssertFalse(controller.canCheckForUpdates)
            XCTAssertFalse(controller.shouldAllowTermination())
            controller.continueInstallation()
            XCTAssertEqual(installs, 0)
            snapshot = UpdateActivity()
            XCTAssertEqual(installs, 0)
            controller.continueInstallation()
            XCTAssertEqual(installs, 1)
            controller.continueInstallation()
            XCTAssertEqual(installs, 1)
        }
    }

    func test_newWorkBeforeTerminationIsCheckedAgainAndResumeRemainsAvailable() {
        var snapshot = UpdateActivity()
        let controller = controller(Backend(defaults: defaults), activity: { snapshot })
        var retries = 0
        XCTAssertFalse(controller.postponeInstallation { retries += 1 })
        snapshot.recording = true
        XCTAssertFalse(controller.shouldAllowTermination())
        XCTAssertEqual(retries, 0)
        snapshot.recording = false
        controller.continueInstallation()
        XCTAssertEqual(retries, 1)
        XCTAssertTrue(controller.shouldAllowTermination())
    }

    func test_resumedSparkleInstallWithoutRelaunchCallbackCanBeRetried() {
        var snapshot = UpdateActivity(editor: true)
        let backend = Backend(defaults: defaults)
        let controller = controller(backend, activity: { snapshot })
        controller.markInstallationRequested()
        XCTAssertFalse(controller.shouldAllowTermination())
        snapshot.editor = false
        controller.continueInstallation()
        XCTAssertEqual(backend.checks, 1)
    }

    func test_busyBackgroundCheckRetriesOnlyWhenIdleAndAutomaticChecksEnabled() {
        var snapshot = UpdateActivity(jobs: true)
        let backend = Backend(defaults: defaults)
        let controller = controller(backend, activity: { snapshot })
        XCTAssertFalse(controller.allowBackgroundCheck())
        controller.resumeDeferredBackgroundCheckIfIdle()
        XCTAssertEqual(backend.backgroundChecks, 0)
        snapshot.jobs = false
        controller.setAutomaticallyChecksForUpdates(false)
        controller.resumeDeferredBackgroundCheckIfIdle()
        XCTAssertEqual(backend.backgroundChecks, 0)
        controller.setAutomaticallyChecksForUpdates(true)
        controller.resumeDeferredBackgroundCheckIfIdle()
        controller.resumeDeferredBackgroundCheckIfIdle()
        XCTAssertEqual(backend.backgroundChecks, 1)
    }

    func test_onlyManualFailuresAreShownAndFinishClearsInstallationGate() {
        let controller = controller(Backend(defaults: defaults))
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        controller.finishUpdateCheck(userInitiated: false, error: offline)
        XCTAssertNil(controller.lastError)
        for code in [SUError.noUpdateError, SUError.installationCanceledError] {
            controller.finishUpdateCheck(userInitiated: true,
                error: NSError(domain: SUSparkleErrorDomain, code: Int(code.rawValue)))
            XCTAssertNil(controller.lastError)
        }
        controller.finishUpdateCheck(userInitiated: true, error: offline)
        XCTAssertNotNil(controller.lastError)
        let feedFailure = NSError(domain: SUSparkleErrorDomain, code: 1002,
                                  userInfo: [NSLocalizedDescriptionKey: "Update failed",
                                             NSLocalizedFailureReasonErrorKey: "The update feed could not be found (404)."])
        controller.finishUpdateCheck(userInitiated: true, error: feedFailure)
        XCTAssertTrue(controller.lastError?.contains("404") == true)
        controller.checkForUpdates()
        XCTAssertNil(controller.lastError)
        controller.markInstallationRequested()
        controller.finishUpdateCheck(userInitiated: true, error: nil)
        XCTAssertFalse(controller.waitingToInstall)
        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertTrue(controller.shouldAllowTermination())
    }

    func test_startupFailureKeepsUpdaterDisabledAndManualDownloadAvailable() {
        let backend = Backend(defaults: defaults)
        backend.startError = NSError(domain: "test", code: 1)
        let controller = controller(backend)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertNotNil(controller.lastError)
        XCTAssertEqual(UpdateController.releasesURL.host, "github.com")
    }
}
