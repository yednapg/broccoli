@preconcurrency import AppKit
import BroccoliCore
import Foundation

enum ActionRisk: Sendable, Equatable {
    case safe
    case disruptive
}

enum ActionPermission: Sendable, Equatable {
    case none
    case automation
    case accessibility
}

struct ActionDefinition: Sendable {
    let id: String
    let title: String
    let aliases: [String]
    let risk: ActionRisk
    let permission: ActionPermission
    let keepsPanelOpen: Bool

    var searchEntry: SearchEntry {
        SearchEntry(
            id: "action:\(id)",
            kind: .action,
            title: title,
            subtitle: risk == .disruptive ? "Power Action" : "Action",
            keywords: aliases,
            iconKey: "action:\(id)",
            target: .action(id: id)
        )
    }
}

enum ActionRegistry {
    static let appearanceToggleID = "appearance.toggleDark"
    static let recoveryActionIDs: Set<String> = ["broccoli.preferences", "broccoli.quit"]
    static let recoveryEntryIDs: Set<String> = Set(recoveryActionIDs.map { "action:\($0)" })
    static let definitions: [ActionDefinition] = [
        ActionDefinition(id: appearanceToggleID, title: "Switch Light / Dark Mode", aliases: ["appearance", "theme", "light mode", "dark mode"], risk: .safe, permission: .automation, keepsPanelOpen: false),
        ActionDefinition(id: "audio.toggleMute", title: "Mute or Unmute", aliases: ["audio", "sound", "silent"], risk: .safe, permission: .none, keepsPanelOpen: false),
        ActionDefinition(id: "audio.volumeUp", title: "Volume Up", aliases: ["audio", "sound", "louder", "increase volume"], risk: .safe, permission: .none, keepsPanelOpen: true),
        ActionDefinition(id: "audio.volumeDown", title: "Volume Down", aliases: ["audio", "sound", "quieter", "decrease volume"], risk: .safe, permission: .none, keepsPanelOpen: true),
        ActionDefinition(id: "screensaver.start", title: "Start Screen Saver", aliases: ["screen saver", "display", "idle"], risk: .safe, permission: .none, keepsPanelOpen: false),
    ] + WindowAction.allCases.map { action in
        ActionDefinition(id: action.actionID, title: action.title, aliases: action.aliases, risk: .safe, permission: .accessibility, keepsPanelOpen: false)
    } + [
        ActionDefinition(id: "catalog.refresh", title: "Refresh Applications", aliases: ["reload", "reindex", "apps"], risk: .safe, permission: .none, keepsPanelOpen: false),
        ActionDefinition(id: "broccoli.preferences", title: "Open Broccoli Settings", aliases: ["preferences", "settings", "options"], risk: .safe, permission: .none, keepsPanelOpen: false),
        ActionDefinition(id: "broccoli.quit", title: "Quit Broccoli", aliases: ["exit", "close launcher"], risk: .safe, permission: .none, keepsPanelOpen: false),
        ActionDefinition(id: "power.sleep", title: "Sleep", aliases: ["power", "suspend"], risk: .disruptive, permission: .automation, keepsPanelOpen: false),
        ActionDefinition(id: "power.restart", title: "Restart", aliases: ["power", "reboot"], risk: .disruptive, permission: .automation, keepsPanelOpen: false),
        ActionDefinition(id: "power.shutdown", title: "Shut Down", aliases: ["power", "turn off", "power off"], risk: .disruptive, permission: .automation, keepsPanelOpen: false),
        ActionDefinition(id: "power.logout", title: "Log Out", aliases: ["power", "sign out"], risk: .disruptive, permission: .automation, keepsPanelOpen: false),
    ]

    static var configurableDefinitions: [ActionDefinition] {
        definitions.filter { !recoveryActionIDs.contains($0.id) }
    }

    static var defaultEnabledActionIDs: Set<String> {
        Set(configurableDefinitions.map(\.id))
    }

    static var searchEntries: [SearchEntry] {
        searchEntries(isDarkMode: false)
    }

    static func searchEntries(isDarkMode: Bool) -> [SearchEntry] {
        definitions.map { searchDefinition($0, isDarkMode: isDarkMode).searchEntry }
    }

    static func searchEntries(
        actionsEnabled: Bool = true,
        enabledActionIDs: Set<String>,
        isDarkMode: Bool = false
    ) -> [SearchEntry] {
        definitions.compactMap { definition in
            guard recoveryActionIDs.contains(definition.id)
                    || (actionsEnabled && enabledActionIDs.contains(definition.id)) else { return nil }
            return searchDefinition(definition, isDarkMode: isDarkMode).searchEntry
        }
    }

    static func definition(id: String) -> ActionDefinition? {
        definitions.first { $0.id == id }
    }

    /// Search snapshots can outlive a system appearance change. Resolve stateful wording
    /// when publishing results too, so an older search cannot put the opposite label back.
    static func resolvingSystemAppearance(
        in results: [RankedResult], isDarkMode: @autoclosure () -> Bool
    ) -> [RankedResult] {
        guard let index = results.firstIndex(where: { $0.entry.target == .action(id: appearanceToggleID) }),
              let definition = definition(id: appearanceToggleID) else { return results }
        let current = searchDefinition(definition, isDarkMode: isDarkMode())
        guard results[index].entry.title != current.title else { return results }
        var updated = results
        updated[index] = RankedResult(entry: current.searchEntry, score: results[index].score)
        return updated
    }

    private static func searchDefinition(
        _ definition: ActionDefinition,
        isDarkMode: Bool
    ) -> ActionDefinition {
        guard definition.id == appearanceToggleID else { return definition }
        return ActionDefinition(
            id: definition.id,
            title: isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
            aliases: definition.aliases,
            risk: definition.risk,
            permission: definition.permission,
            keepsPanelOpen: definition.keepsPanelOpen
        )
    }
}
