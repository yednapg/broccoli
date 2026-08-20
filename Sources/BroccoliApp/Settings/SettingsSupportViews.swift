@preconcurrency import AppKit
import SwiftUI

struct SettingsTokenStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SettingsNavigationRow: View {
    let symbol: String?
    let title: String
    let subtitle: String?
    let action: () -> Void

    init(
        symbol: String? = nil,
        title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SpotlightSettingsRow(
                symbol: symbol,
                title: title,
                subtitle: subtitle,
                accessoryMinimumWidth: 0
            ) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "Open details")
    }
}

struct IgnoredApplicationRow: View {
    let application: IgnoredApplicationDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: application.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !application.isResolved {
                    Text(application.bundleIdentifier)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove \(application.displayName)")
            .accessibilityLabel("Remove \(application.displayName)")
            .accessibilityHint("Stops excluding this application immediately.")
        }
        .frame(minHeight: 48)
    }
}

extension View {
    func settingsToggleAccessibility(_ label: String, isOn: Bool) -> some View {
        toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct SettingsInfoBanner: View {
    let symbol: String
    let message: String
    var color: Color = .secondary
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .spotlightSettingsGlassButtonStyle()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .spotlightSettingsGroupedSurface()
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

struct SettingsFootnote: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
    }
}

struct SettingsDestinationIntro: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

struct SettingsStatusAccessory: View {
    let title: String
    var color: Color = .secondary
    var showsIndicator = false

    var body: some View {
        Group {
            if showsIndicator {
                Label(title, systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(color)
            } else {
                Text(title)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsValueRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        SpotlightSettingsRow(symbol: symbol, title: title) {
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AutomationStatusRow: View {
    let state: AutomationPermissionState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch state {
        case .checking: "Checking Automation access…"
        case .allowed: "Automation is allowed"
        case .notRequested: "Automation has not been requested"
        case .denied: "Automation is denied"
        case .targetUnavailable: "System Events is unavailable"
        case .unknown: "Automation status is unavailable"
        }
    }

    private var detail: String {
        switch state {
        case .checking: "Reading the local macOS permission state without prompting."
        case .allowed: "Dark Mode and confirmed power actions can run."
        case .notRequested: "macOS will ask only when you run an action that needs it."
        case .denied: "Enable System Events below to use Dark Mode and power actions."
        case .targetUnavailable: "Broccoli cannot run protected actions because macOS System Events could not be found."
        case .unknown(let status): "macOS returned status \(status). Search and non-Automation actions still work."
        }
    }

    private var symbol: String {
        switch state {
        case .checking: "ellipsis.circle"
        case .allowed: "checkmark.circle.fill"
        case .notRequested: "circle.dashed"
        case .targetUnavailable: "exclamationmark.triangle.fill"
        case .denied: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .allowed: .green
        case .denied, .targetUnavailable: .red
        case .notRequested: .orange
        case .checking, .unknown: .secondary
        }
    }
}

extension AutomationPermissionState {
    var shortTitle: String {
        switch self {
        case .checking: "Checking"
        case .allowed: "Allowed"
        case .notRequested: "Not Requested"
        case .denied: "Denied"
        case .targetUnavailable: "Unavailable"
        case .unknown: "Unavailable"
        }
    }

    var statusColor: Color {
        switch self {
        case .allowed: .green
        case .denied, .targetUnavailable: .red
        case .notRequested: .orange
        case .checking, .unknown: .secondary
        }
    }
}

struct ClipboardConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var understood = false
    let retentionDays: Int
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text("Enable Clipboard History?")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Copied content will be encrypted and stored only on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Form {
                Section {
                    SpotlightSettingsRow(symbol: "lock.shield", title: "Private and Secure", subtitle: "AES-GCM encryption with a key stored in Keychain")
                    SpotlightSettingsRow(
                        symbol: "clock",
                        title: ClipboardConsentCopy.retentionTitle(days: retentionDays),
                        subtitle: "Older items are removed automatically"
                    )
                    SpotlightSettingsRow(symbol: "eye.slash", title: "Sensitive Sources Excluded", subtitle: "Concealed data and known password apps are ignored")
                }
                Section {
                    Toggle("I understand copied content will be stored on this Mac", isOn: $understood)
                        .toggleStyle(.checkbox)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 245)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enable Clipboard History") {
                    onEnable()
                    dismiss()
                }
                .spotlightSettingsProminentGlassButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(!understood)
            }
        }
        .padding(24)
        .frame(width: 480)
        .frame(minHeight: 410)
    }
}

struct ExamplePill: View {
    let expression: String
    let detail: String

    init(_ expression: String, detail: String) {
        self.expression = expression
        self.detail = detail
    }

    var body: some View {
        HStack {
            Text(expression).font(.system(.callout, design: .monospaced))
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Single Settings-side adapter for ActionRegistry icons. It deliberately contains no icon
/// switch: the launcher, configurable action rows, and always-on Recovery rows all derive from
/// `NativeIconCatalog` and therefore cannot drift into separate artwork.
enum SettingsActionIconSource {
    static func symbolName(for definition: ActionDefinition) -> String {
        NativeIconCatalog.resolvedActionSymbolName(forActionID: definition.id)
    }
}

struct ActionGroupCard: View {
    let title: String
    var subtitle: String? = nil
    let definitions: [ActionDefinition]
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        SpotlightSettingsCard(title) {
            ForEach(definitions, id: \.id) { definition in
                SpotlightSettingsRow(
                    symbol: SettingsActionIconSource.symbolName(for: definition),
                    title: definition.title,
                    subtitle: detail(for: definition)
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.enabledActionIDs.contains(definition.id) },
                        set: { enabled in
                            var values = preferences.enabledActionIDs
                            if enabled { values.insert(definition.id) } else { values.remove(definition.id) }
                            preferences.enabledActionIDs = values
                        }
                    ))
                    .labelsHidden()
                    .settingsToggleAccessibility(
                        definition.title,
                        isOn: preferences.enabledActionIDs.contains(definition.id)
                    )
                }
            }
            if let subtitle {
                Label(subtitle, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .frame(minHeight: 34)
            }
        }
    }

    private func detail(for definition: ActionDefinition) -> String {
        if definition.risk == .disruptive { return "Requires a second Return within five seconds" }
        switch definition.id {
        case "appearance.toggleDark": return "Switch between light and dark appearance"
        case "audio.toggleMute": return "Mute or restore the current output volume"
        case "audio.volumeUp": return "Increase output volume by 10%; repeat with Return"
        case "audio.volumeDown": return "Decrease output volume by 10%; repeat with Return"
        case "screensaver.start": return "Start the current macOS screen saver"
        case "catalog.refresh": return "Refresh the in-memory application index"
        default: return definition.keepsPanelOpen
            ? "Keeps the launcher open so the action can repeat"
            : "Available from launcher search"
        }
    }

}

enum LauncherDesignChooserLayout {
    static let designs: [LauncherDesign] = [.liquidGlass, .minimal]
    static let pickerWidth: CGFloat = 230
}

struct LauncherDesignChooser: View {
    @Binding var selection: LauncherDesign

    var body: some View {
        Picker("Launcher Design", selection: $selection) {
            ForEach(LauncherDesignChooserLayout.designs) { design in
                Text(design.title)
                    .tag(design)
            }
        }
        .pickerStyle(.palette)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Launcher Design")
        .accessibilityValue(selection.title)
    }
}

struct ShortcutRecorderRepresentable: NSViewRepresentable {
    let configuration: HotKeyConfiguration
    var recordingRequest = 0
    let onChange: (HotKeyConfiguration) -> Bool

    final class Coordinator {
        var handledRecordingRequest: Int

        init(handledRecordingRequest: Int) {
            self.handledRecordingRequest = handledRecordingRequest
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handledRecordingRequest: recordingRequest)
    }

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl()
        view.configuration = configuration
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.configuration = configuration
        nsView.onChange = onChange
        guard context.coordinator.handledRecordingRequest != recordingRequest else { return }
        context.coordinator.handledRecordingRequest = recordingRequest
        DispatchQueue.main.async { [weak nsView] in
            _ = nsView?.beginRecording()
        }
    }
}
