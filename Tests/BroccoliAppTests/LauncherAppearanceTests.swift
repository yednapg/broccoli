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

        XCTAssertEqual(minimal.width, 600)
        XCTAssertEqual(minimal.rowHeight, 40)
        XCTAssertEqual(minimal.cornerRadius, 5)
        XCTAssertEqual(minimal.searchHeight, 58)
        XCTAssertEqual(minimal.searchFontSize, 24)
        XCTAssertEqual(minimal.searchHorizontalInset, 20)
        XCTAssertEqual(minimal.searchVerticalInset, 13)
        XCTAssertEqual(minimal.searchHeight - minimal.searchVerticalInset * 2, 32)
        XCTAssertEqual(minimal.surface, .ultraThick)
        XCTAssertFalse(minimal.hasShadow)
        XCTAssertTrue(minimal.showsHeaderSeparator)
        XCTAssertEqual(minimal.resultSelectionCornerRadius, 6)
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
        XCTAssertEqual(classic.rowHeight, 52)
        XCTAssertEqual(classic.panelHeight(resultCount: 0), classic.searchHeight)
        XCTAssertEqual(classic.panelHeight(resultCount: 1), classic.searchHeight + classic.rowHeight)
        XCTAssertEqual(classic.panelHeight(resultCount: 20), classic.searchHeight + 7 * classic.rowHeight)
        XCTAssertEqual(LauncherMotion.panelMorphDuration, 0.18)
        XCTAssertEqual(LauncherMotion.resultRevealDuration, LauncherMotion.panelMorphDuration)
    }

    func testLiquidGlassFigmaContractScalesAsOneOpticalSystem() {
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
                36 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchHorizontalInset,
                25 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchVerticalInset,
                16 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolSize,
                30 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolPointSize,
                28 * LauncherLiquidGlassMetrics.scale,
                accuracy: 0.001
            )
            XCTAssertEqual(
                descriptor.searchMetrics.symbolVerticalOffset,
                LauncherLiquidGlassMetrics.searchSymbolVerticalOffset,
                accuracy: 0.001
            )
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
            25 * LauncherLiquidGlassMetrics.scale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            light.searchHorizontalInset + geometry.searchTextRect.minX,
            75 * LauncherLiquidGlassMetrics.scale
                + LauncherLiquidGlassMetrics.searchTextHorizontalOffset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            geometry.searchTextRect.minX - geometry.searchButtonRect.maxX,
            LauncherLiquidGlassMetrics.searchSymbolTextGap
                + LauncherLiquidGlassMetrics.searchTextHorizontalOffset,
            accuracy: 0.001
        )
        XCTAssertEqual(light.searchMetrics.textVerticalCompensation, 0)
        XCTAssertEqual(geometry.searchButtonRect.midY, geometry.bounds.midY, accuracy: 0.001)
        XCTAssertEqual(geometry.searchTextRect.midY, geometry.bounds.midY, accuracy: 0.001)
        XCTAssertLessThan(geometry.searchTextRect.minY, geometry.searchTextRect.maxY)
        XCTAssertGreaterThanOrEqual(geometry.searchTextRect.minY, 0)
        XCTAssertLessThanOrEqual(geometry.searchTextRect.maxY, fieldHeight)
        XCTAssertEqual(light.searchMetrics.symbolDrawingScale, 1.27)
        XCTAssertEqual(light.searchMetrics.symbolDrawingVerticalScale, 1.27)
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
            XCTAssertEqual(descriptor.width, 600)
            XCTAssertEqual(descriptor.cornerRadius, 5)
            XCTAssertEqual(descriptor.searchHeight, 58)
            XCTAssertEqual(descriptor.searchFontSize, 24)
            XCTAssertEqual(descriptor.searchHorizontalInset, 20)
            XCTAssertEqual(descriptor.searchVerticalInset, 13)
            XCTAssertEqual(descriptor.searchHeight - descriptor.searchVerticalInset * 2, 32)
            XCTAssertEqual(
                descriptor.searchHeight - descriptor.searchControlVerticalInset * 2,
                40
            )
            XCTAssertFalse(descriptor.hasShadow)
            XCTAssertTrue(descriptor.showsHeaderSeparator)
            XCTAssertEqual(descriptor.searchMetrics.fontSize, 24)
            XCTAssertEqual(descriptor.searchMetrics.symbolSize, 24)
            XCTAssertEqual(descriptor.searchMetrics.symbolPointSize, 22)
            XCTAssertEqual(descriptor.searchMetrics.symbolTextGap, 15)
            XCTAssertEqual(descriptor.searchMetrics.symbolVerticalOffset, 5)
            XCTAssertEqual(descriptor.searchMetrics.textLeadingCompensation, 0)
            XCTAssertEqual(descriptor.searchMetrics.textVerticalCompensation, 3)
            XCTAssertEqual(descriptor.searchMetrics.textRectVerticalExpansion, 3)
            XCTAssertEqual(descriptor.searchMetrics.textBaselineOffset, 3)
            XCTAssertEqual(descriptor.searchMetrics.insertionPointHeight, 22)
            XCTAssertEqual(descriptor.searchMetrics.emptyInsertionPointLeadingGap, 4)
            XCTAssertEqual(descriptor.searchMetrics.symbolDrawingScale, 1.08)
            XCTAssertEqual(descriptor.searchMetrics.symbolDrawingVerticalScale, 1.10)
            XCTAssertEqual(descriptor.rowHeight, 40)
            XCTAssertEqual(descriptor.resultHorizontalInset, 7)
            XCTAssertEqual(descriptor.resultTopInset, 3)
            XCTAssertEqual(descriptor.resultBottomInset, 6)
            XCTAssertEqual(descriptor.rowSpacing, 1)
            XCTAssertEqual(
                descriptor.searchMetrics.symbolDrawingOffset,
                NSPoint(x: -0.5, y: -2)
            )
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
        XCTAssertEqual(LauncherMinimalMetrics.separatorTopInset, 57)
        XCTAssertEqual(LauncherMinimalMetrics.separatorLeadingInset, 16)
        XCTAssertEqual(LauncherMinimalMetrics.separatorTrailingInset, 16)
        XCTAssertEqual(LauncherMinimalMetrics.separatorThickness, 1)
        XCTAssertEqual(LauncherMinimalMetrics.resultIconSize, 28)
        XCTAssertEqual(LauncherMinimalMetrics.resultTitleFontSize, 15)
        XCTAssertEqual(LauncherMinimalMetrics.resultSubtitleFontSize, 11)
        XCTAssertEqual(LauncherMinimalMetrics.resultShortcutFontSize, 12)
        XCTAssertEqual(
            light.width
                - LauncherMinimalMetrics.separatorLeadingInset
                - LauncherMinimalMetrics.separatorTrailingInset,
            568
        )

        let searchGeometry = LauncherSearchGeometry(
            bounds: NSRect(x: 0, y: 0, width: 560, height: 40),
            metrics: light.searchMetrics
        )
        XCTAssertEqual(light.searchControlVerticalInset, 9)
        XCTAssertEqual(light.searchControlTopInset, 6)
        XCTAssertEqual(searchGeometry.searchButtonRect, NSRect(x: 0, y: 13, width: 24, height: 24))
        XCTAssertEqual(searchGeometry.searchTextRect.minX, 39)
        XCTAssertEqual(searchGeometry.searchTextRect.minY, 7)
        XCTAssertEqual(searchGeometry.searchTextRect.height, 32)
        XCTAssertEqual(
            light.searchHorizontalInset + searchGeometry.searchButtonRect.minX,
            20,
            "The compact magnifier begins 20 points from the shell's leading edge"
        )
        XCTAssertEqual(
            light.searchControlTopInset
                + 40
                - searchGeometry.searchButtonRect.maxY,
            9,
            "The compact magnifier is vertically balanced inside the header"
        )
        XCTAssertEqual(
            light.searchHorizontalInset
                + searchGeometry.searchButtonRect.maxX
                + light.searchMetrics.symbolTextGap,
            59,
            "The compact query follows the magnifier without an oversized gap"
        )
        XCTAssertEqual(
            light.searchVerticalInset,
            13,
            "The compact search control keeps an even vertical shell inset"
        )
        XCTAssertEqual(
            light.searchHorizontalInset + searchGeometry.searchTextRect.minX,
            59,
            "The native cell and compact optical grid share one query origin"
        )
        XCTAssertEqual(
            light.searchControlTopInset + 40 - searchGeometry.searchTextRect.maxY,
            7,
            "The native editor stays vertically balanced with the compact magnifier"
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
        field.alignFieldEditorToSearchTextBounds()

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        XCTAssertEqual(clipView.frame, field.searchTextBounds.integral)
        XCTAssertEqual(editor.frame.origin, .zero)
        XCTAssertEqual(editor.frame.size, field.searchTextBounds.integral.size)
        XCTAssertGreaterThan(clipView.frame.minX, field.searchButtonBounds.minX)
        XCTAssertEqual(field.searchButtonBounds.size, NSSize(width: 34, height: 34))
        XCTAssertEqual(
            field.searchButtonBounds.midY - field.bounds.midY,
            LauncherSearchGeometry.symbolVerticalOffset
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
        field.placeholderString = "Search Broccoli"
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        XCTAssertTrue(window.makeFirstResponder(field))
        field.alignFieldEditorToSearchTextBounds()
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
        XCTAssertEqual(
            opticalGap,
            23.5 * LauncherLiquidGlassMetrics.scale,
            accuracy: 3,
            "The rendered magnifier and placeholder must read as one compact Spotlight control"
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
        field.placeholderString = "Search Broccoli"
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        XCTAssertTrue(window.makeFirstResponder(field))
        field.alignFieldEditorToSearchTextBounds()

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
        field.alignFieldEditorToSearchTextBounds()
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.needsDisplay = true
        let queryInk = try renderedTextInk()

        XCTAssertEqual(queryInk.minX, placeholderInk.minX, accuracy: 1)
        XCTAssertEqual(queryInk.minY, placeholderInk.minY, accuracy: 1)
    }

    func testMinimalSearchRenderedInkMatchesCompactOpticalPlacement() throws {
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
        field.placeholderAttributedString = LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: .figmaMinimal,
            color: NSColor.black
        )
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        field.alignFieldEditorToSearchTextBounds()
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
        XCTAssertEqual(iconInk.minX, 2, accuracy: 0.75)
        XCTAssertEqual(iconInk.minY, 15, accuracy: 0.75)
        XCTAssertEqual(iconInk.width, 21, accuracy: 1)
        XCTAssertEqual(iconInk.height, 22, accuracy: 1)

        let textInk = try XCTUnwrap(
            darkInkBounds(in: bitmap, constrainedTo: field.searchTextBounds)
        )
        XCTAssertEqual(textInk.minY, 7.5, accuracy: 0.75)
        XCTAssertEqual(textInk.maxY, 29.5, accuracy: 0.75)
        XCTAssertGreaterThanOrEqual(
            field.searchTextBounds.maxY - textInk.maxY,
            1,
            "The Minimal title rectangle must leave visible clearance above every glyph"
        )
    }

    func testLiveMinimalPanelMovesTheWholeTextLineWithoutMovingTheIcon() throws {
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
        (field.currentEditor() as? NSTextView)?.insertionPointColor = .clear
        field.placeholderAttributedString = LauncherNativeSearchFieldStyle.placeholder(
            "Search Broccoli",
            metrics: field.searchMetrics,
            color: NSColor.black
        )
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

        XCTAssertEqual(
            field.placeholderAttributedString?.attribute(
                .baselineOffset,
                at: 0,
                effectiveRange: nil
            ) as? CGFloat,
            3
        )
        XCTAssertEqual(fieldRect.minY, 12, accuracy: 0.25)
        // The panel content is flipped while NSSearchField is not. These are final rendered
        // panel coordinates: both text bounds and ink are two points below the prior build.
        XCTAssertEqual(textRect.minY, 13, accuracy: 0.25)
        XCTAssertEqual(textInk.minY, 13.5, accuracy: 0.75)
        XCTAssertEqual(
            iconInk.minY,
            21,
            accuracy: 0.75,
            "The counter-shift must keep the magnifier at its verified screen coordinate"
        )
        XCTAssertGreaterThan(textInk.minY, textRect.minY)
        XCTAssertLessThan(textInk.maxY, textRect.maxY)
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

    func testSettingsSearchFieldUsesLargeNativeSystemGeometry() {
        let searchField = SettingsSearchField(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        SettingsSearchFieldStyle.apply(to: searchField)

        XCTAssertEqual(SettingsSearchFieldStyle.height, 30)
        XCTAssertEqual(SettingsSearchFieldStyle.cornerRadius, 15)
        XCTAssertEqual(SettingsSearchFieldStyle.horizontalInset, 10)
        XCTAssertEqual(SettingsSearchFieldStyle.topInset, 8)
        XCTAssertEqual(SettingsSearchFieldStyle.bottomInset, 8)
        XCTAssertEqual(searchField.controlSize, .large)
        XCTAssertTrue(searchField.isBezeled)
        XCTAssertTrue(searchField.isEditable)
        XCTAssertTrue(searchField.isSelectable)
        XCTAssertEqual(searchField.focusRingType, .default)
        XCTAssertEqual(searchField.font?.pointSize, 13)
        guard let cell = searchField.cell as? NSSearchFieldCell else {
            return XCTFail("NSSearchField must keep its native search cell")
        }
        let searchButtonRect = cell.searchButtonRect(forBounds: searchField.bounds)
        let searchTextRect = cell.searchTextRect(forBounds: searchField.bounds)
        XCTAssertGreaterThan(searchButtonRect.width, 0)
        XCTAssertGreaterThan(searchTextRect.width, 0)
        XCTAssertGreaterThanOrEqual(searchTextRect.minX, searchButtonRect.maxX - 2)
        XCTAssertLessThanOrEqual(searchTextRect.maxX, searchField.bounds.maxX)
        XCTAssertEqual(searchField.accessibilitySubrole(), .searchField)
        XCTAssertTrue(searchField.sendsSearchStringImmediately)
        XCTAssertFalse(searchField.sendsWholeSearchString)
    }

    @MainActor
    func testSettingsSearchContainerOwnsFullHeightSurfaceAndNativeField() {
        let container = SettingsSearchFieldContainerView(
            frame: NSRect(x: 0, y: 0, width: 204, height: SettingsSearchFieldStyle.height)
        )

        XCTAssertEqual(container.searchField.controlSize, .large)
        XCTAssertTrue(container.searchField.isBezeled)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertEqual(container.intrinsicContentSize.height, SettingsSearchFieldStyle.height)
        container.setFocusAppearance(focused: false)
        XCTAssertEqual(container.surfaceBorderWidth, 0)
        container.setFocusAppearance(focused: true)
        XCTAssertEqual(container.surfaceBorderWidth, 0)
    }

    func testSettingsShellUsesFixedNativeSplitGeometry() {
        XCTAssertEqual(SettingsShellLayout.sidebarWidth, 224)
        XCTAssertEqual(SettingsShellLayout.contentWidth, 800)
        XCTAssertEqual(SettingsShellLayout.detailMinimumWidth, 575)
        XCTAssertEqual(
            SettingsShellLayout.sidebarWidth
                + SettingsShellLayout.splitDividerWidth
                + SettingsShellLayout.detailMinimumWidth,
            SettingsShellLayout.contentWidth
        )
        XCTAssertEqual(SettingsWindowGeometry.initialContentSize.width, SettingsShellLayout.contentWidth)
        XCTAssertEqual(SettingsWindowGeometry.minimumContentSize.width, SettingsShellLayout.contentWidth)
        XCTAssertEqual(SettingsWindowGeometry.maximumContentSize.width, SettingsShellLayout.contentWidth)
        XCTAssertEqual(SettingsWindowGeometry.minimumContentSize.height, 650)
        XCTAssertEqual(SettingsWindowGeometry.maximumContentSize.height, 650)
        XCTAssertTrue(SettingsWindowGeometry.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(SettingsWindowGeometry.collectionBehavior.contains(.fullScreenDisallowsTiling))
        XCTAssertFalse(SettingsWindowGeometry.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(SettingsWindowGeometry.styleMask.contains(.titled))
        XCTAssertTrue(SettingsWindowGeometry.styleMask.contains(.closable))
        XCTAssertTrue(SettingsWindowGeometry.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(SettingsWindowGeometry.styleMask.contains(.miniaturizable))
        XCTAssertFalse(SettingsWindowGeometry.styleMask.contains(.resizable))

        let detailItem = NSSplitViewItem(viewController: NSViewController())
        SettingsShellLayout.lockDetailWidth(detailItem)
        XCTAssertEqual(detailItem.minimumThickness, SettingsShellLayout.detailMinimumWidth)
        XCTAssertEqual(detailItem.maximumThickness, SettingsShellLayout.detailMinimumWidth)
    }

    func testSettingsSidebarTitlesFitOnOneLine() {
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let widestTitle = PreferencesSection.allCases
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // Row insets (20), icon (20), icon spacing (9), and a comfortable trailing margin.
        let availableTitleWidth = SettingsShellLayout.sidebarWidth - 20 - 20 - 9 - 16

        XCTAssertLessThanOrEqual(widestTitle, availableTitleWidth)
    }

    func testSettingsDividerIsAQuietAdaptiveHairline() {
        XCTAssertEqual(SettingsDividerStyle.thickness, 1)

        let dark = SettingsDividerStyle.color(for: NSAppearance(named: .darkAqua)!)
        let light = SettingsDividerStyle.color(for: NSAppearance(named: .aqua)!)
        XCTAssertLessThanOrEqual(dark.alphaComponent, 0.12)
        XCTAssertLessThanOrEqual(light.alphaComponent, 0.10)
        XCTAssertGreaterThan(dark.whiteComponent, light.whiteComponent)
    }

    func testSettingsWindowGeometryKeepsAStablePaneSizedFrame() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowGeometry.initialContentSize),
            styleMask: SettingsWindowGeometry.styleMask,
            backing: .buffered,
            defer: false
        )

        for proposedFrameSize in [
            NSSize(width: 520, height: 700),
            NSSize(width: 1_400, height: 900),
        ] {
            let constrainedFrameSize = SettingsWindowGeometry.constrainedFrameSize(
                proposedFrameSize,
                for: window
            )
            let constrainedContentSize = window.contentRect(
                forFrameRect: NSRect(origin: .zero, size: constrainedFrameSize)
            ).size

            XCTAssertEqual(constrainedContentSize, SettingsWindowGeometry.initialContentSize)
        }
    }

    func testSettingsWindowGeometryRejectsWorkspaceStyleResizing() {
        XCTAssertEqual(
            SettingsWindowGeometry.constrainedContentSize(NSSize(width: 1_400, height: 725)),
            SettingsWindowGeometry.initialContentSize
        )
        XCTAssertEqual(
            SettingsWindowGeometry.constrainedContentSize(NSSize(width: 520, height: 320)),
            SettingsWindowGeometry.minimumContentSize
        )
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

    func testSettingsShellSearchOwnsToolbarTitleAndSectionReset() {
        let shell = SettingsShellModel()
        let initialFocusRequest = shell.searchFocusRequest

        shell.searchQuery = "preview"
        XCTAssertEqual(shell.toolbarTitle, "Search")

        shell.focusSearch()
        XCTAssertEqual(shell.searchFocusRequest, initialFocusRequest + 1)

        shell.navigate(to: .launcherPreview)
        shell.selectSection(.files)
        XCTAssertEqual(shell.searchQuery, "")
        XCTAssertEqual(shell.selection, .files)
        XCTAssertEqual(shell.destination, .section(.files))
        XCTAssertEqual(shell.toolbarTitle, "Files")
        XCTAssertFalse(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)
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

    func testApplicationMenuClosesSettingsWithoutQuittingBackgroundLauncher() {
        _ = NSApplication.shared
        let menu = BroccoliApplicationMenu.make(target: NSObject())
        let applicationMenu = menu.items.first?.submenu
        let close = applicationMenu?.items.first(where: { $0.title == "Close Settings" })
        let settings = applicationMenu?.items.first(where: { $0.title == "Settings…" })

        XCTAssertNil(applicationMenu?.items.first(where: { $0.title == "Quit Broccoli" }))
        XCTAssertEqual(close?.keyEquivalent, "q")
        XCTAssertEqual(close?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(settings?.keyEquivalent, ",")
        XCTAssertEqual(settings?.keyEquivalentModifierMask, .command)
    }

    func testSettingsCloseDoesNotRestoreAccessoryPolicyDuringTermination() {
        var lifecycle = ApplicationLifecycleState()
        XCTAssertTrue(lifecycle.shouldReturnToAccessoryAfterSettingsClose)

        lifecycle.beginTermination()

        XCTAssertTrue(lifecycle.isTerminating)
        XCTAssertFalse(lifecycle.shouldReturnToAccessoryAfterSettingsClose)
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
