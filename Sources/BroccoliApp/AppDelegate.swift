@preconcurrency import AppKit
import Combine
import BroccoliCore

enum ApplicationPresentationMode: Equatable, Sendable {
    case background
    case settings
}

struct ApplicationLifecycleState: Equatable, Sendable {
    private(set) var presentationMode: ApplicationPresentationMode = .background
    private(set) var isTerminating = false

    mutating func beginSettingsPresentation() {
        guard !isTerminating else { return }
        presentationMode = .settings
    }

    mutating func endSettingsPresentation() {
        guard !isTerminating else { return }
        presentationMode = .background
    }

    mutating func beginTermination() {
        isTerminating = true
    }
}

@MainActor
enum ApplicationIconResource {
    static func name(for appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? "Broccoli-AppIcon-Dark-1024"
            : "Broccoli-AppIcon-Light-1024"
    }
}

@MainActor
final class ApplicationIconController {
    typealias ImageSetter = (NSImage?) -> Void
    private let imageSetter: ImageSetter

    init(imageSetter: @escaping ImageSetter = { NSApp.applicationIconImage = $0 }) {
        self.imageSetter = imageSetter
    }

    /// The compiled Icon Composer asset owns Dock appearance in every process state.
    /// A flattened PNG override bypasses that asset and can acquire a second system plate.
    func restoreBundleIcon() { imageSetter(nil) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var settingsContext: BroccoliSettingsContext?

    private var preferences: AppPreferences!
    private var hotKey: GlobalHotKey!
    private let windowManager = WindowManager()
    private var panel: LauncherPanelController!
    private var coordinator: LauncherCoordinator!
    private var catalogService: ApplicationCatalogService!
    private var systemSettingsCatalogService: SystemSettingsCatalogService!
    private var effectiveAppearanceObservation: NSKeyValueObservation?
    private weak var settingsWindow: NSWindow?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var openSettingsAction: (() -> Void)?
    private var isSettingsPresentationPending = false
    private var preferenceObservation: AnyCancellable?
    private var appearanceObservation: AnyCancellable?
    private var preferenceUpdateScheduled = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var diagnosticsStore: DiagnosticsStore!
    private var clipboardMonitor: ClipboardMonitor?
    private var currencyRateService: CurrencyRateService?
    private var supportDirectory: URL!
    private var shortcutRegistrationError: String?
    private var windowShortcutRegistrationError: String?
    private var windowActionTask: Task<Void, Never>?
    private lazy var dragSnapController = WindowDragSnapController(windowManager: windowManager)
    private lazy var tilingController = WindowTilingController(windowManager: windowManager)
    private var registeredWindowBindingIDs: Set<String> = []
    private var windowShortcutsPausedForIgnoredApp = false
    private var windowPreferenceObservation: AnyCancellable?
    private var lifecycleState = ApplicationLifecycleState()
    private let applicationIconController = ApplicationIconController()
    private var lastExternalApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPresentationMode()
        preferences = AppPreferences()
        updateApplicationIcon()
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)

        let resolvedSupportDirectory: URL
        do {
            resolvedSupportDirectory = try PersistencePaths.applicationSupportDirectory()
        } catch {
            resolvedSupportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Broccoli", isDirectory: true)
            try? FileManager.default.createDirectory(at: resolvedSupportDirectory, withIntermediateDirectories: true)
        }
        supportDirectory = resolvedSupportDirectory
        ClipboardStore.secureExistingStorage(
            at: resolvedSupportDirectory.appendingPathComponent("clipboard.sqlite3")
        )

        let catalogStore = CatalogStore(fileURL: resolvedSupportDirectory.appendingPathComponent("catalog.plist"))
        let usageStore = UsageStore(fileURL: resolvedSupportDirectory.appendingPathComponent("usage.plist"))
        diagnosticsStore = DiagnosticsStore(fileURL: resolvedSupportDirectory.appendingPathComponent("diagnostics.json"))

        panel = LauncherPanelController()
        coordinator = LauncherCoordinator(
            panel: panel,
            preferences: preferences,
            usageStore: usageStore,
            diagnosticsStore: diagnosticsStore,
            windowManager: windowManager,
            clipboardMonitor: nil
        )
        coordinator.onResolveWindowTarget = { [weak self] preferredApplication in
            self?.resolveWindowActionTarget(preferredApplication: preferredApplication)
        }
        windowManager.layoutOptionsProvider = { [weak self] in
            self?.preferences.windowManagement.layoutOptions ?? .standard
        }
        windowManager.customLayoutProvider = { [weak self] id in
            self?.preferences.windowManagement.customLayouts.first { $0.id == id }
        }
        windowManager.workspaceProvider = { [weak self] id in
            self?.preferences.windowManagement.workspaces.first { $0.id == id }
        }
        let rateStore = CurrencyRateStore(
            fileURL: resolvedSupportDirectory.appendingPathComponent("currency-rates.json")
        )
        currencyRateService = CurrencyRateService(
            store: rateStore,
            isEnabled: { [weak self] in
                self?.preferences.calculator.onlineRatesEnabled ?? false
            },
            onUpdate: { [weak self] snapshot in
                self?.coordinator.updateCurrencyRates(snapshot)
            }
        )
        currencyRateService?.start()
        catalogService = ApplicationCatalogService(store: catalogStore)
        catalogService.onCatalogChanged = { [weak self] applications in
            self?.coordinator.setApplications(applications)
        }
        systemSettingsCatalogService = SystemSettingsCatalogService()
        systemSettingsCatalogService.onCatalogChanged = { [weak self] entries in
            self?.coordinator.setSystemSettings(entries)
        }
        coordinator.onRefreshCatalog = { [weak self] in
            self?.catalogService.refresh()
            self?.systemSettingsCatalogService.refresh()
        }

        hotKey = GlobalHotKey()
        hotKey.onPressed = { [weak self] in self?.coordinator.togglePanel() }
        registerShortcut(preferences.hotKey)
        windowShortcutRegistrationError = registerWindowShortcutsIfEnabled()

        settingsContext = BroccoliSettingsContext(
            preferences: preferences,
            initialShortcutError: shortcutRegistrationError,
            onShortcutChanged: { [weak self] configuration in
                self?.registerShortcut(configuration)
            },
            initialWindowShortcutError: windowShortcutRegistrationError,
            onWindowShortcutChanged: { [weak self] target, configuration in
                self?.changeWindowShortcut(target, to: configuration)
                    ?? .rejected("Broccoli is shutting down.")
            },
            onWindowShortcutsEnabledChanged: { [weak self] enabled in
                self?.setWindowShortcutsEnabled(enabled)
            },
            onCaptureWorkspace: { [weak self] name in
                await self?.captureWorkspace(named: name)
            },
            onClearUsage: { [weak self] in self?.coordinator.clearUsage() },
            onClearClipboard: { [weak self] in self?.clipboardMonitor?.clear() },
            onExportDiagnostics: { [weak self] in self?.exportDiagnostics() },
            onWindowAttached: { [weak self] window in
                self?.settingsWindowDidAttach(window)
            }
        )

        coordinator.onOpenPreferences = { [weak self] section in self?.showPreferences(section: section) }

        observePreferences()
        observeRunningApplications()
        observeDisplayPreferences()
        catalogService.start()
        systemSettingsCatalogService.start()
        configureClipboardIfNeeded()

        let launchArguments = Set(ProcessInfo.processInfo.arguments.dropFirst())
        if launchArguments.contains("--show-launcher") {
            DispatchQueue.main.async { [weak self] in self?.coordinator.togglePanel() }
        } else if launchArguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showPreferences() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lifecycleState.beginTermination()
        windowActionTask?.cancel()
        return .terminateNow
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        panel?.restoreSearchFocusIfVisible()
        panel?.refreshDisplayedNativeIcons()
    }

    func configureSettingsOpener(_ action: @escaping () -> Void) {
        openSettingsAction = action
        guard isSettingsPresentationPending else { return }
        isSettingsPresentationPending = false
        DispatchQueue.main.async {
            action()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showPreferences(section: PreferencesSection? = nil) {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        lifecycleState.beginSettingsPresentation()
        applyPresentationMode()
        // Activate before SwiftUI creates the Settings scene. Its sidebar requests focus in
        // onAppear, which is ignored when the process is still an inactive accessory app.
        NSApp.activate(ignoringOtherApps: true)
        updateApplicationIcon()
        if let section { settingsContext?.shell.selectSection(section) }
        settingsContext?.previewRenderer.beginSettingsSession()

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else if let openSettingsAction {
            openSettingsAction()
        } else {
            isSettingsPresentationPending = true
        }
    }

    private func settingsWindowDidClose() {
        settingsContext?.previewRenderer.endSettingsSession()
        settingsWindow = nil
        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
            self.settingsWindowCloseObserver = nil
        }
        lifecycleState.endSettingsPresentation()
        guard !lifecycleState.isTerminating else { return }
        applyPresentationMode()
        restoreLastExternalApplication()
    }

    private func settingsWindowDidAttach(_ window: NSWindow) {
        guard settingsWindow !== window else { return }

        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        }
        settingsWindow = window
        // The scene can attach after the activation request. Commit key-window ownership
        // here, then let SwiftUI reflect active and inactive selection normally.
        if lifecycleState.presentationMode == .settings {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        // Keep the Dock on its adaptive bundle asset after the presentation transition.
        updateApplicationIcon()
        settingsContext?.previewRenderer.beginSettingsSession()
        settingsWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settingsWindowDidClose()
            }
        }
    }

    private func applyPresentationMode() {
        switch lifecycleState.presentationMode {
        case .background:
            // The global shortcut and launcher panel do not need a Dock or application-menu
            // presence. Accessory mode keeps Broccoli running and able to receive hot keys.
            NSApp.setActivationPolicy(.accessory)
        case .settings:
            // SwiftUI Settings needs regular-app presentation so it behaves like a normal
            // macOS settings window and owns a Dock icon for as long as that window is open.
            NSApp.setActivationPolicy(.regular)
        }
        applicationIconController.restoreBundleIcon()
    }

    private func observePreferences() {
        // Observe the published value, not only objectWillChange. objectWillChange fires
        // before AppPreferences has stored the replacement struct, so several rapid theme
        // card clicks could coalesce into a callback that read the previous design.
        appearanceObservation = preferences.$appearance
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.coordinator.updateAppearance(appearance)
            }
        preferenceObservation = preferences.objectWillChange.sink { [weak self] _ in
            guard let self, !self.preferenceUpdateScheduled else { return }
            self.preferenceUpdateScheduled = true
            DispatchQueue.main.async {
                self.preferenceUpdateScheduled = false
                self.configureClipboardIfNeeded()
                self.coordinator.updatePreferences()
            }
        }
        // `$windowManagement` publishes before the new value is stored; apply it on the next
        // turn so registration reads the saved preferences.
        windowPreferenceObservation = preferences.$windowManagement
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.applyWindowManagementPreferences(self.preferences.windowManagement)
                }
            }
        applyWindowManagementPreferences(preferences.windowManagement)
    }

    private func configureClipboardIfNeeded() {
        guard preferences.clipboard.enabled else {
            clipboardMonitor?.update(preferences: preferences.clipboard)
            return
        }
        guard clipboardMonitor == nil else {
            clipboardMonitor?.update(preferences: preferences.clipboard)
            return
        }
        guard let keyData = try? ClipboardKeyProvider.loadOrCreate() else { return }
        let databaseURL = supportDirectory.appendingPathComponent("clipboard.sqlite3")
        let clipboardStore: ClipboardStore
        do {
            clipboardStore = try ClipboardStore(databaseURL: databaseURL, keyData: keyData)
        } catch {
            // SQLite could not even open or validate its schema. Clipboard history is optional
            // and encrypted, so discard only these exact unusable files and recreate a clean
            // owner-only store. No payload or path is written to diagnostics.
            ClipboardStore.discardStorage(at: databaseURL)
            guard let recovered = try? ClipboardStore(databaseURL: databaseURL, keyData: keyData)
            else { return }
            clipboardStore = recovered
        }
        let monitor = ClipboardMonitor(store: clipboardStore, preferences: preferences.clipboard)
        clipboardMonitor = monitor
        coordinator.setClipboardMonitor(monitor)
    }

    private func observeRunningApplications() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                let bundleIdentifier = application?.bundleIdentifier
                MainActor.assumeIsolated {
                    if name == NSWorkspace.didTerminateApplicationNotification {
                        self?.forgetExternalApplication(application)
                        if let application { self?.windowManager.forgetApplication(application.processIdentifier) }
                    }
                    self?.coordinator.refreshRunningApplications(
                        bundleIdentifier: bundleIdentifier
                    )
                }
            })
        }
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.rememberExternalApplication(application)
                self?.updateWindowShortcutPause(for: application)
            }
        })
    }

    private func observeDisplayPreferences() {
        effectiveAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.coordinator.refreshAppearanceForSystemChange()
                self?.updateApplicationIcon()
            }
        }
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.refreshAppearanceForSystemChange() }
        })
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // This distributed notification can arrive before NSApp publishes the new
            // effective appearance. Resolve System-mode launcher colors on the next turn.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.coordinator.refreshAppearanceForSystemChange()
                self?.updateApplicationIcon()
            }
        })
    }

    private func updateApplicationIcon() {
        applicationIconController.restoreBundleIcon()
    }

    @discardableResult
    private func registerShortcut(_ configuration: HotKeyConfiguration) -> String? {
        do {
            try hotKey.register(configuration)
            shortcutRegistrationError = nil
            return nil
        } catch {
            let message = error.localizedDescription
            // RegisterEventHotKey is attempted before the existing binding is removed. A
            // failed reassignment therefore reports the requested conflict to Settings while
            // keeping the known-good shortcut intact.
            shortcutRegistrationError = hotKey.configuration == nil ? message : nil
            return message
        }
    }

    private func registerWindowShortcutsIfEnabled() -> String? {
        guard preferences.windowManagement.shortcutsEnabled, !windowShortcutsPausedForIgnoredApp else {
            unregisterWindowShortcuts()
            return nil
        }
        return registerWindowShortcuts()
    }

    /// Registers every assigned window shortcut independently. One conflicting shortcut must
    /// not take the others down with it; the returned message names the ones that failed.
    private func registerWindowShortcuts() -> String? {
        let windowPreferences = preferences.windowManagement
        let targets = windowPreferences.shortcutTargets
        let currentBindingIDs = Set(targets.map(\.bindingID))
        for staleBindingID in registeredWindowBindingIDs.subtracting(currentBindingIDs) {
            hotKey.unregister(staleBindingID)
        }
        registeredWindowBindingIDs = []
        var failedTitles: [String] = []
        for target in targets {
            guard let configuration = windowPreferences.shortcut(for: target) else {
                hotKey.unregister(target.bindingID)
                continue
            }
            do {
                try registerWindowShortcut(target, configuration: configuration)
                registeredWindowBindingIDs.insert(target.bindingID)
            } catch {
                hotKey.unregister(target.bindingID)
                failedTitles.append(windowPreferences.title(for: target))
            }
        }
        return WindowShortcutRegistrationSummary.message(failedTitles: failedTitles)
    }

    private func registerWindowShortcut(
        _ target: WindowShortcutTarget,
        configuration: HotKeyConfiguration
    ) throws {
        try hotKey.register(configuration, for: target.bindingID) { [weak self] in
            self?.performWindowTarget(target)
        }
    }

    private func unregisterWindowShortcuts() {
        for bindingID in registeredWindowBindingIDs { hotKey.unregister(bindingID) }
        for action in WindowAction.allCases { hotKey.unregister(action.hotKeyBindingID) }
        registeredWindowBindingIDs = []
    }

    /// An ignored application receives window shortcut keystrokes itself, so the shortcuts
    /// are released while it is frontmost and registered again once it is not.
    private func updateWindowShortcutPause(for application: NSRunningApplication?) {
        let paused = application?.bundleIdentifier.map {
            preferences.windowManagement.ignoredBundleIdentifiers.contains($0)
        } ?? false
        guard paused != windowShortcutsPausedForIgnoredApp else { return }
        windowShortcutsPausedForIgnoredApp = paused
        windowShortcutRegistrationError = registerWindowShortcutsIfEnabled()
    }

    /// Brings the always-running window features in line with the saved preferences.
    private func applyWindowManagementPreferences(_ windowPreferences: WindowManagementPreferences) {
        dragSnapController.ignoredBundleIdentifiers = windowPreferences.ignoredBundleIdentifiers
        dragSnapController.isEnabled = windowPreferences.dragToSnapEnabled
            && AccessibilityPermissionChecker.isTrusted
        tilingController.isEnabled = windowPreferences.automaticTilingEnabled
            && AccessibilityPermissionChecker.isTrusted
        tilingController.scheduleRetile()
        updateWindowShortcutPause(for: NSWorkspace.shared.frontmostApplication)
        windowShortcutRegistrationError = registerWindowShortcutsIfEnabled()
    }

    private func setWindowShortcutsEnabled(_ enabled: Bool) -> String? {
        if !enabled {
            unregisterWindowShortcuts()
            var value = preferences.windowManagement
            value.shortcutsEnabled = false
            preferences.windowManagement = value
            windowShortcutRegistrationError = nil
            return nil
        }
        var value = preferences.windowManagement
        value.shortcutsEnabled = true
        preferences.windowManagement = value
        let message = registerWindowShortcuts()
        windowShortcutRegistrationError = message
        return message
    }

    private func changeWindowShortcut(
        _ target: WindowShortcutTarget,
        to configuration: HotKeyConfiguration?
    ) -> WindowShortcutChangeResult {
        if let configuration {
            if configuration == preferences.hotKey {
                return .rejected("That shortcut already opens Broccoli.")
            }
            if let owner = preferences.windowManagement.owner(of: configuration, excluding: target) {
                return .rejected("That shortcut is already used by \(owner).")
            }
        }
        if preferences.windowManagement.shortcutsEnabled, !windowShortcutsPausedForIgnoredApp {
            if let configuration {
                do {
                    try registerWindowShortcut(target, configuration: configuration)
                } catch {
                    return .rejected(error.localizedDescription)
                }
            } else {
                hotKey.unregister(target.bindingID)
            }
        }
        var value = preferences.windowManagement
        value.setShortcut(configuration, for: target)
        preferences.windowManagement = value
        let message = registerWindowShortcutsIfEnabled()
        windowShortcutRegistrationError = message
        return .applied(registrationError: message)
    }

    /// Runs a window shortcut against the frontmost application's focused window.
    private func performWindowTarget(_ target: WindowShortcutTarget) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalApplication(frontmost)
        guard AccessibilityPermissionChecker.isTrusted else {
            showWindowManagementPermissionAlert()
            return
        }
        guard let request = windowManager.request(for: target) else {
            NSSound.beep()
            return
        }
        let targetPID = resolveWindowActionTarget(preferredApplication: frontmost)
        // A layout is latest-request-wins in the shared Accessibility worker. Cancel the
        // awaiting task as well so an older hot-key action cannot report or restore state after
        // a newer layout. Step actions queue instead, so each repeated press still applies.
        if !request.isIncremental {
            windowActionTask?.cancel()
        }
        windowActionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.windowManager.perform(request, targetPID: targetPID)
            } catch is CancellationError {
                return
            } catch {
                NSSound.beep()
            }
        }
    }

    private func captureWorkspace(named name: String) async -> String? {
        do {
            let entries = try await windowManager.captureWorkspace()
            var workspace = WindowWorkspace(name: name, entries: entries)
            workspace.sanitize()
            var value = preferences.windowManagement
            guard value.workspaces.count < WindowManagementPreferences.maximumWorkspaces else {
                return "Broccoli can keep up to \(WindowManagementPreferences.maximumWorkspaces) workspaces."
            }
            value.workspaces.append(workspace)
            preferences.windowManagement = value
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func showWindowManagementPermissionAlert() {
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
        } else {
            restoreLastExternalApplication()
        }
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return }
        lastExternalApplication = application
    }

    private func forgetExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              lastExternalApplication?.processIdentifier == application.processIdentifier else {
            return
        }
        lastExternalApplication = nil
    }

    private func resolveWindowActionTarget(
        preferredApplication: NSRunningApplication?
    ) -> pid_t? {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        return WindowActionTargetResolver.processIdentifier(
            candidates: [
                windowActionTargetCandidate(for: preferredApplication),
                windowActionTargetCandidate(for: frontmostApplication),
                windowActionTargetCandidate(for: lastExternalApplication),
            ].compactMap { $0 },
            broccoliBundleIdentifier: Bundle.main.bundleIdentifier,
            broccoliProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
    }

    private func windowActionTargetCandidate(
        for application: NSRunningApplication?
    ) -> WindowActionTargetCandidate? {
        guard let application else { return nil }
        return WindowActionTargetCandidate(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            isTerminated: application.isTerminated
        )
    }

    private func restoreLastExternalApplication() {
        guard let application = lastExternalApplication,
              !application.isTerminated else {
            lastExternalApplication = nil
            return
        }
        // Return to the previous app without raising every one of its windows across Spaces.
        // This mirrors a normal auxiliary Settings window closing rather than an app-wide
        // "bring all to front" command.
        application.activate(options: [])
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Broccoli-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await diagnosticsStore.export(to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}
