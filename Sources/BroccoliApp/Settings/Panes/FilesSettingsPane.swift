import SwiftUI

struct FilesSettingsPane: View {
    let destination: SettingsDestination
    @ObservedObject var preferences: AppPreferences
    let onNavigate: (SettingsDestination) -> Void

    @ViewBuilder
    var body: some View {
        if destination == .excludedLocations {
            excludedLocationsDestination
        } else {
            files
        }
    }

    private var files: some View {
        Group {
            SpotlightSettingsCard("File Search") {
                SpotlightSettingsRow(symbol: "magnifyingglass", title: "Enable File Search", subtitle: "Search filenames and paths only") {
                    Toggle("", isOn: Binding(
                        get: { preferences.fileSearch.enabled },
                        set: { var value = preferences.fileSearch; value.enabled = $0; preferences.fileSearch = value }
                    ))
                    .labelsHidden()
                    .settingsToggleAccessibility("Enable File Search", isOn: preferences.fileSearch.enabled)
                }
                SpotlightSettingsRow(symbol: "textformat", title: "Search Prefixes", subtitle: "Type a prefix followed by a space") {
                    HStack(spacing: 6) {
                        Text("f").modifier(SettingsTokenStyle())
                        Text("find").modifier(SettingsTokenStyle())
                    }
                }
                .disabled(!preferences.fileSearch.enabled)
                SpotlightSettingsRow(symbol: "circle.dashed", title: "Spotlight Status", subtitle: "Availability is checked when a file query starts") {
                    SettingsStatusAccessory(title: "On Demand", color: .secondary, showsIndicator: true)
                }
            }
            SpotlightSettingsCard("Search Locations") {
                SpotlightSettingsRow(symbol: "house", title: "Home Folder", subtitle: "Hidden items, Library, and application bundles are excluded") {
                    SettingsStatusAccessory(title: "Included", color: .green, showsIndicator: true)
                }
                SpotlightSettingsRow(symbol: "externaldrive", title: "Mounted User Volumes", subtitle: "Available external drives are included") {
                    SettingsStatusAccessory(title: "Included", color: .green, showsIndicator: true)
                }
                SettingsNavigationRow(
                    symbol: "eye.slash",
                    title: "Excluded Locations",
                    subtitle: "Review locations Broccoli never searches"
                ) {
                    onNavigate(.excludedLocations)
                }
            }
            .disabled(!preferences.fileSearch.enabled)
            SpotlightSettingsCard("Keyboard") {
                SpotlightSettingsRow(title: "Return") { SettingsStatusAccessory(title: "Open Item") }
                SpotlightSettingsRow(title: "Command–Return") { SettingsStatusAccessory(title: "Reveal in Finder") }
            }
            SettingsFootnote(
                symbol: "checkmark.shield",
                text: "File queries and selected paths are never stored."
            )
        }
    }

    private var excludedLocationsDestination: some View {
        Group {
            SettingsDestinationIntro(
                "These privacy and reliability exclusions always apply to file search."
            )
            SpotlightSettingsCard("Always Excluded") {
                SpotlightSettingsRow(symbol: "folder.badge.minus", title: "Hidden Items", subtitle: "Names beginning with a period are excluded")
                SpotlightSettingsRow(symbol: "books.vertical", title: "Library", subtitle: "Your ~/Library folder is excluded")
                SpotlightSettingsRow(symbol: "app", title: "Application Bundles", subtitle: "Contents inside .app bundles are excluded")
                SpotlightSettingsRow(symbol: "internaldrive", title: "System Locations", subtitle: "System, Library, private, usr, bin, and sbin are excluded")
                SpotlightSettingsRow(symbol: "lock", title: "Inaccessible Paths", subtitle: "Locations macOS does not permit are skipped")
            }
            SettingsFootnote(
                symbol: "checkmark.shield",
                text: "Broccoli never recursively scans these locations."
            )
        }
    }


}

