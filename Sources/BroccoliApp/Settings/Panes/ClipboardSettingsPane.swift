@preconcurrency import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsPane: View {
    let destination: SettingsDestination
    @ObservedObject var preferences: AppPreferences
    let onClearClipboard: () -> Void
    let onNavigate: (SettingsDestination) -> Void

    @State private var clipboardConsent = false
    @State private var confirmClearClipboard = false
    @State private var ignoredAppsDraft: [IgnoredApplicationDraft] = []
    @State private var ignoredAppsEditorMessage: String?

    @ViewBuilder
    var body: some View {
        Group {
            if destination == .ignoredApplications {
                ignoredApplicationsDestination
            } else {
                clipboard
            }
        }
        .sheet(isPresented: $clipboardConsent) {
            ClipboardConsentSheet(retentionDays: preferences.clipboard.retentionDays) {
                var value = preferences.clipboard
                value.enabled = true
                preferences.clipboard = value
            }
        }
        .alert("Clear Clipboard History?", isPresented: $confirmClearClipboard) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Clipboard History", role: .destructive, action: onClearClipboard)
        } message: {
            Text("This permanently removes all encrypted clipboard items stored by Broccoli.")
        }
        .onAppear {
            if destination == .ignoredApplications {
                refreshIgnoredAppsDraft()
            }
        }
    }

    private var clipboard: some View {
        Group {
            if !preferences.clipboard.enabled {
                SettingsInfoBanner(
                    symbol: "lock.fill",
                    message: "Clipboard History is off. Nothing is captured until you enable it.",
                    actionTitle: "Enable…",
                    action: { clipboardConsent = true }
                )
            }

            SpotlightSettingsCard("History") {
                SpotlightSettingsRow(symbol: "clipboard", title: "Clipboard History", subtitle: "Store encrypted clipboard items on this Mac") {
                    Toggle("", isOn: Binding(
                        get: { preferences.clipboard.enabled },
                        set: { enabled in
                            if enabled { clipboardConsent = true }
                            else { var value = preferences.clipboard; value.enabled = false; preferences.clipboard = value }
                        }
                    ))
                    .labelsHidden()
                    .settingsToggleAccessibility("Enable Clipboard History", isOn: preferences.clipboard.enabled)
                }
                SpotlightSettingsRow(title: "Retention") {
                    Picker("Retention", selection: clipboardBinding(\.retentionDays)) {
                        Text("1 Day").tag(1); Text("7 Days").tag(7); Text("30 Days").tag(30)
                    }
                    .labelsHidden().frame(width: 100)
                }
                .disabled(!preferences.clipboard.enabled)
                SpotlightSettingsRow(title: "Maximum Items") {
                    Picker("Maximum Items", selection: clipboardBinding(\.maximumItems)) {
                        Text("100").tag(100); Text("500").tag(500); Text("1,000").tag(1000)
                    }
                    .labelsHidden().frame(width: 100)
                }
                .disabled(!preferences.clipboard.enabled)
                SpotlightSettingsRow(title: "Per-Item Limit", subtitle: "Maximum stored size for one clipboard item") {
                    SettingsStatusAccessory(title: "10 MB")
                }
                .disabled(!preferences.clipboard.enabled)
            }

            SpotlightSettingsCard("Content Types") {
                SpotlightSettingsRow(title: "Plain & Rich Text") {
                    Toggle("", isOn: clipboardBinding(\.capturesText))
                        .labelsHidden()
                        .settingsToggleAccessibility("Capture Plain and Rich Text", isOn: preferences.clipboard.capturesText)
                }
                SpotlightSettingsRow(title: "Links") {
                    Toggle("", isOn: clipboardBinding(\.capturesURLs))
                        .labelsHidden()
                        .settingsToggleAccessibility("Capture Links", isOn: preferences.clipboard.capturesURLs)
                }
                SpotlightSettingsRow(title: "Files") {
                    Toggle("", isOn: clipboardBinding(\.capturesFiles))
                        .labelsHidden()
                        .settingsToggleAccessibility("Capture Files", isOn: preferences.clipboard.capturesFiles)
                }
                SpotlightSettingsRow(title: "Images") {
                    Toggle("", isOn: clipboardBinding(\.capturesImages))
                        .labelsHidden()
                        .settingsToggleAccessibility("Capture Images", isOn: preferences.clipboard.capturesImages)
                }
            }
            .disabled(!preferences.clipboard.enabled)

            SpotlightSettingsCard("Privacy") {
                Button { onNavigate(.ignoredApplications) } label: {
                    SpotlightSettingsRow(symbol: "app.badge", title: "Ignored Applications", subtitle: "Password managers and apps you choose") {
                        HStack(spacing: 6) {
                            Text(ignoredApplicationsCountText)
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
                SpotlightSettingsRow(symbol: "eye.slash", title: "Concealed Content", subtitle: "Transient and sensitive pasteboard data") {
                    SettingsStatusAccessory(title: "Always Ignored", color: .green, showsIndicator: true)
                }
                Button(role: .destructive) { confirmClearClipboard = true } label: {
                    SpotlightSettingsRow(
                        symbol: "trash",
                        title: "Clear Clipboard History…",
                        subtitle: "Permanently remove encrypted clipboard items"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            SettingsFootnote(
                symbol: "key.fill",
                text: "Items are encrypted with a key stored in Keychain and never leave your Mac."
            )
        }
    }

    private var ignoredApplicationsCountText: String {
        let count = preferences.clipboard.ignoredBundleIdentifiers
            .subtracting(ClipboardPreferences.defaultIgnoredBundleIdentifiers)
            .count
        return count == 1 ? "1 App" : "\(count) Apps"
    }

    private var ignoredApplicationsDestination: some View {
        Group {
            SettingsDestinationIntro(
                "Clipboard History skips content copied from applications in this list."
            )
            SpotlightSettingsCard("Applications") {
                if ignoredAppsDraft.isEmpty {
                    ContentUnavailableView(
                        "No Ignored Applications",
                        systemImage: "app.badge",
                        description: Text("Add an application to exclude its copied content.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 132)
                } else {
                    ForEach(ignoredAppsDraft) { application in
                        IgnoredApplicationRow(application: application) {
                            removeIgnoredApplication(application.id)
                        }
                    }
                }
            }
            if let ignoredAppsEditorMessage {
                Label(ignoredAppsEditorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            SpotlightSettingsCard {
                Button(action: presentIgnoredApplicationPicker) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .frame(width: 18)
                        Text("Add Application…")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Ignored Application")
                .accessibilityHint("Opens a file chooser restricted to Mac applications.")
            }
            SpotlightSettingsCard("Built-In Protection") {
                SpotlightSettingsRow(
                    symbol: "lock.shield",
                    title: "Known Password Managers",
                    subtitle: "Built-in password-manager identifiers and concealed content are always ignored"
                ) {
                    SettingsStatusAccessory(title: "Always On", color: .green, showsIndicator: true)
                }
            }
            SettingsFootnote(
                symbol: "lock.fill",
                text: "Clipboard content from ignored applications is never captured."
            )
        }
    }

    private func refreshIgnoredAppsDraft() {
        ignoredAppsEditorMessage = nil
        ignoredAppsDraft = sortIgnoredApplications(
            preferences.clipboard.ignoredBundleIdentifiers
                .subtracting(ClipboardPreferences.defaultIgnoredBundleIdentifiers)
                .map {
                ignoredApplicationDraft(bundleIdentifier: $0)
            }
        )
    }

    private func saveIgnoredApps() {
        var value = preferences.clipboard
        value.ignoredBundleIdentifiers = Set(ignoredAppsDraft.map(\.bundleIdentifier))
            .union(ClipboardPreferences.defaultIgnoredBundleIdentifiers)
        preferences.clipboard = value
    }

    private func presentIgnoredApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = "Add Ignored Applications"
        panel.message = "Choose one or more applications whose clipboard content Broccoli should skip."
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            addIgnoredApplications(panel.urls)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func addIgnoredApplications(_ urls: [URL]) {
        var applicationsByIdentifier = Dictionary(
            uniqueKeysWithValues: ignoredAppsDraft.map { ($0.bundleIdentifier, $0) }
        )
        var skippedApplications = 0

        for selectedURL in urls {
            let url = selectedURL.resolvingSymlinksInPath()
            guard url.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame,
                  let bundleIdentifier = Bundle(url: url)?.bundleIdentifier?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleIdentifier.isEmpty else {
                skippedApplications += 1
                continue
            }
            applicationsByIdentifier[bundleIdentifier] = ignoredApplicationDraft(
                bundleIdentifier: bundleIdentifier,
                preferredURL: url
            )
        }

        ignoredAppsDraft = sortIgnoredApplications(Array(applicationsByIdentifier.values))
        ignoredAppsEditorMessage = IgnoredApplicationsCopy.invalidSelectionMessage(
            count: skippedApplications
        )
        saveIgnoredApps()
    }

    private func removeIgnoredApplication(_ bundleIdentifier: String) {
        ignoredAppsDraft.removeAll { $0.bundleIdentifier == bundleIdentifier }
        ignoredAppsEditorMessage = nil
        saveIgnoredApps()
    }

    private func ignoredApplicationDraft(
        bundleIdentifier: String,
        preferredURL: URL? = nil
    ) -> IgnoredApplicationDraft {
        let applicationURL = preferredURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let displayName: String
        let icon: NSImage

        if let applicationURL {
            let bundle = Bundle(url: applicationURL)
            displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? applicationURL.deletingPathExtension().lastPathComponent
            icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            displayName = "Application Not Installed"
            icon = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }

        return IgnoredApplicationDraft(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            icon: icon,
            isResolved: applicationURL != nil
        )
    }

    private func sortIgnoredApplications(
        _ applications: [IgnoredApplicationDraft]
    ) -> [IgnoredApplicationDraft] {
        applications.sorted { lhs, rhs in
            let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
            return lhs.bundleIdentifier.localizedStandardCompare(rhs.bundleIdentifier) == .orderedAscending
        }
    }

    private func clipboardBinding<Value>(_ keyPath: WritableKeyPath<ClipboardPreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences.clipboard[keyPath: keyPath] }) { newValue in
            var value = preferences.clipboard
            value[keyPath: keyPath] = newValue
            value.sanitize()
            preferences.clipboard = value
        }
    }


}
