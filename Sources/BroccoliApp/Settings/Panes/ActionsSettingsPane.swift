import SwiftUI

struct ActionsSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        actions
    }

    private var actions: some View {
        Group {
            ActionGroupCard(title: "Appearance & Audio", definitions: actionDefinitions(prefixes: ["appearance.", "audio."]), preferences: preferences)
            ActionGroupCard(title: "System", definitions: actionDefinitions(prefixes: ["screensaver.", "catalog."]), preferences: preferences)
            SpotlightSettingsCard("Recovery") {
                ForEach(recoveryActionDefinitions, id: \.id) { definition in
                    SpotlightSettingsRow(
                        symbol: SettingsActionIconSource.symbolName(for: definition),
                        title: definition.id == "broccoli.preferences"
                            ? "Open Broccoli Settings"
                            : definition.title,
                        subtitle: definition.id == "broccoli.preferences"
                            ? "Open this Settings window from launcher search"
                            : "Quit the background launcher"
                    ) {
                        SettingsStatusAccessory(title: "Always On", color: .green, showsIndicator: true)
                    }
                }
            }
            ActionGroupCard(
                title: "Power",
                subtitle: "These commands require a second Return within five seconds.",
                definitions: actionDefinitions(prefixes: ["power."]),
                preferences: preferences
            )
            SettingsFootnote(
                symbol: "lock.shield",
                text: "Protected appearance and power actions request Automation only when first used."
            )
        }
    }

    private var recoveryActionDefinitions: [ActionDefinition] {
        ActionRegistry.definitions.filter { ActionRegistry.recoveryActionIDs.contains($0.id) }
    }

    private func actionDefinitions(prefixes: [String]) -> [ActionDefinition] {
        ActionRegistry.configurableDefinitions.filter { definition in
            prefixes.contains { definition.id.hasPrefix($0) }
        }
    }


}
