@preconcurrency import AppKit
import BroccoliCore

/// Stable semantic SF Symbol mappings for every built-in launcher result.
///
/// Keeping these mappings explicit prevents a newly added Setting or action from silently
/// inheriting a generic icon. SF Symbols remain template-backed so macOS controls their weight,
/// contrast, and Light/Dark rendering; application and file results continue to come from
/// `NSWorkspace` and Quick Look instead.
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
        "window.leftHalf": ["rectangle.lefthalf.inset.filled"],
        "window.rightHalf": ["rectangle.righthalf.inset.filled"],
        "window.topHalf": ["rectangle.tophalf.inset.filled"],
        "window.bottomHalf": ["rectangle.bottomhalf.inset.filled"],
        "window.maximize": ["arrow.up.left.and.arrow.down.right"],
        "window.minimized": ["arrow.down.right.and.arrow.up.left", "rectangle.inset.filled", "rectangle"],
        "window.center": ["rectangle.center.inset.filled"],
        "window.nextDisplay": ["arrow.right.to.line"],
        "window.previousDisplay": ["arrow.left.to.line"],
        "catalog.refresh": ["arrow.clockwise", "arrow.triangle.2.circlepath"],
        "broccoli.preferences": ["gearshape", "gear"],
        "broccoli.quit": ["xmark.circle", "xmark"],
        "power.sleep": ["powersleep", "moon.zzz", "moon.fill", "moon"],
        "power.restart": ["restart", "arrow.clockwise"],
        "power.shutdown": ["poweroff", "power", "power.circle"],
        "power.logout": ["rectangle.portrait.and.arrow.forward", "rectangle.portrait.and.arrow.right", "arrow.right.square"],
    ]

    static var actionSymbols: [String: String] {
        actionSymbolCandidates.compactMapValues(\.first)
    }

    static let settingSymbols: [String: String] = [
        "wifi": "wifi",
        "bluetooth": "bolt.horizontal.circle",
        "network": "network",
        "notifications": "bell.badge",
        "sound": "speaker.wave.3",
        "focus": "moon.fill",
        "general": "gearshape",
        "appearance": "circle.lefthalf.filled",
        "accessibility": "accessibility",
        "control-center": "switch.2",
        "siri-spotlight": "magnifyingglass",
        "desktop-dock": "dock.rectangle",
        "displays": "display",
        // The native Wallpaper extension declares `photos` as an IconServices graphic-icon
        // name, not as a public SF Symbol. Keep this available symbol only as the immediate
        // fallback; IconCache replaces it with the extension's exact NSWorkspace icon.
        "wallpaper": "photo.on.rectangle.angled",
        "screen-saver": "rectangle.inset.filled",
        "battery": "battery.100percent",
        "lock-screen": "lock.rectangle",
        "keyboard": "keyboard",
        "trackpad": "rectangle.and.hand.point.up.left",
        "mouse": "computermouse",
        "printers": "printer",
        "privacy": "hand.raised.fill",
        "software-update": "arrow.triangle.2.circlepath",
        "storage": "internaldrive",
        "date-time": "clock",
        "time-machine": "clock.arrow.circlepath",
        "sharing": "square.and.arrow.up",
        "users": "person.2",
        "login-items": "rectangle.stack.badge.play",
        "keyboard-shortcuts": "command",
        "passwords": "key",
        "internet-accounts": "at",
    ]

    static func symbolName(for entry: SearchEntry) -> String {
        switch entry.target {
        case .action(let id): return actionSymbols[id] ?? "bolt"
        case .setting:
            let id = entry.iconKey.replacingOccurrences(of: "setting:", with: "")
            return settingSymbols[id] ?? "gearshape"
        default:
            return "questionmark.square.dashed"
        }
    }

    static func actionSymbols(for entry: SearchEntry) -> [String] {
        guard case .action(let id) = entry.target else { return [] }
        return actionSymbols(forActionID: id)
    }

    static func actionSymbols(forActionID id: String) -> [String] {
        actionSymbolCandidates[id] ?? ["bolt"]
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
