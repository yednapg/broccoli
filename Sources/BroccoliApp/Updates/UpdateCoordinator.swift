@preconcurrency import AppKit
import Foundation
import Observation
@preconcurrency import Sparkle

@MainActor
@Observable
final class UpdateCoordinator: NSObject, SPUUpdaterDelegate {
    private(set) var phase: UpdatePhase = .idle
    private(set) var candidate: UpdateCandidate?
    private(set) var statusMessage = "Ready to check"
    private(set) var errorMessage: String?
    private(set) var releaseNotes: String?
    private(set) var downloadProgress: Double?
    private(set) var hasQuietBadge = false
    private(set) var isConfigured = false
    private var presentsDeferredUpdateOnActivation = false

    var channel: UpdateChannel {
        didSet {
            UpdateSettingsPersistence.save(channel: channel, to: defaults)
            updater?.updateCheckInterval = channel.checkInterval
            updater?.resetUpdateCycleAfterShortDelay()
        }
    }

    var automaticallyDownloadsImportantUpdates: Bool {
        didSet {
            UpdateSettingsPersistence.saveAutomaticallyDownloadsImportant(
                automaticallyDownloadsImportantUpdates,
                to: defaults
            )
        }
    }

    private let defaults: UserDefaults
    private let hostBundle: Bundle
    private let applicationBundle: Bundle
    private let userDriver: BroccoliUpdateUserDriver
    private var updater: SPUUpdater!
    private var stateMachine = UpdateStateMachine()

    init(
        hostBundle: Bundle = .main,
        applicationBundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) {
        self.hostBundle = hostBundle
        self.applicationBundle = applicationBundle
        self.defaults = defaults
        channel = UpdateSettingsPersistence.channel(from: defaults)
        automaticallyDownloadsImportantUpdates = UpdateSettingsPersistence
            .automaticallyDownloadsImportant(from: defaults)
        userDriver = BroccoliUpdateUserDriver()
        super.init()
        userDriver.coordinator = self
        updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: applicationBundle,
            userDriver: userDriver,
            delegate: self
        )
    }

    var currentVersion: String {
        hostBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    var currentBuild: String {
        hostBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
    }

    var lastCheckDate: Date? { updater?.lastUpdateCheckDate }
    var canCheckForUpdates: Bool { isConfigured && (updater?.canCheckForUpdates ?? false) }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    func start() {
        guard !isConfigured else { return }
        guard configurationIsSafe else {
            statusMessage = "Updates unavailable in this development build"
            return
        }
        updater.updateCheckInterval = channel.checkInterval
        updater.automaticallyDownloadsUpdates = false
        do {
            try updater.start()
            isConfigured = true
            statusMessage = "Ready to check"
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            statusMessage = "Updater configuration failed"
        }
    }

    func checkForUpdates() {
        guard isConfigured else {
            phase = .failed
            errorMessage = "This build does not contain a configured signed update feed."
            statusMessage = "Updates unavailable"
            userDriver.presentWindow()
            return
        }
        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        } else {
            userDriver.showUpdateInFocus()
        }
    }

    func presentAvailableUpdate() {
        hasQuietBadge = false
        userDriver.presentWindow()
    }

    func applicationDidBecomeActive() {
        guard presentsDeferredUpdateOnActivation else { return }
        presentsDeferredUpdateOnActivation = false
        userDriver.presentWindow()
    }

    func openInformationPage() {
        guard let url = candidate?.informationURL else { return }
        NSWorkspace.shared.open(url)
    }

    func allowAutomaticChecks(_ allowed: Bool) { userDriver.answerPermission(allowed: allowed) }
    func downloadAndInstall() { userDriver.chooseInstall() }
    func installAndRelaunch() { userDriver.chooseInstall() }
    func chooseLater() { userDriver.chooseLater() }
    func skipVersion() { userDriver.chooseSkip() }
    func cancelCurrentOperation() { userDriver.cancelCurrentOperation() }
    func retryTermination() { userDriver.retryTermination() }
    func acknowledge() { userDriver.acknowledgeAndClose() }
    func retryUpdate() { userDriver.retryUpdate() }

    func update(
        phase: UpdatePhase,
        message: String,
        error: String? = nil,
        progress: Double? = nil
    ) {
        if !stateMachine.transition(to: phase) {
            stateMachine = UpdateStateMachine()
            _ = stateMachine.transition(to: phase)
        }
        self.phase = stateMachine.phase
        statusMessage = message
        errorMessage = error
        downloadProgress = progress
        writeRehearsalStatusIfRequested()
    }

    func setCandidate(_ candidate: UpdateCandidate, quiet: Bool) {
        self.candidate = candidate
        _ = stateMachine.transition(to: .available)
        phase = stateMachine.phase
        statusMessage = "Version \(candidate.version) is available"
        errorMessage = nil
        hasQuietBadge = quiet
    }

    func setReleaseNotes(_ notes: String?) {
        releaseNotes = notes
    }

    func deferUpdateWindowUntilActivation() {
        presentsDeferredUpdateOnActivation = true
    }

    func shouldAutomaticallyDownload(policy: UpdateActionPolicy) -> Bool {
        automaticallyDownloadsImportantUpdates
            && policy.allowsAutomaticDownload
            && applicationCanBeReplacedWithoutUnexpectedAuthorization
    }

    private var configurationIsSafe: Bool {
        guard let feed = hostBundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed) != nil,
              let key = hostBundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty,
              key != "CONFIGURE_AT_BUILD_TIME" else { return false }
        return true
    }

    private var applicationCanBeReplacedWithoutUnexpectedAuthorization: Bool {
        let appURL = applicationBundle.bundleURL
        let parentURL = appURL.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: appURL.path)
            && FileManager.default.isWritableFile(atPath: parentURL.path)
    }

    private func writeRehearsalStatusIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let markerIndex = arguments.firstIndex(of: "--update-rehearsal-status-file"),
              arguments.indices.contains(markerIndex + 1) else { return }
        let escapedError = (errorMessage ?? "").replacingOccurrences(of: "\n", with: " ")
        let value = "\(phase.rawValue)|\(statusMessage)|\(escapedError)\n"
        try? value.write(
            toFile: arguments[markerIndex + 1],
            atomically: true,
            encoding: .utf8
        )
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { channel.allowedSparkleChannels }
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated {
            hostBundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        }
    }
}
