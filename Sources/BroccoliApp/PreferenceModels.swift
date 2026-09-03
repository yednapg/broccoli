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
    var verticalPosition: Double
    var showsSubtitles: Bool
    var showsShortcuts: Bool

    static func defaults(design: LauncherDesign = .liquidGlass) -> Self {
        Self(
            design: design,
            mode: .system,
            visibleResultCount: 7,
            screen: .active,
            verticalPosition: 0.18,
            showsSubtitles: true,
            showsShortcuts: true
        )
    }

    mutating func sanitize() {
        visibleResultCount = min(10, max(3, visibleResultCount))
        verticalPosition = min(0.5, max(0.05, verticalPosition))
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
