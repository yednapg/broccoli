import AppKit
import BroccoliCore
import ServiceManagement
import SwiftUI
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherAppearanceTests: XCTestCase {
    func testThemeGeometryAtSupportedResultCounts() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            for visibleCount in [3, 7, 10] {
                var preferences = LauncherAppearancePreferences.defaults(design: design)
                preferences.visibleResultCount = visibleCount
                let descriptor = controller.descriptor(for: preferences)

                for resultCount in 0...(visibleCount + 2) {
                    let displayedRows = min(resultCount, visibleCount)
                    let viewportHeight = CGFloat(displayedRows)
                        * (descriptor.rowHeight + descriptor.rowSpacing)
                    let documentHeight = CGFloat(resultCount)
                        * (descriptor.rowHeight + descriptor.rowSpacing)
                    let expectedHeight = descriptor.searchHeight
                        + (displayedRows > 0 ? descriptor.resultTopInset : 0)
                        + viewportHeight
                        + (displayedRows > 0 ? descriptor.resultBottomInset : 0)

                    XCTAssertEqual(
                        descriptor.panelHeight(resultCount: resultCount),
                        expectedHeight,
                        accuracy: 0.001,
                        "\(design) must size exactly to \(displayedRows) visible rows"
                    )
                    XCTAssertEqual(
                        descriptor.resultsViewportHeight(resultCount: resultCount),
                        viewportHeight,
                        accuracy: 0.001,
                        "\(design) viewport must follow Visible Results, not the full list"
                    )
                    XCTAssertEqual(
                        descriptor.resultsDocumentHeight(resultCount: resultCount),
                        documentHeight,
                        accuracy: 0.001
                    )
                    if resultCount <= visibleCount {
                        XCTAssertEqual(
                            descriptor.resultsViewportHeight(resultCount: resultCount),
                            descriptor.resultsDocumentHeight(resultCount: resultCount),
                            accuracy: 0.001,
                            "\(design) must not leave an empty table viewport"
                        )
                    } else {
                        XCTAssertGreaterThan(
                            descriptor.resultsDocumentHeight(resultCount: resultCount),
                            descriptor.resultsViewportHeight(resultCount: resultCount),
                            "\(design) must keep extra matches in a scrollable document"
                        )
                    }
                }
            }
        }
    }

    func testAppKitTableGeometryMatchesThemeWithoutScrollableOverflow() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            for count in [3, 7, 10] {
                var preferences = LauncherAppearancePreferences.defaults(design: design)
                preferences.visibleResultCount = count
                let descriptor = controller.descriptor(for: preferences)
                let rows = TableRows(count: count)
                let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 500, height: 1_000))
                table.addTableColumn(NSTableColumn(identifier: .init("result")))
                table.headerView = nil
                table.style = .fullWidth
                table.rowSizeStyle = .custom
                table.usesAutomaticRowHeights = false
                table.rowHeight = descriptor.rowHeight
                table.intercellSpacing = NSSize(width: 0, height: descriptor.rowSpacing)
                table.dataSource = rows
                table.reloadData()

                let actualDocumentHeight = table.rect(ofRow: count - 1).maxY
                XCTAssertEqual(
                    actualDocumentHeight,
                    descriptor.resultsDocumentHeight(resultCount: count),
                    accuracy: 0.001,
                    "\(design) AppKit row geometry must match the document when it fills the viewport"
                )
                XCTAssertEqual(
                    actualDocumentHeight,
                    descriptor.resultsViewportHeight(resultCount: count),
                    accuracy: 0.001
                )
            }
        }
    }

    func testOverflowResultsKeepAFixedViewportAndATallerDocument() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()
        XCTAssertEqual(LauncherSearchLimits.resultSetCap, 50)
        XCTAssertGreaterThan(LauncherSearchLimits.resultSetCap, 10)

        for design in LauncherDesign.allCases {
            var preferences = LauncherAppearancePreferences.defaults(design: design)
            preferences.visibleResultCount = 3
            let descriptor = controller.descriptor(for: preferences)
            XCTAssertEqual(
                descriptor.panelHeight(resultCount: 12),
                descriptor.panelHeight(resultCount: 3),
                accuracy: 0.001,
                "\(design) window height must follow Visible Results, not the match count"
            )
            XCTAssertEqual(
                descriptor.resultsViewportHeight(resultCount: 12),
                descriptor.resultsViewportHeight(resultCount: 3),
                accuracy: 0.001
            )
            XCTAssertGreaterThan(
                descriptor.resultsDocumentHeight(resultCount: 12),
                descriptor.resultsViewportHeight(resultCount: 12)
            )
        }
    }

    func testSearchResultComposerHonorsTheResultSetCap() {
        let catalog = (0..<60).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "catalog:\(index)",
                    kind: .application,
                    title: "Catalog \(index)",
                    target: .none
                ),
                score: 1_000 - index
            )
        }
        let composed = LauncherMainSearchResultComposer.compose(
            catalogResults: catalog,
            calculatorEvaluation: .notExpression,
            hasVisibleQuery: true,
            noMatch: .inlineStatus,
            limit: LauncherSearchLimits.resultSetCap
        )
        XCTAssertEqual(composed.count, LauncherSearchLimits.resultSetCap)
        XCTAssertEqual(composed.first?.entry.id, "catalog:0")
        XCTAssertEqual(composed.last?.entry.id, "catalog:49")
    }

    func testLockedThemeGeometry() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()
        let minimal = controller.descriptor(for: .defaults(design: .minimal))
        let glass = controller.descriptor(for: .defaults(design: .liquidGlass))

        XCTAssertEqual(LauncherMinimalMetrics.widthScale, 0.90)
        XCTAssertEqual(minimal.width, 600 * LauncherMinimalMetrics.widthScale)
        XCTAssertEqual(minimal.rowHeight, 50)
        XCTAssertEqual(minimal.cornerRadius, 5)
        XCTAssertEqual(minimal.searchHeight, 55)
        XCTAssertEqual(minimal.searchFontSize, 24)
        XCTAssertEqual(minimal.searchHorizontalInset, 20)
        XCTAssertEqual(minimal.searchVerticalInset, 11.5)
        XCTAssertEqual(minimal.searchHeight - minimal.searchVerticalInset * 2, 32)
        XCTAssertEqual(minimal.surface, .ultraThick)
        XCTAssertFalse(minimal.hasShadow)
        XCTAssertTrue(minimal.showsHeaderSeparator)
        XCTAssertEqual(minimal.resultSelectionCornerRadius, 0)
        XCTAssertEqual(minimal.resultHorizontalInset, 0)
        XCTAssertFalse(minimal.shouldShowHeaderSeparator(hasResults: true, selectedRow: 0))
        XCTAssertTrue(minimal.shouldShowHeaderSeparator(hasResults: true, selectedRow: 1))
        XCTAssertFalse(minimal.shouldShowHeaderSeparator(hasResults: false, selectedRow: 0))
        XCTAssertEqual(minimal.resultTableStyle, .fullWidth)
        XCTAssertEqual(glass.width, 640)
        XCTAssertEqual(glass.searchHeight, 58)
        XCTAssertEqual(
            glass.searchFontSize,
            LauncherLiquidGlassMetrics.searchFontSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            glass.searchHorizontalInset,
            LauncherLiquidGlassMetrics.searchHorizontalInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            glass.searchVerticalInset,
            LauncherLiquidGlassMetrics.searchVerticalInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            glass.searchHeight - glass.searchVerticalInset * 2,
            43 * LauncherLiquidGlassMetrics.scale,
            accuracy: 0.001
        )
        XCTAssertEqual(LauncherLiquidGlassSurfaceView.collapsedHeight, 58)
        XCTAssertEqual(
            LauncherLiquidGlassSurfaceView.cornerRadius,
            LauncherLiquidGlassMetrics.cornerRadius,
            accuracy: 0.001
        )
        XCTAssertEqual(glass.rowHeight, glass.searchHeight)
        XCTAssertEqual(glass.resultTopInset, LauncherLiquidGlassMetrics.resultTopInset)
        XCTAssertEqual(glass.resultBottomInset, LauncherLiquidGlassMetrics.resultBottomInset)
        XCTAssertEqual(
            glass.panelHeight(resultCount: 1),
            glass.searchHeight * 2
                + LauncherLiquidGlassMetrics.resultTopInset
                + LauncherLiquidGlassMetrics.resultBottomInset
        )
        XCTAssertGreaterThan(
            glass.searchHeight + glass.resultTopInset,
            glass.headerSeparatorTopInset + glass.headerSeparatorLayoutHeight
        )
        XCTAssertEqual(glass.rowSpacing, 0)
        XCTAssertEqual(glass.cornerRadius, LauncherLiquidGlassMetrics.searchHeight / 2)
        XCTAssertTrue(glass.hasShadow)
        XCTAssertTrue(glass.showsHeaderSeparator)
        XCTAssertEqual(glass.resultSelectionCornerRadius, 12)
        XCTAssertEqual(glass.resultTableStyle, .fullWidth)
        for descriptor in [minimal, glass] {
            XCTAssertEqual(
                descriptor.searchMetrics.emptyInsertionPointLeadingGap,
                LauncherSearchMetrics.sharedEmptyInsertionPointLeadingGap
            )
        }
    }

    func testEveryThemeUsesItsRequestedMagnifierWithEqualHorizontalSpacing() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            let descriptor = controller.descriptor(for: .defaults(design: design))
            let fieldHeight = descriptor.searchHeight
                - descriptor.searchControlVerticalInset * 2
            let geometry = LauncherSearchGeometry(
                bounds: NSRect(
                    x: 0,
                    y: 0,
                    width: descriptor.width - descriptor.searchHorizontalInset * 2,
                    height: fieldHeight
                ),
                metrics: descriptor.searchMetrics
            )
            let shellToIcon = descriptor.searchHorizontalInset
                + geometry.searchButtonRect.minX
            let iconToQuery = geometry.searchTextRect.minX
                - geometry.searchButtonRect.maxX

            let expectedSymbolSize = design == .liquidGlass
                ? LauncherLiquidGlassMetrics.searchSymbolSize
                : descriptor.searchFontSize
            let expectedSymbolPointSize = design == .liquidGlass
                ? LauncherLiquidGlassMetrics.searchSymbolPointSize
                : descriptor.searchFontSize
            XCTAssertEqual(
                descriptor.searchMetrics.symbolSize,
                expectedSymbolSize,
                accuracy: 0.001,
                "\(design.title) magnifier canvas must match its optical contract"
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolPointSize,
                expectedSymbolPointSize,
                accuracy: 0.001,
                "\(design.title) magnifier point size must match its optical contract"
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolTextGap,
                descriptor.searchHorizontalInset,
                accuracy: 0.001,
                "\(design.title) must retain the requested nominal spacing"
            )
            XCTAssertEqual(
                iconToQuery,
                shellToIcon + descriptor.searchMetrics.textLeadingCompensation,
                accuracy: 0.001,
                "\(design.title) must apply only its requested ten-point diagnostic correction"
            )
        }
    }

    func testEveryThemeRendersTheExpectedGapAfterTenPointTextCorrection() throws {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            var preferences = LauncherAppearancePreferences.defaults(design: design)
            preferences.mode = .dark
            let descriptor = controller.descriptor(for: preferences)
            let window = BroccoliAppTestWindows.window(
                size: NSSize(width: descriptor.width, height: descriptor.searchHeight)
            )
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            let field = LauncherNativeSearchField(frame: NSRect(
                x: descriptor.searchHorizontalInset,
                y: descriptor.searchControlVerticalInset,
                width: descriptor.width - descriptor.searchHorizontalInset * 2,
                height: descriptor.searchHeight - descriptor.searchControlVerticalInset * 2
            ))
            LauncherNativeSearchFieldStyle.apply(
                to: field,
                metrics: descriptor.searchMetrics,
                iconColor: descriptor.searchIconColor
            )
            field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
                "Search Broccoli",
                metrics: descriptor.searchMetrics,
                color: descriptor.searchTextColor
            ))
            window.contentView?.addSubview(field)
            window.makeKeyAndOrderFront(nil)
            XCTAssertTrue(window.makeFirstResponder(field))
            field.configureCurrentFieldEditor()
            (field.currentEditor() as? NSTextView)?.insertionPointColor = .clear
            window.displayIfNeeded()
            let content = try XCTUnwrap(window.contentView)
            let bitmap = try XCTUnwrap(
                content.bitmapImageRepForCachingDisplay(in: content.bounds)
            )
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let iconProbe = content.convert(field.searchButtonBounds, from: field)
            let textProbe = content.convert(field.searchTextBounds, from: field)
            let iconInk = try XCTUnwrap(
                brightInkBounds(in: bitmap, constrainedTo: iconProbe)
            )
            let textInk = try XCTUnwrap(
                brightInkBounds(in: bitmap, constrainedTo: textProbe)
            )
            XCTAssertEqual(
                iconInk.minX - 9.5,
                textInk.minX - iconInk.maxX,
                accuracy: 0.25,
                "\(design.title) must preserve its measured ten-point text correction"
            )
            window.orderOut(nil)
        }
    }

    func testLiquidGlassGeometryAndOpticalOverrides() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()
        var lightPreferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        lightPreferences.mode = .light
        var darkPreferences = lightPreferences
        darkPreferences.mode = .dark

        let light = controller.descriptor(
            for: lightPreferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let dark = controller.descriptor(
            for: darkPreferences,
            reducedTransparency: false,
            increasedContrast: false
        )

        if #available(macOS 26, *) {
            XCTAssertEqual(light.surface, .glass)
            XCTAssertEqual(dark.surface, .glass)
        }

        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaWidth, 900)
        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaSearchHeight, 75)
        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaSearchTextLeading, 75)
        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaSeparatorTopInset, 73)

        for descriptor in [light, dark] {
            XCTAssertEqual(descriptor.width, 640)
            XCTAssertEqual(descriptor.searchHeight, 58)
            XCTAssertEqual(
                descriptor.searchFontSize,
                26,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchHorizontalInset,
                20,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchVerticalInset,
                16 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolSize,
                LauncherLiquidGlassMetrics.searchSymbolSize,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolPointSize,
                LauncherLiquidGlassMetrics.searchSymbolPointSize,
                accuracy: 0.001
            )
            XCTAssertEqual(descriptor.searchMetrics.emptyInsertionPointLeadingGap, 1.5)
            XCTAssertTrue(descriptor.showsHeaderSeparator)
            XCTAssertEqual(
                descriptor.headerSeparatorTopInset,
                73 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.headerSeparatorLeadingInset,
                25 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(descriptor.headerSeparatorThickness, 1)
            XCTAssertEqual(
                descriptor.headerSeparatorAngleDegrees,
                0,
                accuracy: 0.000001
            )
        }

        let fieldHeight = light.searchHeight - light.searchControlVerticalInset * 2
        let geometry = LauncherSearchGeometry(
            bounds: NSRect(
                x: 0,
                y: 0,
                width: light.width - light.searchHorizontalInset * 2,
                height: fieldHeight
            ),
            metrics: light.searchMetrics
        )
        XCTAssertEqual(
            light.searchHorizontalInset + geometry.searchButtonRect.minX,
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            light.searchHorizontalInset + geometry.searchTextRect.minX,
            light.searchHorizontalInset * 2
                + light.searchMetrics.symbolSize
                + light.searchMetrics.textLeadingCompensation,
            accuracy: 0.001
        )
        XCTAssertEqual(
            geometry.searchTextRect.minX - geometry.searchButtonRect.maxX,
            light.searchHorizontalInset + light.searchMetrics.textLeadingCompensation,
            accuracy: 0.001
        )
        XCTAssertEqual(geometry.searchButtonRect.midY, geometry.bounds.midY, accuracy: 0.001)
        XCTAssertEqual(geometry.searchTextRect.midY, geometry.bounds.midY, accuracy: 0.001)
        XCTAssertLessThan(geometry.searchTextRect.minY, geometry.searchTextRect.maxY)
        XCTAssertGreaterThanOrEqual(geometry.searchTextRect.minY, 0)
        XCTAssertLessThanOrEqual(geometry.searchTextRect.maxY, fieldHeight)
        XCTAssertEqual(light.searchMetrics.symbolDrawingScale, 1)
        XCTAssertEqual(light.searchMetrics.symbolDrawingVerticalScale, 1)
        XCTAssertEqual(
            light.cornerRadius,
            LauncherLiquidGlassMetrics.cornerRadius,
            accuracy: 0.001
        )

        for descriptor in [light, dark] {
            if descriptor.isDark {
                // Opaque neutral lifts, composited additively so the surface supplies the hue.
                XCTAssertTrue(descriptor.usesAdditiveInk)
                let ink = LauncherLiquidGlassMetrics.darkInkLift
                let query = LauncherLiquidGlassMetrics.darkQueryLift
                let rule = LauncherLiquidGlassMetrics.darkRuleLift
                assertColor(descriptor.searchIconColor, red: ink, green: ink, blue: ink, alpha: 1)
                assertColor(descriptor.searchTextColor, red: query, green: query, blue: query, alpha: 1)
                assertColor(descriptor.headerSeparatorColor, red: rule, green: rule, blue: rule, alpha: 1)
                XCTAssertEqual(LauncherLiquidGlassMetrics.darkRimLift, Double(ink) / 4, accuracy: 0.001,
                               "The rim is half as white as the earlier half-lift border")
            } else {
                XCTAssertFalse(descriptor.usesAdditiveInk)
                XCTAssertEqual(descriptor.searchTextColor, descriptor.searchIconColor)
                assertColor(descriptor.searchIconColor, red: 0, green: 0, blue: 0, alpha: 1)
                assertColor(descriptor.headerSeparatorColor, red: 0, green: 0, blue: 0, alpha: 0.25)
            }
            XCTAssertEqual(descriptor.searchPlaceholderColor, descriptor.searchIconColor)
            XCTAssertEqual(descriptor.headerSeparatorAngleDegrees, 0)
        }
    }

    func testMinimalFigmaContractAcrossLightDarkAndReducedTransparency() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()
        var lightPreferences = LauncherAppearancePreferences.defaults(design: .minimal)
        lightPreferences.mode = .light
        var darkPreferences = lightPreferences
        darkPreferences.mode = .dark

        let light = controller.descriptor(
            for: lightPreferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let dark = controller.descriptor(
            for: darkPreferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let reducedLight = controller.descriptor(
            for: lightPreferences,
            reducedTransparency: true,
            increasedContrast: false
        )
        let reducedDark = controller.descriptor(
            for: darkPreferences,
            reducedTransparency: true,
            increasedContrast: false
        )

        for descriptor in [light, dark, reducedLight, reducedDark] {
            XCTAssertEqual(descriptor.width, 600 * LauncherMinimalMetrics.widthScale)
            XCTAssertEqual(descriptor.cornerRadius, 5)
            XCTAssertEqual(descriptor.searchHeight, 55)
            XCTAssertEqual(descriptor.searchFontSize, 24)
            XCTAssertEqual(descriptor.searchHorizontalInset, 20)
            XCTAssertEqual(descriptor.searchVerticalInset, 11.5)
            XCTAssertEqual(descriptor.searchHeight - descriptor.searchVerticalInset * 2, 32)
            XCTAssertEqual(
                descriptor.searchHeight - descriptor.searchControlVerticalInset * 2,
                37
            )
            XCTAssertFalse(descriptor.hasShadow)
            XCTAssertTrue(descriptor.showsHeaderSeparator)
            XCTAssertEqual(descriptor.searchMetrics.fontSize, 24)
            XCTAssertEqual(descriptor.searchMetrics.symbolSize, 24)
            XCTAssertEqual(descriptor.searchMetrics.symbolPointSize, 24)
            XCTAssertEqual(descriptor.searchMetrics.symbolTextGap, 20)
            XCTAssertEqual(descriptor.searchMetrics.textLeadingCompensation, -10)
            XCTAssertEqual(
                descriptor.searchMetrics.emptyInsertionPointLeadingGap,
                LauncherSearchMetrics.sharedEmptyInsertionPointLeadingGap
            )
            XCTAssertEqual(descriptor.searchMetrics.symbolDrawingScale, 1.08)
            XCTAssertEqual(descriptor.searchMetrics.symbolDrawingVerticalScale, 1.10)
            XCTAssertEqual(descriptor.rowHeight, 50)
            XCTAssertEqual(descriptor.resultHorizontalInset, 0)
            XCTAssertEqual(descriptor.resultSelectionCornerRadius, 0)
            XCTAssertEqual(descriptor.resultTopInset, 0)
            XCTAssertEqual(descriptor.resultBottomInset, 0)
            XCTAssertEqual(descriptor.rowSpacing, 0)
        }

        XCTAssertFalse(light.isDark)
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(light.surface, .ultraThick)
        XCTAssertEqual(dark.surface, .ultraThick)
        XCTAssertEqual(reducedLight.surface, .opaque)
        XCTAssertEqual(reducedDark.surface, .opaque)
        assertSameGeometry(light, reducedLight, design: .minimal)
        assertSameGeometry(dark, reducedDark, design: .minimal)

        XCTAssertEqual(LauncherMinimalMaterialSurfaceView.figmaBackgroundBlur, 60)
        XCTAssertEqual(LauncherMinimalMaterialSurfaceView.lightTintOpacity, 0.60)
        XCTAssertEqual(LauncherMinimalMaterialSurfaceView.darkTintOpacity, 0.92)
        XCTAssertEqual(LauncherMinimalMetrics.separatorTopInset, 54)
        XCTAssertEqual(LauncherMinimalMetrics.separatorLeadingInset, 16)
        XCTAssertEqual(LauncherMinimalMetrics.separatorTrailingInset, 16)
        XCTAssertEqual(LauncherMinimalMetrics.separatorThickness, 1)
        XCTAssertEqual(LauncherMinimalMetrics.resultIconSize, 30)
        XCTAssertEqual(LauncherMinimalMetrics.resultIconOpticalSize, 26)
        XCTAssertEqual(LauncherMinimalMetrics.resultNativeIconSize, 35)
        XCTAssertEqual(LauncherMinimalMetrics.resultNativeIconOpticalSize, 35)
        XCTAssertEqual(LauncherMinimalMetrics.resultActionIconOpticalSize, 16.5)
        XCTAssertEqual(LauncherMinimalMetrics.resultTemplatePointSize, 22)
        XCTAssertEqual(LauncherMinimalMetrics.resultTitleFontSize, 16)
        XCTAssertEqual(LauncherMinimalMetrics.resultSubtitleFontSize, 12)
        XCTAssertEqual(LauncherMinimalMetrics.resultShortcutFontSize, 13)
        XCTAssertEqual(
            light.width
                - LauncherMinimalMetrics.separatorLeadingInset
                - LauncherMinimalMetrics.separatorTrailingInset,
            508
        )

        let searchGeometry = LauncherSearchGeometry(
            bounds: NSRect(
                x: 0,
                y: 0,
                width: 500,
                height: light.searchHeight - light.searchControlVerticalInset * 2
            ),
            metrics: light.searchMetrics
        )
        XCTAssertEqual(light.searchControlVerticalInset, 9)
        let expectedButtonRect = NSRect(
            x: 0,
            y: 6.5,
            width: 24,
            height: 24
        )
        XCTAssertEqual(searchGeometry.searchButtonRect.minX, expectedButtonRect.minX, accuracy: 0.001)
        XCTAssertEqual(searchGeometry.searchButtonRect.minY, expectedButtonRect.minY, accuracy: 0.001)
        XCTAssertEqual(searchGeometry.searchButtonRect.width, expectedButtonRect.width, accuracy: 0.001)
        XCTAssertEqual(searchGeometry.searchButtonRect.height, expectedButtonRect.height, accuracy: 0.001)
        XCTAssertEqual(searchGeometry.searchTextRect.minX, 34)
        XCTAssertEqual(searchGeometry.searchButtonRect.midY, searchGeometry.bounds.midY)
        XCTAssertEqual(searchGeometry.searchTextRect.midY, searchGeometry.bounds.midY)
        XCTAssertEqual(
            light.searchHorizontalInset + searchGeometry.searchButtonRect.minX,
            20,
            "The compact magnifier begins 20 points from the shell's leading edge"
        )
        XCTAssertEqual(
            light.searchControlVerticalInset + searchGeometry.searchButtonRect.minY,
            light.searchHeight
                - light.searchControlVerticalInset
                - searchGeometry.searchButtonRect.maxY,
            accuracy: 0.001,
            "The compact magnifier is automatically centered inside the header"
        )
        XCTAssertEqual(
            light.searchHorizontalInset
                + searchGeometry.searchButtonRect.maxX
                + light.searchMetrics.symbolTextGap
                + light.searchMetrics.textLeadingCompensation,
            54,
            "The compact query follows the magnifier without an oversized gap"
        )
        XCTAssertEqual(
            light.searchVerticalInset,
            11.5,
            "The compact search control keeps an even vertical shell inset"
        )
        XCTAssertEqual(
            light.searchHorizontalInset + searchGeometry.searchTextRect.minX,
            54,
            "The native cell and compact optical grid share one query origin"
        )
        XCTAssertEqual(
            light.searchControlVerticalInset + searchGeometry.searchTextRect.minY,
            light.searchHeight
                - light.searchControlVerticalInset
                - searchGeometry.searchTextRect.maxY,
            accuracy: 0.001,
            "The placeholder line box is automatically centered inside the header"
        )

        assertColor(light.searchTextColor, red: 0, green: 0, blue: 0, alpha: 1)
        assertColor(light.searchIconColor, red: 0, green: 0, blue: 0, alpha: 0.85)
        assertColor(light.headerSeparatorColor, red: 0, green: 0, blue: 0, alpha: 0.25)
        assertColor(dark.searchTextColor, red: 1, green: 1, blue: 1, alpha: 0.82)
        assertColor(dark.searchIconColor, red: 1, green: 1, blue: 1, alpha: 0.85)
        assertColor(dark.headerSeparatorColor, red: 1, green: 1, blue: 1, alpha: 0.25)
        assertColor(
            reducedLight.backgroundColor,
            equals: NSColor(calibratedWhite: 0.93, alpha: 1)
        )
        assertColor(reducedDark.backgroundColor, red: 0, green: 0, blue: 0, alpha: 1)

        let lightSurface = LauncherMinimalMaterialSurfaceView(
            frame: NSRect(x: 0, y: 0, width: light.width, height: light.searchHeight),
            isDark: false
        )
        XCTAssertEqual(lightSurface.layer?.cornerRadius, 5)
        XCTAssertEqual(lightSurface.layer?.cornerCurve, .circular)
        XCTAssertEqual(lightSurface.layer?.borderWidth, 0)
        XCTAssertTrue(lightSurface.layer?.masksToBounds == true)
        let effect = lightSurface.subviews.compactMap { $0 as? NSVisualEffectView }.first
        XCTAssertNotNil(effect)
        XCTAssertEqual(effect?.blendingMode, .behindWindow)
        XCTAssertEqual(effect?.material, .underWindowBackground)
        XCTAssertEqual(effect?.state, .active)
    }

    func testBorderlessNativeSearchEditorUsesAppKitSearchTextBounds() throws {
        _ = NSApplication.shared
        let window = BroccoliAppTestWindows.window(size: NSSize(width: 640, height: 58))
        let field = LauncherNativeSearchField(
            frame: NSRect(x: 28, y: 12, width: 584, height: 34)
        )
        LauncherNativeSearchFieldStyle.apply(to: field)
        field.isBezeled = false
        field.drawsBackground = false
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        XCTAssertEqual(editor.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(
            editor.textContainerInset.width,
            field.searchMetrics.emptyInsertionPointLeadingGap,
            accuracy: 0.001
        )
        XCTAssertEqual(editor.textContainerInset.height, 0, accuracy: 0.001)
        XCTAssertGreaterThan(clipView.frame.minX, field.searchButtonBounds.maxX)
        XCTAssertLessThanOrEqual(clipView.frame.maxX, field.bounds.maxX)
        XCTAssertEqual(field.searchButtonBounds.size, NSSize(width: 34, height: 34))
        XCTAssertEqual(
            field.searchButtonBounds.midY,
            field.bounds.midY
        )
        XCTAssertEqual(
            field.searchTextBounds.minX - field.searchButtonBounds.maxX,
            LauncherSearchGeometry.symbolTextGap
        )
        XCTAssertEqual(field.font?.pointSize, 26)
        XCTAssertTrue(field.cell is LauncherNativeSearchFieldCell)
        let searchImage = try XCTUnwrap(
            (field.cell as? NSSearchFieldCell)?.searchButtonCell?.image
        )
        XCTAssertFalse(
            searchImage.isTemplate,
            "The magnifier is baked in the same device ink as the placeholder"
        )
        XCTAssertEqual(
            (field.cell as? NSSearchFieldCell)?.searchButtonCell?.highlightsBy,
            [],
            "Editing and resizing must not add a separate search-button highlight"
        )
    }

    func testEmptyCaretGapSurvivesNativeEditorRelayoutForEveryDesign() {
        _ = NSApplication.shared
        let fieldBounds = NSRect(x: 0, y: 0, width: 560, height: 40)

        for design in LauncherDesign.allCases {
            let descriptor = LauncherThemeController().descriptor(
                for: .defaults(design: design),
                reducedTransparency: false,
                increasedContrast: false
            )
            let metrics = descriptor.searchMetrics
            let editor = NSTextView(frame: fieldBounds)
            editor.string = ""

            let cell = LauncherNativeSearchFieldCell(textCell: "")
            cell.searchMetrics = metrics
            let searchTextRect = cell.searchTextRect(forBounds: fieldBounds)
            let emptyEditorRect = cell.editorRect(forBounds: fieldBounds, isEmpty: true)
            XCTAssertEqual(
                emptyEditorRect.minX,
                searchTextRect.minX - metrics.emptyInsertionPointLeadingGap,
                accuracy: 0.001,
                design.title
            )
            XCTAssertEqual(emptyEditorRect.maxX, searchTextRect.maxX, accuracy: 0.001)
            XCTAssertEqual(
                emptyEditorRect.minY,
                searchTextRect.minY,
                accuracy: 0.001,
                design.title
            )

            editor.textContainer?.lineFragmentPadding = 5
            editor.textContainerInset = .zero
            cell.configureFieldEditor(editor, isEmpty: true)
            XCTAssertEqual(editor.textContainer?.lineFragmentPadding, 0, design.title)
            XCTAssertEqual(
                editor.textContainerInset.width,
                metrics.emptyInsertionPointLeadingGap,
                accuracy: 0.001,
                design.title
            )
            XCTAssertEqual(
                editor.textContainerInset.height,
                0,
                accuracy: 0.001,
                design.title
            )

        }
    }

    func testLiquidSearchRenderedInkMatchesSpotlightOpticalRhythm() throws {
        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .dark
        let descriptor = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let fieldSize = NSSize(
            width: descriptor.width - descriptor.searchHorizontalInset * 2,
            height: descriptor.searchHeight - descriptor.searchControlVerticalInset * 2
        )
        let window = BroccoliAppTestWindows.window(size: fieldSize)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black

        let field = LauncherNativeSearchField(frame: window.contentView?.bounds ?? .zero)
        field.appearance = NSAppearance(named: .darkAqua)
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: descriptor.searchMetrics,
            iconColor: descriptor.searchIconColor
        )
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: descriptor.searchMetrics,
            color: descriptor.searchTextColor
        ))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()
        (field.currentEditor() as? NSTextView)?.insertionPointColor = .clear
        window.displayIfNeeded()

        let bitmap = try XCTUnwrap(
            window.contentView?.bitmapImageRepForCachingDisplay(
                in: window.contentView?.bounds ?? .zero
            )
        )
        window.contentView?.cacheDisplay(
            in: window.contentView?.bounds ?? .zero,
            to: bitmap
        )

        let iconInk = try XCTUnwrap(
            brightInkBounds(
                in: bitmap,
                constrainedTo: field.searchButtonBounds.insetBy(dx: -1, dy: -1)
            )
        )
        let textProbe = NSRect(
            x: field.searchTextBounds.minX,
            y: field.bounds.minY,
            width: 230,
            height: field.bounds.height
        )
        let textInk = try XCTUnwrap(
            brightInkBounds(in: bitmap, constrainedTo: textProbe)
        )
        let opticalGap = textInk.minX - iconInk.maxX
        let canvasGap = field.searchTextBounds.minX - field.searchButtonBounds.maxX
        XCTAssertGreaterThanOrEqual(opticalGap, canvasGap)
        XCTAssertLessThanOrEqual(
            opticalGap,
            canvasGap + 4,
            "The uncropped magnifier and placeholder must read as one compact Spotlight control"
        )
        XCTAssertEqual(
            textInk.midY - iconInk.midY,
            0,
            accuracy: 3,
            "The rendered magnifier must align with the placeholder's optical center"
        )
    }

    func testLiquidPlaceholderAndTypedQueryShareTheSameInkOrigin() throws {
        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .dark
        let descriptor = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let fieldSize = NSSize(
            width: descriptor.width - descriptor.searchHorizontalInset * 2,
            height: descriptor.searchHeight - descriptor.searchControlVerticalInset * 2
        )
        let window = BroccoliAppTestWindows.window(size: fieldSize)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor.black

        let field = LauncherNativeSearchField(frame: window.contentView?.bounds ?? .zero)
        field.appearance = NSAppearance(named: .darkAqua)
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: descriptor.searchMetrics,
            iconColor: descriptor.searchIconColor
        )
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: descriptor.searchMetrics,
            color: descriptor.searchTextColor
        ))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertionPointColor = NSColor.clear

        func renderedTextInk() throws -> NSRect {
            window.displayIfNeeded()
            let bounds = window.contentView?.bounds ?? .zero
            let bitmap = try XCTUnwrap(
                window.contentView?.bitmapImageRepForCachingDisplay(in: bounds)
            )
            window.contentView?.cacheDisplay(in: bounds, to: bitmap)
            return try XCTUnwrap(
                brightInkBounds(
                    in: bitmap,
                    constrainedTo: NSRect(
                        x: field.searchTextBounds.minX,
                        y: field.bounds.minY,
                        width: 300,
                        height: field.bounds.height
                    )
                )
            )
        }

        editor.string = ""
        let placeholderInk = try renderedTextInk()
        editor.string = "Search Broccoli"
        field.configureCurrentFieldEditor()
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.needsDisplay = true
        let queryInk = try renderedTextInk()

        XCTAssertEqual(queryInk.minX, placeholderInk.minX, accuracy: 1)
        XCTAssertTrue(field.searchTextBounds.contains(placeholderInk))
        XCTAssertTrue(field.searchTextBounds.contains(queryInk))
    }

    func testMinimalPlaceholderAndTypedQueryShareTheSameVerticalInkOrigin() throws {
        _ = NSApplication.shared
        let fieldSize = NSSize(width: 500, height: 40)
        let window = BroccoliAppTestWindows.window(size: fieldSize)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white

        let field = LauncherNativeSearchField(frame: NSRect(origin: .zero, size: fieldSize))
        field.appearance = NSAppearance(named: .aqua)
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: .figmaMinimal,
            iconColor: .black
        )
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: .figmaMinimal,
            color: .black
        ))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertionPointColor = .clear

        func renderedTextInk() throws -> NSRect {
            window.displayIfNeeded()
            let bounds = window.contentView?.bounds ?? .zero
            let bitmap = try XCTUnwrap(
                window.contentView?.bitmapImageRepForCachingDisplay(in: bounds)
            )
            window.contentView?.cacheDisplay(in: bounds, to: bitmap)
            return try XCTUnwrap(
                darkInkBounds(
                    in: bitmap,
                    constrainedTo: NSRect(
                        x: field.searchTextBounds.minX,
                        y: field.bounds.minY,
                        width: 240,
                        height: field.bounds.height
                    )
                )
            )
        }

        editor.string = ""
        field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        let placeholderInk = try renderedTextInk()

        editor.string = "Search Broccoli"
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        let queryInk = try renderedTextInk()

        XCTAssertEqual(queryInk.minY, placeholderInk.minY, accuracy: 0.5)
        XCTAssertEqual(queryInk.maxY, placeholderInk.maxY, accuracy: 0.5)
        XCTAssertEqual(queryInk.midY, placeholderInk.midY, accuracy: 0.5)
    }

    func testMinimalEditorViewportDoesNotMoveWhenClickingDifferentVerticalPoints() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .minimal)
        preferences.mode = .dark
        controller.applyAppearance(preferences, force: true)
        controller.setMode(.main)
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }

        func searchField(in view: NSView) -> LauncherNativeSearchField? {
            if let field = view as? LauncherNativeSearchField { return field }
            for child in view.subviews {
                if let field = searchField(in: child) { return field }
            }
            return nil
        }

        let window = controller.visibilityIsolationWindow
        let content = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(searchField(in: content))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertionPointColor = .clear
        editor.string = "hh"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.deleteBackward(nil)
        XCTAssertEqual(editor.string, "h")
        field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()

        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        let expectedFrame = clipView.frame
        let expectedBounds = clipView.bounds
        let expectedEditorFrame = editor.frame

        func click(atY y: CGFloat) throws {
            let fieldPoint = NSPoint(x: field.searchTextBounds.minX + 30, y: y)
            let windowPoint = field.convert(fieldPoint, to: nil)
            let down = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: windowPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ))
            let up = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: windowPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0
            ))
            NSApp.postEvent(up, atStart: false)
            window.sendEvent(down)
            content.displayIfNeeded()
        }

        try click(atY: 3)
        XCTAssertEqual(clipView.frame, expectedFrame)
        XCTAssertEqual(clipView.bounds, expectedBounds)
        XCTAssertEqual(editor.frame.origin, expectedEditorFrame.origin)
        XCTAssertEqual(editor.frame.height, expectedEditorFrame.height)
        XCTAssertEqual(editor.frame.width, expectedEditorFrame.width, accuracy: 0.5)

        try click(atY: field.bounds.maxY - 3)
        XCTAssertEqual(clipView.frame, expectedFrame)
        XCTAssertEqual(clipView.bounds, expectedBounds)
        XCTAssertEqual(editor.frame.origin, expectedEditorFrame.origin)
        XCTAssertEqual(editor.frame.height, expectedEditorFrame.height)
        XCTAssertEqual(editor.frame.width, expectedEditorFrame.width, accuracy: 0.5)
    }

    func testPlaceholderInkDoesNotMoveWhenFocusChanges() throws {
        _ = NSApplication.shared
        let fieldSize = NSSize(width: 560, height: 40)
        let window = BroccoliAppTestWindows.window(size: fieldSize)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white

        let focusSink = NSView(frame: .zero)
        let field = LauncherNativeSearchField(frame: NSRect(origin: .zero, size: fieldSize))
        field.appearance = NSAppearance(named: .aqua)
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: .figmaMinimal,
            iconColor: NSColor.black.withAlphaComponent(0.85)
        )
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: .figmaMinimal,
            color: .black
        ))
        let nativePlaceholderColor = try XCTUnwrap(
            field.placeholderAttributedString?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(nativePlaceholderColor.alphaComponent, 0, accuracy: 0.001)
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(focusSink)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func placeholderInk() throws -> NSRect {
            window.displayIfNeeded()
            let bounds = window.contentView?.bounds ?? .zero
            let bitmap = try XCTUnwrap(
                window.contentView?.bitmapImageRepForCachingDisplay(in: bounds)
            )
            window.contentView?.cacheDisplay(in: bounds, to: bitmap)
            return try XCTUnwrap(
                darkInkBounds(
                    in: bitmap,
                    constrainedTo: NSRect(
                        // Sample the middle of the placeholder so the field editor's blinking
                        // insertion-point pixels cannot affect the vertical ink bounds.
                        x: field.searchTextBounds.minX + 80,
                        y: field.bounds.minY,
                        width: 220,
                        height: field.bounds.height
                    )
                )
            )
        }

        XCTAssertTrue(window.makeFirstResponder(focusSink))
        let unfocusedInk = try placeholderInk()

        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()
        let firstEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        firstEditor.insertionPointColor = .clear
        firstEditor.needsDisplay = true
        XCTAssertEqual(firstEditor.string, "")
        let firstFocusInk = try placeholderInk()

        XCTAssertTrue(window.makeFirstResponder(focusSink))
        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()
        let secondEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        secondEditor.insertionPointColor = .clear
        secondEditor.needsDisplay = true
        XCTAssertEqual(secondEditor.string, "")
        let secondFocusInk = try placeholderInk()

        XCTAssertEqual(firstFocusInk.minY, unfocusedInk.minY, accuracy: 0.5)
        XCTAssertEqual(secondFocusInk.minY, unfocusedInk.minY, accuracy: 0.5)
        XCTAssertEqual(firstFocusInk.maxY, unfocusedInk.maxY, accuracy: 0.5)
        XCTAssertEqual(secondFocusInk.maxY, unfocusedInk.maxY, accuracy: 0.5)
        XCTAssertEqual(firstFocusInk.midY, unfocusedInk.midY, accuracy: 0.5)
        XCTAssertEqual(secondFocusInk.midY, unfocusedInk.midY, accuracy: 0.5)
    }

    func testMinimalSearchRenderedInkIsAutomaticallyCentered() throws {
        _ = NSApplication.shared
        let window = BroccoliAppTestWindows.window(size: NSSize(width: 560, height: 40))
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white

        let field = LauncherNativeSearchField(frame: window.contentView?.bounds ?? .zero)
        field.appearance = NSAppearance(named: .aqua)
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: .figmaMinimal,
            iconColor: NSColor.black.withAlphaComponent(0.85)
        )
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: .figmaMinimal,
            color: NSColor.black
        ))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        field.configureCurrentFieldEditor()
        (field.currentEditor() as? NSTextView)?.insertionPointColor = .clear
        window.displayIfNeeded()

        let bitmap = try XCTUnwrap(
            window.contentView?.bitmapImageRepForCachingDisplay(
                in: window.contentView?.bounds ?? .zero
            )
        )
        window.contentView?.cacheDisplay(
            in: window.contentView?.bounds ?? .zero,
            to: bitmap
        )

        let iconInk = try XCTUnwrap(
            darkInkBounds(in: bitmap, constrainedTo: field.searchButtonBounds)
        )
        XCTAssertEqual(iconInk.midY, field.bounds.midY, accuracy: 0.75)
        XCTAssertGreaterThan(iconInk.minX, field.searchButtonBounds.minX)
        XCTAssertLessThan(iconInk.maxX, field.searchButtonBounds.maxX)
        XCTAssertGreaterThan(iconInk.minY, field.searchButtonBounds.minY)
        XCTAssertLessThan(iconInk.maxY, field.searchButtonBounds.maxY)

        let textInk = try XCTUnwrap(
            darkInkBounds(in: bitmap, constrainedTo: field.searchTextBounds)
        )
        XCTAssertEqual(
            textInk.midY,
            field.bounds.midY,
            accuracy: 2.25,
            "The font's own ascender/descender balance may offset its ink within a centered line box"
        )
        XCTAssertGreaterThanOrEqual(
            field.searchTextBounds.maxY - textInk.maxY,
            1,
            "The Minimal title rectangle must leave visible clearance above every glyph"
        )
    }

    func testLiveMinimalPanelAutomaticallyCentersIconAndPlaceholder() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .minimal)
        preferences.mode = .light
        controller.applyAppearance(preferences, force: true)
        controller.setMode(.main)
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }

        let window = controller.visibilityIsolationWindow
        let content = try XCTUnwrap(window.contentView)

        func searchField(in view: NSView) -> LauncherNativeSearchField? {
            if let field = view as? LauncherNativeSearchField { return field }
            for child in view.subviews {
                if let field = searchField(in: child) { return field }
            }
            return nil
        }

        let field = try XCTUnwrap(searchField(in: content))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertionPointColor = .clear
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: field.searchMetrics,
            color: NSColor.black
        ))
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()

        let fieldRect = content.convert(field.bounds, from: field)
        let textRect = content.convert(field.searchTextBounds, from: field)
        let iconRect = content.convert(
            field.searchButtonBounds.insetBy(dx: -1, dy: -1),
            from: field
        )
        let bitmap = try XCTUnwrap(
            content.bitmapImageRepForCachingDisplay(in: content.bounds)
        )
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let textInk = try XCTUnwrap(darkInkBounds(in: bitmap, constrainedTo: textRect))
        let iconInk = try XCTUnwrap(darkInkBounds(in: bitmap, constrainedTo: iconRect))

        XCTAssertNil(field.centeredPlaceholderAttributedString?.attribute(
            .baselineOffset,
            at: 0,
            effectiveRange: nil
        ))
        XCTAssertEqual(
            fieldRect.midY,
            LauncherMinimalMetrics.searchHeight / 2,
            accuracy: 0.25
        )
        XCTAssertEqual(textRect.midY, fieldRect.midY, accuracy: 0.25)
        XCTAssertEqual(iconRect.midY, fieldRect.midY, accuracy: 0.25)
        XCTAssertGreaterThan(textInk.minY, textRect.minY)
        XCTAssertLessThan(textInk.maxY, textRect.maxY)
        XCTAssertGreaterThan(iconInk.minY, iconRect.minY)
        XCTAssertLessThan(iconInk.maxY, iconRect.maxY)

        editor.string = "Search Broccoli"
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        let typedBitmap = try XCTUnwrap(
            content.bitmapImageRepForCachingDisplay(in: content.bounds)
        )
        content.cacheDisplay(in: content.bounds, to: typedBitmap)
        let typedInk = try XCTUnwrap(
            darkInkBounds(in: typedBitmap, constrainedTo: textRect)
        )
        XCTAssertEqual(typedInk.minY, textInk.minY, accuracy: 0.5)
        XCTAssertEqual(typedInk.maxY, textInk.maxY, accuracy: 0.5)
        XCTAssertEqual(typedInk.midY, textInk.midY, accuracy: 0.5)
    }

    func testLiveLiquidPanelUsesNativeCaretAndTracksArrowKeySelection() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .light
        controller.applyAppearance(preferences, force: true)
        controller.setMode(.main)
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }

        func searchField(in view: NSView) -> LauncherNativeSearchField? {
            if let field = view as? LauncherNativeSearchField { return field }
            for child in view.subviews {
                if let field = searchField(in: child) { return field }
            }
            return nil
        }

        let content = try XCTUnwrap(controller.visibilityIsolationWindow.contentView)
        let field = try XCTUnwrap(searchField(in: content))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = "10 + 1"
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let before = editor.firstRect(
            forCharacterRange: editor.selectedRange(),
            actualRange: &actualRange
        )

        editor.moveLeft(nil)
        let after = editor.firstRect(
            forCharacterRange: editor.selectedRange(),
            actualRange: &actualRange
        )

        XCTAssertEqual(editor.selectedRange().location, 5)
        XCTAssertLessThan(after.minX, before.minX)
        XCTAssertTrue(editor.shouldDrawInsertionPoint)
    }

    func testRewritingMinimalQueryMovesTheNativeCaretToTheFinalPosition() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .minimal), force: true)
        controller.setMode(.main)
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }

        func searchField(in view: NSView) -> LauncherNativeSearchField? {
            if let field = view as? LauncherNativeSearchField { return field }
            for child in view.subviews {
                if let field = searchField(in: child) { return field }
            }
            return nil
        }

        let content = try XCTUnwrap(controller.visibilityIsolationWindow.contentView)
        let field = try XCTUnwrap(searchField(in: content))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = "long query"
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let longQueryCaret = editor.firstRect(
            forCharacterRange: editor.selectedRange(),
            actualRange: &actualRange
        )

        editor.string = "q"
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        let rewrittenCaret = editor.firstRect(
            forCharacterRange: editor.selectedRange(),
            actualRange: &actualRange
        )

        XCTAssertLessThan(rewrittenCaret.minX, longQueryCaret.minX)
        XCTAssertTrue(editor.shouldDrawInsertionPoint)
    }

    private func brightInkBounds(
        in bitmap: NSBitmapImageRep,
        constrainedTo rect: NSRect
    ) -> NSRect? {
        let scaleX = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / bitmap.size.height
        let pixelRect = NSRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral.intersection(
            NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        )
        guard !pixelRect.isEmpty else { return nil }

        var minX = Int(pixelRect.maxX)
        var minY = Int(pixelRect.maxY)
        var maxX = Int(pixelRect.minX) - 1
        var maxY = Int(pixelRect.minY) - 1
        for y in Int(pixelRect.minY)..<Int(pixelRect.maxY) {
            for x in Int(pixelRect.minX)..<Int(pixelRect.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                let luminance = color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                guard color.alphaComponent > 0.1, luminance > 0.18 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NSRect(
            x: CGFloat(minX) / scaleX,
            y: CGFloat(minY) / scaleY,
            width: CGFloat(maxX - minX + 1) / scaleX,
            height: CGFloat(maxY - minY + 1) / scaleY
        )
    }

    private func darkInkBounds(
        in bitmap: NSBitmapImageRep,
        constrainedTo rect: NSRect
    ) -> NSRect? {
        let scaleX = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / bitmap.size.height
        let pixelRect = NSRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral.intersection(
            NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        )
        guard !pixelRect.isEmpty else { return nil }

        var minX = Int(pixelRect.maxX)
        var minY = Int(pixelRect.maxY)
        var maxX = Int(pixelRect.minX) - 1
        var maxY = Int(pixelRect.minY) - 1
        for y in Int(pixelRect.minY)..<Int(pixelRect.maxY) {
            for x in Int(pixelRect.minX)..<Int(pixelRect.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                let luminance = color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                guard color.alphaComponent > 0.1, luminance < 0.72 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NSRect(
            x: CGFloat(minX) / scaleX,
            y: CGFloat(minY) / scaleY,
            width: CGFloat(maxX - minX + 1) / scaleX,
            height: CGFloat(maxY - minY + 1) / scaleY
        )
    }

    func testLiquidSearchMagnifierTemplateRemainsStableAcrossExpansion() throws {
        _ = NSApplication.shared
        let surface = LauncherLiquidGlassSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 58),
            interactive: false
        )
        let content = NSView(frame: surface.bounds)
        let field = LauncherNativeSearchField(
            frame: NSRect(x: 28, y: 12, width: 584, height: 34)
        )
        LauncherNativeSearchFieldStyle.apply(to: field)
        content.addSubview(field)
        surface.setContentView(content)
        surface.layoutSubtreeIfNeeded()

        let cell = try XCTUnwrap(field.cell as? NSSearchFieldCell)
        let image = try XCTUnwrap(cell.searchButtonCell?.image)
        let beforeBitmap = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))
        )
        let before = try XCTUnwrap(
            beforeBitmap.representation(using: .png, properties: [:])
        )

        field.stringValue = "finder"
        surface.frame.size.height = 128
        content.frame = surface.bounds
        surface.layoutSubtreeIfNeeded()
        field.layoutSubtreeIfNeeded()

        let afterImage = try XCTUnwrap(cell.searchButtonCell?.image)
        let afterBitmap = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(afterImage.tiffRepresentation))
        )
        let after = try XCTUnwrap(
            afterBitmap.representation(using: .png, properties: [:])
        )
        XCTAssertFalse(afterImage.isTemplate)
        XCTAssertEqual(before, after, "The magnifier pixels must not change during expansion")
    }

    func testLiquidSurfaceChangesBackdropOnlyWithAppearance() throws {
        let surface = LauncherLiquidGlassSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 58),
            interactive: false
        )
        let material = try XCTUnwrap(
            surface.subviews.compactMap { $0 as? NSVisualEffectView }.first
        )

        surface.appearance = NSAppearance(named: .aqua)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(material.material, .hudWindow)

        surface.frame.size.height = 450
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            material.material,
            .hudWindow,
            "Showing results must not change the surface material"
        )

        let content = NSView()
        surface.setContentView(content)
        XCTAssertTrue(content.superview === material, "Light content stays in the HUD's vibrancy")
        let backdrop = try XCTUnwrap(
            surface.subviews.first { $0 is NSHostingView<LauncherDarkGlassBackdrop> }
        )
        XCTAssertTrue(backdrop.isHidden)
        XCTAssertEqual(material.state, .active)

        for name in [NSAppearance.Name.darkAqua, .accessibilityHighContrastDarkAqua] {
            surface.appearance = NSAppearance(named: name)
            for height: CGFloat in [58, 450, 58] {
                surface.frame.size.height = height
                surface.layoutSubtreeIfNeeded()
                XCTAssertTrue(surface.usesDarkBackdrop)
                XCTAssertTrue(material.isHidden)
                XCTAssertEqual(material.state, .inactive, "An inactive HUD does not sample a second background")
                XCTAssertFalse(backdrop.isHidden)
                XCTAssertEqual(backdrop.frame, surface.bounds)
                XCTAssertEqual(backdrop.layer?.cornerRadius, LauncherLiquidGlassMetrics.cornerRadius)
                XCTAssertTrue(backdrop.layer?.masksToBounds ?? false)
                XCTAssertTrue(content.superview === surface)
                XCTAssertGreaterThan(
                    try XCTUnwrap(surface.subviews.firstIndex(of: content)),
                    try XCTUnwrap(surface.subviews.firstIndex(of: backdrop))
                )
            }
        }

        surface.appearance = NSAppearance(named: .aqua)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(material.material, .hudWindow, "Returning to Light restores the HUD")
        XCTAssertFalse(material.isHidden)
        XCTAssertEqual(material.state, .active)
        XCTAssertTrue(backdrop.isHidden)
        XCTAssertTrue(content.superview === material)
        XCTAssertFalse(material.wantsLayer)
        XCTAssertNotNil(material.maskImage)
    }

    func testLiquidHeaderSeparatorUsesSearchInkWithoutVibrancy() {
        let ink = NSColor(calibratedWhite: 0, alpha: 0.25)
        let separator = LauncherHeaderSeparatorView()
        separator.color = ink
        XCTAssertFalse(separator.allowsVibrancy)
        XCTAssertFalse(separator.isOpaque)
        XCTAssertFalse(separator.wantsLayer)
        XCTAssertEqual(separator.color, ink)
    }

    func testLiquidPlaceholderViewDoesNotUseVibrancy() {
        let ink = NSColor(calibratedWhite: 0, alpha: 1)
        let field = LauncherNativeSearchField(frame: NSRect(x: 0, y: 0, width: 640, height: 58))
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: .figmaLiquidGlass,
            iconColor: ink,
            placeholderColor: ink
        )
        field.setCenteredPlaceholder(LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: .figmaLiquidGlass,
            color: ink
        ))
        let placeholder = field.subviews.compactMap { $0 as? NSTextView }.first
        XCTAssertEqual(placeholder?.allowsVibrancy, false)
        XCTAssertEqual(placeholder?.textColor, ink)
        XCTAssertEqual(
            field.centeredPlaceholderAttributedString?.attribute(
                .foregroundColor, at: 0, effectiveRange: nil
            ) as? NSColor,
            ink
        )
    }

    func testLiquidCancelControlKeepsTheXKnockout() throws {
        let ink = NSColor(calibratedWhite: 0, alpha: 1)
        let field = LauncherNativeSearchField(frame: NSRect(x: 0, y: 0, width: 640, height: 58))
        LauncherNativeSearchFieldStyle.apply(
            to: field,
            metrics: .figmaLiquidGlass,
            iconColor: ink,
            placeholderColor: ink
        )
        let cancel = try XCTUnwrap(
            (field.cell as? NSSearchFieldCell)?.cancelButtonCell?.image
        )
        XCTAssertFalse(cancel.isTemplate)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(cancel.tiffRepresentation))
        )
        let center = try XCTUnwrap(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        )
        let ring = try XCTUnwrap(
            bitmap.colorAt(
                x: bitmap.pixelsWide / 2 + max(2, bitmap.pixelsWide / 4),
                y: bitmap.pixelsHigh / 2
            )
        )
        XCTAssertLessThan(
            center.alphaComponent,
            0.25,
            "The X must stay knocked out so the control cannot read as a solid disc"
        )
        XCTAssertGreaterThan(
            ring.alphaComponent,
            0.5,
            "The circle must keep the same search ink as the query"
        )
    }

    func testResultCountChangesPreservePanelTopEdge() {
        _ = NSApplication.shared
        let descriptor = LauncherThemeController().descriptor(
            for: .defaults(design: .liquidGlass)
        )
        let screen = NSRect(x: 0, y: 48, width: 1_920, height: 1_032)
        var frame = LauncherPanelGeometry.positionedFrame(
            in: screen,
            preferredWidth: descriptor.width,
            height: descriptor.panelHeight(resultCount: 0),
            originX: descriptor.originX,
            originY: descriptor.originY
        )
        let fixedTopEdge = frame.maxY

        for resultCount in [1, 7, 2, 10, 0, 3] {
            frame = LauncherPanelGeometry.resizing(
                frame,
                toHeight: descriptor.panelHeight(resultCount: resultCount)
            )
            XCTAssertEqual(frame.maxY, fixedTopEdge, accuracy: 0.001)
        }
    }

    func testLiquidPresentationPositionsTheGlassAndWindowAtTheSameScreenFrame() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = LauncherPanelController()
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        controller.applyAppearance(preferences)
        let expected = LauncherPanelGeometry.positionedFrame(
            in: screen.visibleFrame,
            preferredWidth: LauncherLiquidGlassMetrics.width,
            height: LauncherLiquidGlassMetrics.searchHeight,
            originX: CGFloat(preferences.originX),
            originY: CGFloat(preferences.originY)
        )
        XCTAssertEqual(expected.midX, screen.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(
            expected.maxY,
            screen.visibleFrame.maxY - screen.visibleFrame.height * CGFloat(preferences.originY),
            accuracy: 0.5
        )

        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let root = try XCTUnwrap(window.contentView)
        let surface = try XCTUnwrap(root.subviews.compactMap { $0 as? LauncherLiquidGlassSurfaceView }.first)
        let visibleScreenFrame = window.convertToScreen(surface.convert(surface.bounds, to: nil))
        XCTAssertEqual(visibleScreenFrame, window.frame)
        XCTAssertEqual(visibleScreenFrame.width, LauncherLiquidGlassMetrics.width)
        XCTAssertEqual(visibleScreenFrame.height, LauncherLiquidGlassMetrics.searchHeight)
        XCTAssertLessThanOrEqual(window.frame.maxX, 0)
        XCTAssertLessThanOrEqual(window.frame.maxY, 0)
    }

    func testReduceTransparencyChangesMaterialWithoutChangingGeometry() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            let standard = controller.descriptor(
                for: preferences,
                reducedTransparency: false,
                increasedContrast: false
            )
            let reduced = controller.descriptor(
                for: preferences,
                reducedTransparency: true,
                increasedContrast: false
            )

            assertSameGeometry(standard, reduced, design: design)
            if design == .minimal {
                XCTAssertEqual(reduced.surface, .opaque)
                XCTAssertNotEqual(standard.surface, reduced.surface)
            } else {
                XCTAssertEqual(reduced.surface, .glass)
                XCTAssertEqual(standard.surface, reduced.surface)
            }
        }
    }

    func testDefaultLauncherDesignIsLiquidGlass() {
        let preferences = AppPreferences(defaults: makeDefaults())
        XCTAssertEqual(preferences.appearance.design, .liquidGlass)
    }

    func testAppearanceSanitizationClampsOriginToVisibleFrame() {
        var preferences = LauncherAppearancePreferences.defaults()
        preferences.originX = -1
        preferences.originY = -1
        preferences.sanitize()
        XCTAssertEqual(preferences.originX, 0)
        XCTAssertEqual(preferences.originY, 0)

        preferences.originX = 1.8
        preferences.originY = 0.8
        preferences.sanitize()
        XCTAssertEqual(preferences.originX, 1)
        XCTAssertEqual(preferences.originY, 0.8)

        preferences.originX = .nan
        preferences.originY = .infinity
        preferences.sanitize()
        XCTAssertEqual(preferences.originX, LauncherAppearancePreferences.defaultOriginX)
        XCTAssertEqual(preferences.originY, LauncherAppearancePreferences.defaultOriginY)
    }

    func testAppearanceLayoutComparisonIgnoresOrigin() {
        var moved = LauncherAppearancePreferences.defaults()
        moved.originX = 0.1
        moved.originY = 0.9
        XCTAssertTrue(moved.hasSameLayout(as: .defaults()))

        var restyled = moved
        restyled.design = .minimal
        XCTAssertFalse(moved.hasSameLayout(as: restyled))
    }

    func testAppDefaultsHideRecentSelectionsForAnEmptyQueryAndPersistOptIn() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.recentItemsEnabled)
        XCTAssertFalse(preferences.searchPreferences.recentItemsEnabled)

        preferences.recentItemsEnabled = true

        let optedIn = AppPreferences(defaults: defaults)
        XCTAssertTrue(optedIn.recentItemsEnabled)
        XCTAssertTrue(optedIn.searchPreferences.recentItemsEnabled)
    }

    func testWebSearchDefaultsToGoogleAndKeepsAnEarlierOptOut() {
        let defaults = makeDefaults()
        XCTAssertEqual(AppPreferences(defaults: defaults).webSearchEngine, .google)

        let optedOut = makeDefaults()
        optedOut.set(false, forKey: "search.webSearchFallbackEnabled")
        XCTAssertEqual(AppPreferences(defaults: optedOut).webSearchEngine, .off)

        let preferences = AppPreferences(defaults: defaults)
        preferences.webSearchEngine = .duckDuckGo
        XCTAssertEqual(AppPreferences(defaults: defaults).webSearchEngine, .duckDuckGo)
    }

    func testAppearancePersistsWithoutRestart() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        var changed = preferences.appearance
        changed.design = .minimal
        changed.mode = .dark
        changed.visibleResultCount = 10
        preferences.appearance = changed

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, changed)
    }

    func testRetiredAppearanceDesignFallsBackWithoutResettingOtherChoices() throws {
        let defaults = makeDefaults()
        let storedValue: [String: Any] = [
            "design": "retired-design",
            "mode": "dark",
            "visibleResultCount": 10,
            "screen": "pointer",
            "verticalPosition": 0.25,
            "showsSubtitles": false,
            "showsShortcuts": false,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: storedValue,
            format: .binary,
            options: 0
        )
        defaults.set(data, forKey: "appearance.configuration.v1")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.appearance.design, .liquidGlass)
        XCTAssertEqual(preferences.appearance.mode, .dark)
        XCTAssertEqual(preferences.appearance.visibleResultCount, 10)
        XCTAssertEqual(preferences.appearance.screen, .pointer)
        XCTAssertEqual(preferences.appearance.originX, LauncherAppearancePreferences.defaultOriginX)
        XCTAssertEqual(preferences.appearance.originY, 0.25)
        XCTAssertFalse(preferences.appearance.showsSubtitles)
        XCTAssertFalse(preferences.appearance.showsShortcuts)
    }

    func testAppearanceMigratesLegacyVerticalPositionToCenteredOrigin() throws {
        let defaults = makeDefaults()
        let storedValue: [String: Any] = [
            "design": "liquidGlass",
            "mode": "system",
            "visibleResultCount": 7,
            "screen": "active",
            "verticalPosition": 0.32,
            "showsSubtitles": true,
            "showsShortcuts": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: storedValue,
            format: .binary,
            options: 0
        )
        defaults.set(data, forKey: "appearance.configuration.v1")

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance.originX, 0.5)
        XCTAssertEqual(preferences.appearance.originY, 0.32)
    }

    func testAppearancePersistsNormalizedOriginWithoutWritingVerticalPosition() throws {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        var changed = preferences.appearance
        changed.originX = 0.2
        changed.originY = 0.65
        preferences.appearance = changed

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.appearance.originX, 0.2)
        XCTAssertEqual(reloaded.appearance.originY, 0.65)

        let stored = try XCTUnwrap(defaults.data(forKey: "appearance.configuration.v1"))
        let decoded = try PropertyListSerialization.propertyList(
            from: stored,
            options: [],
            format: nil
        ) as? [String: Any]
        XCTAssertNil(decoded?["verticalPosition"])
        XCTAssertEqual(decoded?["originX"] as? Double, 0.2)
        XCTAssertEqual(decoded?["originY"] as? Double, 0.65)
    }

    func testPositionedFrameUsesNormalizedOriginAndClampsToVisibleFrame() {
        let visible = NSRect(x: 100, y: 48, width: 1_440, height: 900)
        let width: CGFloat = 640
        let height: CGFloat = 58

        let centered = LauncherPanelGeometry.positionedFrame(
            in: visible,
            preferredWidth: width,
            height: height,
            originX: 0.5,
            originY: 0.18
        )
        XCTAssertEqual(centered.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(centered.maxY, visible.maxY - visible.height * 0.18, accuracy: 0.001)
        XCTAssertEqual(centered.width, width)
        XCTAssertEqual(centered.height, height)

        let right = LauncherPanelGeometry.positionedFrame(
            in: visible,
            preferredWidth: width,
            height: height,
            originX: 1,
            originY: 0
        )
        XCTAssertEqual(right.maxX, visible.maxX, accuracy: 0.001)
        XCTAssertEqual(right.maxY, visible.maxY, accuracy: 0.001)

        let overflowing = LauncherPanelGeometry.positionedFrame(
            in: visible,
            preferredWidth: width,
            height: height,
            originX: -0.4,
            originY: 1.4
        )
        XCTAssertGreaterThanOrEqual(overflowing.minX, visible.minX)
        XCTAssertLessThanOrEqual(overflowing.maxX, visible.maxX)
        XCTAssertGreaterThanOrEqual(overflowing.minY, visible.minY)
        XCTAssertLessThanOrEqual(overflowing.maxY, visible.maxY)

        let clamped = LauncherPanelGeometry.clamped(
            NSRect(x: visible.maxX + 80, y: visible.minY - 40, width: width, height: height),
            to: visible
        )
        XCTAssertEqual(clamped.maxX, visible.maxX, accuracy: 0.001)
        XCTAssertEqual(clamped.minY, visible.minY, accuracy: 0.001)

        let placed = LauncherPanelGeometry.positionedFrame(
            in: visible,
            preferredWidth: width,
            height: height,
            originX: 0.2,
            originY: 0.4
        )
        let origin = LauncherPanelGeometry.normalizedOrigin(for: placed, in: visible)
        XCTAssertEqual(origin.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0.4, accuracy: 0.001)
    }

    func testDraggableChromeExcludesSearchFieldAndResults() {
        // Chrome mouse-downs are handed to Window Server via performDrag(with:). The search
        // field and result rows must keep their own tracking, or typing and selection break.
        let searchField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        let results = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        let document = NSView(frame: results.bounds)
        results.documentView = document
        let chrome = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))

        XCTAssertTrue(
            LauncherPanelGeometry.isDraggableChrome(
                hitView: chrome,
                searchField: searchField,
                resultsView: results
            )
        )
        XCTAssertTrue(
            LauncherPanelGeometry.isDraggableChrome(
                hitView: nil,
                searchField: searchField,
                resultsView: results
            )
        )
        XCTAssertFalse(
            LauncherPanelGeometry.isDraggableChrome(
                hitView: searchField,
                searchField: searchField,
                resultsView: results
            )
        )
        XCTAssertFalse(
            LauncherPanelGeometry.isDraggableChrome(
                hitView: document,
                searchField: searchField,
                resultsView: results
            )
        )
    }

    func testLauncherPanelStaysMovableSoWindowServerCanDragIt() {
        let controller = LauncherPanelController()
        XCTAssertTrue(controller.visibilityIsolationWindow.isMovable)
        XCTAssertFalse(controller.visibilityIsolationWindow.isMovableByWindowBackground)
    }

    func testCalculatorPreferenceMigrationPreservesOldEnablement() throws {
        let defaults = makeDefaults()
        let oldValue = try PropertyListSerialization.data(
            fromPropertyList: ["enabled": false],
            format: .binary,
            options: 0
        )
        defaults.set(oldValue, forKey: "calculator.configuration.v1")

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.calculator.enabled)
        XCTAssertEqual(preferences.calculator.significantDigits, 12)
        XCTAssertFalse(preferences.calculator.usesGroupingSeparator)
    }

    func testSettingsSearchMatchesNavigationTerms() {
        XCTAssertEqual(PreferencesSection.privacy.title, "Permissions")
        XCTAssertTrue(PreferencesSection.appearance.matches(settingsQuery: "liquid"))
        XCTAssertTrue(PreferencesSection.general.matches(settingsQuery: "hotkey"))
        XCTAssertFalse(SettingsSearchItem.all.contains { $0.id == "menu-bar" })
        XCTAssertTrue(PreferencesSection.privacy.matches(settingsQuery: "automation"))
        XCTAssertFalse(PreferencesSection.about.matches(settingsQuery: "clipboard"))
    }

    func testSettingsToolbarTitleTracksSearchState() {
        XCTAssertEqual(
            SettingsToolbarPresentation.title(destinationTitle: "Appearance", searchQuery: ""),
            "Appearance"
        )
        XCTAssertEqual(
            SettingsToolbarPresentation.title(destinationTitle: "Appearance", searchQuery: "   \n"),
            "Appearance"
        )
        XCTAssertEqual(
            SettingsToolbarPresentation.title(destinationTitle: "Appearance", searchQuery: "preview"),
            "Search"
        )
    }

    func testSettingsShellUsesCherrySceneGeometry() {
        XCTAssertEqual(SettingsShellLayout.sidebarWidth, 209)
        XCTAssertEqual(SettingsShellLayout.contentWidth, 980)
        XCTAssertEqual(SettingsShellLayout.splitDividerWidth, 0)
        XCTAssertEqual(SettingsShellLayout.detailMinimumWidth, 771)
        XCTAssertEqual(SettingsShellLayout.searchFieldHeight, 36)
        XCTAssertEqual(SettingsShellLayout.searchFieldControlSize, .extraLarge)
        XCTAssertEqual(SettingsShellLayout.sidebarLabelFontSize, 14)
        XCTAssertEqual(
            SettingsShellLayout.searchFieldFontSize,
            SettingsShellLayout.sidebarLabelFontSize
        )
        XCTAssertEqual(SettingsShellLayout.searchHorizontalInset, 16)
        XCTAssertEqual(SettingsShellLayout.searchTopInset, 8)
        XCTAssertEqual(SettingsShellLayout.sidebarRowContentHeight, 28)
        XCTAssertEqual(SettingsShellLayout.sidebarIconCanvasSize, 18)
        XCTAssertEqual(SettingsShellLayout.sidebarIconTrailingPadding, 3)
        XCTAssertEqual(
            SettingsShellLayout.sidebarWidth
                + SettingsShellLayout.splitDividerWidth
                + SettingsShellLayout.detailMinimumWidth,
            SettingsShellLayout.contentWidth
        )
        XCTAssertEqual(SettingsWindowGeometry.initialContentSize.width, SettingsShellLayout.contentWidth)
        XCTAssertEqual(SettingsWindowGeometry.initialContentSize.height, 680)

        let detailItem = NSSplitViewItem(viewController: NSViewController())
        SettingsShellLayout.lockDetailWidth(detailItem)
        XCTAssertEqual(detailItem.minimumThickness, SettingsShellLayout.detailMinimumWidth)
        XCTAssertEqual(detailItem.maximumThickness, SettingsShellLayout.detailMinimumWidth)
    }

    func testLauncherDesignChooserShowsProductionMiniPreviews() {
        XCTAssertEqual(LauncherDesign.allCases, [.minimal, .liquidGlass])
        XCTAssertEqual(LauncherDesignChooserLayout.designs, [.liquidGlass, .minimal])
        XCTAssertEqual(
            LauncherDesignChooserLayout.designs.map(\.title),
            ["Liquid Glass", "Minimal"]
        )
        XCTAssertEqual(LauncherDesignChooserLayout.accessibilityLabel, "Launcher Design")
        XCTAssertEqual(
            LauncherDesignChooserLayout.pickerWidth,
            LauncherDesignChooserLayout.thumbnailWidth * 2
                + LauncherDesignChooserLayout.thumbnailSpacing,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LauncherDesignChooserLayout.neighbor(of: .liquidGlass, offset: 1),
            .minimal
        )
        XCTAssertNil(LauncherDesignChooserLayout.neighbor(of: .liquidGlass, offset: -1))
        XCTAssertEqual(
            LauncherDesignChooserLayout.neighbor(of: .minimal, offset: -1),
            .liquidGlass
        )
        XCTAssertNil(LauncherDesignChooserLayout.neighbor(of: .minimal, offset: 1))

        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.visibleResultCount = 3
        let descriptor = LauncherThemeController().descriptor(for: preferences)
        let productionSize = CGSize(
            width: descriptor.width,
            height: descriptor.panelHeight(
                resultCount: LauncherPreviewFixture.standard.results.count
            )
        )
        let fitted = LauncherDesignChooserLayout.fittedImageSize(for: productionSize)
        XCTAssertEqual(
            fitted.width / fitted.height,
            productionSize.width / productionSize.height,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LauncherDesignChooserLayout.thumbnailHeight,
            fitted.height + LauncherDesignChooserLayout.thumbnailPadding * 2,
            accuracy: 0.001
        )
        XCTAssertLessThan(fitted.width, productionSize.width)
        XCTAssertLessThan(fitted.height, productionSize.height)
    }

    func testLauncherDesignChooserKeepsSelectionChromeOnTheClickedCard() {
        XCTAssertTrue(LauncherDesignChooserLayout.disablesGroupFocusEffect)
        XCTAssertEqual(LauncherDesignChooserLayout.unselectedStrokeNSColor, .separatorColor)
        XCTAssertGreaterThan(
            LauncherDesignChooserLayout.selectedLineWidth,
            LauncherDesignChooserLayout.unselectedLineWidth
        )

        let liquid = LauncherDesignChooserLayout.selectionWellFrame(for: .liquidGlass)
        let minimal = LauncherDesignChooserLayout.selectionWellFrame(for: .minimal)
        XCTAssertEqual(liquid.size, LauncherDesignChooserLayout.selectionWellSize)
        XCTAssertEqual(minimal.size, LauncherDesignChooserLayout.selectionWellSize)
        XCTAssertEqual(liquid.width, LauncherDesignChooserLayout.thumbnailWidth)
        XCTAssertEqual(liquid.height, LauncherDesignChooserLayout.thumbnailHeight)
        XCTAssertFalse(
            liquid.intersects(minimal),
            "Selecting Liquid Glass must not cover the Minimal well"
        )
        XCTAssertLessThan(
            liquid.width,
            LauncherDesignChooserLayout.pickerWidth,
            "Selection chrome is one card, not the whole chooser"
        )
        XCTAssertLessThan(
            LauncherDesignChooserLayout.pickerWidth,
            SettingsShellLayout.detailMinimumWidth,
            "Chooser cards must not span the full Appearance row"
        )

        XCTAssertEqual(
            LauncherDesignChooserLayout.design(at: CGPoint(x: liquid.midX, y: liquid.midY)),
            .liquidGlass
        )
        XCTAssertEqual(
            LauncherDesignChooserLayout.design(at: CGPoint(x: minimal.midX, y: minimal.midY)),
            .minimal
        )
        let gap = CGPoint(
            x: liquid.maxX + LauncherDesignChooserLayout.thumbnailSpacing / 2,
            y: liquid.midY
        )
        XCTAssertNil(
            LauncherDesignChooserLayout.design(at: gap),
            "The space between cards is not a selection target"
        )
        XCTAssertNil(
            LauncherDesignChooserLayout.design(at: CGPoint(x: -40, y: liquid.midY)),
            "The Launcher Design title sits outside the card hit targets"
        )
        XCTAssertNil(
            LauncherDesignChooserLayout.design(
                at: CGPoint(x: LauncherDesignChooserLayout.pickerWidth + 12, y: liquid.midY)
            )
        )
    }

    func testSettingsSidebarUsesCherryStyleFilledSymbols() {
        let expectedSymbols: [PreferencesSection: String] = [
            .general: "gearshape.fill",
            .appearance: "paintbrush.fill",
            .search: "magnifyingglass",
            .files: "folder.fill",
            .calculator: "function",
            .clipboard: "clipboard.fill",
            .windows: "macwindow",
            .actions: "bolt.fill",
            .privacy: "hand.raised.fill",
            .about: "info.circle.fill",
        ]

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: PreferencesSection.allCases.map { ($0, $0.symbol) }),
            expectedSymbols
        )
        for symbol in expectedSymbols.values {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        }
    }

    func testSettingsSidebarTitlesFitOnOneLine() {
        let font = NSFont.systemFont(
            ofSize: SettingsShellLayout.sidebarLabelFontSize,
            weight: .medium
        )
        let widestTitle = PreferencesSection.allCases
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // Row insets (20), icon (20), icon spacing (9), and a comfortable trailing margin.
        let availableTitleWidth = SettingsShellLayout.sidebarWidth - 20 - 20 - 9 - 16

        XCTAssertLessThanOrEqual(widestTitle, availableTitleWidth)
    }

    func testSettingsSearchFieldCentersNativeControlInsideGlassSurface() {
        let surfaceBounds = NSRect(x: 0, y: 0, width: 184, height: 36)
        let frame = SettingsSearchFieldGeometry.nativeControlFrame(
            in: surfaceBounds,
            intrinsicHeight: 20
        )

        XCTAssertEqual(frame.width, surfaceBounds.width)
        XCTAssertEqual(frame.height, 20)
        XCTAssertEqual(frame.midY, surfaceBounds.midY, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 8, accuracy: 0.001)
    }

    func testSettingsNativeSearchFieldUsesSelectorHeightAndProportionalText() {
        let field = NSSearchField()

        SettingsNativeSearchFieldAppearance.apply(to: field)

        XCTAssertEqual(field.controlSize, .extraLarge)
        XCTAssertEqual(field.intrinsicContentSize.height, SettingsShellLayout.searchFieldHeight)
        XCTAssertEqual(field.font?.pointSize, SettingsShellLayout.searchFieldFontSize)
    }

    func testLauncherVisibilitySessionTemporarilySuppressesOnlyOtherVisibleWindows() {
        let launcher = BroccoliAppTestWindows.panel(
            size: NSSize(width: 100, height: 40),
            deferred: true
        )
        let settings = BroccoliAppTestWindows.window(
            size: NSSize(width: 200, height: 160),
            styleMask: .titled,
            deferred: true
        )
        let alreadyHidden = BroccoliAppTestWindows.window(
            size: NSSize(width: 100, height: 100),
            styleMask: .titled,
            deferred: true
        )
        defer {
            launcher.orderOut(nil)
            settings.orderOut(nil)
            alreadyHidden.orderOut(nil)
        }

        launcher.orderFront(nil)
        settings.orderFront(nil)
        XCTAssertTrue(launcher.isVisible)
        XCTAssertTrue(settings.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)

        let session = LauncherWindowVisibilitySession()
        session.suppress(
            windows: [settings, alreadyHidden, launcher],
            excluding: launcher
        )

        XCTAssertTrue(launcher.isVisible)
        XCTAssertFalse(settings.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)
        XCTAssertEqual(session.suppressedWindowCount, 1)

        session.restore()
        XCTAssertTrue(settings.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)
        XCTAssertEqual(session.suppressedWindowCount, 0)
    }

    func testLauncherVisibilitySessionKeepsTheForegroundBroccoliWindowVisible() {
        let launcher = BroccoliAppTestWindows.panel(
            size: NSSize(width: 100, height: 40),
            deferred: true
        )
        let foregroundSettings = BroccoliAppTestWindows.window(
            size: NSSize(width: 200, height: 160),
            styleMask: .titled,
            deferred: true
        )
        let backgroundBroccoliWindow = BroccoliAppTestWindows.window(
            size: NSSize(width: 180, height: 140),
            styleMask: .titled,
            deferred: true
        )
        defer {
            launcher.orderOut(nil)
            foregroundSettings.orderOut(nil)
            backgroundBroccoliWindow.orderOut(nil)
        }

        launcher.orderFront(nil)
        backgroundBroccoliWindow.orderFront(nil)
        foregroundSettings.orderFront(nil)

        let session = LauncherWindowVisibilitySession()
        session.suppress(
            windows: [foregroundSettings, backgroundBroccoliWindow, launcher],
            excluding: launcher,
            preserving: foregroundSettings
        )

        XCTAssertTrue(launcher.isVisible)
        XCTAssertTrue(foregroundSettings.isVisible)
        XCTAssertFalse(backgroundBroccoliWindow.isVisible)
        XCTAssertEqual(session.suppressedWindowCount, 1)

        session.restore()
        XCTAssertTrue(foregroundSettings.isVisible)
        XCTAssertTrue(backgroundBroccoliWindow.isVisible)
    }

    func testSettingsFindShortcutAllowsCapsLockButRejectsOtherModifiers() {
        XCTAssertTrue(SettingsKeyboardShortcut.isFind(
            modifierFlags: .command,
            charactersIgnoringModifiers: "f"
        ))
        XCTAssertTrue(SettingsKeyboardShortcut.isFind(
            modifierFlags: [.command, .capsLock],
            charactersIgnoringModifiers: "F"
        ))

        for flags: NSEvent.ModifierFlags in [
            [.command, .shift],
            [.command, .option],
            [.command, .control],
            [.command, .function],
        ] {
            XCTAssertFalse(SettingsKeyboardShortcut.isFind(
                modifierFlags: flags,
                charactersIgnoringModifiers: "f"
            ))
        }
        XCTAssertFalse(SettingsKeyboardShortcut.isFind(
            modifierFlags: .command,
            charactersIgnoringModifiers: "g"
        ))
    }

    func testIgnoredApplicationSelectionCopyPluralizesImmediateResult() {
        XCTAssertNil(IgnoredApplicationsCopy.invalidSelectionMessage(count: 0))
        XCTAssertEqual(
            IgnoredApplicationsCopy.invalidSelectionMessage(count: 1),
            "1 selected application did not provide a valid bundle identifier and was not added."
        )
        XCTAssertEqual(
            IgnoredApplicationsCopy.invalidSelectionMessage(count: 2),
            "2 selected applications did not provide a valid bundle identifier and were not added."
        )
    }

    func testClipboardConsentUsesConfiguredRetentionCopy() {
        XCTAssertEqual(ClipboardConsentCopy.retentionTitle(days: 1), "1-Day Retention")
        XCTAssertEqual(ClipboardConsentCopy.retentionTitle(days: 7), "7-Day Retention")
        XCTAssertEqual(ClipboardConsentCopy.retentionTitle(days: 30), "30-Day Retention")
    }

    func testSettingsShellKeepsToolbarHistoryAndSelectionSynchronized() {
        let shell = SettingsShellModel()

        XCTAssertEqual(shell.selection, .general)
        XCTAssertEqual(shell.destination, .section(.general))
        XCTAssertEqual(shell.toolbarTitle, "General")
        XCTAssertFalse(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)

        shell.navigate(to: .launcherPreview)
        XCTAssertEqual(shell.selection, .appearance)
        XCTAssertEqual(shell.destination, .launcherPreview)
        XCTAssertEqual(shell.toolbarTitle, "Launcher Preview")
        XCTAssertTrue(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)

        shell.goBack()
        XCTAssertEqual(shell.destination, .section(.general))
        XCTAssertFalse(shell.canGoBack)
        XCTAssertTrue(shell.canGoForward)

        shell.goForward()
        XCTAssertEqual(shell.destination, .launcherPreview)
        XCTAssertTrue(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)
    }

    func testSettingsSearchFieldKeepsTheCompleteFieldEditorTransparent() throws {
        let field = SpotlightSettingsNativeTextField(
            frame: NSRect(x: 0, y: 0, width: 180, height: 22)
        )
        field.isBezeled = false
        field.drawsBackground = false

        let window = BroccoliAppTestWindows.window(
            size: NSSize(width: 220, height: 80),
            styleMask: [.titled]
        )
        window.contentView?.addSubview(field)

        XCTAssertTrue(window.makeFirstResponder(field))
        field.makeCurrentEditorTransparent()

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertFalse(field.drawsBackground)
        XCTAssertFalse(editor.drawsBackground)

        if let clipView = editor.superview as? NSClipView {
            XCTAssertFalse(clipView.drawsBackground)
            if let scrollView = clipView.superview as? NSScrollView {
                XCTAssertFalse(scrollView.drawsBackground)
            }
        }
    }

    func testSettingsShellSearchOwnsToolbarTitleAndSectionReset() {
        let shell = SettingsShellModel()

        shell.searchQuery = "preview"
        XCTAssertEqual(shell.toolbarTitle, "Search")

        XCTAssertFalse(shell.isSearchPresented)
        shell.focusSearch()
        XCTAssertTrue(shell.isSearchPresented)

        shell.navigate(to: .launcherPreview)
        shell.selectSection(.files)
        XCTAssertEqual(shell.searchQuery, "")
        XCTAssertFalse(shell.isSearchPresented)
        XCTAssertEqual(shell.selection, .files)
        XCTAssertEqual(shell.destination, .section(.files))
        XCTAssertEqual(shell.toolbarTitle, "Files")
        XCTAssertFalse(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)
    }

    func testSettingsShellCanKeepCherrySearchWhileChangingVisibleSelection() {
        let shell = SettingsShellModel()
        shell.searchQuery = "clipboard"

        shell.selectSection(.clipboard, clearingSearch: false)

        XCTAssertEqual(shell.selection, .clipboard)
        XCTAssertEqual(shell.destination, .section(.clipboard))
        XCTAssertEqual(shell.searchQuery, "clipboard")
    }

    func testSettingsPaneRestorationRoundTripsAndRejectsUnknownValues() {
        let suite = "BroccoliSettingsPaneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SettingsPaneRestoration.restoredSection(from: defaults), .general)
        SettingsPaneRestoration.save(.windows, to: defaults)
        XCTAssertEqual(SettingsPaneRestoration.restoredSection(from: defaults), .windows)

        defaults.set("missing-pane", forKey: SettingsPaneRestoration.defaultsKey)
        XCTAssertEqual(SettingsPaneRestoration.restoredSection(from: defaults), .general)
    }

    func testSettingsShellStartsOnRestoredPaneAndPersistsNavigation() {
        let shell = SettingsShellModel(initialSection: .appearance)
        var persisted: [PreferencesSection] = []
        shell.selectionDidChange = { persisted.append($0) }

        XCTAssertEqual(shell.selection, .appearance)
        XCTAssertEqual(shell.destination, .section(.appearance))
        XCTAssertEqual(shell.toolbarTitle, "Appearance")

        shell.selectSection(.windows)
        shell.navigate(to: .automation)
        shell.goBack()

        XCTAssertEqual(persisted, [.windows, .privacy, .windows])
    }

    func testSettingsShellNativeSearchClearsSidebarSelectionAndCancelsInTwoStages() {
        let shell = SettingsShellModel()

        XCTAssertEqual(shell.sidebarSelection, .general)
        XCTAssertFalse(shell.cancelSearch())

        shell.searchQuery = "preview"
        XCTAssertNil(shell.sidebarSelection)
        XCTAssertEqual(shell.toolbarTitle, "Search")
        XCTAssertTrue(shell.cancelSearch())

        XCTAssertEqual(shell.searchQuery, "")
        XCTAssertEqual(shell.sidebarSelection, .general)
        XCTAssertEqual(shell.toolbarTitle, "General")
        XCTAssertFalse(shell.cancelSearch())
    }

    func testApplicationBundleDeclaresNormalSwiftUIAppMode() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot.appendingPathComponent("Support/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNil(info["LSUIElement"])
        XCTAssertEqual(info["CFBundleIconName"] as? String, "Broccoli")
    }

    func testApplicationPresentationModeTracksSettingsWithoutChangingDuringTermination() {
        var lifecycle = ApplicationLifecycleState()
        XCTAssertEqual(lifecycle.presentationMode, .background)

        lifecycle.beginSettingsPresentation()
        XCTAssertEqual(lifecycle.presentationMode, .settings)

        lifecycle.endSettingsPresentation()
        XCTAssertEqual(lifecycle.presentationMode, .background)

        lifecycle.beginSettingsPresentation()
        lifecycle.beginTermination()
        lifecycle.endSettingsPresentation()

        XCTAssertTrue(lifecycle.isTerminating)
        XCTAssertEqual(lifecycle.presentationMode, .settings)
    }

    func testApplicationIconResourceTracksTheResolvedSystemAppearance() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertEqual(
            ApplicationIconResource.name(for: light),
            "Broccoli-AppIcon-Light-1024"
        )
        XCTAssertEqual(
            ApplicationIconResource.name(for: dark),
            "Broccoli-AppIcon-Dark-1024"
        )
    }

    func testApplicationIconControllerRestoresAdaptiveBundleArtwork() {
        var appliedImages: [NSImage?] = []
        let controller = ApplicationIconController(imageSetter: { appliedImages.append($0) })
        controller.restoreBundleIcon()
        controller.restoreBundleIcon()
        XCTAssertEqual(appliedImages.count, 2)
        XCTAssertTrue(appliedImages.allSatisfy { $0 == nil },
            "Dock artwork must come from the adaptive bundle, without a flattened PNG override")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "BroccoliAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func assertSameGeometry(
        _ lhs: LauncherThemeDescriptor,
        _ rhs: LauncherThemeDescriptor,
        design: LauncherDesign,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.width, rhs.width, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.cornerRadius, rhs.cornerRadius, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchHeight, rhs.searchHeight, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.rowHeight, rhs.rowHeight, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchFontSize, rhs.searchFontSize, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchMetrics, rhs.searchMetrics, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchHorizontalInset, rhs.searchHorizontalInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchVerticalInset, rhs.searchVerticalInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.resultHorizontalInset, rhs.resultHorizontalInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.resultTopInset, rhs.resultTopInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.resultBottomInset, rhs.resultBottomInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.rowSpacing, rhs.rowSpacing, "\(design)", file: file, line: line)
    }

    private func assertColor(
        _ color: NSColor,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = color.usingColorSpace(.deviceRGB) else {
            return XCTFail("Expected an RGB color", file: file, line: line)
        }
        XCTAssertEqual(resolved.redComponent, red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.alphaComponent, alpha, accuracy: 0.001, file: file, line: line)
    }

    private func assertColor(
        _ color: NSColor,
        equals expectedColor: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = color.usingColorSpace(.deviceRGB),
              let expected = expectedColor.usingColorSpace(.deviceRGB) else {
            return XCTFail("Expected RGB colors", file: file, line: line)
        }
        XCTAssertEqual(
            resolved.redComponent,
            expected.redComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            resolved.greenComponent,
            expected.greenComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            resolved.blueComponent,
            expected.blueComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            resolved.alphaComponent,
            expected.alphaComponent,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }
}

private final class TableRows: NSObject, NSTableViewDataSource {
    let count: Int
    init(count: Int) { self.count = count }
    func numberOfRows(in tableView: NSTableView) -> Int { count }
}
