import XCTest
@testable import BroccoliCore

final class SettingsCatalogTests: XCTestCase {
    private let panes = [
        SystemSettingsPane(
            bundleIdentifier: "com.apple.Keyboard-Settings.extension",
            title: "Keyboard",
            route: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            searchTerms: [
                SystemSettingsSearchTerm(
                    id: "Keyboard:0",
                    destination: "Keyboard",
                    title: "Keyboard",
                    keywords: ["input devices"]
                ),
                SystemSettingsSearchTerm(
                    id: "KeyboardBrightness:0",
                    destination: "KeyboardBrightness",
                    title: "Adjust keyboard brightness in low light",
                    keywords: ["Illuminate keyboard", "backlight brightness"]
                ),
            ]
        ),
        SystemSettingsPane(
            bundleIdentifier: "com.apple.Displays-Settings.extension",
            title: "Displays",
            route: "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        ),
    ]

    func testDiscoveredPanesProduceUniqueParentAndSearchTermEntries() {
        let entries = SettingsCatalog.searchEntries(from: panes)

        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(entries.filter { $0.title == "Keyboard" }.count, 1)
        XCTAssertEqual(
            entries.first { $0.title == "Keyboard" }?.keywords,
            ["input devices"]
        )
        XCTAssertTrue(entries.contains { $0.title == "Adjust keyboard brightness in low light" })
        XCTAssertTrue(entries.allSatisfy {
            guard case .setting(let route) = $0.target else { return false }
            return route?.hasPrefix("x-apple.systempreferences:") == true
        })
    }

    func testSearchTermUsesItsSystemSettingsDestination() throws {
        let entry = try XCTUnwrap(
            SettingsCatalog.searchEntries(from: panes).first {
                $0.title == "Adjust keyboard brightness in low light"
            }
        )
        guard case .setting(let route) = entry.target else {
            return XCTFail("Expected a Settings target")
        }
        XCTAssertEqual(
            route,
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardBrightness"
        )
    }

    func testMultiTermSettingsQueryCanMatchAcrossTitleAndKeywords() {
        let results = SearchEngine().search(
            query: "keyboard brightness",
            snapshot: .init(entries: SettingsCatalog.searchEntries(from: panes)),
            usage: [:]
        )

        XCTAssertEqual(results.first?.entry.title, "Adjust keyboard brightness in low light")
    }
}
