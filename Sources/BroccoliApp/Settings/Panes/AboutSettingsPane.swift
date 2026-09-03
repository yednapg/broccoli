@preconcurrency import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    @Bindable var updateCoordinator: UpdateCoordinator
    let onExportDiagnostics: () -> Void

    var body: some View {
        about
    }

    private var about: some View {
        Group {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Broccoli").font(.system(size: 24, weight: .semibold))
                    Text("Version \(appVersion) (\(appBuild))").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("A fast, private launcher for macOS.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            SpotlightSettingsCard("Information") {
                SpotlightSettingsRow(title: "Privacy") {
                    SettingsStatusAccessory(title: "Local Only", color: .green, showsIndicator: true)
                }
            }
            SpotlightSettingsCard("Updates") {
                SpotlightSettingsRow(
                    title: "Release Channel",
                    subtitle: updateCoordinator.channel == .stable
                        ? "Production releases only"
                        : "Stable and prerelease builds"
                ) {
                    Picker("", selection: $updateCoordinator.channel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                SpotlightSettingsRow(
                    title: "Automatic Checks",
                    subtitle: updateCoordinator.channel == .stable
                        ? "Checks at most every 24 hours"
                        : "Checks at most every 6 hours"
                ) {
                    Toggle("", isOn: Binding(
                        get: { updateCoordinator.automaticallyChecksForUpdates },
                        set: { updateCoordinator.automaticallyChecksForUpdates = $0 }
                    ))
                    .labelsHidden()
                    .disabled(!updateCoordinator.isConfigured)
                }
                SpotlightSettingsRow(
                    title: "Automatic Important Downloads",
                    subtitle: "Downloads important or critical updates only when Broccoli can update without an unexpected authorization prompt"
                ) {
                    Toggle("", isOn: $updateCoordinator.automaticallyDownloadsImportantUpdates)
                        .labelsHidden()
                }
                SpotlightSettingsRow(
                    title: "Last Check",
                    subtitle: lastCheckDescription
                ) {
                    SettingsStatusAccessory(
                        title: updateCoordinator.hasQuietBadge ? "Update Available" : updateCoordinator.phase.rawValue.capitalized,
                        color: updateCoordinator.hasQuietBadge ? .orange : statusColor,
                        showsIndicator: true
                    )
                }
                SpotlightSettingsRow(
                    title: "Update Status",
                    subtitle: updateCoordinator.statusMessage
                ) {
                    Button(updateCoordinator.hasQuietBadge ? "View Update" : "Check for Updates") {
                        if updateCoordinator.hasQuietBadge {
                            updateCoordinator.presentAvailableUpdate()
                        } else {
                            updateCoordinator.checkForUpdates()
                        }
                    }
                    .disabled(!updateCoordinator.isConfigured && !updateCoordinator.hasQuietBadge)
                    .spotlightSettingsProminentGlassButtonStyle()
                }
            }
            SpotlightSettingsCard("Support") {
                Button(action: onExportDiagnostics) {
                    SpotlightSettingsRow(symbol: "square.and.arrow.up", title: "Export Diagnostics", subtitle: "Create a sanitized local report") {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 3) {
                Text("© 2026 Gaurav Pandey. MIT License.")
                Text("No telemetry. No analytics. Your searches stay on this Mac.")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
    }

    private var lastCheckDescription: String {
        guard let date = updateCoordinator.lastCheckDate else { return "Never on this Mac" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var statusColor: Color {
        switch updateCoordinator.phase {
        case .failed: .red
        case .available, .ready: .orange
        case .completed, .current: .green
        default: .secondary
        }
    }

}
