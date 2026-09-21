import Foundation

enum LauncherDesign: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal
    case liquidGlass

    var id: String { rawValue }
    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .liquidGlass: "Liquid Glass"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .liquidGlass
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum LauncherAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum LauncherScreenPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case pointer
    case primary

    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: "Active display"
        case .pointer: "Display under pointer"
        case .primary: "Primary display"
        }
    }
}

struct LauncherAppearancePreferences: Codable, Equatable, Sendable {
    var design: LauncherDesign
    var mode: LauncherAppearanceMode
    var visibleResultCount: Int
    var screen: LauncherScreenPreference
    /// Remaining-width fraction of the panel's leading edge in the visible frame. `0.5` is centered.
    var originX: Double
    /// Top-edge inset as a fraction of the visible frame height. Migrated from the retired `verticalPosition`.
    var originY: Double
    var showsSubtitles: Bool
    var showsShortcuts: Bool

    static let defaultOriginX: Double = 0.5
    static let defaultOriginY: Double = 0.18

    static func defaults(design: LauncherDesign = .liquidGlass) -> Self {
        Self(
            design: design,
            mode: .system,
            visibleResultCount: 7,
            screen: .active,
            originX: defaultOriginX,
            originY: defaultOriginY,
            showsSubtitles: true,
            showsShortcuts: true
        )
    }

    mutating func sanitize() {
        visibleResultCount = min(10, max(3, visibleResultCount))
        originX = Self.sanitizedOrigin(originX, fallback: Self.defaultOriginX)
        originY = Self.sanitizedOrigin(originY, fallback: Self.defaultOriginY)
    }

    private static func sanitizedOrigin(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(1, max(0, value))
    }

    private enum CodingKeys: String, CodingKey {
        case design, mode, visibleResultCount, screen
        case originX, originY, verticalPosition
        case showsSubtitles, showsShortcuts
    }

    init(
        design: LauncherDesign,
        mode: LauncherAppearanceMode,
        visibleResultCount: Int,
        screen: LauncherScreenPreference,
        originX: Double,
        originY: Double,
        showsSubtitles: Bool,
        showsShortcuts: Bool
    ) {
        self.design = design
        self.mode = mode
        self.visibleResultCount = visibleResultCount
        self.screen = screen
        self.originX = originX
        self.originY = originY
        self.showsSubtitles = showsSubtitles
        self.showsShortcuts = showsShortcuts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        design = try container.decodeIfPresent(LauncherDesign.self, forKey: .design) ?? .liquidGlass
        mode = try container.decodeIfPresent(LauncherAppearanceMode.self, forKey: .mode) ?? .system
        visibleResultCount = try container.decodeIfPresent(Int.self, forKey: .visibleResultCount) ?? 7
        screen = try container.decodeIfPresent(LauncherScreenPreference.self, forKey: .screen) ?? .active
        showsSubtitles = try container.decodeIfPresent(Bool.self, forKey: .showsSubtitles) ?? true
        showsShortcuts = try container.decodeIfPresent(Bool.self, forKey: .showsShortcuts) ?? true
        let decodedX = try container.decodeIfPresent(Double.self, forKey: .originX)
        let decodedY = try container.decodeIfPresent(Double.self, forKey: .originY)
        let legacyY = try container.decodeIfPresent(Double.self, forKey: .verticalPosition)
        originX = decodedX ?? Self.defaultOriginX
        originY = decodedY ?? legacyY ?? Self.defaultOriginY
        sanitize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(design, forKey: .design)
        try container.encode(mode, forKey: .mode)
        try container.encode(visibleResultCount, forKey: .visibleResultCount)
        try container.encode(screen, forKey: .screen)
        try container.encode(originX, forKey: .originX)
        try container.encode(originY, forKey: .originY)
        try container.encode(showsSubtitles, forKey: .showsSubtitles)
        try container.encode(showsShortcuts, forKey: .showsShortcuts)
    }
}

struct FileSearchPreferences: Codable, Equatable, Sendable {
    var enabled = true
}

struct CalculatorPreferences: Codable, Equatable, Sendable {
    var enabled: Bool
    var significantDigits: Int
    var usesGroupingSeparator: Bool

    init(
        enabled: Bool = true,
        significantDigits: Int = 12,
        usesGroupingSeparator: Bool = false
    ) {
        self.enabled = enabled
        self.significantDigits = significantDigits
        self.usesGroupingSeparator = usesGroupingSeparator
        sanitize()
    }

    mutating func sanitize() {
        significantDigits = [6, 9, 12].contains(significantDigits) ? significantDigits : 12
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, significantDigits, usesGroupingSeparator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        significantDigits = try container.decodeIfPresent(Int.self, forKey: .significantDigits) ?? 12
        usesGroupingSeparator = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesGroupingSeparator
        ) ?? false
        sanitize()
    }
}

struct ClipboardPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var retentionDays = 7
    var maximumItems = 500
    var maximumItemBytes = 10 * 1_024 * 1_024
    var capturesText = true
    var capturesURLs = true
    var capturesFiles = true
    var capturesImages = true
    var ignoredBundleIdentifiers: Set<String> = Self.defaultIgnoredBundleIdentifiers

    static let defaultIgnoredBundleIdentifiers: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
    ]

    mutating func sanitize() {
        retentionDays = [1, 7, 30].contains(retentionDays) ? retentionDays : 7
        maximumItems = [100, 500, 1_000].contains(maximumItems) ? maximumItems : 500
        maximumItemBytes = 10 * 1_024 * 1_024
    }
}

enum LauncherMode: Equatable, Sendable {
    case main
    case fileSearch(query: String)
    case clipboard(query: String)
}
