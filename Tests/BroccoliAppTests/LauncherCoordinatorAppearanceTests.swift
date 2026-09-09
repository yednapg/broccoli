import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherCoordinatorAppearanceTests: XCTestCase {
    func testResolvingActionWordingPreservesRankingAndDoesNotIntroduceDisabledActions() throws {
        let entries = ActionRegistry.searchEntries(isDarkMode: true)
        let results = entries.enumerated().map { RankedResult(entry: $0.element, score: 500 - $0.offset) }
        let updated = ActionRegistry.resolvingSystemAppearance(in: results, isDarkMode: false)
        XCTAssertEqual(updated.map(\.entry.id), results.map(\.entry.id))
        XCTAssertEqual(updated.map(\.score), results.map(\.score))
        XCTAssertEqual(updated.map(\.entry.target), results.map(\.entry.target))
        let action = try XCTUnwrap(updated.first { $0.entry.target == .action(id: ActionRegistry.appearanceToggleID) })
        XCTAssertEqual(action.entry.title, "Switch to Dark Mode")
        XCTAssertEqual(action.entry.normalizedTitle, SearchNormalizer.normalize(action.entry.title))
        let withoutAppearanceAction = results.filter { $0.entry.target != action.entry.target }
        func unexpectedAppearanceRead() -> Bool {
            XCTFail("Ordinary results need no appearance lookup")
            return false
        }
        XCTAssertEqual(ActionRegistry.resolvingSystemAppearance(
            in: withoutAppearanceAction, isDarkMode: unexpectedAppearanceRead()), withoutAppearanceAction)
    }

    func testSystemAppearanceChangeRefreshesVisibleActionWithoutChangingEditingState() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.panel.show(on: NSScreen.main)
        fixture.search("dark mode")
        try await fixture.waitForTitle("Switch to Light Mode")
        let editor = try XCTUnwrap(fixture.panel.visibilityIsolationWindow.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        let selectedID = fixture.panel.selectedResultID

        for appearance in [LauncherPreviewResolvedAppearance.light, .dark, .light] {
            fixture.appearance = appearance
            fixture.coordinator.refreshAppearanceForSystemChange()
            try await fixture.waitForTitle(appearance == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
            XCTAssertEqual(fixture.panel.query, "dark mode")
            XCTAssertEqual(fixture.panel.selectedResultID, selectedID)
            XCTAssertTrue(fixture.panel.visibilityIsolationWindow.firstResponder === editor)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 2))
        }
    }

    func testSearchFromOlderSnapshotResolvesCurrentSystemModeBeforePublishing() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        // Keep the launcher explicitly dark. The command changes macOS, so its label must
        // follow system state even when the launcher's appearance preference differs.
        fixture.preferences.appearance.mode = .dark
        fixture.coordinator.updatePreferences()
        fixture.panel.show(on: NSScreen.main)
        fixture.search("dark mode")
        // This main-actor turn cannot publish the pending search yet. Simulate a system
        // change before its notification is delivered; the snapshot still describes Dark.
        fixture.appearance = .light
        try await fixture.waitForTitle("Switch to Dark Mode")
        XCTAssertEqual(fixture.panel.visibilityIsolationWindow.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)

        for appearance in [LauncherPreviewResolvedAppearance.dark, .light, .dark] {
            fixture.panel.dismiss(notify: false)
            fixture.appearance = appearance
            fixture.coordinator.refreshAppearanceForSystemChange()
            fixture.panel.show(on: NSScreen.main)
            fixture.search("light mode")
            try await fixture.waitForTitle(appearance == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
        }
    }

    @MainActor private final class Fixture {
        let suite = "BroccoliCoordinatorAppearanceTests.\(UUID().uuidString)"
        let preferences: AppPreferences
        let panel: LauncherPanelController
        let coordinator: LauncherCoordinator
        private let source = AppearanceSource()
        var appearance: LauncherPreviewResolvedAppearance {
            get { source.appearance }
            set { source.appearance = newValue }
        }

        init() throws {
            _ = NSApplication.shared
            preferences = AppPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
            let environmentProvider = { @MainActor [source] in source.environment }
            panel = LauncherPanelController(environmentProvider: environmentProvider)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            coordinator = LauncherCoordinator(
                panel: panel, preferences: preferences,
                usageStore: UsageStore(fileURL: directory.appendingPathComponent("usage.json")),
                diagnosticsStore: DiagnosticsStore(fileURL: directory.appendingPathComponent("diagnostics.json")),
                windowManager: WindowManager(),
                environmentProvider: environmentProvider
            )
        }

        func close() {
            panel.dismiss(notify: false)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }

        func search(_ query: String) {
            panel.setMode(.main, initialQuery: query)
            panel.onQueryChanged?(query)
        }

        func waitForTitle(_ expected: String) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while actionTitle != expected, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(actionTitle, expected)
        }

        private var actionTitle: String? {
            guard let row = panel.listedResultIDs.firstIndex(of: "action:\(ActionRegistry.appearanceToggleID)") else { return nil }
            return panel.tableView(NSTableView(), viewFor: nil, row: row)?.accessibilityLabel()
        }
    }

    @MainActor private final class AppearanceSource {
        var appearance = LauncherPreviewResolvedAppearance.dark
        var environment: LauncherAppearanceEnvironment {
            LauncherAppearanceEnvironment(reducesTransparency: false, increasesContrast: false,
                                          resolvedAppearance: appearance)
        }
    }
}
