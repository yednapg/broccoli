import Foundation

public struct SettingsDefinition: Sendable {
    public let id: String
    public let title: String
    public let aliases: [String]
    private let routesByMajorVersion: [Int: String]
    public var route: String? {
        route(forMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    public init(id: String, title: String, aliases: [String], route: String?) {
        self.id = id
        self.title = title
        self.aliases = aliases
        routesByMajorVersion = route.map { [15: $0, 26: $0, 27: $0] } ?? [:]
    }

    public init(
        id: String,
        title: String,
        aliases: [String],
        routesByMajorVersion: [Int: String]
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.routesByMajorVersion = routesByMajorVersion
    }

    public func route(forMajorVersion majorVersion: Int) -> String? {
        routesByMajorVersion[majorVersion]
    }

    public var searchEntry: SearchEntry {
        SearchEntry(
            id: "setting:\(id)",
            kind: .systemSetting,
            title: title,
            subtitle: "System Settings → \(title)",
            keywords: aliases,
            iconKey: "setting:\(id)",
            target: .setting(route: route)
        )
    }
}

public enum SettingsCatalog {
    public static let definitions: [SettingsDefinition] = [
        item("wifi", "Wi-Fi", ["wireless", "internet"], "com.apple.wifi-settings-extension"),
        item("bluetooth", "Bluetooth", ["devices", "wireless"], "com.apple.BluetoothSettings"),
        item("network", "Network", ["ethernet", "vpn", "internet"], "com.apple.Network-Settings.extension"),
        item("notifications", "Notifications", ["alerts", "banners"], "com.apple.Notifications-Settings.extension"),
        item("sound", "Sound", ["audio", "volume", "microphone", "speakers"], "com.apple.Sound-Settings.extension"),
        item("focus", "Focus", ["do not disturb", "dnd"], "com.apple.Focus-Settings.extension"),
        item("general", "General", ["about", "language", "startup disk"], "com.apple.systempreferences.GeneralSettings"),
        item("appearance", "Appearance", ["dark mode", "light mode", "theme"], "com.apple.Appearance-Settings.extension"),
        item("accessibility", "Accessibility", ["vision", "hearing", "motor"], "com.apple.Accessibility-Settings.extension"),
        item("control-center", "Control Center", ["menu bar", "modules"], "com.apple.ControlCenter-Settings.extension"),
        item("siri-spotlight", "Siri & Spotlight", ["search", "assistant", "spotlight"], "com.apple.Siri-Settings.extension"),
        item("desktop-dock", "Desktop & Dock", ["dock", "mission control", "stage manager"], "com.apple.Desktop-Settings.extension"),
        item("displays", "Displays", ["screen", "monitor", "resolution", "brightness"], "com.apple.Displays-Settings.extension"),
        item("wallpaper", "Wallpaper", ["background", "desktop picture"], "com.apple.Wallpaper-Settings.extension"),
        item("screen-saver", "Screen Saver", ["screensaver", "idle"], "com.apple.ScreenSaver-Settings.extension"),
        item("battery", "Battery", ["energy", "power", "low power mode"], "com.apple.Battery-Settings.extension"),
        item("lock-screen", "Lock Screen Settings", ["password", "display off", "login window"], "com.apple.Lock-Screen-Settings.extension"),
        item("keyboard", "Keyboard", ["shortcuts", "input sources", "typing"], "com.apple.Keyboard-Settings.extension"),
        item("trackpad", "Trackpad", ["gestures", "click", "scroll"], "com.apple.Trackpad-Settings.extension"),
        item("mouse", "Mouse", ["pointer", "scroll", "click"], "com.apple.Mouse-Settings.extension"),
        item("printers", "Printers & Scanners", ["printer", "scanner"], "com.apple.Print-Scan-Settings.extension"),
        item("privacy", "Privacy & Security", ["permissions", "security", "automation", "location"], "com.apple.settings.PrivacySecurity.extension"),
        item("software-update", "Software Update", ["update", "macos update"], "com.apple.Software-Update-Settings.extension"),
        item("storage", "Storage", ["disk", "space"], "com.apple.settings.Storage"),
        item("date-time", "Date & Time", ["clock", "timezone", "time zone"], "com.apple.Date-Time-Settings.extension"),
        item("time-machine", "Time Machine", ["backup", "restore"], "com.apple.Time-Machine-Settings.extension"),
        item("sharing", "Sharing", ["remote login", "screen sharing", "file sharing"], "com.apple.Sharing-Settings.extension"),
        item("users", "Users & Groups", ["account", "user"], "com.apple.Users-Groups-Settings.extension"),
        item("login-items", "Login Items", ["startup apps", "open at login", "background items"], "com.apple.LoginItems-Settings.extension"),
        item("keyboard-shortcuts", "Keyboard Shortcuts", ["hotkeys", "spotlight shortcut", "key bindings"], "com.apple.Keyboard-Settings.extension?Shortcuts"),
        item("passwords", "Passwords", ["passkeys", "credentials"], "com.apple.Passwords-Settings.extension"),
        item("internet-accounts", "Internet Accounts", ["mail account", "calendar account"], "com.apple.Internet-Accounts-Settings.extension"),
    ]

    public static var searchEntries: [SearchEntry] {
        definitions.map(\.searchEntry)
    }

    private static func item(
        _ id: String,
        _ title: String,
        _ aliases: [String],
        _ paneIdentifier: String
    ) -> SettingsDefinition {
        let route = "x-apple.systempreferences:\(paneIdentifier)"
        return SettingsDefinition(
            id: id,
            title: title,
            aliases: aliases,
            routesByMajorVersion: [15: route, 26: route, 27: route]
        )
    }
}
