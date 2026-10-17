@preconcurrency import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import Observation

enum PreferencesSection: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, search, files, calculator, clipboard, windows, actions, privacy, about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .search: "Search"
        case .files: "Files"
        case .calculator: "Calculator"
        case .clipboard: "Clipboard"
        case .windows: "Window Management"
        case .actions: "Actions"
        case .privacy: "Permissions"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .search: "magnifyingglass"
        case .files: "folder.fill"
        case .calculator: "function"
        case .clipboard: "clipboard.fill"
        case .windows: "macwindow"
        case .actions: "bolt.fill"
        case .privacy: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }
}

enum SettingsDestination: Hashable {
    case section(PreferencesSection)
    case shortcutTroubleshooting
    case launcherPreview
    case excludedLocations
    case ignoredApplications
    case automation

    var section: PreferencesSection {
        switch self {
        case .section(let section): section
        case .shortcutTroubleshooting: .general
        case .launcherPreview: .appearance
        case .excludedLocations: .files
        case .ignoredApplications: .clipboard
        case .automation: .privacy
        }
    }

    var title: String {
        switch self {
        case .section(let section): section.title
        case .shortcutTroubleshooting: "Shortcut Troubleshooting"
        case .launcherPreview: "Launcher Preview"
        case .excludedLocations: "Excluded Locations"
        case .ignoredApplications: "Ignored Applications"
        case .automation: "Automation"
        }
    }
}

enum LaunchAtLoginMessageStyle: Equatable {
    case none
    case information
    case error

    var symbol: String {
        switch self {
        case .none, .information: "info.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .none, .information: .secondary
        case .error: .red
        }
    }
}

enum SettingsShellLayout {
    // Cherry's reference Settings window uses a 209-point sidebar inside a 980-point scene.
    // The compatibility split view and the native scene's initial split position share it.
    static let sidebarWidth: CGFloat = 209
    static let contentWidth: CGFloat = 980
    static let searchFieldControlSize: NSControl.ControlSize = .extraLarge
    static let sidebarLabelFontSize: CGFloat = 14
    static let searchFieldFontSize = sidebarLabelFontSize
    static let sidebarRowContentHeight: CGFloat = 28
    static let sidebarIconCanvasSize: CGFloat = 18
    static let sidebarIconTrailingPadding: CGFloat = 3
}

enum SettingsWindowGeometry {
    static let initialContentSize = NSSize(width: SettingsShellLayout.contentWidth, height: 680)
}

enum SettingsPaneRestoration {
    static let defaultsKey = "settings.lastPane"

    static func restoredSection(from defaults: UserDefaults) -> PreferencesSection {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let section = PreferencesSection(rawValue: rawValue) else {
            return .general
        }
        return section
    }

    static func save(_ section: PreferencesSection, to defaults: UserDefaults) {
        defaults.set(section.rawValue, forKey: defaultsKey)
    }
}

enum IgnoredApplicationsCopy {
    static func invalidSelectionMessage(count: Int) -> String? {
        guard count > 0 else { return nil }
        let noun = count == 1 ? "application" : "applications"
        return "\(count) selected \(noun) did not provide a valid bundle identifier and \(count == 1 ? "was" : "were") not added."
    }
}

struct IgnoredApplicationDraft: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage
    let isResolved: Bool

    var id: String { bundleIdentifier }
}

/// Shared state for the native Settings sidebar, search, and drill-down navigation.
@MainActor
@Observable
final class SettingsShellModel {
    private(set) var selection: PreferencesSection
    private(set) var destination: SettingsDestination
    private(set) var backHistory: [SettingsDestination] = []
    private(set) var forwardHistory: [SettingsDestination] = []
    var searchQuery = "" {
        didSet { presentationDidChange?() }
    }
    var isSearchPresented = false

    /// AppKit uses this lightweight callback to keep native toolbar controls synchronized.
    /// SwiftUI continues to observe the published values directly.
    @ObservationIgnored var presentationDidChange: (() -> Void)?
    @ObservationIgnored var selectionDidChange: ((PreferencesSection) -> Void)?

    init(initialSection: PreferencesSection = .general) {
        selection = initialSection
        destination = .section(initialSection)
    }

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }
    var sidebarSelection: PreferencesSection? {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? selection
            : nil
    }

    /// Sidebar changes represent a new top-level context and intentionally reset detail
    /// history. Drill-down rows use `navigate(to:)` so Back and Forward remain meaningful.
    func selectSection(_ section: PreferencesSection, clearingSearch: Bool = true) {
        selection = section
        destination = .section(section)
        backHistory.removeAll(keepingCapacity: true)
        forwardHistory.removeAll(keepingCapacity: true)
        if clearingSearch {
            searchQuery = ""
            isSearchPresented = false
        }
        selectionDidChange?(section)
        presentationDidChange?()
    }

    func navigate(to destination: SettingsDestination) {
        guard destination != self.destination else { return }
        backHistory.append(self.destination)
        forwardHistory.removeAll(keepingCapacity: true)
        self.destination = destination
        selection = destination.section
        selectionDidChange?(destination.section)
        presentationDidChange?()
    }

    func goBack() {
        guard let destination = backHistory.popLast() else { return }
        forwardHistory.append(self.destination)
        self.destination = destination
        selection = destination.section
        selectionDidChange?(destination.section)
        presentationDidChange?()
    }

    func goForward() {
        guard let destination = forwardHistory.popLast() else { return }
        backHistory.append(self.destination)
        self.destination = destination
        selection = destination.section
        selectionDidChange?(destination.section)
        presentationDidChange?()
    }
}

/// Dependencies and persistent navigation state owned by Broccoli's native SwiftUI Settings
/// scene. The scene, rather than an AppKit window controller, now owns the Settings window.
@MainActor
final class BroccoliSettingsContext {
    let shell: SettingsShellModel
    let preferences: AppPreferences
    let initialShortcutError: String?
    let onShortcutChanged: (HotKeyConfiguration) -> String?
    let initialWindowShortcutError: String?
    let onWindowShortcutChanged: (WindowShortcutTarget, HotKeyConfiguration?) -> WindowShortcutChangeResult
    let onWindowShortcutsEnabledChanged: (Bool) -> String?
    let onUseRecommendedWindowShortcuts: () -> String?
    let onCaptureWorkspace: (String) async -> String?
    let onClearUsage: () -> Void
    let onClearClipboard: () -> Void
    let onExportDiagnostics: () -> Void
    let previewRenderer: LauncherPreviewRenderer
    let onWindowAttached: (NSWindow) -> Void

    init(
        preferences: AppPreferences,
        initialShortcutError: String?,
        onShortcutChanged: @escaping (HotKeyConfiguration) -> String?,
        initialWindowShortcutError: String?,
        onWindowShortcutChanged: @escaping (WindowShortcutTarget, HotKeyConfiguration?) -> WindowShortcutChangeResult,
        onWindowShortcutsEnabledChanged: @escaping (Bool) -> String?,
        onUseRecommendedWindowShortcuts: @escaping () -> String?,
        onCaptureWorkspace: @escaping (String) async -> String?,
        onClearUsage: @escaping () -> Void,
        onClearClipboard: @escaping () -> Void,
        onExportDiagnostics: @escaping () -> Void,
        onWindowAttached: @escaping (NSWindow) -> Void,
        restorationDefaults: UserDefaults = .standard
    ) {
        let shell = SettingsShellModel(
            initialSection: SettingsPaneRestoration.restoredSection(from: restorationDefaults)
        )
        shell.selectionDidChange = { section in
            SettingsPaneRestoration.save(section, to: restorationDefaults)
        }

        self.shell = shell
        self.preferences = preferences
        self.initialShortcutError = initialShortcutError
        self.onShortcutChanged = onShortcutChanged
        self.initialWindowShortcutError = initialWindowShortcutError
        self.onWindowShortcutChanged = onWindowShortcutChanged
        self.onWindowShortcutsEnabledChanged = onWindowShortcutsEnabledChanged
        self.onUseRecommendedWindowShortcuts = onUseRecommendedWindowShortcuts
        self.onCaptureWorkspace = onCaptureWorkspace
        self.onClearUsage = onClearUsage
        self.onClearClipboard = onClearClipboard
        self.onExportDiagnostics = onExportDiagnostics
        previewRenderer = LauncherPreviewRenderer()
        self.onWindowAttached = onWindowAttached
    }
}

/// Root content declared directly inside `Settings {}` in `BroccoliMain`, matching Cherry's
/// native scene ownership and material composition.
