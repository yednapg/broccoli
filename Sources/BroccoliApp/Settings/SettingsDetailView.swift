import SwiftUI

/// Routes native Settings destinations to focused feature panes.
///
/// Each pane owns only the transient state and preference observation it needs. Keeping this
/// router state-free prevents a change in one feature from invalidating every Settings page.
struct SettingsDetailView: View {
    let destination: SettingsDestination
    let context: BroccoliSettingsContext
    let onNavigate: (SettingsDestination) -> Void

    var body: some View {
        SpotlightSettingsPane(
            title: destination.title
        ) {
            pageContent
        }
        .id(destination)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch destination.section {
        case .general:
            GeneralSettingsPane(
                destination: destination,
                preferences: context.preferences,
                initialShortcutError: context.initialShortcutError,
                onShortcutChanged: context.onShortcutChanged,
                onNavigate: onNavigate
            )
        case .appearance:
            AppearanceSettingsPane(
                destination: destination,
                preferences: context.preferences,
                previewRenderer: context.previewRenderer,
                onNavigate: onNavigate
            )
        case .search:
            SearchSettingsPane(
                preferences: context.preferences,
                onClearUsage: context.onClearUsage
            )
        case .files:
            FilesSettingsPane(
                destination: destination,
                preferences: context.preferences,
                onNavigate: onNavigate
            )
        case .calculator:
            CalculatorSettingsPane(preferences: context.preferences)
        case .clipboard:
            ClipboardSettingsPane(
                destination: destination,
                preferences: context.preferences,
                onClearClipboard: context.onClearClipboard,
                onNavigate: onNavigate
            )
        case .windows:
            WindowManagementSettingsPane(
                preferences: context.preferences,
                initialWindowShortcutError: context.initialWindowShortcutError,
                onWindowShortcutChanged: context.onWindowShortcutChanged,
                onWindowShortcutsEnabledChanged: context.onWindowShortcutsEnabledChanged
            )
        case .actions:
            ActionsSettingsPane(preferences: context.preferences)
        case .privacy:
            PermissionsSettingsPane(
                destination: destination,
                preferences: context.preferences,
                onClearUsage: context.onClearUsage,
                onExportDiagnostics: context.onExportDiagnostics,
                onNavigate: onNavigate
            )
        case .about:
            AboutSettingsPane(
                updateCoordinator: context.updateCoordinator,
                onExportDiagnostics: context.onExportDiagnostics
            )
        }
    }
}
