@preconcurrency import AppKit
import Foundation
@preconcurrency import Sparkle

@MainActor
final class BroccoliUpdateUserDriver: NSObject, SPUUserDriver {
    weak var coordinator: UpdateCoordinator?

    private var windowController: BroccoliUpdateWindowController?
    private var permissionReply: ((SUUpdatePermissionResponse) -> Void)?
    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var acknowledgement: (() -> Void)?
    private var cancellation: (() -> Void)?
    private var retryTerminationHandler: (() -> Void)?
    private var expectedDownloadLength: UInt64 = 0
    private var downloadedLength: UInt64 = 0
    private var isAutomatedRehearsal: Bool {
        ProcessInfo.processInfo.arguments.contains("--update-rehearsal-auto-accept")
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        permissionReply = reply
        if isAutomatedRehearsal {
            answerPermission(allowed: true)
            return
        }
        coordinator?.update(
            phase: .permissionRequest,
            message: "Choose how Broccoli checks for updates"
        )
        presentWindow()
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        coordinator?.update(phase: .checking, message: "Checking for updates…")
        if !isAutomatedRehearsal { presentWindow() }
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        cancellation = nil
        updateReply = reply
        let properties = appcastItem.propertiesDictionary
        let parsedPriority = UpdatePriorityParser.parse(
            properties: properties,
            isCriticalUpdate: appcastItem.isCriticalUpdate
        )

        if parsedPriority == .critical && !appcastItem.isCriticalUpdate {
            updateReply = nil
            reply(.dismiss)
            coordinator?.update(
                phase: .failed,
                message: "The update feed is invalid",
                error: "A critical Broccoli update must include Sparkle’s critical-update marker."
            )
            presentWindow()
            return
        }

        let priority = appcastItem.isCriticalUpdate ? .critical : parsedPriority
        let candidate = UpdateCandidate(
            version: appcastItem.displayVersionString,
            build: appcastItem.versionString,
            title: appcastItem.title ?? "Broccoli \(appcastItem.displayVersionString)",
            priority: priority,
            isCritical: appcastItem.isCriticalUpdate,
            isInformationalOnly: appcastItem.isInformationOnlyUpdate,
            informationURL: appcastItem.infoURL
        )
        if let embeddedNotes = appcastItem.itemDescription, !embeddedNotes.isEmpty {
            coordinator?.setReleaseNotes(embeddedNotes)
        }

        let policy = UpdateActionPolicy(
            priority: priority,
            isCritical: appcastItem.isCriticalUpdate,
            isInformationalOnly: appcastItem.isInformationOnlyUpdate
        )
        let decision = UpdatePresentationPolicy.decision(
            for: policy,
            userInitiated: state.userInitiated,
            automaticDownloadConsent: coordinator?.automaticallyDownloadsImportantUpdates ?? false,
            destinationWritable: coordinator?.shouldAutomaticallyDownload(policy: policy) == true
        )

        if (decision.automaticallyDownload || isAutomatedRehearsal),
           state.stage == .notDownloaded,
           !appcastItem.isInformationOnlyUpdate {
            coordinator?.setCandidate(candidate, quiet: false)
            updateReply = nil
            reply(.install)
            return
        }

        coordinator?.setCandidate(candidate, quiet: decision.showQuietBadge)
        if decision.showWindow {
            if policy == .important && !state.userInitiated && !NSApp.isActive {
                coordinator?.deferUpdateWindowUntilActivation()
            } else {
                presentWindow()
            }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        let encoding = downloadData.textEncodingName
            .flatMap { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
            .map { CFStringConvertEncodingToNSStringEncoding($0) }
            .map(String.Encoding.init(rawValue:)) ?? .utf8
        coordinator?.setReleaseNotes(String(data: downloadData.data, encoding: encoding))
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        coordinator?.setReleaseNotes("Release notes could not be loaded: \(error.localizedDescription)")
    }

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        self.acknowledgement = acknowledgement
        coordinator?.update(
            phase: .current,
            message: "Broccoli is up to date",
            error: (error as NSError).localizedRecoverySuggestion
        )
        presentWindow()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        self.acknowledgement = acknowledgement
        coordinator?.update(
            phase: .failed,
            message: "The update could not be completed",
            error: actionableMessage(for: error)
        )
        presentWindow()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        expectedDownloadLength = 0
        downloadedLength = 0
        coordinator?.update(phase: .downloading, message: "Downloading update…", progress: 0)
        presentWindow()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadLength = expectedContentLength
        publishDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedLength += length
        publishDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        coordinator?.update(phase: .extracting, message: "Preparing update…", progress: nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        coordinator?.update(
            phase: .extracting,
            message: "Preparing update…",
            progress: max(0, min(progress, 1))
        )
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if isAutomatedRehearsal {
            reply(.install)
            return
        }
        updateReply = reply
        coordinator?.update(phase: .ready, message: "Ready to install and relaunch")
        presentWindow()
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        retryTerminationHandler = applicationTerminated ? nil : retryTerminatingApplication
        coordinator?.update(
            phase: .installing,
            message: applicationTerminated
                ? "Installing update…"
                : "Waiting for Broccoli to quit…"
        )
        presentWindow()
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        self.acknowledgement = acknowledgement
        coordinator?.update(
            phase: .completed,
            message: relaunched ? "Update installed and Broccoli relaunched" : "Update installed"
        )
        presentWindow()
    }

    func dismissUpdateInstallation() {
        clearHandlers()
        coordinator?.update(phase: .idle, message: "Ready to check")
        windowController?.closeWithoutCallback()
    }

    func showUpdateInFocus() { presentWindow() }

    func presentWindow() {
        guard let coordinator else { return }
        if windowController == nil {
            windowController = BroccoliUpdateWindowController(coordinator: coordinator) { [weak self] in
                self?.userClosedWindow()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func answerPermission(allowed: Bool) {
        guard let reply = permissionReply else { return }
        permissionReply = nil
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: allowed,
            // Broccoli applies its narrower important/critical policy itself. Leaving
            // Sparkle's blanket automatic-download switch off prevents routine downloads.
            automaticUpdateDownloading: NSNumber(value: false),
            sendSystemProfile: false
        ))
        closeWindow()
    }

    func chooseInstall() {
        guard let reply = updateReply else { return }
        updateReply = nil
        reply(.install)
    }

    func chooseLater() {
        if let reply = updateReply {
            updateReply = nil
            reply(.dismiss)
        } else if let reply = permissionReply {
            permissionReply = nil
            reply(SUUpdatePermissionResponse(
                automaticUpdateChecks: false,
                automaticUpdateDownloading: NSNumber(value: false),
                sendSystemProfile: false
            ))
        }
        closeWindow()
    }

    func chooseSkip() {
        guard let reply = updateReply else { return }
        updateReply = nil
        reply(.skip)
        closeWindow()
    }

    func cancelCurrentOperation() {
        let operation = cancellation
        cancellation = nil
        operation?()
        coordinator?.update(phase: .cancelled, message: "Update cancelled")
    }

    func retryTermination() { retryTerminationHandler?() }

    func acknowledgeAndClose() {
        let handler = acknowledgement
        acknowledgement = nil
        handler?()
        closeWindow()
    }

    func retryUpdate() {
        let handler = acknowledgement
        acknowledgement = nil
        handler?()
        closeWindow()
        DispatchQueue.main.async { [weak coordinator] in
            coordinator?.checkForUpdates()
        }
    }

    private func userClosedWindow() {
        if let operation = cancellation {
            cancellation = nil
            operation()
            coordinator?.update(phase: .cancelled, message: "Update cancelled")
            return
        }
        if let reply = updateReply {
            updateReply = nil
            reply(.dismiss)
        } else if let reply = permissionReply {
            permissionReply = nil
            reply(SUUpdatePermissionResponse(
                automaticUpdateChecks: false,
                automaticUpdateDownloading: NSNumber(value: false),
                sendSystemProfile: false
            ))
        }
    }

    private func closeWindow() {
        windowController?.closeWithoutCallback()
    }

    private func clearHandlers() {
        permissionReply = nil
        updateReply = nil
        acknowledgement = nil
        cancellation = nil
        retryTerminationHandler = nil
    }

    private func publishDownloadProgress() {
        let progress: Double? = expectedDownloadLength > 0
            ? min(Double(downloadedLength) / Double(expectedDownloadLength), 1)
            : nil
        coordinator?.update(phase: .downloading, message: "Downloading update…", progress: progress)
    }

    private func actionableMessage(for error: Error) -> String {
        let nsError = error as NSError
        return [
            nsError.localizedDescription,
            nsError.localizedRecoverySuggestion,
            nsError.localizedFailureReason,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}
