import SwiftUI

struct SearchSettingsPane: View {
    @ObservedObject var preferences: AppPreferences
    let onClearUsage: () -> Void

    @State private var confirmClearUsage = false

    var body: some View {
        search
            .alert("Clear Learned Usage?", isPresented: $confirmClearUsage) {
                Button("Cancel", role: .cancel) {}
                Button("Clear Learned Usage", role: .destructive, action: onClearUsage)
            } message: {
                Text("This resets local result ranking. Your preferences and clipboard history are not affected.")
            }
    }

    private var search: some View {
        Group {
            SpotlightSettingsCard("Result Sources") {
                SpotlightSettingsRow(symbol: "app", title: "Applications", subtitle: "Installed apps from standard folders and Spotlight discovery") {
                    Toggle("", isOn: $preferences.applicationsEnabled)
                        .labelsHidden()
                        .settingsToggleAccessibility("Include Applications", isOn: preferences.applicationsEnabled)
                }
                SpotlightSettingsRow(symbol: "gearshape", title: "System Settings", subtitle: "Settings panes and common destinations") {
                    Toggle("", isOn: $preferences.settingsEnabled)
                        .labelsHidden()
                        .settingsToggleAccessibility("Include System Settings", isOn: preferences.settingsEnabled)
                }
                SpotlightSettingsRow(symbol: "bolt", title: "System Actions", subtitle: "Built-in audited commands") {
                    Toggle("", isOn: $preferences.actionsEnabled)
                        .labelsHidden()
                        .settingsToggleAccessibility("Include System Actions", isOn: preferences.actionsEnabled)
                }
            }
            SpotlightSettingsCard("Suggestions") {
                SpotlightSettingsRow(title: "Recent Selections", subtitle: "Show recent items when the search field is empty") {
                    Toggle("", isOn: $preferences.recentItemsEnabled)
                        .labelsHidden()
                        .settingsToggleAccessibility("Show Recent Selections", isOn: preferences.recentItemsEnabled)
                }
                SpotlightSettingsRow(title: "Adaptive Ranking", subtitle: "Improve ordering from selections stored only on this Mac") {
                    Toggle("", isOn: $preferences.adaptiveRankingEnabled)
                        .labelsHidden()
                        .settingsToggleAccessibility("Use Adaptive Ranking", isOn: preferences.adaptiveRankingEnabled)
                }
                Button { confirmClearUsage = true } label: {
                    SpotlightSettingsRow(
                        symbol: "trash",
                        title: "Clear Learned Usage…",
                        subtitle: "Return result ordering to its default state"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            SettingsFootnote(
                symbol: "lock.fill",
                text: "Search queries are never saved or sent off this Mac."
            )
        }
    }


}

