import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherPanelPreparedViewTests: XCTestCase {
    func testMaximumResultRowsArePrebuiltAndStableAcrossReloads() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var appearance = LauncherAppearancePreferences.defaults(design: .minimal)
        appearance.visibleResultCount = 10
        controller.applyAppearance(appearance, force: true)
        controller.apply((0..<12).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .status,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 0
            )
        })

        let table = NSTableView()
        XCTAssertEqual(controller.preparedResultRowCount, 10)
        XCTAssertEqual(controller.numberOfRows(in: table), 10)

        let firstPass = try (0..<10).map { row in
            try XCTUnwrap(controller.tableView(table, viewFor: nil, row: row))
        }
        let secondPass = try (0..<10).map { row in
            try XCTUnwrap(controller.tableView(table, viewFor: nil, row: row))
        }
        XCTAssertEqual(Set(firstPass.map(ObjectIdentifier.init)).count, 10)
        for row in 0..<10 {
            XCTAssertTrue(firstPass[row] === secondPass[row])
        }
        XCTAssertNil(controller.tableView(table, viewFor: nil, row: 10))
    }

    func testLauncherSearchAndResultsExposeVoiceOverLabels() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()

        XCTAssertEqual(controller.searchAccessibilityLabel, "Search Broccoli")
        XCTAssertEqual(controller.resultsAccessibilityLabel, "Search results")
        XCTAssertFalse(controller.visibilityIsolationWindow.hidesOnDeactivate)
    }

    func testResigningKeyDismissesWithoutRequestingPreviousApplicationRestore() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var didHide = false
        var requestedPreviousApplicationRestore = false
        controller.onDidHide = { didHide = true }
        controller.onDismiss = { requestedPreviousApplicationRestore = true }
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)

        controller.windowDidResignKey(Notification(
            name: NSWindow.didResignKeyNotification,
            object: controller.visibilityIsolationWindow
        ))

        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(didHide)
        XCTAssertFalse(requestedPreviousApplicationRestore)
    }

    func testRestoringVisibleSearchFocusPreservesTheMouseSelectedCaretPosition() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
        defer { controller.dismiss(notify: false) }
        let editor = try XCTUnwrap(
            controller.visibilityIsolationWindow.firstResponder as? NSTextView
        )
        editor.string = "abcdef"
        editor.setSelectedRange(NSRange(location: 2, length: 0))

        controller.restoreSearchFocusIfVisible()

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testLauncherToggleDismissesOnlyAnActiveKeyPresentation() {
        XCTAssertEqual(
            LauncherToggleDecision.resolve(
                panelIsVisible: true,
                panelIsKey: true,
                applicationIsActive: true
            ),
            .dismiss
        )

        for state in [
            (false, false, false),
            (true, false, true),
            (true, true, false),
            (true, false, false),
        ] {
            XCTAssertEqual(
                LauncherToggleDecision.resolve(
                    panelIsVisible: state.0,
                    panelIsKey: state.1,
                    applicationIsActive: state.2
                ),
                .present,
                "A hidden or stale panel must be presented, never treated as a toggle-off"
            )
        }
    }

    func testGlobalHotKeyDefersWindowWorkUntilAfterTheCarbonCallback() async {
        var delivered = false
        GlobalHotKeyActionDelivery.enqueue { delivered = true }

        XCTAssertFalse(delivered)
        await Task.yield()
        XCTAssertTrue(delivered)
    }

    func testLiquidGlassHierarchyRemainsWindowBackedWhileLauncherIsHidden() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .liquidGlass), force: true)

        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(controller.isContentViewAttached)
        XCTAssertTrue(controller.isSearchSurfaceWindowBacked)

        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
        XCTAssertTrue(controller.isContentViewAttached)
        XCTAssertTrue(controller.isSearchSurfaceWindowBacked)

        controller.dismiss(notify: false)
        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(controller.isContentViewAttached)
        XCTAssertTrue(controller.isSearchSurfaceWindowBacked)
    }

    func testLiquidMainLauncherStaysCollapsedForAnEmptyQuery() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .liquidGlass), force: true)
        let recent = RankedResult(
            entry: SearchEntry(
                id: "fixture:recent",
                kind: .application,
                title: "Recent App",
                target: .none
            ),
            score: 1
        )

        controller.setMode(.main)
        controller.apply([recent])
        XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 0)

        controller.setMode(.fileSearch(query: ""))
        controller.apply([recent])
        XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 1)
    }

    func testEveryLauncherDesignExposesTheSameSearchPlaceholderAndNativeControl() {
        _ = NSApplication.shared

        for design in LauncherDesign.allCases {
            let controller = LauncherPanelController()
            controller.applyAppearance(.defaults(design: design), force: true)
            controller.setMode(.main)

            XCTAssertTrue(controller.usesNativeSearchField, design.title)
            XCTAssertEqual(controller.searchPlaceholder, "Search Broccoli", design.title)
        }
    }

    func testLiquidMainImmediatelyShowsSingleAndMultipleSuggestions() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        controller.applyAppearance(preferences, force: true)
        let fixtures = (0..<2).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .application,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 1
            )
        }

        controller.setMode(.main, initialQuery: "wal")
        controller.apply(Array(fixtures.prefix(1)))
        XCTAssertTrue(controller.isResultViewportVisible)
        XCTAssertNil(controller.inlineSuggestionText)
        let oneResultHeight = controller.currentPanelHeight
        XCTAssertEqual(
            oneResultHeight,
            LauncherThemeController().descriptor(for: preferences).panelHeight(resultCount: 1)
        )

        controller.setMode(.main, initialQuery: "w")
        controller.apply(fixtures)
        XCTAssertTrue(controller.isResultViewportVisible)
        XCTAssertNil(controller.inlineSuggestionText)
        XCTAssertEqual(
            controller.currentPanelHeight,
            LauncherThemeController().descriptor(for: preferences).panelHeight(resultCount: 2)
        )

        controller.apply(Array(fixtures.prefix(1)))
        XCTAssertTrue(controller.isResultViewportVisible)
        XCTAssertEqual(controller.currentPanelHeight, oneResultHeight)
    }
}
