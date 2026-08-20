import SwiftUI

struct SettingsSearchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let destination: SettingsDestination
    let terms: String

    static let all: [Self] = [
        .init(id: "shortcut", title: "Global Shortcut", subtitle: "General", destination: .section(.general), terms: "hotkey command space conflict registered"),
        .init(id: "shortcut-help", title: "Shortcut Troubleshooting", subtitle: "General", destination: .shortcutTroubleshooting, terms: "spotlight conflict keyboard shortcuts recover"),
        .init(id: "login", title: "Launch at Login", subtitle: "General", destination: .section(.general), terms: "startup automatic sign in"),
        .init(id: "design", title: "Launcher Design", subtitle: "Appearance", destination: .section(.appearance), terms: "minimal liquid glass theme"),
        .init(id: "launcher-preview", title: "Launcher Preview", subtitle: "Appearance", destination: .launcherPreview, terms: "real screenshot fixture preview"),
        .init(id: "color", title: "Color Mode", subtitle: "Appearance", destination: .section(.appearance), terms: "system light dark"),
        .init(id: "display", title: "Display and Position", subtitle: "Appearance", destination: .section(.appearance), terms: "screen vertical results subtitles shortcuts"),
        .init(id: "sources", title: "Result Sources", subtitle: "Search", destination: .section(.search), terms: "applications system settings actions"),
        .init(id: "ranking", title: "Adaptive Ranking", subtitle: "Search", destination: .section(.search), terms: "recent selections learned usage clear"),
        .init(id: "file-search", title: "File Search", subtitle: "Files", destination: .section(.files), terms: "find spotlight metadata filename folder"),
        .init(id: "file-scope", title: "Search Locations", subtitle: "Files", destination: .section(.files), terms: "home mounted volumes hidden library"),
        .init(id: "excluded-locations", title: "Excluded Locations", subtitle: "Files", destination: .excludedLocations, terms: "hidden library system inaccessible application bundles"),
        .init(id: "calculator", title: "Offline Calculator", subtitle: "Calculator", destination: .section(.calculator), terms: "math expression scientific conversion units"),
        .init(id: "clipboard", title: "Clipboard History", subtitle: "Clipboard", destination: .section(.clipboard), terms: "copy paste encrypted retention"),
        .init(id: "ignored-apps", title: "Ignored Applications", subtitle: "Clipboard", destination: .ignoredApplications, terms: "password concealed sensitive apps"),
        .init(id: "window-management", title: "Window Management", subtitle: "Window Management", destination: .section(.windows), terms: "rectangle snap tile resize move window shortcut monitor display"),
        .init(id: "window-accessibility", title: "Window Control Permission", subtitle: "Window Management", destination: .section(.windows), terms: "permission privacy focused window accessibility device control data access"),
        .init(id: "appearance-actions", title: "Appearance and Audio Actions", subtitle: "Actions", destination: .section(.actions), terms: "dark mode volume mute screen saver"),
        .init(id: "power-actions", title: "Power Actions", subtitle: "Actions", destination: .section(.actions), terms: "sleep restart shutdown log out"),
        .init(id: "automation", title: "Automation", subtitle: "Permissions", destination: .automation, terms: "system events permission denied"),
        .init(id: "diagnostics", title: "Local Diagnostics", subtitle: "Permissions", destination: .section(.privacy), terms: "export json errors performance"),
    ]

    func matches(_ query: String) -> Bool {
        let haystack = "\(title) \(subtitle) \(terms)"
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

struct SettingsSearchResultsView: View {
    let query: String
    let onSelect: (SettingsDestination) -> Void

    private var results: [SettingsSearchItem] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return SettingsSearchItem.all.filter { $0.matches(value) }
    }

    var body: some View {
        Form {
            if results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Settings Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            } else {
                Section {
                    ForEach(results) { result in
                        Button { onSelect(result.destination) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: result.destination.section.symbol)
                                    .font(.system(size: 16))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).font(.system(size: 13, weight: .medium))
                                    Text(result.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(results.count) matching settings")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
    }
}
