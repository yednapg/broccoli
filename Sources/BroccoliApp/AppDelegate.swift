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
    typealias ImageLoader = (String) -> NSImage?
    typealias ImageSetter = (NSImage) -> Void

    private let imageLoader: ImageLoader
    private let imageSetter: ImageSetter
    private(set) var resourceName: String?
    private var image: NSImage?

    init(
        imageLoader: @escaping ImageLoader = { resourceName in
            guard let iconURL = Bundle.main.url(forResource: resourceName, withExtension: "png")
            else { return nil }
            return NSImage(contentsOf: iconURL)
        },
        imageSetter: @escaping ImageSetter = { image in
            NSApp.applicationIconImage = image
        }
    ) {
        self.imageLoader = imageLoader
        self.imageSetter = imageSetter
    }

    func update(for appearance: NSAppearance) {
        let resourceName = ApplicationIconResource.name(for: appearance)
        guard let image = imageLoader(resourceName) else { return }
        image.isTemplate = false
        self.resourceName = resourceName
        self.image = image
        imageSetter(image)
    }

    func reapplyCurrentImage() {
        guard let image else { return }
        imageSetter(image)
    }
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
    private var supportDirectory: URL!
    private var shortcutRegistrationError: String?
    private var windowShortcutRegistrationError: String?
    private var windowActionTask: Task<Void, Never>?
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
            onWindowShortcutChanged: { [weak self] action, configuration in
                self?.changeWindowShortcut(action, to: configuration)
            },
            onWindowShortcutsEnabledChanged: { [weak self] enabled in
                self?.setWindowShortcutsEnabled(enabled)
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
        // NSApp can briefly retain Aqua while an accessory app is becoming regular. The
        // attached window already owns the correct system appearance, so use it to choose the
        // Dock/About icon as soon as Settings enters the window hierarchy.
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
        // Changing activation policy rebuilds the Dock tile and can momentarily restore the
        // bundle icon. Reapply the already-resolved appearance-specific image afterward.
        applicationIconController.reapplyCurrentImage()
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
            }
        })
    }

    private func observeDisplayPreferences() {
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
        let appearance = settingsWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        applicationIconController.update(for: appearance)
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
        guard preferences.windowManagement.shortcutsEnabled else {
            unregisterWindowShortcuts()
            return nil
        }
        do {
            for action in WindowAction.allCases {
                try registerWindowShortcut(
                    action,
                    configuration: preferences.windowManagement.shortcut(for: action)
                )
            }
            return nil
        } catch {
            unregisterWindowShortcuts()
            return error.localizedDescription
        }
    }

    private func registerWindowShortcut(
        _ action: WindowAction,
        configuration: HotKeyConfiguration
    ) throws {
        try hotKey.register(configuration, for: action.hotKeyBindingID) { [weak self] in
            self?.performWindowAction(action)
        }
    }

    private func unregisterWindowShortcuts() {
        for action in WindowAction.allCases { hotKey.unregister(action.hotKeyBindingID) }
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
        do {
            for action in WindowAction.allCases {
                try registerWindowShortcut(
                    action,
                    configuration: preferences.windowManagement.shortcut(for: action)
                )
            }
            var value = preferences.windowManagement
            value.shortcutsEnabled = true
            preferences.windowManagement = value
            windowShortcutRegistrationError = nil
            return nil
        } catch {
            unregisterWindowShortcuts()
            let message = error.localizedDescription
            windowShortcutRegistrationError = message
            return message
        }
    }

    private func changeWindowShortcut(
        _ action: WindowAction,
        to configuration: HotKeyConfiguration
    ) -> String? {
        if preferences.windowManagement.shortcutsEnabled {
            do {
                try registerWindowShortcut(action, configuration: configuration)
            } catch {
                let message = error.localizedDescription
                windowShortcutRegistrationError = message
                return message
            }
        }
        var value = preferences.windowManagement
        value.shortcuts[action] = configuration
        preferences.windowManagement = value
        windowShortcutRegistrationError = nil
        return nil
    }

    private func performWindowAction(_ action: WindowAction) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        rememberExternalApplication(frontmost)
        guard AccessibilityPermissionChecker.isTrusted else {
            showWindowManagementPermissionAlert()
            return
        }
        let targetPID = resolveWindowActionTarget(preferredApplication: frontmost)
        // The shared Accessibility worker is latest-request-wins. Cancel the awaiting task as
        // well so an older hot-key action cannot report or restore state after a newer layout.
        windowActionTask?.cancel()
        windowActionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.windowManager.perform(action, targetPID: targetPID)
            } catch is CancellationError {
                return
            } catch {
                NSSound.beep()
            }
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
