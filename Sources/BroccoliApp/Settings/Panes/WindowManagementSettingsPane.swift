@preconcurrency import AppKit
import SwiftUI

struct WindowManagementSettingsPane: View {
    @ObservedObject var preferences: AppPreferences
    let initialWindowShortcutError: String?
    let onWindowShortcutChanged: (WindowShortcutTarget, HotKeyConfiguration?) -> WindowShortcutChangeResult
    let onWindowShortcutsEnabledChanged: (Bool) -> String?
    let onCaptureWorkspace: (String) async -> String?

    @State private var windowShortcutStatus = ""
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted
    @State private var editingLayout: EditingLayout?
    @State private var isSavingWorkspace = false
    @State private var ignoredAppsMessage: String?

    private struct EditingLayout: Identifiable {
        let layout: CustomWindowLayout
        let isNew: Bool
        var id: UUID { layout.id }
    }

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
            .sheet(item: $editingLayout) { editing in
                CustomWindowLayoutEditor(
                    layout: editing.layout,
                    isNew: editing.isNew,
                    onSave: { saveLayout($0) },
                    onCancel: { editingLayout = nil }
                )
            }
            .sheet(isPresented: $isSavingWorkspace) {
                WindowWorkspaceSaveSheet(onSave: onCaptureWorkspace) {
                    isSavingWorkspace = false
                }
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

            sizesCard
            behaviorCard
            SettingsFootnote(
                symbol: "info.circle",
                text: "If macOS also tiles windows you drag to a screen edge, turn off “Drag windows to screen edges to tile” in Desktop & Dock settings."
            )
            ignoredApplicationsCard
            customLayoutsCard
            workspacesCard

            ForEach(WindowActionGroup.allCases, id: \.self) { group in
                SpotlightSettingsCard(group.title) {
                    if group == .tiling {
                        SpotlightSettingsRow(
                            title: "Tile Windows Automatically",
                            subtitle: "Two windows split the screen. Three stack the extras. Four or more divide it evenly"
                        ) {
                            Toggle("", isOn: windowManagementBinding(\.automaticTilingEnabled))
                                .labelsHidden()
                                .settingsToggleAccessibility(
                                    "Tile Windows Automatically",
                                    isOn: preferences.windowManagement.automaticTilingEnabled
                                )
                        }
                    }
                    ForEach(group.actions, id: \.self) { action in
                        shortcutRow(
                            for: .action(action),
                            title: action.title,
                            subtitle: action.aliases.first ?? "Window action"
                        )
                    }
                }
            }

            SettingsFootnote(
                symbol: "delete.left",
                text: "To remove a shortcut, click it and press Delete."
            )
            SettingsFootnote(
                symbol: "magnifyingglass",
                text: "Every layout is also available by name in Broccoli search, even when global window shortcuts are off."
            )
            SettingsFootnote(
                symbol: "arrow.left.and.right",
                text: "Pressing Left Half, Right Half, Top Half, Bottom Half, or a quarter again cycles that window through half, a third, and two thirds."
            )
        }
    }

    // MARK: - Cards

    private var sizesCard: some View {
        SpotlightSettingsCard("Sizes") {
            SpotlightSettingsRow(
                title: "Resize Step",
                subtitle: "How far Make Larger and Make Smaller change a window"
            ) {
                Picker("Resize Step", selection: windowManagementBinding(\.resizeStep)) {
                    ForEach(WindowManagementPreferences.resizeStepOptions, id: \.self) { step in
                        Text("\(Int(step)) pt").tag(step)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            SpotlightSettingsRow(
                title: "Almost Maximize",
                subtitle: "Share of the screen an almost maximized window fills"
            ) {
                Picker("Almost Maximize", selection: windowManagementBinding(\.almostMaximizeFraction)) {
                    ForEach(WindowManagementPreferences.almostMaximizeOptions, id: \.self) { fraction in
                        Text("\(Int((fraction * 100).rounded()))%").tag(fraction)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            SpotlightSettingsRow(
                title: "Screen Edge Gap",
                subtitle: "Space between windows and the edges of the screen, including Maximize"
            ) {
                gapPicker("Screen Edge Gap", keyPath: \.screenEdgeGap)
            }
            SpotlightSettingsRow(
                title: "Gap Between Windows",
                subtitle: "Space between windows placed side by side"
            ) {
                gapPicker("Gap Between Windows", keyPath: \.windowGap)
            }
        }
    }

    private var behaviorCard: some View {
        SpotlightSettingsCard("Behavior") {
            SpotlightSettingsRow(
                title: "When Pressed Again",
                subtitle: "Left Half again goes from half, to a third, to two thirds"
            ) {
                Picker("When Pressed Again", selection: windowManagementBinding(\.repeatBehavior)) {
                    ForEach(WindowRepeatBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SpotlightSettingsRow(
                title: "Snap by Dragging",
                subtitle: "Drag a window to a screen edge or corner to snap it into place"
            ) {
                Toggle("", isOn: windowManagementBinding(\.dragToSnapEnabled))
                    .labelsHidden()
                    .settingsToggleAccessibility(
                        "Snap by Dragging",
                        isOn: preferences.windowManagement.dragToSnapEnabled
                    )
            }
        }
    }

    private var ignoredApplicationsCard: some View {
        Group {
            SpotlightSettingsCard("Ignored Applications") {
                ForEach(ignoredApplications) { application in
                    IgnoredApplicationRow(application: application) {
                        var value = preferences.windowManagement
                        value.ignoredBundleIdentifiers.remove(application.bundleIdentifier)
                        preferences.windowManagement = value
                    }
                }
                addRow(
                    title: "Add Application…",
                    accessibilityLabel: "Add Ignored Application",
                    action: presentIgnoredApplicationPicker
                )
            }
            if let ignoredAppsMessage {
                Label(ignoredAppsMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            SettingsFootnote(
                symbol: "hand.raised",
                text: "While an ignored application is in front, it receives window shortcut keys itself. Snapping and automatic tiling also leave its windows alone."
            )
        }
    }

    private var customLayoutsCard: some View {
        SpotlightSettingsCard("Custom Layouts") {
            ForEach(preferences.windowManagement.customLayouts) { layout in
                shortcutRow(for: .layout(layout.id), title: layout.name, subtitle: layout.summary) {
                    Menu {
                        Button("Edit…") { editingLayout = EditingLayout(layout: layout, isNew: false) }
                        Button("Delete", role: .destructive) { deleteLayout(layout.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("\(layout.name) options")
                }
            }
            if preferences.windowManagement.customLayouts.count < WindowManagementPreferences.maximumCustomLayouts {
                addRow(title: "Add Layout…", accessibilityLabel: "Add Custom Layout") {
                    editingLayout = EditingLayout(
                        layout: CustomWindowLayout(name: "Layout \(preferences.windowManagement.customLayouts.count + 1)"),
                        isNew: true
                    )
                }
            }
        }
    }

    private var workspacesCard: some View {
        SpotlightSettingsCard("Workspaces") {
            ForEach(preferences.windowManagement.workspaces) { workspace in
                shortcutRow(for: .workspace(workspace.id), title: workspace.name, subtitle: workspace.summary) {
                    Button {
                        deleteWorkspace(workspace.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(workspace.name)")
                }
            }
            if preferences.windowManagement.workspaces.count < WindowManagementPreferences.maximumWorkspaces {
                addRow(title: "Save Current Windows…", accessibilityLabel: "Save Current Windows as a Workspace") {
                    isSavingWorkspace = true
                }
            }
        }
    }

    // MARK: - Rows

    private func shortcutRow(
        for target: WindowShortcutTarget,
        title: String,
        subtitle: String
    ) -> some View {
        shortcutRow(for: target, title: title, subtitle: subtitle) { EmptyView() }
    }

    private func shortcutRow<Trailing: View>(
        for target: WindowShortcutTarget,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        SpotlightSettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                ShortcutRecorderRepresentable(
                    configuration: preferences.windowManagement.shortcut(for: target),
                    onChange: { applyWindowShortcutChange(target, $0) },
                    onClear: { applyWindowShortcutChange(target, nil) }
                )
                .frame(width: 132, height: 30)
                .accessibilityLabel("\(title) shortcut")
                trailing()
            }
        }
    }

    private func addRow(
        title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func gapPicker(
        _ title: String,
        keyPath: WritableKeyPath<WindowManagementPreferences, Double>
    ) -> some View {
        Picker(title, selection: windowManagementBinding(keyPath)) {
            ForEach(WindowManagementPreferences.gapOptions, id: \.self) { gap in
                Text(gap == 0 ? "None" : "\(Int(gap)) pt").tag(gap)
            }
        }
        .labelsHidden()
        .frame(width: 100)
    }

    // MARK: - State

    private var ignoredApplications: [IgnoredApplicationDraft] {
        IgnoredApplicationPicker.sorted(
            preferences.windowManagement.ignoredBundleIdentifiers.map {
                IgnoredApplicationPicker.draft(bundleIdentifier: $0)
            }
        )
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

    private func windowManagementBinding<Value>(
        _ keyPath: WritableKeyPath<WindowManagementPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { preferences.windowManagement[keyPath: keyPath] },
            set: { newValue in
                var value = preferences.windowManagement
                value[keyPath: keyPath] = newValue
                preferences.windowManagement = value
            }
        )
    }

    private func presentIgnoredApplicationPicker() {
        IgnoredApplicationPicker.present(
            title: "Add Ignored Applications",
            message: "Choose applications that should keep their own shortcuts and be left alone by window management."
        ) { urls in
            let selection = IgnoredApplicationPicker.bundleIdentifiers(from: urls)
            var value = preferences.windowManagement
            value.ignoredBundleIdentifiers.formUnion(selection.identifiers.map(\.0))
            preferences.windowManagement = value
            ignoredAppsMessage = IgnoredApplicationsCopy.invalidSelectionMessage(count: selection.skipped)
        }
    }

    private func saveLayout(_ layout: CustomWindowLayout) {
        var value = preferences.windowManagement
        if let index = value.customLayouts.firstIndex(where: { $0.id == layout.id }) {
            value.customLayouts[index] = layout
        } else {
            value.customLayouts.append(layout)
        }
        preferences.windowManagement = value
        editingLayout = nil
    }

    private func deleteLayout(_ id: UUID) {
        var value = preferences.windowManagement
        value.customLayouts.removeAll { $0.id == id }
        preferences.windowManagement = value
    }

    private func deleteWorkspace(_ id: UUID) {
        var value = preferences.windowManagement
        value.workspaces.removeAll { $0.id == id }
        preferences.windowManagement = value
    }

    private func applyWindowShortcutsEnabled(_ enabled: Bool) {
        if let error = onWindowShortcutsEnabledChanged(enabled) {
            windowShortcutStatus = error
            return
        }
        windowShortcutStatus = "Shortcuts ready"
    }

    private func applyWindowShortcutChange(
        _ target: WindowShortcutTarget,
        _ configuration: HotKeyConfiguration?
    ) -> Bool {
        switch onWindowShortcutChanged(target, configuration) {
        case .applied(let registrationError):
            windowShortcutStatus = registrationError ?? "Shortcuts ready"
            return true
        case .rejected(let message):
            windowShortcutStatus = message
            return false
        }
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
