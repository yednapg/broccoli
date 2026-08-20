@preconcurrency import AppKit
import SwiftUI

struct WindowManagementSettingsPane: View {
    @ObservedObject var preferences: AppPreferences
    let initialWindowShortcutError: String?
    let onWindowShortcutChanged: (WindowAction, HotKeyConfiguration) -> String?
    let onWindowShortcutsEnabledChanged: (Bool) -> String?

    @State private var windowShortcutStatus = ""
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted

    var body: some View {
        windows
            .onAppear {
                if windowShortcutStatus.isEmpty {
                    windowShortcutStatus = initialWindowShortcutError ?? "Shortcuts ready"
                }
                accessibilityTrusted = AccessibilityPermissionChecker.isTrusted
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accessibilityTrusted = AccessibilityPermissionChecker.isTrusted
            }
    }

    private var windows: some View {
        Group {
            SpotlightSettingsCard("Permission") {
                SpotlightSettingsRow(
                    symbol: "accessibility",
                    title: "Window Control",
                    subtitle: accessibilityTrusted
                        ? "Broccoli can move and resize the focused window"
                        : "macOS is not granting window control to this build"
                ) {
                    Group {
                        if accessibilityTrusted {
                            SettingsStatusAccessory(
                                title: "Active",
                                color: .green,
                                showsIndicator: true
                            )
                        } else {
                            Button("Review Settings…") {
                                AccessibilityPermissionChecker.request()
                                AccessibilityPermissionChecker.openSettings()
                            }
                        }
                    }
                }
            }
            SettingsFootnote(
                symbol: "gearshape",
                text: "macOS manages this permission in \(WindowManagementPermissionPresentation.settingsName)."
            )

            SpotlightSettingsCard("Global Shortcuts") {
                SpotlightSettingsRow(
                    symbol: "command",
                    title: "Enable Window Shortcuts",
                    subtitle: "Use window shortcuts from any application"
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.windowManagement.shortcutsEnabled },
                        set: applyWindowShortcutsEnabled
                    ))
                    .labelsHidden()
                    .settingsToggleAccessibility(
                        "Enable Window Shortcuts",
                        isOn: preferences.windowManagement.shortcutsEnabled
                    )
                }
                SpotlightSettingsRow(
                    symbol: windowShortcutReadiness.symbol,
                    title: windowShortcutReadiness.title,
                    subtitle: windowShortcutReadiness.subtitle
                ) {
                    EmptyView()
                }
                .foregroundStyle(windowShortcutReadiness.color)
            }

            SpotlightSettingsCard("Layouts") {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    SpotlightSettingsRow(
                        symbol: NativeIconCatalog.resolvedActionSymbolName(forActionID: action.actionID),
                        title: action.title,
                        subtitle: action.aliases.first ?? "Window action"
                    ) {
                        ShortcutRecorderRepresentable(
                            configuration: preferences.windowManagement.shortcut(for: action),
                            onChange: { applyWindowShortcutChange(action, $0) }
                        )
                        .frame(width: 132, height: 30)
                        .accessibilityLabel("\(action.title) shortcut")
                    }
                }
            }

            SettingsFootnote(
                symbol: "magnifyingglass",
                text: "Every layout is also available by name in Broccoli search, even when global window shortcuts are off."
            )
        }
    }

    private var windowShortcutReadiness: WindowShortcutReadiness {
        WindowShortcutReadiness.resolve(
            enabled: preferences.windowManagement.shortcutsEnabled,
            accessibilityTrusted: accessibilityTrusted,
            registrationError: windowShortcutStatus == "Shortcuts ready"
                ? nil
                : windowShortcutStatus
        )
    }

    private func applyWindowShortcutsEnabled(_ enabled: Bool) {
        if let error = onWindowShortcutsEnabledChanged(enabled) {
            windowShortcutStatus = error
            return
        }
        windowShortcutStatus = "Shortcuts ready"
    }

    private func applyWindowShortcutChange(
        _ action: WindowAction,
        _ configuration: HotKeyConfiguration
    ) -> Bool {
        if let error = onWindowShortcutChanged(action, configuration) {
            windowShortcutStatus = error
            return false
        }
        windowShortcutStatus = "Shortcuts ready"
        return true
    }
}

private extension WindowShortcutReadiness {
    var color: Color {
        switch self {
        case .ready: .green
        case .disabled: .secondary
        case .permissionRequired: .orange
        case .registrationFailed: .red
        }
    }
}
