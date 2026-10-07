import Foundation
import XCTest
@testable import BroccoliCore

/// Results of one kind stay together so the list does not alternate between actions and
/// settings, and hidden index keywords only answer a query when no name of that kind does.
final class SearchGroupingTests: XCTestCase {
    private let engine = SearchEngine()
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func action(_ id: String, _ title: String, keywords: [String] = []) -> SearchEntry {
        SearchEntry(id: "action:\(id)", kind: .action, title: title, subtitle: "Action",
                    keywords: keywords, target: .action(id: id))
    }

    private func setting(_ id: String, _ title: String, keywords: [String] = []) -> SearchEntry {
        SearchEntry(id: "setting:\(id)", kind: .systemSetting, title: title,
                    keywords: keywords, target: .setting(route: nil))
    }

    func testRecentItemsStayGroupedByKindInOrderOfTheMostUsed() {
        let entries = [
            action("left-half", "Left Half"),
            setting("liquid-glass", "Liquid Glass"),
            setting("login-items", "Login Items"),
            action("light-mode", "Switch to Light Mode"),
            setting("captions", "Language (Live Captions)"),
            action("left-third", "Left Third"),
        ]
        // Selection counts interleave the kinds: 6, 5, 4, 3, 2, 1.
        var usage: [String: UsageRecord] = [:]
        for (rank, entry) in entries.enumerated() {
            usage[entry.id] = UsageRecord(selectionCount: entries.count - rank, lastUsed: now)
        }

        let results = engine.search(
            query: "",
            snapshot: SearchSnapshot(entries: entries),
            usage: usage,
            preferences: SearchPreferences(recentItemsEnabled: true),
            now: now,
            limit: 10
        )

        XCTAssertEqual(results.map(\.entry.id), [
            "action:left-half", "action:light-mode", "action:left-third",
            "setting:liquid-glass", "setting:login-items", "setting:captions",
        ])
    }

    func testTypedResultsKeepTheirKindTogetherAndTheBestMatchFirst() {
        let entries = [
            setting("login-items", "Login Items"),
            action("log-out", "Log Out"),
            setting("logs", "Logging"),
            action("lock", "Lock Screen", keywords: ["log off"]),
        ]

        let results = engine.search(
            query: "lo",
            snapshot: SearchSnapshot(entries: entries),
            usage: ["action:log-out": UsageRecord(selectionCount: 8, lastUsed: now)],
            now: now,
            limit: 10
        )

        let kinds = results.map(\.entry.kind)
        XCTAssertEqual(results.first?.entry.id, "action:log-out")
        XCTAssertEqual(kinds, kinds.sorted { $0 == .action && $1 != .action },
                       "Every action precedes every setting once an action leads")
    }

    func testAKeywordOnlyMatchGivesWayToANamedMatchOfTheSameKind() {
        let wallpaper = setting("wallpaper", "Wallpaper")
        let windowLook = setting(
            "window-look",
            "Button, menu, and window look",
            keywords: ["desktop, customize, appearance, wallpaper tint, tint window"]
        )

        let results = engine.search(
            query: "wallpaper",
            snapshot: SearchSnapshot(entries: [wallpaper, windowLook]),
            usage: [:],
            limit: 10
        )

        XCTAssertEqual(results.map(\.entry.id), ["setting:wallpaper"])
    }

    func testAKeywordOnlyMatchStaysWhenNoNameOfItsKindMatches() {
        let appearance = setting(
            "appearance",
            "Appearance",
            keywords: ["light, dark, theme, mode, Dark Mode"]
        )
        let darkMode = action("dark-mode", "Switch to Dark Mode")

        let results = engine.search(
            query: "dark",
            snapshot: SearchSnapshot(entries: [appearance, darkMode]),
            usage: [:],
            limit: 10
        )

        XCTAssertEqual(results.map(\.entry.id), ["action:dark-mode", "setting:appearance"])
    }
}
