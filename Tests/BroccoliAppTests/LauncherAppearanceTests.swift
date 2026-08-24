import AppKit
import ServiceManagement
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
                    let documentHeight = CGFloat(displayedRows)
                        * (descriptor.rowHeight + descriptor.rowSpacing)
                    let expectedHeight = descriptor.searchHeight
                        + (displayedRows > 0 ? descriptor.resultTopInset : 0)
                        + documentHeight
                        + (displayedRows > 0 ? descriptor.resultBottomInset : 0)

                    XCTAssertEqual(
                        descriptor.panelHeight(resultCount: resultCount),
                        expectedHeight,
                        accuracy: 0.001,
                        "\(design) must size exactly to \(displayedRows) visible rows"
                    )
                    XCTAssertEqual(
                        descriptor.resultsViewportHeight(resultCount: resultCount),
                        descriptor.resultsDocumentHeight(resultCount: resultCount),
                        accuracy: 0.001,
                        "\(design) must not leave an empty table viewport"
                    )
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
                    "\(design) AppKit row geometry must match the fixed viewport"
                )
                XCTAssertEqual(
                    actualDocumentHeight,
                    descriptor.resultsViewportHeight(resultCount: count),
                    accuracy: 0.001
                )
            }
        }
    }

    func testLockedThemeGeometry() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()
        let minimal = controller.descriptor(for: .defaults(design: .minimal))
        let glass = controller.descriptor(for: .defaults(design: .liquidGlass))
        let classic = controller.descriptor(for: .defaults(design: .yosemiteClassic))

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
            LauncherLiquidGlassSurfaceView.expandedCornerRadius,
            LauncherLiquidGlassMetrics.expandedCornerRadius,
            accuracy: 0.001
        )
        XCTAssertEqual(glass.rowHeight, 56)
        XCTAssertEqual(glass.rowSpacing, 0)
        XCTAssertEqual(glass.cornerRadius, 29)
        XCTAssertFalse(glass.hasShadow)
        XCTAssertTrue(glass.showsHeaderSeparator)
        XCTAssertEqual(glass.resultSelectionCornerRadius, 12)
        XCTAssertEqual(glass.resultTableStyle, .fullWidth)
        XCTAssertEqual(classic.width, 820)
        XCTAssertEqual(classic.searchFontSize, 26)
        XCTAssertEqual(classic.searchHorizontalInset, 16)
        XCTAssertEqual(classic.searchMetrics.symbolSize, 26)
        XCTAssertEqual(classic.searchMetrics.symbolPointSize, 26)
        XCTAssertEqual(classic.searchMetrics.symbolTextGap, 16)
        XCTAssertEqual(classic.searchMetrics.textLeadingCompensation, -10)
        XCTAssertEqual(classic.rowHeight, 52)
        XCTAssertEqual(classic.panelHeight(resultCount: 0), classic.searchHeight)
        XCTAssertEqual(classic.panelHeight(resultCount: 1), classic.searchHeight + classic.rowHeight)
        XCTAssertEqual(classic.panelHeight(resultCount: 20), classic.searchHeight + 7 * classic.rowHeight)
        for descriptor in [minimal, glass, classic] {
            XCTAssertEqual(
                descriptor.searchMetrics.emptyInsertionPointLeadingGap,
                LauncherSearchMetrics.sharedEmptyInsertionPointLeadingGap
            )
        }
        XCTAssertEqual(LauncherMotion.panelMorphDuration, 0.18)
        XCTAssertEqual(LauncherMotion.resultRevealDuration, LauncherMotion.panelMorphDuration)
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
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: descriptor.width,
                    height: descriptor.searchHeight
                ),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
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

        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaWidth, 900)
        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaSearchHeight, 75)
        XCTAssertEqual(LauncherLiquidGlassMetrics.figmaExpandedCornerRadius, 34)
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
            XCTAssertEqual(
                descriptor.searchMetrics.insertionPointHeight ?? -1,
                LauncherLiquidGlassMetrics.insertionPointHeight,
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
                0.2882782,
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
            light.surfaceCornerRadius(panelHeight: light.searchHeight),
            LauncherLiquidGlassMetrics.compactCornerRadius,
            accuracy: 0.001
        )
        XCTAssertEqual(
            light.surfaceCornerRadius(panelHeight: light.panelHeight(resultCount: 3)),
            LauncherLiquidGlassMetrics.expandedCornerRadius,
            accuracy: 0.001
        )

        assertColor(light.searchTextColor, red: 0, green: 0, blue: 0, alpha: 1)
        assertColor(light.searchIconColor, red: 0, green: 0, blue: 0, alpha: 0.85)
        assertColor(dark.searchTextColor, red: 1, green: 1, blue: 1, alpha: 1)
        assertColor(dark.searchIconColor, red: 1, green: 1, blue: 1, alpha: 0.85)
        guard let lightGlassTint = light.glassTintColor else {
            return XCTFail("Light Liquid Glass must provide its white readability tint")
        }
        assertColor(
            lightGlassTint,
            red: 1,
            green: 1,
            blue: 1,
            alpha: LauncherLiquidGlassMetrics.lightGlassTintAlpha
        )
        XCTAssertEqual(LauncherLiquidGlassMetrics.lightGlassTintAlpha, 0.30)
        XCTAssertNil(dark.glassTintColor)
        assertColor(light.headerSeparatorColor, red: 0, green: 0, blue: 0, alpha: 0.25)
        assertColor(dark.headerSeparatorColor, red: 1, green: 1, blue: 1, alpha: 0.25)
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
            XCTAssertEqual(descriptor.searchMetrics.insertionPointHeight, 24)
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
        XCTAssertEqual(LauncherMinimalMetrics.resultActionIconOpticalSize, 22)
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 58),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
            "The magnifier must not re-vibrantize when Liquid Glass expands"
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
            let editor = LauncherSearchFieldEditor(frame: fieldBounds)
            editor.insertionPointHeight = metrics.insertionPointHeight
            editor.emptyInsertionPointLeadingGap = metrics.emptyInsertionPointLeadingGap
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
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fieldSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fieldSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fieldSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
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
        let editor = try XCTUnwrap(field.currentEditor() as? LauncherSearchFieldEditor)
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
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fieldSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
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

    func testLiveLiquidPanelInstallsTheShortenedCustomCaretEditor() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .light
        controller.applyAppearance(preferences, force: true)
        controller.setMode(.main)
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
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
        let editor = try XCTUnwrap(field.currentEditor() as? LauncherSearchFieldEditor)
        XCTAssertEqual(LauncherLiquidGlassMetrics.insertionPointHeight, 28)
        XCTAssertEqual(
            editor.insertionPointHeight ?? -1,
            LauncherLiquidGlassMetrics.insertionPointHeight,
            accuracy: 0.001
        )
        XCTAssertFalse(editor.shouldDrawInsertionPoint)
        let indicatorFrame = try XCTUnwrap(editor.launcherInsertionIndicatorFrame)
        XCTAssertEqual(
            indicatorFrame.height,
            LauncherLiquidGlassMetrics.insertionPointHeight,
            accuracy: 1
        )
        let indicatorFrameInField = field.convert(indicatorFrame, from: editor)
        XCTAssertEqual(
            indicatorFrameInField.midX,
            field.searchTextBounds.minX - field.searchMetrics.emptyInsertionPointLeadingGap,
            accuracy: 0.75
        )
    }

    func testRewritingMinimalQueryRepaintsTheWholeEditorAtTheFinalCaretPosition() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .minimal), force: true)
        controller.setMode(.main)
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
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
        let editor = try XCTUnwrap(field.currentEditor() as? LauncherSearchFieldEditor)
        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        editor.string = "long query"
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.updateLauncherInsertionIndicator()
        let longQueryCaret = try XCTUnwrap(editor.launcherInsertionIndicatorFrame)

        editor.string = "q"
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        field.needsDisplay = false
        editor.needsDisplay = false
        clipView.needsDisplay = false
        field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        let rewrittenCaret = try XCTUnwrap(editor.launcherInsertionIndicatorFrame)

        XCTAssertTrue(field.needsDisplay)
        XCTAssertTrue(editor.needsDisplay)
        XCTAssertTrue(clipView.needsDisplay)
        XCTAssertLessThan(rewrittenCaret.minX, longQueryCaret.minX)
        XCTAssertEqual(
            editor.subviews.filter { $0 is NSTextInsertionIndicator }.count,
            1,
            "A rewrite must leave only the final caret visible"
        )
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

    func testLiquidSearchMagnifierPixelsRemainFrozenAcrossExpansion() throws {
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

    func testLiquidMaterialStaysStableAcrossExpansionAndMatchesAppearance() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Native Liquid Glass requires macOS 26")
        }
        let surface = LauncherLiquidGlassSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 58),
            interactive: false
        )
        let glass = try XCTUnwrap(
            surface.subviews.compactMap { $0 as? NSGlassEffectView }.first
        )

        surface.configure(isDark: false, tintColor: nil)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(glass.style, .clear)

        surface.frame.size.height = 450
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            glass.style,
            .clear,
            "Showing results must not replace transparent light glass with regular material"
        )

        surface.configure(isDark: true, tintColor: nil)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            glass.style,
            .regular,
            "Dark mode must use Spotlight's denser regular-glass material"
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
            verticalPosition: descriptor.verticalPosition
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

    func testLiquidCompositingOutsetPreservesTheVisualSurfaceFrame() {
        let visualFrame = NSRect(x: 280, y: 640, width: 640, height: 58)
        let outset = LauncherLiquidGlassMetrics.liveCompositingOutset
        let outerFrame = LauncherPanelGeometry.addingCompositingOutset(
            outset,
            to: visualFrame
        )

        XCTAssertEqual(outerFrame.midX, visualFrame.midX, accuracy: 0.001)
        XCTAssertEqual(outerFrame.midY, visualFrame.midY, accuracy: 0.001)
        XCTAssertEqual(outerFrame.width, visualFrame.width + outset * 2, accuracy: 0.001)
        XCTAssertEqual(outerFrame.height, visualFrame.height + outset * 2, accuracy: 0.001)
        XCTAssertEqual(
            LauncherPanelGeometry.removingCompositingOutset(outset, from: outerFrame),
            visualFrame
        )
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
            XCTAssertEqual(reduced.surface, .opaque)
            XCTAssertNotEqual(standard.surface, reduced.surface)
        }
    }

    func testFreshAndExistingInstallDesignMigration() {
        let freshDefaults = makeDefaults()
        let fresh = AppPreferences(defaults: freshDefaults)
        XCTAssertEqual(fresh.appearance.design, .liquidGlass)

        let existingDefaults = makeDefaults()
        existingDefaults.set(true, forKey: "onboarding.completed")
        let existing = AppPreferences(defaults: existingDefaults)
        XCTAssertEqual(existing.appearance.design, .minimal)
    }

    func testAppearanceSanitizationMatchesSettingsVerticalPositionRange() {
        var preferences = LauncherAppearancePreferences.defaults()
        preferences.verticalPosition = -1
        preferences.sanitize()
        XCTAssertEqual(preferences.verticalPosition, 0.05)

        preferences.verticalPosition = 0.8
        preferences.sanitize()
        XCTAssertEqual(preferences.verticalPosition, 0.5)
    }

    func testAppDefaultsShowRecentSelectionsForAnEmptyQuery() {
        let preferences = AppPreferences(defaults: makeDefaults())
        XCTAssertTrue(preferences.recentItemsEnabled)
        XCTAssertTrue(preferences.searchPreferences.recentItemsEnabled)
    }

    func testMenuBarVisibilityDefaultsOnAndPersistsUserChoice() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.menuBarIconEnabled)

        preferences.menuBarIconEnabled = false

        XCTAssertFalse(AppPreferences(defaults: defaults).menuBarIconEnabled)
    }

    func testOnboardingNeutralizesUnavailableLaunchAtLogin() {
        let unavailable = LaunchAtLoginAvailability(status: .notFound)
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertFalse(unavailable.isAvailable)

        let notRegistered = LaunchAtLoginAvailability(status: .notRegistered)
        XCTAssertFalse(notRegistered.isEnabled)
        XCTAssertTrue(notRegistered.isAvailable)

        let enabled = LaunchAtLoginAvailability(status: .enabled)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.isAvailable)

        let requiresApproval = LaunchAtLoginAvailability(status: .requiresApproval)
        XCTAssertFalse(requiresApproval.isEnabled)
        XCTAssertTrue(requiresApproval.isAvailable)
    }

    func testAppearancePersistsWithoutRestart() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        var changed = preferences.appearance
        changed.design = .yosemiteClassic
        changed.mode = .dark
        changed.visibleResultCount = 10
        preferences.appearance = changed

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, changed)
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
        let menuBar = SettingsSearchItem.all.first { $0.id == "menu-bar" }
        XCTAssertEqual(menuBar?.destination, .section(.general))
        XCTAssertTrue(menuBar?.matches("menu bar") == true)
        XCTAssertTrue(menuBar?.matches("hide") == true)
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
        XCTAssertEqual(SettingsShellLayout.searchFieldHeight, 34)
        XCTAssertEqual(SettingsShellLayout.searchHorizontalInset, 16)
        XCTAssertEqual(SettingsShellLayout.searchTopInset, 8)
        XCTAssertEqual(SettingsShellLayout.sidebarRowContentHeight, 26)
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
            .updates: "arrow.triangle.2.circlepath",
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
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let widestTitle = PreferencesSection.allCases
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // Row insets (20), icon (20), icon spacing (9), and a comfortable trailing margin.
        let availableTitleWidth = SettingsShellLayout.sidebarWidth - 20 - 20 - 9 - 16

        XCTAssertLessThanOrEqual(widestTitle, availableTitleWidth)
    }

    func testSettingsSearchFieldCentersNativeControlInsideGlassSurface() {
        let surfaceBounds = NSRect(x: 0, y: 0, width: 184, height: 34)
        let frame = SettingsSearchFieldGeometry.nativeControlFrame(
            in: surfaceBounds,
            intrinsicHeight: 19
        )

        XCTAssertEqual(frame.width, surfaceBounds.width)
        XCTAssertEqual(frame.height, 19)
        XCTAssertEqual(frame.midY, surfaceBounds.midY, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 7.5, accuracy: 0.001)
    }

    func testLauncherVisibilitySessionTemporarilySuppressesOnlyOtherVisibleWindows() {
        let launcher = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        let settings = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        let alreadyHidden = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .titled,
            backing: .buffered,
            defer: true
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
        let launcher = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        let foregroundSettings = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        let backgroundBroccoliWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 140),
            styleMask: .titled,
            backing: .buffered,
            defer: true
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
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
        XCTAssertEqual(lhs.previewWidth, rhs.previewWidth, "\(design)", file: file, line: line)
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
