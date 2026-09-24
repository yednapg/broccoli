import Foundation
import XCTest
@testable import BroccoliCore

final class SearchEngineTests: XCTestCase {
    private let engine = SearchEngine()

    func testNormalization() {
        XCTAssertEqual(SearchNormalizer.normalize("  CAFÉ　Tool  "), "cafe tool")
        XCTAssertEqual(SearchNormalizer.compact(" Wi‑Fi "), "wifi")
    }

    func testPunctuationInsensitiveTitleOutranksLooseSubstring() {
        let wifi = SearchEntry(
            id: "setting:wifi",
            kind: .systemSetting,
            title: "Wi-Fi",
            target: .setting(route: nil)
        )
        let swift = entry("swift", "Swift Playground.app")

        let results = engine.search(
            query: "wif",
            snapshot: .init(entries: [swift, wifi]),
            usage: [:]
        )

        XCTAssertEqual(results.first?.entry.id, "setting:wifi")
        XCTAssertEqual(results.first?.score, 800)
    }

    func testNumericOnlyQueryDoesNotMatchDigitsBuriedInCatalogText() {
        let numericApplication = entry("one-password", "1Password")
        let networkSetting = SearchEntry(
            id: "setting:network:8021x",
            kind: .systemSetting,
            title: "802.1X",
            target: .setting(route: nil)
        )
        let metadataMatch = SearchEntry(
            id: "setting:network",
            kind: .systemSetting,
            title: "Network",
            keywords: ["802.1X enterprise"],
            target: .setting(route: nil)
        )
        let snapshot = SearchSnapshot(entries: [networkSetting, metadataMatch, numericApplication])

        let results = engine.search(query: "1", snapshot: snapshot, usage: [:])

        XCTAssertEqual(results.map(\.entry.id), ["one-password"])
        XCTAssertEqual(
            engine.search(query: "802", snapshot: snapshot, usage: [:]).first?.entry.id,
            "setting:network:8021x"
        )
    }

    func testRankingRules() {
        let entries = [
            entry("exact", "Visual Studio Code"),
            entry("prefix", "Visual Studio Code Insiders"),
            entry("word", "The Visual Tool"),
            entry("acronym", "Very Special Companion"),
            entry("substring", "My Visualizer"),
            entry("keyword", "Editor", keywords: ["visual"]),
        ]
        let exact = engine.search(query: "visual studio code", snapshot: .init(entries: entries), usage: [:])
        XCTAssertEqual(exact.first?.entry.id, "exact")

        let acronym = engine.search(query: "vsc", snapshot: .init(entries: entries), usage: [:])
        XCTAssertEqual(acronym.first?.entry.id, "acronym")

        let keyword = engine.search(query: "visual", snapshot: .init(entries: [entries.last!]), usage: [:])
        XCTAssertEqual(keyword.first?.score, 350)
    }

    func testBonusesDoNotOutrankMatchClasses() {
        var prefix = entry("prefix", "Bluetooth Utility")
        let exact = entry("exact", "Bluetooth")
        prefix.isRunning = true
        let usage = [
            prefix.id: UsageRecord(selectionCount: 1_000, lastUsed: Date()),
        ]
        let results = engine.search(
            query: "bluetooth",
            snapshot: .init(entries: [prefix, exact]),
            usage: usage
        )
        XCTAssertEqual(results.first?.entry.id, "exact")
    }

    func testEmptyQueryIsBlankByDefault() {
        let recent = entry("recent", "Chromium")
        let results = engine.search(
            query: "",
            snapshot: .init(entries: [recent]),
            usage: [recent.id: UsageRecord(selectionCount: 2, lastUsed: Date())]
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyQueryRecentsWhenEnabled() {
        let first = entry("a", "Alpha")
        let second = entry("b", "Beta")
        let results = engine.search(
            query: "",
            snapshot: .init(entries: [first, second]),
            usage: [second.id: UsageRecord(selectionCount: 2, lastUsed: Date())],
            preferences: SearchPreferences(recentItemsEnabled: true)
        )
        XCTAssertEqual(results.map(\.entry.id), ["b"])
    }

    func testDisabledCategories() {
        let app = entry("app", "Calendar")
        let setting = SearchEntry(
            id: "setting",
            kind: .systemSetting,
            title: "Calendar Accounts",
            target: .setting(route: nil)
        )
        let preferences = SearchPreferences(applicationsEnabled: false)
        let results = engine.search(
            query: "calendar",
            snapshot: .init(entries: [app, setting]),
            usage: [:],
            preferences: preferences
        )
        XCTAssertEqual(results.map(\.entry.id), ["setting"])
    }

    func testDeterministicTies() {
        let results = engine.search(
            query: "a",
            snapshot: .init(entries: [entry("2", "Alpine"), entry("1", "Alpha")]),
            usage: [:]
        )
        XCTAssertEqual(results.map(\.entry.id), ["1", "2"])
    }

    func testSingleCharacterMatchesOnlyTheStartsOfWords() {
        let results = engine.search(query: "j", snapshot: .init(entries: journalFixture), usage: [:])

        XCTAssertEqual(results.map(\.entry.id), ["journal", "setting:joining"],
                       "Letters inside words and keyword metadata must not flood a one-letter query")
    }

    func testSingleCharacterPutsTheMostSelectedMatchFirst() {
        let now = Date()
        let usage = [
            "setting:joining": UsageRecord(selectionCount: 12, lastUsed: now.addingTimeInterval(-3 * 86_400)),
            "setting:emoji": UsageRecord(selectionCount: 50, lastUsed: now),
        ]

        let results = engine.search(query: "j", snapshot: .init(entries: journalFixture), usage: usage, now: now)

        XCTAssertEqual(results.map(\.entry.id), ["setting:joining", "journal"],
                       "What the user picks for a letter leads, whether an app or a setting")
        XCTAssertFalse(results.contains { $0.entry.id == "setting:emoji" },
                       "Selection history never admits an entry the letter does not start")
    }

    func testSingleCharacterOrdersSelectedMatchesByHowOftenTheyWereChosen() {
        let now = Date()
        let entries = [entry("safari", "Safari"), entry("slack", "Slack"), entry("steam", "Steam")]
        let usage = [
            "slack": UsageRecord(selectionCount: 3, lastUsed: now),
            "steam": UsageRecord(selectionCount: 40, lastUsed: now),
        ]

        let results = engine.search(query: "s", snapshot: .init(entries: entries), usage: usage, now: now)

        XCTAssertEqual(results.map(\.entry.id), ["steam", "slack", "safari"])
    }

    func testSingleCharacterSelectionPriorityFollowsAdaptiveRanking() {
        let usage = ["setting:joining": UsageRecord(selectionCount: 12, lastUsed: Date())]

        let results = engine.search(
            query: "j",
            snapshot: .init(entries: journalFixture),
            usage: usage,
            preferences: SearchPreferences(adaptiveRankingEnabled: false)
        )

        XCTAssertEqual(results.first?.entry.id, "journal")
    }

    func testSingleCharacterKeepsApplicationsWhenPanesFillTheAlphabeticalWindow() {
        let panes = (0..<60).map { index in
            SearchEntry(
                id: "setting:\(index)",
                kind: .systemSetting,
                title: String(format: "Sa pane %02d", index),
                target: .setting(route: nil)
            )
        }
        let slack = entry("slack", "Slack")

        let results = engine.search(query: "s", snapshot: .init(entries: panes + [slack]), usage: [:], limit: 8)

        XCTAssertEqual(results.first?.entry.id, "slack")
    }

    private var journalFixture: [SearchEntry] {
        [
            entry("journal", "Journal"),
            SearchEntry(id: "setting:joining", kind: .systemSetting, title: "Joining a Wi-Fi network",
                        target: .setting(route: nil)),
            SearchEntry(id: "setting:emoji", kind: .systemSetting,
                        title: "Show keyboard and emoji viewers in menu bar", target: .setting(route: nil)),
            SearchEntry(id: "setting:layouts", kind: .systemSetting, title: "Keyboard layouts",
                        keywords: ["japanese"], target: .setting(route: nil)),
            SearchEntry(id: "setting:adjust", kind: .systemSetting,
                        title: "Use keyboard shortcuts to adjust zoom window", target: .setting(route: nil)),
        ]
    }

    func testMultiTermQueryRequiresEveryTermButCanMatchDifferentFields() {
        let keyboard = SearchEntry(
            id: "keyboard-brightness",
            kind: .systemSetting,
            title: "Illuminate keyboard",
            keywords: ["backlight brightness"],
            target: .setting(route: nil)
        )
        let display = SearchEntry(
            id: "display-brightness",
            kind: .systemSetting,
            title: "Display brightness",
            target: .setting(route: nil)
        )

        let results = engine.search(
            query: "keyboard brightness",
            snapshot: .init(entries: [display, keyboard]),
            usage: [:]
        )

        XCTAssertEqual(results.map(\.entry.id), ["keyboard-brightness"])
    }

    private func entry(_ id: String, _ title: String, keywords: [String] = []) -> SearchEntry {
        SearchEntry(
            id: id,
            kind: .application,
            title: title,
            keywords: keywords,
            target: .application(path: "/Applications/\(title).app", bundleIdentifier: nil)
        )
    }
}
