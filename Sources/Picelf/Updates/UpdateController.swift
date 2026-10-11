import AppKit
import Combine
import Sparkle

/// Snapshots are evaluated again immediately before an update terminates the app.
struct UpdateActivity: Equatable {
    var capture = false
    var recording = false
    var jobs = false
    var relay = false
    var editor = false
    var canvas = false

    var blockingReason: String? {
        if capture { return L10n.localized("请先结束当前捕获，再继续更新。", "Finish the current capture before continuing the update.") }
        if recording { return L10n.localized("请先停止录屏并等待保存完成，再继续更新。", "Stop recording and wait for it to save before continuing the update.") }
        if jobs { return L10n.localized("请等待工作台任务完成，再继续更新。", "Wait for Workbench tasks to finish before continuing the update.") }
        if relay { return L10n.localized("请先完成当前接力任务，再继续更新。", "Finish the current relay task before continuing the update.") }
        if editor || canvas { return L10n.localized("请先保存或导出编辑内容并关闭编辑器和画布，再继续更新。", "Save or export your work and close the editor and canvas before continuing the update.") }
        return nil
    }
}

struct UpdateRuntimeConfiguration {
    let enabled: Bool
    let testFeedURL: URL?

    static func resolve(isDebug: Bool, isTestHost: Bool, environment: [String: String]) -> Self {
        guard !isTestHost else { return Self(enabled: false, testFeedURL: nil) }
        if !isDebug { return Self(enabled: true, testFeedURL: nil) }
        guard environment["PICELF_RUN_LIVE_UPDATE_TESTS"] == "1",
              let value = environment["PICELF_UPDATE_TEST_FEED_URL"],
              let url = URL(string: value), url.scheme == "https", url.host != nil else {
            return Self(enabled: false, testFeedURL: nil)
        }
        return Self(enabled: true, testFeedURL: url)
    }

    static var current: Self {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let env = ProcessInfo.processInfo.environment
        return resolve(isDebug: isDebug,
                       isTestHost: env["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil,
                       environment: env)
    }
}

@MainActor
protocol UpdateBackend: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    var stateDidChange: (() -> Void)? { get set }
    func start() throws
    func checkForUpdates()
    func checkForUpdatesInBackground()
}

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()
    static let releasesURL = URL(string: "https://github.com/Poseima/picelf-open/releases/latest")!

    @Published private(set) var isEnabled = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var availableVersion: String?
    @Published private(set) var waitingToInstall = false
    @Published private(set) var installationMessage: String?
    @Published private(set) var lastError: String?

    var onInstallationDeferred: (() -> Void)?
    private var backend: UpdateBackend?
    private let configuration: UpdateRuntimeConfiguration
    private var activity: () -> UpdateActivity
    private var installHandler: (() -> Void)?
    private var updateRequestsTermination = false
    private var started = false
    private var userInitiated = false
    private var backgroundCheckDeferred = false
    private var deferredCheckTimer: Timer?

    var isDevelopmentBuild: Bool { !configuration.enabled }
    var localizedInstallationMessage: String {
        activity().blockingReason ?? L10n.localized("当前工作完成后，点击继续更新。", "Click Continue Update after finishing your work.")
    }

    var versionNumber: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
    var versionDescription: String { "\(versionNumber) (\(buildNumber))" }

    init(backend: UpdateBackend? = nil,
         configuration: UpdateRuntimeConfiguration = .current,
         activity: @escaping () -> UpdateActivity = { UpdateActivity() }) {
        self.backend = backend
        self.configuration = configuration
        self.activity = activity
        super.init()
    }

    func start(activity: (() -> UpdateActivity)? = nil) {
        if let activity { self.activity = activity }
        guard !started else { return }
        started = true
        guard configuration.enabled else { return }
        if backend == nil { backend = SparkleUpdateBackend(delegate: self) }
        backend?.stateDidChange = { [weak self] in self?.refreshState() }
        do {
            try backend?.start()
            isEnabled = true
            refreshState()
            if backend is SparkleUpdateBackend {
                let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.resumeDeferredBackgroundCheckIfIdle() }
                }
                timer.tolerance = 5
                RunLoop.main.add(timer, forMode: .common)
                deferredCheckTimer = timer
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isEnabled else { return }
        backend?.automaticallyChecksForUpdates = enabled
        refreshState()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        lastError = nil
        availableVersion = nil
        userInitiated = true
        backend?.checkForUpdates()
    }

    func openReleases() { NSWorkspace.shared.open(Self.releasesURL) }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.localized("检查更新…", "Check for Updates…"),
                              action: #selector(checkForUpdatesFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = canCheckForUpdates
        return item
    }

    @objc func checkForUpdatesFromMenu(_ sender: Any?) { checkForUpdates() }

    private func refreshState() {
        canCheckForUpdates = isEnabled && backend?.canCheckForUpdates == true && !waitingToInstall
        automaticallyChecksForUpdates = backend?.automaticallyChecksForUpdates ?? true
        lastUpdateCheckDate = backend?.lastUpdateCheckDate
    }

    /// Keep the resume block until Sparkle finishes; it can also retry after a
    /// termination request is cancelled because work started during download.
    @discardableResult
    func postponeInstallation(until handler: @escaping () -> Void) -> Bool {
        updateRequestsTermination = true
        installHandler = handler
        if let reason = activity().blockingReason {
            deferInstallation(reason: reason)
            return true
        }
        return false
    }

    func continueInstallation() {
        guard waitingToInstall else { return }
        if let reason = activity().blockingReason {
            installationMessage = reason
            return
        }
        waitingToInstall = false
        installationMessage = nil
        // Only this explicit click resumes installation; becoming idle never does.
        if let installHandler { installHandler() }
        else { backend?.checkForUpdates() }
    }

    func markInstallationRequested() { updateRequestsTermination = true }

    func allowBackgroundCheck() -> Bool {
        guard activity().blockingReason == nil else {
            backgroundCheckDeferred = true
            return false
        }
        backgroundCheckDeferred = false
        return true
    }

    func resumeDeferredBackgroundCheckIfIdle() {
        guard backgroundCheckDeferred, isEnabled, automaticallyChecksForUpdates,
              backend?.canCheckForUpdates == true, activity().blockingReason == nil else { return }
        backgroundCheckDeferred = false
        backend?.checkForUpdatesInBackground()
    }

    func shouldAllowTermination() -> Bool {
        guard updateRequestsTermination else { return true }
        guard let reason = activity().blockingReason else { return true }
        deferInstallation(reason: reason)
        return false
    }

    private func deferInstallation(reason: String) {
        waitingToInstall = true
        installationMessage = reason
        refreshState()
        onInstallationDeferred?()
    }

    func finishUpdateCheck(userInitiated: Bool, error: Error?) {
        if userInitiated, let error {
            let nsError = error as NSError
            if nsError.domain != SUSparkleErrorDomain ||
                ![Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)].contains(nsError.code) {
                let reason = nsError.localizedFailureReason ??
                    (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription
                lastError = [error.localizedDescription, reason]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        self.userInitiated = false
        updateRequestsTermination = false
        installHandler = nil
        waitingToInstall = false
        installationMessage = nil
        refreshState()
    }
}

extension UpdateController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }
}

extension UpdateController: SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { configuration.testFeedURL?.absoluteString }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        userInitiated = updateCheck == .updates
        if !userInitiated, !allowBackgroundCheck() {
            throw NSError(domain: "com.picelf.update", code: 1, userInfo: [NSLocalizedDescriptionKey:
                L10n.localized("当前工作完成后再检查更新。", "Updates will be checked after the current work is finished.")])
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        activity().blockingReason == nil
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { availableVersion = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { availableVersion = nil }
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallation(until: installHandler)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        markInstallationRequested()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        finishUpdateCheck(userInitiated: updateCheck == .updates || userInitiated, error: error)
    }
}

@MainActor
private final class SparkleUpdateBackend: UpdateBackend {
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []
    var stateDidChange: (() -> Void)?

    init(delegate: UpdateController) {
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: delegate, userDriverDelegate: delegate)
        for keyPath in [\SPUUpdater.canCheckForUpdates, \SPUUpdater.automaticallyChecksForUpdates] {
            observations.append(controller.updater.observe(keyPath, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.stateDidChange?() }
            })
        }
        observations.append(controller.updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.stateDidChange?() }
        })
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
    func start() throws { try controller.updater.start() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
    func checkForUpdatesInBackground() { controller.updater.checkForUpdatesInBackground() }
}
