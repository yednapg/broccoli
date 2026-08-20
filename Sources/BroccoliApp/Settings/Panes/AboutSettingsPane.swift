@preconcurrency import AppKit
import SwiftUI

struct AboutSettingsPane: View {
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

}
