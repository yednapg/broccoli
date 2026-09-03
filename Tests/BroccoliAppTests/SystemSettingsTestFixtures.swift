import BroccoliCore

enum SystemSettingsTestFixtures {
    static let entries: [SearchEntry] = [
        entry("wallpaper", "Wallpaper", "com.apple.Wallpaper-Settings.extension"),
        entry("passwords", "Passwords", "com.apple.Passwords-Settings.extension"),
        entry("screen-saver", "Screen Saver", "com.apple.ScreenSaver-Settings.extension"),
        entry("keyboard", "Keyboard", "com.apple.Keyboard-Settings.extension"),
        entry(
            "keyboard-shortcuts",
            "Keyboard Shortcuts",
            "com.apple.Keyboard-Settings.extension",
            destination: "Shortcuts"
        ),
        entry("battery", "Battery", "com.apple.Battery-Settings.extension"),
    ]

    private static func entry(
        _ id: String,
        _ title: String,
        _ bundleIdentifier: String,
        destination: String? = nil
    ) -> SearchEntry {
        let suffix = destination.map { "?\($0)" } ?? ""
        return SearchEntry(
            id: "setting:\(id)",
            kind: .systemSetting,
            title: title,
            iconKey: "setting:\(id)",
            target: .setting(
                route: "x-apple.systempreferences:\(bundleIdentifier)\(suffix)"
            )
        )
    }
}
