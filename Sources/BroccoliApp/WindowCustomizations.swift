import BroccoliCore
import CoreGraphics
import Foundation

enum WindowAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .top: "Top"
        case .topRight: "Top Right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom Right"
        }
    }

    /// 0 = leading edge, 0.5 = centered, 1 = trailing edge.
    var horizontalFraction: CGFloat {
        switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .top, .center, .bottom: 0.5
        case .topRight, .right, .bottomRight: 1
        }
    }

    var verticalFraction: CGFloat {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .left, .center, .right: 0.5
        case .bottomLeft, .bottom, .bottomRight: 1
        }
    }
}

/// A size and position the user saved in Settings, available by name and by shortcut.
struct CustomWindowLayout: Codable, Equatable, Identifiable, Sendable {
    static let maximumNameLength = 60

    var id: UUID
    var name: String
    var width: WindowDimension
    var height: WindowDimension
    var anchor: WindowAnchor
    var shortcut: HotKeyConfiguration?

    init(
        id: UUID = UUID(),
        name: String,
        width: WindowDimension = .percent(60),
        height: WindowDimension = .percent(70),
        anchor: WindowAnchor = .center,
        shortcut: HotKeyConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.anchor = anchor
        self.shortcut = shortcut
    }

    var summary: String {
        "\(width.displayText) × \(height.displayText), \(anchor.title)"
    }

    var actionID: String { WindowShortcutTarget.layout(id).bindingID }

    var frameSpec: WindowFrameSpec {
        WindowFrameSpec(width: width, height: height, placement: .anchor(anchor), usesGaps: true)
    }

    mutating func sanitize() {
        name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNameLength))
        if name.isEmpty { name = "Custom Layout" }
        width = width.sanitized
        height = height.sanitized
    }
}

/// A saved arrangement of several applications' windows. Only application identifiers and
/// relative frames are stored; window titles and contents are never recorded.
struct WindowWorkspace: Codable, Equatable, Identifiable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var bundleIdentifier: String
        var displayIndex: Int
        /// Frame as fractions of the display's usable area, so the arrangement survives a
        /// resolution change.
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        mutating func sanitize() {
            displayIndex = max(0, displayIndex)
            func unit(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
            x = unit(x)
            y = unit(y)
            width = max(0.05, unit(width))
            height = max(0.05, unit(height))
        }
    }

    static let maximumEntries = 40

    var id: UUID
    var name: String
    var entries: [Entry]
    var shortcut: HotKeyConfiguration?

    init(id: UUID = UUID(), name: String, entries: [Entry], shortcut: HotKeyConfiguration? = nil) {
        self.id = id
        self.name = name
        self.entries = entries
        self.shortcut = shortcut
    }

    var actionID: String { WindowShortcutTarget.workspace(id).bindingID }

    var summary: String {
        let applications = Set(entries.map(\.bundleIdentifier)).count
        let windows = entries.count
        return "\(windows) \(windows == 1 ? "window" : "windows") from \(applications) \(applications == 1 ? "app" : "apps")"
    }

    mutating func sanitize() {
        name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CustomWindowLayout.maximumNameLength))
        if name.isEmpty { name = "Workspace" }
        entries = entries
            .filter { !$0.bundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(Self.maximumEntries)
            .map { entry in
                var entry = entry
                entry.sanitize()
                return entry
            }
    }
}

/// Launcher rows for window targets that are not fixed actions.
enum WindowSearchEntries {
    static func customizations(_ preferences: WindowManagementPreferences) -> [SearchEntry] {
        preferences.customLayouts.map { layout in
            entry(
                id: layout.actionID,
                title: layout.name,
                subtitle: "Custom Layout · \(layout.summary)",
                keywords: ["window layout", "custom layout"]
            )
        } + preferences.workspaces.map { workspace in
            entry(
                id: workspace.actionID,
                title: workspace.name,
                subtitle: "Workspace · \(workspace.summary)",
                keywords: ["workspace", "window arrangement", "open windows"]
            )
        }
    }

    private static func entry(id: String, title: String, subtitle: String, keywords: [String]) -> SearchEntry {
        SearchEntry(
            id: "action:\(id)",
            kind: .action,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            iconKey: "action:\(id)",
            target: .action(id: id)
        )
    }
}

/// A frame described relative to the window and its display rather than as a named layout.
struct WindowFrameSpec: Equatable, Sendable {
    enum Placement: Equatable, Sendable {
        case anchor(WindowAnchor)
        /// Keep the window's top-left corner, sliding it back onto the display if needed.
        case keepOrigin
        /// Top-left corner offset from the top-left of the usable display.
        case offset(x: Double, y: Double)
    }

    /// `nil` keeps the window's current size on that axis.
    var width: WindowDimension?
    var height: WindowDimension?
    var placement: Placement
    var usesGaps: Bool

    init(width: WindowDimension?, height: WindowDimension?, placement: Placement, usesGaps: Bool) {
        self.width = width
        self.height = height
        self.placement = placement
        self.usesGaps = usesGaps
    }
}

/// Everything the window engine can be asked to do.
enum WindowRequest: Equatable, Sendable {
    case action(WindowAction)
    case frame(WindowFrameSpec)
    case workspace(WindowWorkspace)

    var isIncremental: Bool {
        if case .action(let action) = self { return action.isIncremental }
        return false
    }

    var logName: String {
        switch self {
        case .action(let action): action.rawValue
        case .frame: "customFrame"
        case .workspace: "workspace"
        }
    }
}
