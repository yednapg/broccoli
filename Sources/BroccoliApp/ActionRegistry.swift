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
    static let recoveryActionIDs: Set<String> = ["broccoli.preferences", "broccoli.quit"]
    static let recoveryEntryIDs: Set<String> = Set(recoveryActionIDs.map { "action:\($0)" })
    static let definitions: [ActionDefinition] = [
        ActionDefinition(id: "appearance.toggleDark", title: "Toggle Dark Mode", aliases: ["appearance", "theme", "light mode"], risk: .safe, permission: .automation, keepsPanelOpen: false),
        ActionDefinition(id: "audio.toggleMute", title: "Mute or Unmute", aliases: ["audio", "sound", "silent"], risk: .safe, permission: .none, keepsPanelOpen: false),
        ActionDefinition(id: "audio.volumeUp", title: "Volume Up", aliases: ["audio", "sound", "louder", "increase volume"], risk: .safe, permission: .none, keepsPanelOpen: true),
        ActionDefinition(id: "audio.volumeDown", title: "Volume Down", aliases: ["audio", "sound", "quieter", "decrease volume"], risk: .safe, permission: .none, keepsPanelOpen: true),
        ActionDefinition(id: "screensaver.start", title: "Start Screen Saver", aliases: ["screen saver", "display", "idle"], risk: .safe, permission: .none, keepsPanelOpen: false),
        ActionDefinition(id: "window.leftHalf", title: "Left Half", aliases: ["window left", "snap left", "tile left"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.rightHalf", title: "Right Half", aliases: ["window right", "snap right", "tile right"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.topHalf", title: "Top Half", aliases: ["window top", "snap top", "tile top"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.bottomHalf", title: "Bottom Half", aliases: ["window bottom", "snap bottom", "tile bottom"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.maximize", title: "Maximize Window", aliases: ["window full", "fill screen", "zoom window"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.minimized", title: "Minimized", aliases: ["window minimized", "minimize window", "shrink window", "restore down"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.center", title: "Center Window", aliases: ["window center", "recenter"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.nextDisplay", title: "Move to Next Display", aliases: ["window next monitor", "move display", "next screen"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
        ActionDefinition(id: "window.previousDisplay", title: "Move to Previous Display", aliases: ["window previous monitor", "previous screen"], risk: .safe, permission: .accessibility, keepsPanelOpen: false),
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

    static var searchEntries: [SearchEntry] { definitions.map(\.searchEntry) }

    static func searchEntries(
        actionsEnabled: Bool = true,
        enabledActionIDs: Set<String>
    ) -> [SearchEntry] {
        definitions.compactMap { definition in
            guard recoveryActionIDs.contains(definition.id)
                    || (actionsEnabled && enabledActionIDs.contains(definition.id)) else { return nil }
            return definition.searchEntry
        }
    }

    static func definition(id: String) -> ActionDefinition? {
        definitions.first { $0.id == id }
    }
}
