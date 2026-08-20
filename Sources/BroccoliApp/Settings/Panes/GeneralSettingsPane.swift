@preconcurrency import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    let destination: SettingsDestination
    @ObservedObject var preferences: AppPreferences
    let initialShortcutError: String?
    let onShortcutChanged: (HotKeyConfiguration) -> String?
    let onNavigate: (SettingsDestination) -> Void

    @State private var shortcutStatus = ""
    @State private var shortcutRecordingRequest = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginMessage = ""
    @State private var launchAtLoginMessageStyle: LaunchAtLoginMessageStyle = .none
    @State private var launchAtLoginAvailable = SMAppService.mainApp.status != .notFound
    @State private var launchAtLoginRequiresApproval = false

    @ViewBuilder
    var body: some View {
        Group {
            if destination == .shortcutTroubleshooting {
                shortcutTroubleshooting
            } else {
                general
            }
        }
        .onAppear {
            if shortcutStatus.isEmpty {
                shortcutStatus = initialShortcutError ?? "Shortcut registered"
            }
            refreshLaunchAtLoginStatus()
        }
    }

    private var general: some View {
        Group {
            generalShortcutCard
            generalStartupCard
            generalLaunchAtLoginBanner
        }
    }

    private var generalShortcutCard: some View {
        SpotlightSettingsCard {
            SpotlightSettingsRow(
                symbol: "command",
                title: "Global Shortcut",
                subtitle: shortcutStatus == "Shortcut registered"
                    ? "Open Broccoli from anywhere"
                    : "Choose an available shortcut to open Broccoli"
            ) {
                ShortcutRecorderRepresentable(
                    configuration: preferences.hotKey,
                    recordingRequest: shortcutRecordingRequest,
                    onChange: applyShortcutChange
                )
                .frame(width: 132, height: 30)
                .accessibilityLabel("Global Shortcut")
                .accessibilityValue(preferences.hotKey.displayName)
            }
            SpotlightSettingsRow(
                symbol: shortcutStatus == "Shortcut registered"
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill",
                symbolColor: shortcutStatus == "Shortcut registered" ? .green : .red,
                title: shortcutStatus == "Shortcut registered"
                    ? "Shortcut registered"
                    : "Shortcut unavailable",
                subtitle: shortcutStatus == "Shortcut registered"
                    ? "Ready to open from any application"
                    : (shortcutStatus.isEmpty ? "Checking the current shortcut" : shortcutStatus)
            ) {
                Button("Change…") { shortcutRecordingRequest &+= 1 }
            }
            SettingsNavigationRow(
                symbol: "questionmark.circle",
                title: "Having shortcut trouble?",
                subtitle: "Resolve Spotlight conflicts or recover an invalid shortcut"
            ) {
                onNavigate(.shortcutTroubleshooting)
            }
        }
    }

    private var generalStartupCard: some View {
        SpotlightSettingsCard {
            SpotlightSettingsRow(
                symbol: "power",
                title: "Launch at Login",
                subtitle: launchAtLoginAvailable
                    ? "Start Broccoli automatically when you sign in"
                    : "Unavailable in this development build"
            ) {
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: updateLaunchAtLogin
                ))
                .labelsHidden()
                .disabled(!launchAtLoginAvailable)
                .settingsToggleAccessibility("Launch Broccoli at Login", isOn: launchAtLogin)
                .accessibilityHint(
                    launchAtLoginAvailable
                        ? "Starts Broccoli after you sign in."
                        : "Unavailable in this build."
                )
            }
        }
    }

    @ViewBuilder private var generalLaunchAtLoginBanner: some View {
        if shouldShowLaunchAtLoginBanner {
            if launchAtLoginRequiresApproval {
                SettingsInfoBanner(
                    symbol: launchAtLoginMessageStyle.symbol,
                    message: launchAtLoginMessage,
                    color: launchAtLoginMessageStyle.color,
                    actionTitle: "Open Login Items…",
                    action: openLoginItemsSettings
                )
            } else {
                SettingsInfoBanner(
                    symbol: launchAtLoginMessageStyle.symbol,
                    message: launchAtLoginMessage,
                    color: launchAtLoginMessageStyle.color
                )
            }
        }
    }

    private var shouldShowLaunchAtLoginBanner: Bool {
        !launchAtLoginMessage.isEmpty
            && (launchAtLoginAvailable || launchAtLoginMessageStyle == .error)
    }

    private func applyShortcutChange(_ value: HotKeyConfiguration) -> Bool {
        if let error = onShortcutChanged(value) {
            shortcutStatus = error
            return false
        }
        preferences.hotKey = value
        shortcutStatus = "Shortcut registered"
        return true
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginMessage = "Couldn’t change Launch at Login: \(error.localizedDescription)"
            launchAtLoginMessageStyle = .error
        }
    }

    private var shortcutTroubleshooting: some View {
        Group {
            SettingsDestinationIntro("Resolve a conflicting or unavailable global shortcut.")
            SpotlightSettingsCard("Current Shortcut") {
                SpotlightSettingsRow(symbol: "keyboard", title: preferences.hotKey.displayName, subtitle: shortcutStatus) {
                    Button("Retry") {
                        if let error = onShortcutChanged(preferences.hotKey) {
                            shortcutStatus = error
                        } else {
                            shortcutStatus = "Shortcut registered"
                        }
                    }
                }
            }
            SpotlightSettingsCard("Spotlight Conflict") {
                Button(action: openKeyboardShortcuts) {
                    SpotlightSettingsRow(
                        symbol: "1.circle",
                        title: "Open Keyboard Shortcuts",
                        subtitle: "Choose Spotlight in the sidebar."
                    ) {
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                SpotlightSettingsRow(
                    symbol: "2.circle",
                    title: "Turn Off “Show Spotlight Search”",
                    subtitle: "This releases Command-Space for Broccoli."
                )
                SpotlightSettingsRow(
                    symbol: "3.circle",
                    title: "Return Here and Retry",
                    subtitle: "The launcher needs no permission; only window actions use \(WindowManagementPermissionPresentation.settingsName)."
                )
            }
            SettingsFootnote(
                symbol: "hand.raised",
                text: "Changing this setting only opens System Settings; Broccoli never edits macOS shortcuts automatically."
            )
        }
    }

    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginAvailable = status != .notFound
        launchAtLoginRequiresApproval = status == .requiresApproval
        switch status {
        case .enabled, .notRegistered:
            launchAtLoginMessage = ""
            launchAtLoginMessageStyle = .none
        case .requiresApproval:
            launchAtLoginMessage = "Approval is required in System Settings → General → Login Items."
            launchAtLoginMessageStyle = .information
        case .notFound:
            launchAtLoginMessage = "Launch at Login is unavailable in this build."
            launchAtLoginMessageStyle = .information
        @unknown default:
            launchAtLoginAvailable = false
            launchAtLoginMessage = "macOS returned an unknown Launch at Login status."
            launchAtLoginMessageStyle = .error
        }
    }

    private func openKeyboardShortcuts() {
        if let route = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
        ), NSWorkspace.shared.open(route) {
            return
        }
        openSystemSettingsHome()
    }

    private func openLoginItemsSettings() {
        if let route = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ), NSWorkspace.shared.open(route) {
            return
        }
        openSystemSettingsHome()
    }

    private func openSystemSettingsHome() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: .init()
        )
    }


}
