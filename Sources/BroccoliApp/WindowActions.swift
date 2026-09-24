import Carbon
import CoreGraphics
import Foundation

enum WindowActionGroup: String, CaseIterable, Sendable {
    case fillAndCenter
    case resize
    case arrange
    case tiling
    case displays
    case halvesAndQuarters
    case thirds

    var title: String {
        switch self {
        case .halvesAndQuarters: "Halves & Quarters"
        case .thirds: "Thirds"
        case .fillAndCenter: "Fill & Center"
        case .resize: "Resize"
        case .displays: "Displays"
        case .arrange: "Arrange All Windows"
        case .tiling: "Automatic Tiling"
        }
    }

    var actions: [WindowAction] {
        WindowAction.allCases.filter { $0.group == self }
    }
}

enum WindowAction: String, Codable, CaseIterable, Hashable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case firstThird
    case lastThird
    case maximize
    // The stored identifier predates the Almost Maximize title. Keep it so saved shortcuts
    // and search preferences continue to resolve.
    case minimized
    case maximizeHeight
    case maximizeWidth
    case center
    case makeLarger
    case makeSmaller
    case nextDisplay
    case previousDisplay
    case restore
    case tileAll
    case cascadeAll
    case rotateLayout
    case retileWindows
    case toggleFloating

    init?(actionID: String) {
        guard actionID.hasPrefix("window.") else { return nil }
        self.init(rawValue: String(actionID.dropFirst("window.".count)))
    }

    var actionID: String { "window.\(rawValue)" }
    var hotKeyBindingID: String { actionID }

    var group: WindowActionGroup {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            .halvesAndQuarters
        case .firstThird, .lastThird:
            .thirds
        case .maximize, .minimized, .maximizeHeight, .maximizeWidth, .center, .restore:
            .fillAndCenter
        case .makeLarger, .makeSmaller:
            .resize
        case .nextDisplay, .previousDisplay:
            .displays
        case .tileAll, .cascadeAll:
            .arrange
        case .rotateLayout, .retileWindows, .toggleFloating:
            .tiling
        }
    }

    /// Step actions build on the window's current frame. Repeated presses must each apply in
    /// order instead of the newest press cancelling the ones still waiting to run.
    var isIncremental: Bool {
        group == .resize
    }

    /// Halves and quarters cycle through half, a third, and two thirds when the same
    /// shortcut is pressed again on the same window.
    var cyclesSize: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeftQuarter: "Top Left Quarter"
        case .topRightQuarter: "Top Right Quarter"
        case .bottomLeftQuarter: "Bottom Left Quarter"
        case .bottomRightQuarter: "Bottom Right Quarter"
        case .firstThird: "Left Third"
        case .lastThird: "Right Third"
        case .maximize: "Maximize Window"
        case .minimized: "Almost Maximize"
        case .maximizeHeight: "Maximize Height"
        case .maximizeWidth: "Maximize Width"
        case .center: "Center Window"
        case .makeLarger: "Make Larger"
        case .makeSmaller: "Make Smaller"
        case .nextDisplay: "Move to Next Display"
        case .previousDisplay: "Move to Previous Display"
        case .restore: "Restore Previous Size"
        case .tileAll: "Tile All Windows"
        case .cascadeAll: "Cascade All Windows"
        case .rotateLayout: "Rotate Tiling Layout"
        case .retileWindows: "Retile Windows"
        case .toggleFloating: "Float or Tile Window"
        }
    }

    /// Search keywords. Settings shows the first one as the row's subtitle.
    var aliases: [String] {
        switch self {
        case .leftHalf: ["window left", "snap left", "tile left"]
        case .rightHalf: ["window right", "snap right", "tile right"]
        case .topHalf: ["window top", "snap top", "tile top"]
        case .bottomHalf: ["window bottom", "snap bottom", "tile bottom"]
        case .topLeftQuarter: ["window top left", "snap top left", "corner top left"]
        case .topRightQuarter: ["window top right", "snap top right", "corner top right"]
        case .bottomLeftQuarter: ["window bottom left", "snap bottom left", "corner bottom left"]
        case .bottomRightQuarter: ["window bottom right", "snap bottom right", "corner bottom right"]
        case .firstThird: ["window left third", "first third", "tile third"]
        case .lastThird: ["window right third", "last third"]
        case .maximize: ["window full", "fill screen", "zoom window"]
        case .minimized: ["window almost maximize", "reasonable size", "window minimized", "minimize window", "restore down"]
        case .maximizeHeight: ["window full height", "fill height", "stretch vertically"]
        case .maximizeWidth: ["window full width", "fill width", "stretch horizontally"]
        case .center: ["window center", "recenter"]
        case .makeLarger: ["window larger", "grow window", "increase window size", "bigger"]
        case .makeSmaller: ["window smaller", "shrink window", "decrease window size"]
        case .nextDisplay: ["window next monitor", "move display", "next screen"]
        case .previousDisplay: ["window previous monitor", "previous screen"]
        case .restore: ["window restore", "undo window", "original size"]
        case .tileAll: ["windows grid", "tile windows", "arrange windows"]
        case .cascadeAll: ["windows cascade", "stack windows", "overlap windows"]
        case .rotateLayout: ["tiling rotate", "flip layout"]
        case .retileWindows: ["tiling retile", "rearrange tiles"]
        case .toggleFloating: ["tiling float", "untile window", "float window"]
        }
    }

    /// Public SF Symbols in preference order, resolved by `NativeIconCatalog`.
    var symbolCandidates: [String] {
        switch self {
        case .leftHalf: ["rectangle.lefthalf.inset.filled"]
        case .rightHalf: ["rectangle.righthalf.inset.filled"]
        case .topHalf: ["rectangle.tophalf.inset.filled"]
        case .bottomHalf: ["rectangle.bottomhalf.inset.filled"]
        case .topLeftQuarter: ["rectangle.inset.topleft.filled", "rectangle.split.2x2"]
        case .topRightQuarter: ["rectangle.inset.topright.filled", "rectangle.split.2x2"]
        case .bottomLeftQuarter: ["rectangle.inset.bottomleft.filled", "rectangle.split.2x2"]
        case .bottomRightQuarter: ["rectangle.inset.bottomright.filled", "rectangle.split.2x2"]
        case .firstThird: ["rectangle.leadingthird.inset.filled", "rectangle.split.3x1"]
        case .lastThird: ["rectangle.trailingthird.inset.filled", "rectangle.split.3x1"]
        case .maximize: ["arrow.up.left.and.arrow.down.right"]
        case .minimized: ["arrow.down.right.and.arrow.up.left", "rectangle.inset.filled", "rectangle"]
        case .maximizeHeight: ["arrow.up.and.down"]
        case .maximizeWidth: ["arrow.left.and.right"]
        case .center: ["rectangle.center.inset.filled"]
        case .makeLarger: ["plus.rectangle", "plus.square"]
        case .makeSmaller: ["minus.rectangle", "minus.square"]
        case .nextDisplay: ["arrow.right.to.line"]
        case .previousDisplay: ["arrow.left.to.line"]
        case .restore: ["arrow.uturn.backward"]
        case .tileAll: ["square.grid.2x2"]
        case .cascadeAll: ["square.stack.3d.down.right", "square.stack"]
        case .rotateLayout: ["rotate.right"]
        case .retileWindows: ["rectangle.3.group"]
        case .toggleFloating: ["pip"]
        }
    }

    /// Only the original layouts ship with shortcuts. There are not enough memorable key
    /// combinations for every action, so the rest start unassigned.
    var defaultShortcut: HotKeyConfiguration? {
        let command = UInt32(cmdKey)
        let commandOption = UInt32(cmdKey | optionKey)
        switch self {
        case .leftHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_LeftArrow), modifiers: command)
        case .rightHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_RightArrow), modifiers: command)
        case .topHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_UpArrow), modifiers: commandOption)
        case .bottomHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_DownArrow), modifiers: commandOption)
        case .maximize:
            return HotKeyConfiguration(keyCode: UInt32(kVK_UpArrow), modifiers: command)
        case .minimized:
            return HotKeyConfiguration(keyCode: UInt32(kVK_DownArrow), modifiers: command)
        case .center:
            return HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_C), modifiers: commandOption)
        case .nextDisplay:
            return HotKeyConfiguration(keyCode: UInt32(kVK_RightArrow), modifiers: commandOption)
        case .previousDisplay:
            return HotKeyConfiguration(keyCode: UInt32(kVK_LeftArrow), modifiers: commandOption)
        default:
            return nil
        }
    }
}

enum WindowRepeatBehavior: String, Codable, CaseIterable, Sendable {
    case none
    case cycleSizes

    var title: String {
        switch self {
        case .none: "Do Nothing"
        case .cycleSizes: "Cycle ½, ⅓, ⅔"
        }
    }
}

struct WindowLayoutOptions: Equatable, Sendable {
    var resizeStep: CGFloat
    var almostMaximizeFraction: CGFloat
    /// Make Smaller and the edge actions stop at this share of the screen on each axis.
    var minimumSizeFraction: CGFloat
    var repeatBehavior: WindowRepeatBehavior = .cycleSizes
    var screenEdgeGap: CGFloat = 0
    var windowGap: CGFloat = 0
    var ignoredBundleIdentifiers: Set<String> = []
    var automaticTilingEnabled = false

    static let standard = WindowLayoutOptions(
        resizeStep: 30,
        almostMaximizeFraction: 0.9,
        minimumSizeFraction: 0.25
    )
}

struct WindowManagementPreferences: Codable, Equatable, Sendable {
    static let resizeStepOptions: [Double] = [10, 20, 30, 50, 100]
    static let almostMaximizeOptions: [Double] = [0.8, 0.85, 0.9, 0.95]
    static let gapOptions: [Double] = [0, 4, 8, 12, 16, 24]
    static let defaultResizeStep: Double = 30
    static let defaultAlmostMaximizeFraction: Double = 0.9
    static let maximumCustomLayouts = 50
    static let maximumWorkspaces = 20

    var shortcutsEnabled: Bool
    var shortcuts: [WindowAction: HotKeyConfiguration]
    /// Actions whose default shortcut the user removed. Without this, a missing entry would
    /// be refilled with the default on the next launch.
    var unassignedShortcuts: Set<WindowAction>
    var resizeStep: Double
    var almostMaximizeFraction: Double
    var repeatBehavior: WindowRepeatBehavior = .cycleSizes
    /// Set once the development default of “do nothing” has been replaced by size cycling,
    /// so a later choice of Do Nothing is kept.
    var repeatedSizeCycleAdopted = false
    var screenEdgeGap: Double = 0
    var windowGap: Double = 0
    /// Window shortcuts pause while one of these applications is frontmost, so it receives
    /// the keystroke. Automatic tiling also leaves their windows alone.
    var ignoredBundleIdentifiers: Set<String> = []
    var customLayouts: [CustomWindowLayout] = []
    var workspaces: [WindowWorkspace] = []
    var dragToSnapEnabled = false
    var automaticTilingEnabled = false

    init(
        shortcutsEnabled: Bool = false,
        shortcuts: [WindowAction: HotKeyConfiguration] = [:],
        unassignedShortcuts: Set<WindowAction> = [],
        resizeStep: Double = Self.defaultResizeStep,
        almostMaximizeFraction: Double = Self.defaultAlmostMaximizeFraction
    ) {
        self.shortcutsEnabled = shortcutsEnabled
        self.shortcuts = shortcuts
        self.unassignedShortcuts = unassignedShortcuts
        self.resizeStep = resizeStep
        self.almostMaximizeFraction = almostMaximizeFraction
        for action in WindowAction.allCases
        where self.shortcuts[action] == nil && !unassignedShortcuts.contains(action) {
            self.shortcuts[action] = action.defaultShortcut
        }
        for action in unassignedShortcuts { self.shortcuts[action] = nil }
    }

    func shortcut(for action: WindowAction) -> HotKeyConfiguration? {
        shortcuts[action]
    }

    mutating func setShortcut(_ configuration: HotKeyConfiguration?, for action: WindowAction) {
        shortcuts[action] = configuration
        if configuration == nil {
            unassignedShortcuts.insert(action)
        } else {
            unassignedShortcuts.remove(action)
        }
    }

    /// The window action other than `action` that already uses `configuration`, if any.
    func action(using configuration: HotKeyConfiguration, excluding action: WindowAction) -> WindowAction? {
        WindowAction.allCases.first { $0 != action && shortcuts[$0] == configuration }
    }

    func shortcut(for target: WindowShortcutTarget) -> HotKeyConfiguration? {
        switch target {
        case .action(let action): shortcut(for: action)
        case .layout(let id): customLayouts.first { $0.id == id }?.shortcut
        case .workspace(let id): workspaces.first { $0.id == id }?.shortcut
        }
    }

    mutating func setShortcut(_ configuration: HotKeyConfiguration?, for target: WindowShortcutTarget) {
        switch target {
        case .action(let action):
            setShortcut(configuration, for: action)
        case .layout(let id):
            guard let index = customLayouts.firstIndex(where: { $0.id == id }) else { return }
            customLayouts[index].shortcut = configuration
        case .workspace(let id):
            guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
            workspaces[index].shortcut = configuration
        }
    }

    /// Every window target that can carry a shortcut, in Settings order.
    var shortcutTargets: [WindowShortcutTarget] {
        WindowAction.allCases.map(WindowShortcutTarget.action)
            + customLayouts.map { .layout($0.id) }
            + workspaces.map { .workspace($0.id) }
    }

    func title(for target: WindowShortcutTarget) -> String {
        switch target {
        case .action(let action): action.title
        case .layout(let id): customLayouts.first { $0.id == id }?.name ?? "Custom Layout"
        case .workspace(let id): workspaces.first { $0.id == id }?.name ?? "Workspace"
        }
    }

    /// The title of the window target other than `target` that already uses `configuration`.
    func owner(of configuration: HotKeyConfiguration, excluding target: WindowShortcutTarget) -> String? {
        shortcutTargets.first { $0 != target && shortcut(for: $0) == configuration }.map(title(for:))
    }

    var layoutOptions: WindowLayoutOptions {
        WindowLayoutOptions(
            resizeStep: CGFloat(resizeStep),
            almostMaximizeFraction: CGFloat(almostMaximizeFraction),
            minimumSizeFraction: WindowLayoutOptions.standard.minimumSizeFraction,
            repeatBehavior: repeatBehavior,
            screenEdgeGap: CGFloat(screenEdgeGap),
            windowGap: CGFloat(windowGap),
            ignoredBundleIdentifiers: ignoredBundleIdentifiers,
            automaticTilingEnabled: automaticTilingEnabled
        )
    }

    mutating func sanitize() {
        resizeStep = Self.nearest(resizeStep, in: Self.resizeStepOptions, fallback: Self.defaultResizeStep)
        almostMaximizeFraction = Self.nearest(
            almostMaximizeFraction,
            in: Self.almostMaximizeOptions,
            fallback: Self.defaultAlmostMaximizeFraction
        )
        screenEdgeGap = Self.nearest(screenEdgeGap, in: Self.gapOptions, fallback: 0)
        windowGap = Self.nearest(windowGap, in: Self.gapOptions, fallback: 0)
        ignoredBundleIdentifiers = Set(ignoredBundleIdentifiers.compactMap { identifier in
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        })

        var seenLayouts = Set<UUID>()
        customLayouts = customLayouts
            .filter { seenLayouts.insert($0.id).inserted }
            .prefix(Self.maximumCustomLayouts)
            .map { layout in
                var layout = layout
                layout.sanitize()
                return layout
            }
        var seenWorkspaces = Set<UUID>()
        workspaces = workspaces
            .filter { seenWorkspaces.insert($0.id).inserted }
            .prefix(Self.maximumWorkspaces)
            .map { workspace in
                var workspace = workspace
                workspace.sanitize()
                return workspace
            }

        // Two targets must never share a shortcut; keep the first and clear later copies.
        var claimed: [HotKeyConfiguration] = []
        for target in shortcutTargets {
            guard let configuration = shortcut(for: target) else { continue }
            if claimed.contains(configuration) {
                setShortcut(nil, for: target)
            } else {
                claimed.append(configuration)
            }
        }
    }

    /// Pressing a half or quarter again cycles its size. Installations saved before that
    /// was the default still say Do Nothing; adopt the cycle once, then leave the choice alone.
    mutating func adoptRepeatedSizeCycle() {
        guard !repeatedSizeCycleAdopted else { return }
        if repeatBehavior == .none { repeatBehavior = .cycleSizes }
        repeatedSizeCycleAdopted = true
    }

    mutating func migrateInterimDefaultShortcuts() {
        guard shortcuts == Self.interimDefaultShortcuts else { return }
        shortcuts = WindowAction.allCases.reduce(into: [:]) { result, action in
            result[action] = action.defaultShortcut
        }
    }

    private static func nearest(_ value: Double, in options: [Double], fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return options.min { abs($0 - value) < abs($1 - value) } ?? fallback
    }

    // These defaults shipped briefly during development. Migrate only an exact match so
    // user-customized shortcuts are never overwritten.
    private static let interimDefaultShortcuts: [WindowAction: HotKeyConfiguration] = [
        .leftHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .rightHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .topHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .bottomHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .maximize: HotKeyConfiguration(
            keyCode: UInt32(kVK_Return),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .minimized: HotKeyConfiguration(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(cmdKey)
        ),
        .center: HotKeyConfiguration(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .nextDisplay: HotKeyConfiguration(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
        .previousDisplay: HotKeyConfiguration(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
    ]

    private enum CodingKeys: String, CodingKey {
        case shortcutsEnabled, shortcuts, unassignedShortcuts, resizeStep, almostMaximizeFraction
        case repeatBehavior, repeatedSizeCycleAdopted, screenEdgeGap, windowGap, ignoredBundleIdentifiers
        case customLayouts, workspaces, dragToSnapEnabled, automaticTilingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shortcutsEnabled: try container.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? false,
            shortcuts: Self.decodeShortcuts(from: container),
            unassignedShortcuts: Set(
                ((try? container.decodeIfPresent([String].self, forKey: .unassignedShortcuts)) ?? [])
                    .compactMap(WindowAction.init(rawValue:))
            ),
            resizeStep: (try? container.decodeIfPresent(Double.self, forKey: .resizeStep))
                ?? Self.defaultResizeStep,
            almostMaximizeFraction: (try? container.decodeIfPresent(Double.self, forKey: .almostMaximizeFraction))
                ?? Self.defaultAlmostMaximizeFraction
        )
        // Each newer setting decodes on its own so one unreadable value falls back to its
        // default without discarding the rest of the window preferences.
        repeatBehavior = (try? container.decodeIfPresent(WindowRepeatBehavior.self, forKey: .repeatBehavior)) ?? .cycleSizes
        repeatedSizeCycleAdopted = (try? container.decodeIfPresent(Bool.self, forKey: .repeatedSizeCycleAdopted)) ?? false
        screenEdgeGap = (try? container.decodeIfPresent(Double.self, forKey: .screenEdgeGap)) ?? 0
        windowGap = (try? container.decodeIfPresent(Double.self, forKey: .windowGap)) ?? 0
        ignoredBundleIdentifiers = Set(
            (try? container.decodeIfPresent([String].self, forKey: .ignoredBundleIdentifiers)) ?? []
        )
        customLayouts = Self.decodeLossy(CustomWindowLayout.self, from: container, forKey: .customLayouts)
        workspaces = Self.decodeLossy(WindowWorkspace.self, from: container, forKey: .workspaces)
        dragToSnapEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .dragToSnapEnabled)) ?? false
        automaticTilingEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .automaticTilingEnabled)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shortcutsEnabled, forKey: .shortcutsEnabled)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(unassignedShortcuts.map(\.rawValue).sorted(), forKey: .unassignedShortcuts)
        try container.encode(resizeStep, forKey: .resizeStep)
        try container.encode(almostMaximizeFraction, forKey: .almostMaximizeFraction)
        try container.encode(repeatBehavior, forKey: .repeatBehavior)
        try container.encode(repeatedSizeCycleAdopted, forKey: .repeatedSizeCycleAdopted)
        try container.encode(screenEdgeGap, forKey: .screenEdgeGap)
        try container.encode(windowGap, forKey: .windowGap)
        try container.encode(ignoredBundleIdentifiers.sorted(), forKey: .ignoredBundleIdentifiers)
        try container.encode(customLayouts, forKey: .customLayouts)
        try container.encode(workspaces, forKey: .workspaces)
        try container.encode(dragToSnapEnabled, forKey: .dragToSnapEnabled)
        try container.encode(automaticTilingEnabled, forKey: .automaticTilingEnabled)
    }

    /// Decodes an array element by element, skipping any element this build cannot read.
    private static func decodeLossy<Element: Decodable>(
        _ type: Element.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [Element] {
        guard var elements = try? container.nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [Element] = []
        while !elements.isAtEnd {
            if let element = try? elements.decode(Element.self) {
                result.append(element)
            } else if (try? elements.decode(LossySkip.self)) == nil {
                break
            }
        }
        return result
    }

    private struct LossySkip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    /// Swift encodes a dictionary keyed by a `String` enum as alternating key and value
    /// entries. Read that format one pair at a time so an identifier from a newer or older
    /// build is skipped instead of discarding every saved shortcut.
    private static func decodeShortcuts(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [WindowAction: HotKeyConfiguration] {
        guard var pairs = try? container.nestedUnkeyedContainer(forKey: .shortcuts) else { return [:] }
        var result: [WindowAction: HotKeyConfiguration] = [:]
        while !pairs.isAtEnd {
            guard let rawValue = try? pairs.decode(String.self),
                  !pairs.isAtEnd,
                  let configuration = try? pairs.decode(HotKeyConfiguration.self) else { break }
            if let action = WindowAction(rawValue: rawValue) {
                result[action] = configuration
            }
        }
        return result
    }
}

enum WindowShortcutRegistrationSummary {
    static func message(failedTitles: [String]) -> String? {
        switch failedTitles.count {
        case 0:
            nil
        case 1:
            "The \(failedTitles[0]) shortcut is already in use or unavailable."
        default:
            "\(failedTitles.count) shortcuts are already in use or unavailable: \(failedTitles.joined(separator: ", "))."
        }
    }
}

/// Anything in Window Management that can own a global shortcut.
enum WindowShortcutTarget: Hashable, Sendable {
    case action(WindowAction)
    case layout(UUID)
    case workspace(UUID)

    var bindingID: String {
        switch self {
        case .action(let action): action.hotKeyBindingID
        case .layout(let id): "\(Self.layoutPrefix)\(id.uuidString)"
        case .workspace(let id): "\(Self.workspacePrefix)\(id.uuidString)"
        }
    }

    static let layoutPrefix = "window.layout."
    static let workspacePrefix = "window.workspace."

    /// Parses the launcher and hot-key identifier form, such as `window.leftHalf` or
    /// `window.layout.<UUID>`.
    init?(actionID: String) {
        if actionID.hasPrefix(Self.layoutPrefix) {
            guard let id = UUID(uuidString: String(actionID.dropFirst(Self.layoutPrefix.count))) else { return nil }
            self = .layout(id)
        } else if actionID.hasPrefix(Self.workspacePrefix) {
            guard let id = UUID(uuidString: String(actionID.dropFirst(Self.workspacePrefix.count))) else { return nil }
            self = .workspace(id)
        } else if let action = WindowAction(actionID: actionID) {
            self = .action(action)
        } else {
            return nil
        }
    }
}

enum WindowShortcutChangeResult: Equatable, Sendable {
    /// The shortcut was saved. `registrationError` reports any window shortcut that still
    /// could not be registered, including ones unrelated to this change.
    case applied(registrationError: String?)
    case rejected(String)
}
