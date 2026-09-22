import AppKit
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
}
