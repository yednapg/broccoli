@preconcurrency import AppKit
import SwiftUI

struct PermissionsSettingsPane: View {
    let destination: SettingsDestination
    @ObservedObject var preferences: AppPreferences
    let onClearUsage: () -> Void
    let onExportDiagnostics: () -> Void
    let onNavigate: (SettingsDestination) -> Void

    @State private var confirmClearUsage = false
    @State private var automationPermission: AutomationPermissionState = .checking

    @ViewBuilder
    var body: some View {
        Group {
            if destination == .automation {
                automationDestination
            } else {
                privacy
            }
        }
        .alert("Clear Learned Usage?", isPresented: $confirmClearUsage) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Learned Usage", role: .destructive, action: onClearUsage)
        } message: {
            Text("This resets local result ranking. Your preferences and clipboard history are not affected.")
        }
        .task {
            automationPermission = await AutomationPermissionChecker.current()
        }
    }

    private var privacy: some View {
        Group {
            SpotlightSettingsCard("Permissions") {
                Button { onNavigate(.automation) } label: {
                    SpotlightSettingsRow(symbol: "gearshape.2", title: "Automation", subtitle: "Required only for appearance and confirmed power actions") {
                        HStack(spacing: 6) {
                            SettingsStatusAccessory(
                                title: automationPermission.shortTitle,
                                color: automationPermission.statusColor,
                                showsIndicator: true
                            )
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
                SpotlightSettingsRow(
                    symbol: "accessibility",
                    title: "Window Control",
                    subtitle: "Managed in \(WindowManagementPermissionPresentation.settingsName)"
                ) {
                    SettingsStatusAccessory(
                        title: AccessibilityPermissionChecker.isTrusted ? "Granted" : "On Demand",
                        color: AccessibilityPermissionChecker.isTrusted ? .green : .secondary,
                        showsIndicator: true
                    )
                }
                SpotlightSettingsRow(symbol: "folder", title: "Files & Folders", subtitle: "Availability is checked when a file query starts") {
                    SettingsStatusAccessory(title: "On Demand", color: .secondary, showsIndicator: true)
                }
            }
            SpotlightSettingsCard("Local Data") {
                SpotlightSettingsRow(symbol: "waveform.path.ecg", title: "Learned Usage", subtitle: "Selection counts used for adaptive ranking") {
                    Button("Clear…") { confirmClearUsage = true }
                }
                SpotlightSettingsRow(symbol: "clipboard", title: "Clipboard History", subtitle: "Encrypted locally when enabled") {
                    SettingsStatusAccessory(
                        title: preferences.clipboard.enabled ? "On" : "Off",
                        color: preferences.clipboard.enabled ? .green : .secondary,
                        showsIndicator: true
                    )
                }
                SpotlightSettingsRow(symbol: "internaldrive", title: "Application Catalog", subtitle: "Cached locally for faster startup") {
                    SettingsStatusAccessory(title: "Local", color: .green, showsIndicator: true)
                }
            }
            SpotlightSettingsCard("Diagnostics") {
                Button(action: onExportDiagnostics) {
                    SpotlightSettingsRow(
                        symbol: "square.and.arrow.up",
                        title: "Export Diagnostics",
                        subtitle: "JSON without queries, titles, paths, or clipboard data"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            SettingsFootnote(
                symbol: "lock.fill",
                text: "Broccoli sends no telemetry, analytics, queries, or usage history."
            )
        }
    }

    private var automationDestination: some View {
        Group {
            SettingsDestinationIntro(
                "Broccoli asks only when a protected action is used for the first time."
            )
            SpotlightSettingsCard("System Events") {
                AutomationStatusRow(state: automationPermission)
                    .frame(minHeight: 54)
                SpotlightSettingsRow(
                    symbol: "circle.lefthalf.filled",
                    title: "Protected Actions",
                    subtitle: "Dark Mode and confirmed power actions require Automation"
                ) {
                    SettingsStatusAccessory(title: "On First Use", color: .orange, showsIndicator: true)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Refresh Status", action: refreshAutomationPermission)
                if automationPermission == .denied {
                    Button("Open Privacy Settings…", action: openAutomationSettings)
                        .spotlightSettingsProminentGlassButtonStyle()
                }
            }
            SettingsFootnote(
                symbol: "lock.open",
                text: "Search, application launching, audio controls, and file search do not require Automation."
            )
        }
    }

    private func refreshAutomationPermission() {
        automationPermission = .checking
        Task { automationPermission = await AutomationPermissionChecker.current() }
    }

    private func openAutomationSettings() {
        if let route = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
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

