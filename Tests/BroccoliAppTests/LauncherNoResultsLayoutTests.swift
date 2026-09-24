import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherNoResultsLayoutTests: XCTestCase {
    func testStatusAndGoogleRowsUseTheSameRowAndWindowSizeAsAnOrdinaryResult() async throws {
        for mode in [LauncherAppearanceMode.light, .dark] {
            try await checkVisibleTransitions(mode: mode)
        }
    }

    func testInlineNoResultsKeepsOnlyTheSearchBandInEveryDesign() throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController(expansionAnimationDuration: { 0 })
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .notExpression, hasVisibleQuery: true,
            noMatch: .inlineStatus, limit: 7)
        for design in [LauncherDesign.liquidGlass, .minimal, .liquidGlass] {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            panel.applyAppearance(preferences)
            panel.setMode(.main, initialQuery: "unmatched")
            panel.apply(results)
            let theme = LauncherThemeController().descriptor(for: preferences)
            XCTAssertEqual(panel.currentPanelHeight, theme.searchHeight)
            XCTAssertFalse(panel.isResultViewportVisible)
            XCTAssertEqual(panel.inlineSuggestionText, "— No results")
        }
    }

    func testUnfinishedCalculationDoesNotOpenAResultRow() throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController(expansionAnimationDuration: { 0 })
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .incomplete, hasVisibleQuery: true,
            noMatch: .inlineStatus, limit: 7)
        for design in [LauncherDesign.liquidGlass, .minimal] {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            panel.applyAppearance(preferences)
            panel.setMode(.main, initialQuery: "1+")
            panel.apply(results)
            let theme = LauncherThemeController().descriptor(for: preferences)
            XCTAssertEqual(panel.currentPanelHeight, theme.searchHeight)
            XCTAssertFalse(panel.isResultViewportVisible)
            XCTAssertTrue(panel.listedResultIDs.isEmpty)
        }
    }

    private func checkVisibleTransitions(mode: LauncherAppearanceMode) async throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController(expansionAnimationDuration: { 0 })
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = mode
        panel.applyAppearance(preferences)
        panel.showForAutomatedTests()
        defer { panel.dismiss(notify: false) }
        panel.setMode(.main, initialQuery: "unmatched")
        let google = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .notExpression, hasVisibleQuery: true,
            noMatch: .webSearch(query: "unmatched", engine: .google), limit: 7)
        let normal = Array(LauncherPreviewFixture.standard.results.prefix(1))
        var ordinaryWindowFrame: NSRect?
        var ordinaryRowFrame: NSRect?
        for results in [normal, google, normal, google] {
            panel.apply(results)
            try await Task.sleep(for: .milliseconds(20))
            let root = try XCTUnwrap(panel.visibilityIsolationWindow.contentView)
            root.layoutSubtreeIfNeeded()
            let table = try XCTUnwrap(descendants(root).compactMap { $0 as? NSTableView }.first)
            let row = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
            row.layoutSubtreeIfNeeded()
            let title = try XCTUnwrap(descendants(row).compactMap { $0 as? NSTextField }.first { $0.stringValue == results[0].entry.title })
            let icon = try XCTUnwrap(descendants(row).compactMap { $0 as? NSImageView }.first)
            let rowBounds = row.convert(row.bounds, to: root)
            let titleBounds = title.convert(title.bounds, to: root)
            let iconBounds = icon.convert(icon.bounds, to: root)
            if ordinaryWindowFrame == nil {
                ordinaryWindowFrame = panel.visibilityIsolationWindow.frame
                ordinaryRowFrame = rowBounds
            }
            XCTAssertEqual(panel.visibilityIsolationWindow.frame, try XCTUnwrap(ordinaryWindowFrame),
                           "Changing a single result to a status message must not resize or move the window")
            XCTAssertEqual(rowBounds, try XCTUnwrap(ordinaryRowFrame),
                           "The status message must occupy the same native table row")
            XCTAssertEqual(rowBounds.height, LauncherLiquidGlassMetrics.searchHeight,
                           "Liquid Glass search and result bars must share one height")
            XCTAssertEqual(titleBounds.midY, rowBounds.midY, accuracy: 0.5)
            XCTAssertEqual(iconBounds.midY, rowBounds.midY, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(iconBounds.minY, rowBounds.minY)
            XCTAssertLessThanOrEqual(iconBounds.maxY, rowBounds.maxY)
            XCTAssertGreaterThanOrEqual(titleBounds.minY, rowBounds.minY)
            XCTAssertLessThanOrEqual(titleBounds.maxY, rowBounds.maxY)
            XCTAssertEqual(rowBounds.minY, LauncherLiquidGlassMetrics.resultBottomInset, accuracy: 0.5)
            XCTAssertEqual(root.bounds.maxY - rowBounds.maxY,
                           LauncherLiquidGlassMetrics.searchHeight + LauncherLiquidGlassMetrics.resultTopInset,
                           accuracy: 0.5)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
