import Carbon
import Combine
import Foundation
import BroccoliCore

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let applicationsEnabled = "search.applicationsEnabled"
        static let settingsEnabled = "search.settingsEnabled"
        static let actionsEnabled = "search.actionsEnabled"
        static let recentItemsEnabled = "search.recentItemsEnabled"
        static let adaptiveRankingEnabled = "search.adaptiveRankingEnabled"
        static let hotKey = "shortcut.configuration"
        static let appearance = "appearance.configuration.v1"
        static let fileSearch = "files.configuration.v1"
        static let calculator = "calculator.configuration.v1"
        static let clipboard = "clipboard.configuration.v1"
        static let enabledActionIDs = "actions.enabledIDs.v1"
        static let windowManagement = "windowManagement.configuration.v1"
    }

    private let defaults: UserDefaults

    @Published var applicationsEnabled: Bool { didSet { save(applicationsEnabled, Key.applicationsEnabled) } }
    @Published var settingsEnabled: Bool { didSet { save(settingsEnabled, Key.settingsEnabled) } }
    @Published var actionsEnabled: Bool { didSet { save(actionsEnabled, Key.actionsEnabled) } }
    @Published var recentItemsEnabled: Bool { didSet { save(recentItemsEnabled, Key.recentItemsEnabled) } }
    @Published var adaptiveRankingEnabled: Bool { didSet { save(adaptiveRankingEnabled, Key.adaptiveRankingEnabled) } }
    @Published var hotKey: HotKeyConfiguration { didSet { saveHotKey() } }
    @Published var appearance: LauncherAppearancePreferences {
        didSet {
            save(appearance, Key.appearance)
        }
    }
    @Published var fileSearch: FileSearchPreferences { didSet { save(fileSearch, Key.fileSearch) } }
    @Published var calculator: CalculatorPreferences { didSet { save(calculator, Key.calculator) } }
    @Published var clipboard: ClipboardPreferences { didSet { save(clipboard, Key.clipboard) } }
    @Published var enabledActionIDs: Set<String> { didSet { save(enabledActionIDs, Key.enabledActionIDs) } }
    @Published var windowManagement: WindowManagementPreferences {
        didSet { save(windowManagement, Key.windowManagement) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.applicationsEnabled: true,
            Key.settingsEnabled: true,
            Key.actionsEnabled: true,
            Key.recentItemsEnabled: false,
            Key.adaptiveRankingEnabled: true,
        ])
        applicationsEnabled = defaults.bool(forKey: Key.applicationsEnabled)
        settingsEnabled = defaults.bool(forKey: Key.settingsEnabled)
        actionsEnabled = defaults.bool(forKey: Key.actionsEnabled)
        recentItemsEnabled = defaults.bool(forKey: Key.recentItemsEnabled)
        adaptiveRankingEnabled = defaults.bool(forKey: Key.adaptiveRankingEnabled)
        var loadedAppearance = Self.load(
            LauncherAppearancePreferences.self,
            key: Key.appearance,
            defaults: defaults
        ) ?? .defaults(design: .liquidGlass)
        loadedAppearance.sanitize()
        appearance = loadedAppearance
        fileSearch = Self.load(FileSearchPreferences.self, key: Key.fileSearch, defaults: defaults)
            ?? FileSearchPreferences()
        var loadedCalculator = Self.load(
            CalculatorPreferences.self,
            key: Key.calculator,
            defaults: defaults
        ) ?? CalculatorPreferences()
        loadedCalculator.sanitize()
        calculator = loadedCalculator
        var loadedClipboard = Self.load(ClipboardPreferences.self, key: Key.clipboard, defaults: defaults)
            ?? ClipboardPreferences()
        loadedClipboard.sanitize()
        clipboard = loadedClipboard
        var loadedWindowManagement = Self.load(
            WindowManagementPreferences.self,
            key: Key.windowManagement,
            defaults: defaults
        ) ?? WindowManagementPreferences()
        loadedWindowManagement.migrateInterimDefaultShortcuts()
        windowManagement = loadedWindowManagement
        var loadedActionIDs = Self.load(
            Set<String>.self,
            key: Key.enabledActionIDs,
            defaults: defaults
        ) ?? ActionRegistry.defaultEnabledActionIDs
        // Window actions were added after per-action preferences shipped. They have their own
        // Settings page, so make them searchable for existing installs without disturbing any
        // earlier action choices the user made.
        loadedActionIDs.formUnion(WindowAction.allCases.map(\.actionID))
        enabledActionIDs = loadedActionIDs
        if let data = defaults.data(forKey: Key.hotKey),
           let decoded = try? PropertyListDecoder().decode(HotKeyConfiguration.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = .commandSpace
        }
    }

    var searchPreferences: SearchPreferences {
        SearchPreferences(
            applicationsEnabled: applicationsEnabled,
            settingsEnabled: settingsEnabled,
            actionsEnabled: actionsEnabled,
            recentItemsEnabled: recentItemsEnabled,
            adaptiveRankingEnabled: adaptiveRankingEnabled,
            alwaysIncludedEntryIDs: ActionRegistry.recoveryEntryIDs
        )
    }

    private func save(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveHotKey() {
        guard let data = try? PropertyListEncoder().encode(hotKey) else { return }
        defaults.set(data, forKey: Key.hotKey)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? PropertyListEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? PropertyListDecoder().decode(type, from: data)
    }

}
