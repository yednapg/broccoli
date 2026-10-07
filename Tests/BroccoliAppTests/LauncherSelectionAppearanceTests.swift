import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherSelectionAppearanceTests: XCTestCase {
    func testLightLiquidGlassUsesAccentSelectionAndMatchingForegrounds() throws {
        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .light

        let theme = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )

        XCTAssertTrue(theme.selectionColor.isEqual(NSColor.controlAccentColor))
        XCTAssertTrue(theme.selectedTextColor.isEqual(NSColor.alternateSelectedControlTextColor))
        XCTAssertTrue(theme.selectedShortcutTextColor.isEqual(NSColor.alternateSelectedControlTextColor))

        let result = try XCTUnwrap(LauncherPreviewFixture.standard.results.first)
        let row = ResultRowView()
        row.configure(
            result: result,
            icon: LauncherPreviewIconProvider().image(for: result.entry),
            confirmation: false,
            row: 0,
            selected: true,
            theme: theme
        )
        let shortcut = try XCTUnwrap(row.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.stringValue == LauncherNumericShortcut.label(forRow: 0, visibleResultCount: theme.visibleResultCount) })

        row.effectiveAppearance.performAsCurrentDrawingAppearance {
            XCTAssertEqual(row.layer?.backgroundColor, theme.selectionColor.cgColor)
        }
        XCTAssertTrue(shortcut.textColor?.isEqual(NSColor.alternateSelectedControlTextColor) == true)

        row.setSelected(false)
        XCTAssertTrue(shortcut.textColor?.isEqual(NSColor.tertiaryLabelColor) == true)
    }

    func testMinimalRowsUseTheSystemFontAtTheReferenceWeights() throws {
        _ = NSApplication.shared
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .minimal))
        let result = try XCTUnwrap(LauncherPreviewFixture.standard.results.first)
        let row = ResultRowView()
        row.configure(
            result: result,
            icon: LauncherPreviewIconProvider().image(for: result.entry),
            confirmation: false,
            row: 0,
            selected: false,
            theme: theme
        )
        let fields = row.subviews.compactMap { $0 as? NSTextField }
        let title = try XCTUnwrap(fields.first { $0.font?.pointSize == 18 })
        let subtitle = try XCTUnwrap(fields.first { $0.font?.pointSize == 12 })
        let shortcut = try XCTUnwrap(fields.first { $0.font?.pointSize == 14 })
        XCTAssertEqual(title.font?.fontName, NSFont.systemFont(ofSize: 18, weight: .regular).fontName)
        XCTAssertEqual(subtitle.font?.fontName, NSFont.systemFont(ofSize: 12, weight: .regular).fontName)
        XCTAssertEqual(shortcut.font?.fontName, NSFont.systemFont(ofSize: 14, weight: .regular).fontName)
    }

    func testDarkLiquidGlassUsesTheSameAccentSelectionContract() {
        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .dark

        let theme = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )

        XCTAssertTrue(theme.selectionColor.isEqual(NSColor.controlAccentColor))
        XCTAssertTrue(theme.selectedTextColor.isEqual(NSColor.alternateSelectedControlTextColor))
    }

    /// Typing or erasing used to keep the previous query's pick. When that entry ranked lower
    /// for the new query, the highlight moved below the visible rows while the list scrolled
    /// back to the top, so no visible row looked selected.
    func testANewQueryStartsOnItsBestMatchWhileARefreshKeepsTheSelection() {
        _ = NSApplication.shared
        let results = (0..<14).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "app:\(index)",
                    kind: .application,
                    title: "App \(index)",
                    target: .application(path: "/Applications/App \(index).app", bundleIdentifier: nil)
                ),
                score: 800
            )
        }
        let reordered = Array(results.dropFirst()) + [results[0]]
        let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
        controller.applyAppearance(.defaults(design: .minimal))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }

        controller.setMode(.main, initialQuery: "a")
        controller.apply(results, preservingSelection: true)
        XCTAssertEqual(controller.selectedResultID, "app:0")

        controller.setMode(.main, initialQuery: "al")
        controller.apply(reordered, preservingSelection: true)
        XCTAssertEqual(controller.selectedResultRow, 0)
        XCTAssertEqual(controller.selectedResultID, "app:1")

        controller.apply(Array(reordered.reversed()), preservingSelection: true)
        XCTAssertEqual(controller.selectedResultID, "app:1", "A refresh of the same query keeps the pick")
    }

    /// A longer result list whose preserved selection lands on another row used to select
    /// and refresh rows the table did not have yet. AppKit raised `NSTableViewException`
    /// inside the search task, and the launcher crashed on the next keystroke.
    func testGrowingResultsKeepTheSelectionWithoutQueryingRowsTheTableLacks() throws {
        _ = NSApplication.shared
        let candidates = LauncherPreviewFixture.standard.results.filter { $0.entry.kind != .status }
        XCTAssertGreaterThanOrEqual(candidates.count, 3)
        let first = candidates[0], second = candidates[1], third = candidates[2]
        let growths: [[RankedResult]] = [
            // The selection moves to a row the table already has.
            [second, first, third],
            // The selection moves to a row that exists only after the reload.
            [second, third, first],
        ]
        for design in [LauncherDesign.minimal, .liquidGlass] {
            for grown in growths {
                let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
                controller.applyAppearance(.defaults(design: design))
                controller.showForAutomatedTests()
                defer { controller.dismiss(notify: false) }
                controller.setMode(.main, initialQuery: "fixture")
                controller.apply([first, second])
                XCTAssertEqual(controller.selectedResultID, first.entry.id)

                controller.apply(grown, preservingSelection: true)

                XCTAssertEqual(controller.selectedResultID, first.entry.id, "\(design)")
            }
        }
    }
}
