@preconcurrency import AppKit
import BroccoliCore
import Foundation
import OSLog

private final class SearchCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

struct DisruptiveActionConfirmation: Equatable, Sendable {
    private(set) var id: String?
    private(set) var expiresAt: Date?

    mutating func needsConfirmation(
        for actionID: String,
        now: Date = Date(),
        timeout: TimeInterval = 5
    ) -> Bool {
        if id == actionID, let expiresAt, expiresAt > now {
            cancel()
            return false
        }
        id = actionID
        expiresAt = now.addingTimeInterval(timeout)
        return true
    }

    func isPending(for actionID: String, now: Date = Date()) -> Bool {
        id == actionID && (expiresAt ?? .distantPast) > now
    }

    mutating func cancel() {
        id = nil
        expiresAt = nil
    }
}

enum AutomationPreflightDecision: Equatable, Sendable {
    case proceed
    case explainFirstUse
    case recoverDenied
    case unavailable

    static func resolve(_ state: AutomationPermissionState) -> Self {
        switch state {
        case .allowed, .checking, .unknown:
            .proceed
        case .notRequested:
            .explainFirstUse
        case .denied:
            .recoverDenied
        case .targetUnavailable:
            .unavailable
        }
    }
}

enum LauncherToggleDecision: Equatable, Sendable {
    case present
    case dismiss

    static func resolve(
        panelIsVisible: Bool,
        panelIsKey: Bool
    ) -> Self {
        panelIsVisible && panelIsKey ? .dismiss : .present
    }
}

/// Resolves the main launcher's mutually exclusive search states. A calculator expression is
/// not also a catalog query: presenting both at once produces irrelevant matches such as the
/// System Settings term “802.1X” for `1+1` and leaves selection semantics ambiguous.
enum LauncherMainSearchResultComposer {
    static func compose(
        catalogResults: [RankedResult],
        calculatorEvaluation: CalculatorEvaluation,
        hasVisibleQuery: Bool,
        limit: Int
    ) -> [RankedResult] {
        let resolved: [RankedResult]
        switch calculatorEvaluation {
        case .value(let calculation):
            let entry = SearchEntry(
                id: "calculator:answer",
                kind: .calculator,
                title: calculation.displayText,
                subtitle: "Calculator · Return to copy",
                iconKey: "calculator",
                target: .calculator(result: calculation.copyText)
            )
            resolved = [RankedResult(entry: entry, score: Int.max)]
        case .incomplete:
            resolved = hasVisibleQuery ? [statusResult(
                id: "status:calculator-incomplete",
                title: "Continue typing",
                subtitle: "Complete the expression to calculate",
                iconKey: "calculator"
            )] : []
        case .invalid:
            // Once the calculator has claimed a query, an invalid expression must not fall
            // through to fuzzy catalog matching. Show a deterministic status row instead.
            resolved = hasVisibleQuery ? [noResultsResult] : []
        case .notExpression:
            resolved = catalogResults.isEmpty && hasVisibleQuery
                ? [noResultsResult]
                : catalogResults
        }
        return Array(resolved.prefix(max(0, limit)))
    }

    private static var noResultsResult: RankedResult {
        statusResult(
            id: "status:no-results",
            title: "No results",
            subtitle: "Try a different search",
            iconKey: "status:no-results"
        )
    }

    private static func statusResult(
        id: String,
        title: String,
        subtitle: String,
        iconKey: String
    ) -> RankedResult {
        RankedResult(
            entry: SearchEntry(
                id: id,
                kind: .status,
                title: title,
                subtitle: subtitle,
                iconKey: iconKey,
                target: .none
            ),
            score: 0
        )
    }
}

/// Temporarily removes ordinary Broccoli windows from the active window stack while the
/// launcher panel is presented. Activating the process otherwise raises Settings alongside the
/// launcher, which is unlike Spotlight and also obscures the user's previous application.
@MainActor
final class LauncherWindowVisibilitySession {
    enum RestorationOrdering {
        /// Reconstruct the Broccoli window stack after an ordinary launcher dismissal.
        case original
        /// Make the windows visible again without putting them above the application that the
        /// launcher just opened. This is the Spotlight-style external-dispatch behavior.
        case behindForegroundApplication
    }

    private var suppressedWindows: [NSWindow] = []

    var suppressedWindowCount: Int { suppressedWindows.count }

    func suppress(
        windows: [NSWindow],
        excluding launcherWindow: NSWindow,
        preserving foregroundWindow: NSWindow? = nil
    ) {
        // A presentation should always finish before another begins. Recover defensively if an
        // AppKit ordering race left a prior snapshot behind.
        restore()
        suppressedWindows = windows.filter { window in
            window !== launcherWindow
                && window !== foregroundWindow
                && window.isVisible
                && !window.isMiniaturized
                && window.sheetParent == nil
        }
        for window in suppressedWindows {
            window.orderOut(nil)
        }
    }

    func restore(ordering: RestorationOrdering = .original) {
        let windows = suppressedWindows
        suppressedWindows.removeAll(keepingCapacity: true)
        switch ordering {
        case .original:
            // NSApplication.orderedWindows is front-to-back. Replaying it in reverse preserves
            // the original top-level ordering without activating Broccoli by itself.
            for window in windows.reversed() where !window.isVisible {
                window.orderFront(nil)
            }
        case .behindForegroundApplication:
            // `orderFront` can place Settings above a target whose activation is still settling
            // (notably Screenshot, which behaves like a utility rather than a normal app).
            // `orderBack` restores Mission Control presence while keeping the user's target—or
            // their previous app for background utilities—visually in front.
            for window in windows where !window.isVisible {
                window.orderBack(nil)
            }
        }
    }
}

@MainActor
final class LauncherCoordinator {
    private static var systemIsDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private let panel: LauncherPanelController
    private let preferences: AppPreferences
    private let usageStore: UsageStore
    private let diagnosticsStore: DiagnosticsStore
    private let actionExecutor: ActionExecutor
    private let searchEngine = SearchEngine()
    private let calculatorEngine = CalculatorEngine()
    private let searchQueue = DispatchQueue(
        label: "dev.gauravpandey.broccoli.search",
        qos: .userInteractive
    )
    private let fileSearchService = FileSearchService()
    private let modeController = LauncherModeController()
    private let windowVisibilitySession = LauncherWindowVisibilitySession()
    private var clipboardMonitor: ClipboardMonitor?
    private let signposter = OSSignposter(
        subsystem: "dev.gauravpandey.broccoli",
        category: "Performance"
    )
    private var snapshot = SearchSnapshot.empty
    private var applications: [CachedApplication] = []
    private var systemSettings: [SearchEntry] = []
    private var usage: [String: UsageRecord] = [:]
    private var queryGeneration = 0
    private var searchCancellationToken: SearchCancellationToken?
    private var snapshotBuildGeneration = 0
    private var snapshotBuildTask: Task<Void, Never>?
    private var previousApplication: NSRunningApplication?
    private weak var previousKeyWindow: NSWindow?
    private weak var previousFirstResponder: NSResponder?
    private var windowActionTask: Task<Void, Never>?
    /// External launches activate asynchronously. Keep Settings suppressed until the target
    /// application is frontmost so restoring its visibility cannot steal focus from the app
    /// the user just opened through Broccoli.
    private var defersSuppressedWindowRestoration = false
    private var confirmation = DisruptiveActionConfirmation()
    private var appliedAppearance: LauncherAppearancePreferences
    private var appliedSearchConfiguration: SearchConfiguration
    private var appliedClipboardPreferences: ClipboardPreferences

    var onRefreshCatalog: (() -> Void)?
    var onOpenPreferences: ((PreferencesSection) -> Void)?
    var onResolveWindowTarget: ((NSRunningApplication?) -> pid_t?)?

    init(
        panel: LauncherPanelController,
        preferences: AppPreferences,
        usageStore: UsageStore,
        diagnosticsStore: DiagnosticsStore,
        windowManager: WindowManager,
        clipboardMonitor: ClipboardMonitor? = nil
    ) {
        self.panel = panel
        self.preferences = preferences
        self.usageStore = usageStore
        self.diagnosticsStore = diagnosticsStore
        actionExecutor = ActionExecutor(windowManager: windowManager)
        self.clipboardMonitor = clipboardMonitor
        appliedAppearance = preferences.appearance
        appliedSearchConfiguration = SearchConfiguration(preferences: preferences)
        appliedClipboardPreferences = preferences.clipboard
        panel.onQueryChanged = { [weak self] query in self?.search(query) }
        panel.onExecute = { [weak self] result in self?.execute(result) }
        panel.onDidHide = { [weak self] in
            guard let self, !self.defersSuppressedWindowRestoration else { return }
            self.windowVisibilitySession.restore()
        }
        panel.onDismiss = { [weak self] in self?.restorePreviousApplication() }
        panel.onCancel = { [weak self] in self?.cancelOrDismiss() }
        panel.onReveal = { [weak self] result in self?.reveal(result) }
        panel.onPreferences = { [weak self] in
            self?.panel.dismiss(notify: false)
            self?.onOpenPreferences?(.general)
        }
        panel.onSelectionChanged = { [weak self] in self?.cancelConfirmation() }
        panel.applyAppearance(preferences.appearance)
        snapshot = SearchSnapshot(entries:
            ActionRegistry.searchEntries(
                    actionsEnabled: preferences.actionsEnabled,
                    enabledActionIDs: preferences.enabledActionIDs,
                    isDarkMode: Self.systemIsDarkMode
                )
                + [Self.clipboardCommand]
        )
        attachClipboardMonitor(clipboardMonitor)
        Task {
            usage = await usageStore.load()
            await diagnosticsStore.load()
        }
    }

    func setApplications(_ applications: [CachedApplication]) {
        guard applications != self.applications else { return }
        self.applications = applications
        scheduleSnapshotRebuild(prewarmIcons: true)
    }

    func setSystemSettings(_ entries: [SearchEntry]) {
        guard entries != systemSettings else { return }
        systemSettings = entries
        panel.prepareIcons(for: entries)
        scheduleSnapshotRebuild(prewarmIcons: false)
    }

    func togglePanel() {
        let toggleDecision = LauncherToggleDecision.resolve(
            panelIsVisible: panel.isVisible,
            panelIsKey: panel.isKeyWindow
        )
        if toggleDecision == .dismiss {
            panel.dismiss()
            return
        }
        // A panel can remain nominally visible while its process is no longer active during
        // an AppKit ordering transition. Treat that as stale presentation state: close it
        // without reactivating its old owner, then make this hotkey press a fresh presentation.
        if panel.isVisible {
            panel.dismiss(notify: false)
            clearPreviousFocusState()
        }
        let state = signposter.beginInterval("HotKeyToPanel")
        let start = ContinuousClock.now
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousKeyWindow = NSApp.keyWindow
        previousFirstResponder = previousKeyWindow?.firstResponder
        let foregroundBroccoliWindow: NSWindow? = if previousApplication?.bundleIdentifier
            == Bundle.main.bundleIdentifier {
            previousKeyWindow
        } else {
            nil
        }
        windowVisibilitySession.suppress(
            windows: NSApp.orderedWindows,
            excluding: panel.visibilityIsolationWindow,
            preserving: foregroundBroccoliWindow
        )
        modeController.reset()
        panel.setMode(.main)
        panel.show(on: activeScreen())
        signposter.endInterval("HotKeyToPanel", state)
        recordDuration(from: start, metric: .hotKeyToPanel)
    }

    func updatePreferences() {
        var shouldRefreshVisibleSearch = false

        if appliedAppearance != preferences.appearance {
            updateAppearance(preferences.appearance)
        }

        let searchConfiguration = SearchConfiguration(preferences: preferences)
        if appliedSearchConfiguration != searchConfiguration {
            let snapshotChanged = appliedSearchConfiguration.snapshotInputs != searchConfiguration.snapshotInputs
            appliedSearchConfiguration = searchConfiguration
            if snapshotChanged { scheduleSnapshotRebuild(prewarmIcons: false) }
            shouldRefreshVisibleSearch = true
        }

        if appliedClipboardPreferences != preferences.clipboard {
            appliedClipboardPreferences = preferences.clipboard
            clipboardMonitor?.update(preferences: preferences.clipboard)
            shouldRefreshVisibleSearch = true
        }

        if shouldRefreshVisibleSearch, panel.isVisible { search(panel.query) }
    }

    func updateAppearance(_ appearance: LauncherAppearancePreferences) {
        guard appliedAppearance != appearance else { return }
        appliedAppearance = appearance
        panel.applyAppearance(appearance)
        if panel.isVisible { search(panel.query) }
    }

    func refreshAppearanceForSystemChange() {
        // System/contrast/transparency state can change while the persisted preference value
        // remains identical, so this is the one path that deliberately forces a restyle.
        panel.applyAppearance(preferences.appearance, force: true)
        scheduleSnapshotRebuild(prewarmIcons: false)
    }

    func setClipboardMonitor(_ monitor: ClipboardMonitor?) {
        clipboardMonitor?.onChange = nil
        clipboardMonitor?.stop()
        clipboardMonitor = monitor
        attachClipboardMonitor(monitor)
        monitor?.update(preferences: preferences.clipboard)
    }

    func clearUsage() {
        usage = [:]
        Task { await usageStore.clear() }
        if panel.isVisible { search(panel.query) }
    }

    func refreshRunningApplications(bundleIdentifier: String? = nil) {
        if let bundleIdentifier,
           !applications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return
        }
        scheduleSnapshotRebuild(prewarmIcons: false)
    }

    private func scheduleSnapshotRebuild(prewarmIcons: Bool) {
        snapshotBuildGeneration += 1
        let generation = snapshotBuildGeneration
        let applications = applications
        let systemSettings = systemSettings
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let enabledActionIDs = preferences.enabledActionIDs
        let applicationsEnabled = preferences.applicationsEnabled
        let settingsEnabled = preferences.settingsEnabled
        let actionsEnabled = preferences.actionsEnabled
        let isDarkMode = Self.systemIsDarkMode
        let clipboardCommand = Self.clipboardCommand
        snapshotBuildTask?.cancel()
        snapshotBuildTask = Task.detached(priority: .utility) { [weak self] in
            let appEntries: [SearchEntry] = applicationsEnabled ? applications.map { cached -> SearchEntry in
                var entry = cached.searchEntry
                entry.isRunning = cached.bundleIdentifier.map(runningIDs.contains) ?? false
                return entry
            } : []
            guard !Task.isCancelled else { return }
            let nextSnapshot = SearchSnapshot(
                entries: appEntries
                    + (settingsEnabled ? systemSettings : [])
                    + ActionRegistry.searchEntries(
                        actionsEnabled: actionsEnabled,
                        enabledActionIDs: enabledActionIDs,
                        isDarkMode: isDarkMode
                    )
                    + [clipboardCommand]
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, generation == self.snapshotBuildGeneration else { return }
                self.snapshot = nextSnapshot
                if prewarmIcons { self.panel.prepareIcons(for: appEntries) }
                if self.panel.isVisible { self.search(self.panel.query) }
            }
        }
    }

    private func search(_ query: String) {
        cancelConfirmation()
        searchCancellationToken?.cancel()
        let cancellationToken = SearchCancellationToken()
        searchCancellationToken = cancellationToken
        queryGeneration += 1
        let generation = queryGeneration

        switch modeController.mode {
        case .clipboard:
            _ = modeController.update(query: query, fileSearchEnabled: preferences.fileSearch.enabled)
            searchClipboard(query)
            return
        case .fileSearch:
            _ = modeController.update(query: query, fileSearchEnabled: preferences.fileSearch.enabled)
            searchFiles(query, generation: generation, showsLoadingState: false)
            return
        case .main:
            break
        }

        if preferences.fileSearch.enabled, let fileQuery = LauncherModeController.fileQuery(from: query) {
            let nextMode = modeController.update(query: query, fileSearchEnabled: true)
            panel.setMode(nextMode, initialQuery: fileQuery)
            searchFiles(fileQuery, generation: generation, showsLoadingState: true)
            return
        }

        let snapshot = snapshot
        let usage = usage
        let searchPreferences = preferences.searchPreferences
        let calculatorPreferences = preferences.calculator
        let resultLimit = preferences.appearance.visibleResultCount
        let hasVisibleQuery = !SearchNormalizer.normalize(query).isEmpty
        let state = signposter.beginInterval("QueryToResults")
        let start = ContinuousClock.now
        searchQueue.async { [weak self, searchEngine, calculatorEngine] in
            guard !cancellationToken.isCancelled else {
                Task { @MainActor [weak self] in
                    self?.signposter.endInterval("QueryToResults", state)
                }
                return
            }
            let calculatorEvaluation: CalculatorEvaluation = calculatorPreferences.enabled
                ? calculatorEngine.classify(
                    query,
                    maximumSignificantDigits: calculatorPreferences.significantDigits,
                    usesGroupingSeparator: calculatorPreferences.usesGroupingSeparator
                ) : .notExpression
            // Calculator classification is substantially cheaper than a 10,000-entry search
            // and decides whether catalog matching is semantically applicable at all.
            let catalogResults: [RankedResult] = if calculatorEvaluation == .notExpression {
                searchEngine.search(
                    query: query,
                    snapshot: snapshot,
                    usage: usage,
                    preferences: searchPreferences,
                    limit: resultLimit
                )
            } else {
                []
            }
            let results = LauncherMainSearchResultComposer.compose(
                catalogResults: catalogResults,
                calculatorEvaluation: calculatorEvaluation,
                hasVisibleQuery: hasVisibleQuery,
                limit: resultLimit
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.signposter.endInterval("QueryToResults", state)
                guard !cancellationToken.isCancelled,
                      generation == self.queryGeneration else { return }
                self.panel.apply(results, preservingSelection: true)
                self.recordDuration(from: start, metric: .queryToResults)
            }
        }
    }

    private func execute(_ result: RankedResult) {
        let dispatchState = signposter.beginInterval("ReturnToDispatch")
        let dispatchStart = ContinuousClock.now

        if case .action(let id) = result.entry.target,
           let definition = ActionRegistry.definition(id: id),
           definition.risk == .disruptive,
           confirmation.needsConfirmation(for: id) {
            panel.showConfirmation(for: result.entry.id)
            scheduleConfirmationExpiry(id: id)
            signposter.endInterval("ReturnToDispatch", dispatchState)
            recordDuration(from: dispatchStart, metric: .returnToDispatch)
            return
        }

        confirmation.cancel()
        if result.entry.kind == .application
            || result.entry.kind == .systemSetting
            || result.entry.kind == .action {
            recordSelection(result.entry.id)
        }

        switch result.entry.target {
        case .application(let path, let bundleIdentifier):
            dismissForExternalDispatch()
            launchApplication(path: path, bundleIdentifier: bundleIdentifier)
        case .setting(let route):
            dismissForExternalDispatch()
            openSetting(route: route)
        case .action(let id):
            dispatchAction(id: id)
        case .file(let path, _):
            dismissForExternalDispatch()
            _ = NSWorkspace.shared.open(URL(fileURLWithPath: path))
            finishExternalDispatchAfterActivation()
        case .calculator(let result):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(result, forType: .string)
            panel.dismiss(notify: false)
        case .clipboardCommand:
            guard preferences.clipboard.enabled, clipboardMonitor != nil else {
                panel.dismiss(notify: false)
                onOpenPreferences?(.clipboard)
                break
            }
            modeController.enterClipboard()
            panel.setMode(modeController.mode)
            searchClipboard("")
        case .clipboardItem(let id):
            clipboardMonitor?.restore(id: id) { [weak self] succeeded in
                if succeeded { self?.panel.dismiss(notify: false) }
            }
        case .none:
            break
        }

        signposter.endInterval("ReturnToDispatch", dispatchState)
        recordDuration(from: dispatchStart, metric: .returnToDispatch)
    }

    private func dispatchAction(id: String) {
        switch id {
        case "catalog.refresh":
            panel.dismiss(notify: false)
            onRefreshCatalog?()
            return
        case "broccoli.preferences":
            panel.dismiss(notify: false)
            onOpenPreferences?(.general)
            return
        case "broccoli.quit":
            NSApp.terminate(nil)
            return
        default:
            break
        }

        guard let definition = ActionRegistry.definition(id: id) else {
            executeAction(id: id, automationRelated: false)
            return
        }
        if definition.permission == .accessibility {
            executeWindowAction(id: id)
            return
        }
        guard definition.permission == .automation else {
            executeAction(id: id, automationRelated: false)
            return
        }

        Task {
            let permission = await AutomationPermissionChecker.current()
            switch AutomationPreflightDecision.resolve(permission) {
            case .proceed:
                executeAction(id: id, automationRelated: true)
            case .explainFirstUse:
                guard panel.confirmAutomationFirstUse(actionTitle: definition.title) else { return }
                executeAction(id: id, automationRelated: true)
            case .recoverDenied:
                panel.showAutomationDenied(actionTitle: definition.title)
            case .unavailable:
                panel.showAutomationUnavailable(actionTitle: definition.title)
            }
        }
    }

    private func executeAction(id: String, automationRelated: Bool) {
        Task {
            do {
                let result = try await actionExecutor.execute(id: id)
                switch result {
                case .completed: panel.dismiss(notify: false)
                case .keepPanelOpen: break
                }
            } catch {
                panel.showError(error, automationRelated: automationRelated)
            }
        }
    }

    private func executeWindowAction(id: String) {
        guard AccessibilityPermissionChecker.isTrusted else {
            panel.dismiss(notify: false)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Window Control Access Is Not Active"
            alert.informativeText = "macOS is not currently granting Broccoli access in \(WindowManagementPermissionPresentation.settingsName). If Broccoli is already on, turn it off and on once to refresh the app identity."
            alert.addButton(withTitle: "Review Settings")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                AccessibilityPermissionChecker.request()
                AccessibilityPermissionChecker.openSettings()
            }
            clearPreviousFocusState()
            return
        }

        let targetPID = onResolveWindowTarget?(previousApplication)
        panel.dismiss(notify: false)
        windowActionTask?.cancel()
        windowActionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await actionExecutor.execute(id: id, targetPID: targetPID)
                try Task.checkCancellation()
                restorePreviousApplication(activateAllWindows: false)
            } catch is CancellationError {
                return
            } catch {
                clearPreviousFocusState()
                panel.showError(error, automationRelated: false)
            }
        }
    }

    private func launchApplication(path: String, bundleIdentifier: String?) {
        if let bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            if running.activate(options: [.activateAllWindows]) {
                finishExternalDispatchAfterActivation(expectedApplication: running)
                return
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: configuration
        ) { [weak self] application, error in
            guard let self else { return }
            guard let error else {
                Task { @MainActor [weak self] in
                    _ = application?.activate(options: [.activateAllWindows])
                    self?.finishExternalDispatchAfterActivation(expectedApplication: application)
                }
                return
            }
            let nsError = error as NSError
            Logger.launcher.error(
                "Application launch failed (domain: \(nsError.domain, privacy: .public), code: \(nsError.code, privacy: .public))"
            )
            Task { @MainActor [weak self] in
                self?.finishExternalDispatchImmediately()
                self?.panel.showError(error, automationRelated: false)
            }
        }
    }

    private func openSetting(route: String?) {
        if let route, let url = URL(string: route), NSWorkspace.shared.open(url) {
            let settingsApplication = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.systempreferences"
            ).first
            finishExternalDispatchAfterActivation(expectedApplication: settingsApplication)
            return
        }
        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: settingsURL, configuration: configuration) {
                [weak self] application, _ in
                Task { @MainActor [weak self] in
                    _ = application?.activate(options: [.activateAllWindows])
                    self?.finishExternalDispatchAfterActivation(expectedApplication: application)
                }
            }
        } else {
            finishExternalDispatchImmediately()
        }
    }

    private func dismissForExternalDispatch() {
        defersSuppressedWindowRestoration = true
        panel.dismiss(notify: false)
    }

    private func finishExternalDispatchAfterActivation(
        expectedApplication: NSRunningApplication? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Workspace completion means the application launched, not necessarily that its
            // activation transaction has reached the window server. Wait for actual foreground
            // ownership instead of relying on a fixed delay that fails on cold launches.
            let expectedProcessIdentifier = expectedApplication?.processIdentifier
            for _ in 0..<40 {
                let frontmost = NSWorkspace.shared.frontmostApplication
                let targetIsFrontmost: Bool
                if let expectedProcessIdentifier {
                    targetIsFrontmost = frontmost?.processIdentifier == expectedProcessIdentifier
                } else {
                    targetIsFrontmost = frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier
                }
                if targetIsFrontmost { break }
                try? await Task.sleep(for: .milliseconds(25))
            }

            // Some Apple utilities (including Screenshot on some macOS builds) intentionally do
            // not become the frontmost application. In that case return focus to the app that
            // was active before Broccoli, never to Broccoli Settings.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
               let previousApplication = self.previousApplication,
               previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier,
               !previousApplication.isTerminated {
                _ = previousApplication.activate(options: [.activateAllWindows])
                for _ in 0..<8 where !previousApplication.isActive {
                    try? await Task.sleep(for: .milliseconds(25))
                }
            }

            self.finishExternalDispatchImmediately(
                restorationOrdering: .behindForegroundApplication
            )
        }
    }

    private func finishExternalDispatchImmediately(
        restorationOrdering: LauncherWindowVisibilitySession.RestorationOrdering = .original
    ) {
        defersSuppressedWindowRestoration = false
        windowVisibilitySession.restore(ordering: restorationOrdering)
        clearPreviousFocusState()
    }

    private func recordSelection(_ id: String) {
        var record = usage[id] ?? UsageRecord(selectionCount: 0, lastUsed: Date())
        record.selectionCount += 1
        record.lastUsed = Date()
        usage[id] = record
        Task { await usageStore.recordSelection(id: id, at: record.lastUsed) }
    }

    private func scheduleConfirmationExpiry(id: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.confirmation.id == id else { return }
            self.cancelConfirmation()
        }
    }

    private func cancelConfirmation() {
        confirmation.cancel()
        panel.clearConfirmation()
    }

    private func restorePreviousApplication(activateAllWindows: Bool = true) {
        guard let previousApplication, !previousApplication.isTerminated else {
            clearPreviousFocusState()
            return
        }
        if previousApplication.bundleIdentifier == Bundle.main.bundleIdentifier,
           let previousKeyWindow {
            previousKeyWindow.makeKeyAndOrderFront(nil)
            previousKeyWindow.makeFirstResponder(previousFirstResponder)
        } else if !previousApplication.isActive {
            // A non-activating launcher normally leaves the external application active, so
            // ordering the panel out is enough to return keyboard ownership. Activate only
            // for fallback paths where foreground ownership actually changed.
            previousApplication.activate(
                options: activateAllWindows ? [.activateAllWindows] : []
            )
        }
        clearPreviousFocusState()
    }

    private func clearPreviousFocusState() {
        self.previousApplication = nil
        previousKeyWindow = nil
        previousFirstResponder = nil
    }

    private func activeScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        let pointer = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        switch preferences.appearance.screen {
        case .active: return NSScreen.main ?? pointer ?? NSScreen.screens.first
        case .pointer: return pointer ?? NSScreen.main ?? NSScreen.screens.first
        case .primary: return NSScreen.screens.first ?? NSScreen.main
        }
    }

    private func cancelOrDismiss() {
        switch modeController.mode {
        case .main:
            panel.dismiss()
        case .fileSearch, .clipboard:
            fileSearchService.cancel()
            _ = modeController.exitSubmode()
            panel.setMode(.main)
            search("")
        }
    }

    private func reveal(_ result: RankedResult) {
        if case .file(let path, _) = result.entry.target {
            panel.dismiss(notify: false)
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            execute(result)
        }
    }

    private func searchFiles(
        _ query: String,
        generation: Int,
        showsLoadingState: Bool
    ) {
        let loading = SearchEntry(
            id: "status:file-searching",
            kind: .status,
            title: query.isEmpty ? "Type a filename" : "Searching files…",
            subtitle: query.isEmpty ? "Search by name or path" : "Using Spotlight metadata",
            iconKey: "status:file-searching",
            target: .none
        )
        if showsLoadingState || query.isEmpty {
            panel.apply([RankedResult(entry: loading, score: 0)])
        }
        fileSearchService.search(
            query: query,
            generation: generation,
            limit: preferences.appearance.visibleResultCount
        ) { [weak self] returnedGeneration, outcome in
            guard let self, returnedGeneration == self.queryGeneration,
                  case .fileSearch = self.modeController.mode else { return }
            switch outcome {
            case .results(let items):
                let results = items.enumerated().map {
                    RankedResult(entry: $0.element.searchEntry, score: 1_000 - $0.offset)
                }
                if results.isEmpty {
                    let entry = SearchEntry(
                        id: "status:no-files",
                        kind: .status,
                        title: self.panel.query.isEmpty ? "Type a filename" : "No files found",
                        subtitle: self.panel.query.isEmpty ? "Search by name or path" : "Try a different name or path",
                        iconKey: "status:no-files",
                        target: .none
                    )
                    self.panel.apply([RankedResult(entry: entry, score: 0)])
                } else {
                    // Metadata queries stream additional matches. Keep the user's chosen
                    // stable entry selected while rows reorder around it so Return cannot
                    // silently jump to a different file.
                    self.panel.apply(results, preservingSelection: true)
                }
            case .unavailable:
                let entry = SearchEntry(
                    id: "file:unavailable",
                    kind: .file,
                    title: "File search is unavailable",
                    subtitle: "Check Spotlight privacy and indexing settings",
                    iconKey: "file:unavailable",
                    target: .setting(route: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension")
                )
                self.panel.apply([RankedResult(entry: entry, score: 0)])
            }
        }
    }

    private func searchClipboard(_ query: String) {
        guard let clipboardMonitor else {
            let entry = SearchEntry(
                id: "status:clipboard-unavailable",
                kind: .status,
                title: "Clipboard history is unavailable",
                subtitle: "Enable it in Broccoli Settings",
                iconKey: "status:clipboard-unavailable",
                target: .none
            )
            panel.apply([RankedResult(entry: entry, score: 0)])
            return
        }
        let count = preferences.appearance.visibleResultCount
        let results: [RankedResult] = clipboardMonitor.filteredSummaries(query: query)
            .prefix(count).enumerated().map {
            let summary = $0.element
            let entry = SearchEntry(
                id: "clipboard:\(summary.id)",
                kind: .clipboard,
                title: summary.preview,
                subtitle: "\(summary.kind.rawValue.capitalized) · \(summary.createdAt.formatted(date: .abbreviated, time: .shortened))",
                iconKey: "clipboard:\(summary.kind.rawValue)",
                target: .clipboardItem(id: summary.id)
            )
            return RankedResult(entry: entry, score: 1_000 - $0.offset)
        }
        if results.isEmpty {
            let entry = SearchEntry(
                id: "status:clipboard-empty",
                kind: .status,
                title: query.isEmpty ? "Clipboard history is empty" : "No clipboard matches",
                subtitle: query.isEmpty ? "Copy something to add it here" : "Try a different search",
                iconKey: "status:clipboard-empty",
                target: .none
            )
            panel.apply([RankedResult(entry: entry, score: 0)])
        } else {
            panel.apply(results)
        }
    }

    private func attachClipboardMonitor(_ monitor: ClipboardMonitor?) {
        monitor?.onChange = { [weak self] _ in
            guard let self, case .clipboard(let query) = self.modeController.mode else { return }
            self.searchClipboard(query)
        }
    }

    private static let clipboardCommand = SearchEntry(
        id: "command:clipboard",
        kind: .clipboard,
        title: "Clipboard History",
        subtitle: "Browse recent clipboard items",
        keywords: ["clip", "paste", "copy"],
        iconKey: "clipboard:command",
        target: .clipboardCommand
    )

    private func recordDuration(from start: ContinuousClock.Instant, metric: DiagnosticMetric) {
        let duration = start.duration(to: .now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        Task {
            await diagnosticsStore.append(
                DiagnosticSample(metric: metric, durationMilliseconds: milliseconds)
            )
        }
    }
}

private struct SearchConfiguration: Equatable {
    struct SnapshotInputs: Equatable {
        let applicationsEnabled: Bool
        let settingsEnabled: Bool
        let actionsEnabled: Bool
        let enabledActionIDs: Set<String>
    }

    let snapshotInputs: SnapshotInputs
    let recentItemsEnabled: Bool
    let adaptiveRankingEnabled: Bool
    let calculatorPreferences: CalculatorPreferences
    let fileSearchEnabled: Bool

    @MainActor
    init(preferences: AppPreferences) {
        snapshotInputs = SnapshotInputs(
            applicationsEnabled: preferences.applicationsEnabled,
            settingsEnabled: preferences.settingsEnabled,
            actionsEnabled: preferences.actionsEnabled,
            enabledActionIDs: preferences.enabledActionIDs
        )
        recentItemsEnabled = preferences.recentItemsEnabled
        adaptiveRankingEnabled = preferences.adaptiveRankingEnabled
        calculatorPreferences = preferences.calculator
        fileSearchEnabled = preferences.fileSearch.enabled
    }
}

private extension Logger {
    static let launcher = Logger(subsystem: "dev.gauravpandey.broccoli", category: "Launcher")
}
