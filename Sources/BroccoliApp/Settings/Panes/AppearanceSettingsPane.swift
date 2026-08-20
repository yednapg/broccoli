import SwiftUI

struct AppearanceSettingsPane: View {
    let destination: SettingsDestination
    @ObservedObject var preferences: AppPreferences
    let previewRenderer: LauncherPreviewRenderer
    let onNavigate: (SettingsDestination) -> Void

    @ViewBuilder
    var body: some View {
        if destination == .launcherPreview {
            launcherPreviewDestination
        } else {
            appearance
        }
    }

    private var appearance: some View {
        Group {
            SpotlightSettingsCard("Appearance") {
                SpotlightSettingsRow(title: "Launcher Design") {
                    LauncherDesignChooser(selection: appearanceBinding(\.design))
                        .frame(width: LauncherDesignChooserLayout.pickerWidth)
                }
                SpotlightSettingsRow(title: "Color Mode") {
                    Picker("Color Mode", selection: appearanceBinding(\.mode)) {
                        ForEach(LauncherAppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                SpotlightSettingsRow(title: "Visible Results") {
                    Stepper(
                        value: appearanceBinding(\.visibleResultCount),
                        in: 3...10
                    ) { Text("\(preferences.appearance.visibleResultCount)").monospacedDigit() }
                        .frame(width: 82)
                        .accessibilityLabel("Visible Results")
                        .accessibilityValue("\(preferences.appearance.visibleResultCount)")
                }
                SpotlightSettingsRow(title: "Display") {
                    Picker("Display", selection: appearanceBinding(\.screen)) {
                        ForEach(LauncherScreenPreference.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                SpotlightSettingsRow(title: "Vertical Position") {
                    Slider(value: appearanceBinding(\.verticalPosition), in: 0.05...0.5)
                        .frame(width: 210)
                        .accessibilityLabel("Launcher Vertical Position")
                        .accessibilityValue("\(Int(preferences.appearance.verticalPosition * 100)) percent from the top")
                }
            }
            SpotlightSettingsCard("Result Details") {
                SpotlightSettingsRow(
                    title: "Show Subtitles",
                    subtitle: preferences.appearance.design == .liquidGlass
                        ? "Liquid Glass uses Spotlight-style single-line results"
                        : nil
                ) {
                    Toggle("", isOn: appearanceBinding(\.showsSubtitles))
                        .labelsHidden()
                        .disabled(preferences.appearance.design == .liquidGlass)
                        .settingsToggleAccessibility(
                            "Show Result Subtitles",
                            isOn: preferences.appearance.showsSubtitles
                        )
                }
                SpotlightSettingsRow(title: "Show Keyboard Shortcuts") {
                    Toggle("", isOn: appearanceBinding(\.showsShortcuts))
                        .labelsHidden()
                        .settingsToggleAccessibility(
                            "Show Result Keyboard Shortcuts",
                            isOn: preferences.appearance.showsShortcuts
                        )
                }
            }
            SpotlightSettingsCard {
                SettingsNavigationRow(
                    symbol: "rectangle.on.rectangle",
                    title: "Preview Launcher",
                    subtitle: "Try the production launcher with safe fixture results"
                ) {
                    onNavigate(.launcherPreview)
                }
            }
        }
    }

    private var launcherPreviewDestination: some View {
        Group {
            SettingsDestinationIntro(
                "Try the production launcher surface with safe, deterministic fixture results."
            )
            SpotlightSettingsCard("Interactive Fixture") {
                VStack(alignment: .leading, spacing: 10) {
                    LauncherInteractivePreview(
                        preferences: preferences.appearance,
                        renderer: previewRenderer
                    )
                    Text("Click the search field to edit the preview. Use ↑ and ↓ to move selection; Return is intentionally disabled.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
            }
            SpotlightSettingsCard("Preview Settings") {
                SpotlightSettingsRow(symbol: "paintbrush", title: "Launcher Design") {
                    SettingsStatusAccessory(title: preferences.appearance.design.title)
                }
                SpotlightSettingsRow(symbol: "circle.lefthalf.filled", title: "Color Mode") {
                    SettingsStatusAccessory(title: preferences.appearance.mode.title)
                }
                SpotlightSettingsRow(symbol: "shield", title: "Safe Preview", subtitle: "Cannot execute actions or update learned usage") {
                    SettingsStatusAccessory(title: "Read Only", color: .green, showsIndicator: true)
                }
            }
        }
    }

    private func updateAppearance(_ mutate: (inout LauncherAppearancePreferences) -> Void) {
        var value = preferences.appearance
        mutate(&value)
        value.sanitize()
        preferences.appearance = value
    }

    private func appearanceBinding<Value>(_ keyPath: WritableKeyPath<LauncherAppearancePreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences.appearance[keyPath: keyPath] }) { newValue in
            updateAppearance { $0[keyPath: keyPath] = newValue }
        }
    }


}
