import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherInlineSuggestionTests: XCTestCase {
    func testCalculatorAnswerUsesInlinePresentationAndReturnExecutesIt() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        let calculation = calculatorResult("11")
        var executed: RankedResult?
        controller.onExecute = { executed = $0 }

        controller.apply([calculation])

        XCTAssertEqual(controller.inlineSuggestionText, "= 11")
        XCTAssertFalse(controller.isResultViewportVisible)
        XCTAssertTrue(controller.control(
            NSTextField(),
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(executed, calculation)
    }

    func testConversionTextDoesNotReceiveASecondEqualsSign() {
        let result = calculatorResult("10 km = 6.2 mi")
        XCTAssertEqual(
            LauncherInlineSuggestionManager.displayText(
                for: result,
                query: "10 km in mi"
            ),
            "= 6.2 mi"
        )
    }

    func testTrailingEqualsShowsOnlyTheAnswerSuffix() {
        XCTAssertEqual(
            LauncherInlineSuggestionManager.displayText(
                for: calculatorResult("2"),
                query: "1+1="
            ),
            "2"
        )
    }

    func testCalculatorAnswerIsPositionedImmediatelyAfterTheQueryInsideTheSearchField() throws {
        _ = NSApplication.shared
        let field = LauncherNativeSearchField(
            frame: NSRect(x: 0, y: 0, width: 600, height: 58)
        )
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: .figmaLiquidGlass,
            iconColor: .labelColor
        )
        field.stringValue = "10 + 1"
        field.setInlineSuggestion("= 11", color: .secondaryLabelColor)
        field.layoutSubtreeIfNeeded()

        let suggestionFrame = try XCTUnwrap(field.inlineSuggestionFrame)
        let queryWidth = (field.stringValue as NSString).size(
            withAttributes: [.font: field.searchMetrics.font]
        ).width
        let expectedQueryEnd = field.searchTextBounds.minX + queryWidth
        let suggestionWidth = ("= 11" as NSString).size(
            withAttributes: [.font: field.searchMetrics.font]
        ).width

        XCTAssertEqual(suggestionFrame.minX, ceil(expectedQueryEnd + 8), accuracy: 1)
        XCTAssertGreaterThanOrEqual(suggestionFrame.width, suggestionWidth)
        XCTAssertLessThan(suggestionFrame.midX, field.searchTextBounds.midX)
        XCTAssertLessThanOrEqual(suggestionFrame.maxX, field.searchTextBounds.maxX)
    }

    func testRefreshingResultsPreservesExplicitRowSelection() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        let first = applicationResult(id: "first", title: "First")
        let second = applicationResult(id: "second", title: "Second")
        controller.apply([first, second])
        XCTAssertEqual(controller.selectedResultID, "first")

        XCTAssertTrue(controller.control(
            NSTextField(),
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        XCTAssertEqual(controller.selectedResultID, "second")

        controller.apply([first, second], preservingSelection: true)
        XCTAssertEqual(controller.selectedResultID, "second")
    }

    func testReturnPrefersInlineCalculatorWhenNoListedResultIsSelected() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        let calculation = calculatorResult("11")
        let application = applicationResult(id: "notes", title: "Notes")
        var executed: RankedResult?
        controller.onExecute = { executed = $0 }

        controller.apply([calculation, application])
        XCTAssertNil(controller.selectedResultID)
        XCTAssertTrue(controller.control(
            NSTextField(),
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        XCTAssertEqual(executed, calculation)
    }

    func testNoResultsIsPresentedInlineAndKeepsTheSearchBandCompact() {
        _ = NSApplication.shared
        for design in [LauncherDesign.liquidGlass, .minimal] {
            let controller = LauncherPanelController()
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            controller.applyAppearance(preferences, force: true)
            controller.setMode(.main, initialQuery: "jknnnjnfsjn")
            let results = LauncherMainSearchResultComposer.compose(
                catalogResults: [],
                calculatorEvaluation: .notExpression,
                hasVisibleQuery: true,
                noMatch: .inlineStatus,
                limit: 7
            )
            var executed: RankedResult?
            controller.onExecute = { executed = $0 }

            controller.apply(results)

            XCTAssertEqual(controller.inlineSuggestionText, "— No results")
            XCTAssertTrue(controller.listedResultIDs.isEmpty)
            XCTAssertFalse(controller.isResultViewportVisible)
            XCTAssertEqual(
                controller.currentPanelHeight,
                LauncherThemeController().descriptor(for: preferences).searchHeight,
                "An unmatched query leaves only the search band, with no empty result row"
            )
            XCTAssertTrue(controller.control(
                NSTextField(),
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            ))
            XCTAssertNil(executed, "Return on the inline message must not execute anything")
        }
    }

    func testGoogleFallbackIsASelectedRowThatReturnExecutes() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        controller.applyAppearance(preferences, force: true)
        controller.setMode(.main, initialQuery: "c++ tutorial")
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [],
            calculatorEvaluation: .notExpression,
            hasVisibleQuery: true,
            noMatch: .webSearch(query: "c++ tutorial", engine: .google),
            limit: 7
        )
        var executed: RankedResult?
        controller.onExecute = { executed = $0 }

        controller.apply(results)

        XCTAssertNil(controller.inlineSuggestionText)
        XCTAssertEqual(controller.listedResultIDs, [WebSearch.googleEntryID])
        XCTAssertEqual(controller.selectedResultID, WebSearch.googleEntryID)
        XCTAssertEqual(
            controller.currentPanelHeight,
            LauncherThemeController().descriptor(for: preferences).panelHeight(resultCount: 1)
        )
        XCTAssertTrue(controller.control(
            NSTextField(),
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        let entry = try XCTUnwrap(executed?.entry)
        XCTAssertEqual(entry.kind, .webSearch)
        XCTAssertEqual(entry.title, "Search Google for “c++ tutorial”")
        XCTAssertFalse(entry.id.contains("tutorial"), "The query must never become a usage key")
        guard case .webSearch(let url) = entry.target else {
            return XCTFail("The Google row must open a web search")
        }
        XCTAssertEqual(url.absoluteString, "https://www.google.com/search?q=c%2B%2B%20tutorial")
    }

    func testCalculatorStateSuppressesIncidentalCatalogMatches() {
        let networkSetting = RankedResult(
            entry: SearchEntry(
                id: "setting:network:8021x",
                kind: .systemSetting,
                title: "802.1X",
                target: .setting(route: nil)
            ),
            score: 450
        )
        let catalogResults = [networkSetting]
        let evaluation = CalculatorEngine().classify("1+1", locale: Locale(identifier: "en_US_POSIX"))

        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: catalogResults,
            calculatorEvaluation: evaluation,
            hasVisibleQuery: true,
            noMatch: .inlineStatus,
            limit: 8
        )

        XCTAssertEqual(results.map(\.entry.id), ["calculator:answer"])
        XCTAssertEqual(results.first?.entry.title, "2")
        XCTAssertFalse(results.contains { $0.entry.title == "802.1X" })
    }

    func testTrailingEqualsKeepsCalculatorStateAndSuppressesCatalogMatches() {
        let catalogResults = [applicationResult(id: "802.1x", title: "802.1X")]
        let evaluation = CalculatorEngine().classify("1+1=", locale: Locale(identifier: "en_US_POSIX"))
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: catalogResults,
            calculatorEvaluation: evaluation,
            hasVisibleQuery: true,
            noMatch: .inlineStatus,
            limit: 8
        )
        let controller = LauncherPanelController()
        controller.setMode(.main, initialQuery: "1+1=")
        controller.apply(results)

        XCTAssertEqual(results.map(\.entry.id), ["calculator:answer"])
        XCTAssertEqual(controller.inlineSuggestionText, "2")
        XCTAssertTrue(controller.listedResultIDs.isEmpty)
        XCTAssertFalse(controller.isResultViewportVisible)
    }

    func testANumberBeingTypedDoesNotOfferAWebSearch() {
        let evaluation = CalculatorEngine().classify("3", locale: Locale(identifier: "en_US_POSIX"))
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [],
            calculatorEvaluation: evaluation,
            hasVisibleQuery: true,
            noMatch: .stillTyping,
            limit: 8
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testAnUnsolvableCalculationOffersTheSelectedWebSearch() {
        let evaluation = CalculatorEngine().classify("2 + )", locale: Locale(identifier: "en_US_POSIX"))
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [],
            calculatorEvaluation: evaluation,
            hasVisibleQuery: true,
            noMatch: .webSearch(query: "2 + )", engine: .duckDuckGo),
            limit: 8
        )

        XCTAssertEqual(evaluation, .invalid)
        XCTAssertEqual(results.map(\.entry.id), [WebSearch.duckDuckGoEntryID])
        XCTAssertEqual(results.first?.entry.title, "Search DuckDuckGo for “2 + )”")
    }

    func testCatalogMatchesAreNeverReplacedByTheGoogleFallback() {
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [applicationResult(id: "notes", title: "Notes")],
            calculatorEvaluation: .notExpression,
            hasVisibleQuery: true,
            noMatch: .webSearch(query: "notes", engine: .google),
            limit: 8
        )

        XCTAssertEqual(results.map(\.entry.id), ["notes"])
    }

    func testApplyingResultsDoesNotTakeFocusFromNativeFieldEditor() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let responder = try XCTUnwrap(window.firstResponder as? NSTextView)

        controller.apply([applicationResult(id: "finder", title: "Finder")])

        XCTAssertTrue(window.firstResponder === responder)
        XCTAssertTrue(responder.shouldDrawInsertionPoint)
    }

    private func calculatorResult(_ title: String) -> RankedResult {
        RankedResult(
            entry: SearchEntry(
                id: "calculator:answer",
                kind: .calculator,
                title: title,
                iconKey: "calculator",
                target: .calculator(result: title)
            ),
            score: 2_000
        )
    }

    private func applicationResult(id: String, title: String) -> RankedResult {
        RankedResult(
            entry: SearchEntry(
                id: id,
                kind: .application,
                title: title,
                iconKey: "/Applications/\(title).app",
                target: .application(path: "/Applications/\(title).app", bundleIdentifier: nil)
            ),
            score: 800
        )
    }
}
