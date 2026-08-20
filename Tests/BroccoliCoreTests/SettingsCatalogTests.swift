import XCTest
@testable import BroccoliCore

final class SettingsCatalogTests: XCTestCase {
    func testUniqueRoutes() {
        let ids = SettingsCatalog.definitions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(SettingsCatalog.definitions.allSatisfy { definition in
            [15, 26, 27].allSatisfy { major in
                definition.route(forMajorVersion: major)?.hasPrefix("x-apple.systempreferences:") == true
            }
        })
    }

    func testUnknownSystemVersionFallsBackToSettingsHome() {
        XCTAssertTrue(SettingsCatalog.definitions.allSatisfy {
            $0.route(forMajorVersion: 99) == nil
        })
    }

    func testAliases() {
        let engine = SearchEngine()
        let screenResults = engine.search(
            query: "screen",
            snapshot: .init(entries: SettingsCatalog.searchEntries),
            usage: [:]
        )
        XCTAssertTrue(screenResults.contains { $0.entry.title == "Displays" })

        let startupResults = engine.search(
            query: "startup apps",
            snapshot: .init(entries: SettingsCatalog.searchEntries),
            usage: [:]
        )
        XCTAssertEqual(startupResults.first?.entry.title, "Login Items")
    }
}
