import Foundation
import XCTest
@testable import BroccoliCore

/// Querying “setting” matches many System Settings panes and the System Settings
/// application with the same token-prefix score. Equal relevance must favor launchable
/// applications so the app is never buried under alphabetically earlier panes.
final class SearchTieBreakTests: XCTestCase {
    private let engine = SearchEngine()

    func testSettingQuerySurfacesTheSystemSettingsApplication() {
        let app = SearchEntry(
            id: "app:system-settings",
            kind: .application,
            title: "System Settings",
            target: .application(
                path: "/System/Applications/System Settings.app",
                bundleIdentifier: "com.apple.systempreferences"
            )
        )
        let panes: [SearchEntry] = [
            SearchEntry(id: "setting:wallpaper", kind: .systemSetting, title: "Wallpaper",
                        keywords: ["setting wallpaper desktop"], target: .setting(route: nil)),
            SearchEntry(id: "setting:network", kind: .systemSetting, title: "Network",
                        keywords: ["setting network wifi"], target: .setting(route: nil)),
            SearchEntry(id: "setting:sound", kind: .systemSetting, title: "Sound",
                        keywords: ["setting sound volume"], target: .setting(route: nil)),
            SearchEntry(id: "setting:display", kind: .systemSetting, title: "Displays",
                        keywords: ["setting display brightness"], target: .setting(route: nil)),
            SearchEntry(id: "setting:bluetooth", kind: .systemSetting, title: "Bluetooth",
                        keywords: ["setting bluetooth"], target: .setting(route: nil)),
            SearchEntry(id: "setting:printer", kind: .systemSetting, title: "Printers & Scanners",
                        keywords: ["setting printer scanner"], target: .setting(route: nil)),
            SearchEntry(id: "setting:battery", kind: .systemSetting, title: "Battery",
                        keywords: ["setting battery energy"], target: .setting(route: nil)),
            SearchEntry(id: "setting:privacy", kind: .systemSetting, title: "Privacy & Security",
                        keywords: ["setting privacy security"], target: .setting(route: nil)),
            SearchEntry(id: "setting:setting-up-printers", kind: .systemSetting,
                        title: "Setting up printers", target: .setting(route: nil)),
            SearchEntry(id: "setting:setting-up-scanners", kind: .systemSetting,
                        title: "Setting up scanners", target: .setting(route: nil)),
        ]
        let snapshot = SearchSnapshot(entries: [app] + panes)

        let results = engine.search(query: "setting", snapshot: snapshot, usage: [:], limit: 7)
        XCTAssertEqual(results.first?.entry.id, "app:system-settings")
        XCTAssertTrue(results.contains { $0.entry.id == "app:system-settings" })
    }

    func testExactTitleStillOutranksKindPriority() {
        let pane = SearchEntry(id: "setting:settings", kind: .systemSetting, title: "Settings",
                               target: .setting(route: nil))
        let app = SearchEntry(id: "app:settings-helper", kind: .application, title: "Settings Helper",
                              target: .application(path: "/Applications/SH.app", bundleIdentifier: nil))
        let snapshot = SearchSnapshot(entries: [app, pane])

        let results = engine.search(query: "settings", snapshot: snapshot, usage: [:], limit: 7)
        XCTAssertEqual(results.first?.entry.id, "setting:settings",
                       "A higher score must still win over the kind tie-break")
    }
}
