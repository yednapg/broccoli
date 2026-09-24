@preconcurrency import AppKit
import BroccoliCore

/// Stable semantic SF Symbol mappings for built-in launcher actions.
///
/// Keeping these mappings explicit prevents a newly added action from silently inheriting a
/// generic icon. SF Symbols remain template-backed so macOS controls their weight, contrast,
/// and Light/Dark rendering. Application, Settings, and file results come from `NSWorkspace`
/// and Quick Look instead of stand-in glyphs.
enum NativeIconCatalog {
    /// Public SF Symbols in semantic preference order. Every primary symbol is available on
    /// the macOS 15 deployment target; the older, broader fallbacks keep the launcher usable if
    /// Apple changes symbol availability on a later release. These are deliberately unstyled:
    /// `IconCache` turns the resolved glyph into a template image and AppKit supplies its tint.
    static let actionSymbolCandidates: [String: [String]] = [
        "appearance.toggleDark": ["circle.lefthalf.filled", "circle.lefthalf.fill", "circle"],
        "audio.toggleMute": ["speaker.slash.fill", "speaker.slash", "speaker"],
        "audio.volumeUp": ["speaker.plus.fill", "speaker.wave.3.fill", "speaker.plus", "speaker.wave.3", "speaker"],
        "audio.volumeDown": ["speaker.minus.fill", "speaker.wave.1.fill", "speaker.minus", "speaker.wave.1", "speaker"],
        "screensaver.start": ["tv.fill", "display", "rectangle"],
        "catalog.refresh": ["arrow.clockwise", "arrow.triangle.2.circlepath"],
        "broccoli.preferences": ["gearshape", "gear"],
        "broccoli.quit": ["xmark.circle", "xmark"],
        "power.sleep": ["powersleep", "moon.zzz", "moon.fill", "moon"],
        "power.restart": ["restart", "arrow.clockwise"],
        "power.shutdown": ["poweroff", "power", "power.circle"],
        "power.logout": ["rectangle.portrait.and.arrow.forward", "rectangle.portrait.and.arrow.right", "arrow.right.square"],
    ].merging(
        WindowAction.allCases.map { ($0.actionID, $0.symbolCandidates) },
        uniquingKeysWith: { current, _ in current }
    )

    static var actionSymbols: [String: String] {
        actionSymbolCandidates.compactMapValues(\.first)
    }

    static func actionSymbols(for entry: SearchEntry) -> [String] {
        guard case .action(let id) = entry.target else { return [] }
        return actionSymbols(forActionID: id)
    }

    static func actionSymbols(forActionID id: String) -> [String] {
        if let symbols = actionSymbolCandidates[id] { return symbols }
        if id.hasPrefix(WindowShortcutTarget.layoutPrefix) { return ["rectangle.dashed", "rectangle"] }
        if id.hasPrefix(WindowShortcutTarget.workspacePrefix) { return ["rectangle.3.group", "square.grid.2x2"] }
        return ["bolt"]
    }

    /// SwiftUI's `Image(systemName:)` accepts one name, so Settings resolves the same ordered
    /// candidates used by the launcher before constructing its row. The returned glyph is
    /// always supplied by macOS; Broccoli never substitutes bundled artwork.
    static func resolvedActionSymbolName(forActionID id: String) -> String {
        var visited = Set<String>()
        for name in actionSymbols(forActionID: id) + ["bolt", "questionmark"]
        where visited.insert(name).inserted {
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                return name
            }
        }
        return "questionmark"
    }
}
