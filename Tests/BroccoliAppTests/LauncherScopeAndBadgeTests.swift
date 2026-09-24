import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherScopeAndBadgeTests: XCTestCase {
    func testScopeTokenCentersItsTitleAndSitsAheadOfTheMagnifier() throws {
        _ = NSApplication.shared
        for metrics in [LauncherSearchMetrics.figmaLiquidGlass, .figmaMinimal] {
            let field = LauncherNativeSearchField(frame: NSRect(x: 0, y: 0, width: 600, height: 40))
            LauncherNativeSearchFieldStyle.apply(to: field, metrics: metrics, iconColor: .labelColor)
            field.layoutSubtreeIfNeeded()
            let plainTextBounds = field.searchTextBounds
            let plainButtonBounds = field.searchButtonBounds

            for title in ["Files", "Clipboard"] {
                field.setScope(title)
                field.layoutSubtreeIfNeeded()
                let token = try XCTUnwrap(field.scopeTokenFrame)
                let tokenView = try XCTUnwrap(
                    field.subviews.compactMap { $0 as? LauncherSearchScopeTokenView }.first
                )
                tokenView.layoutSubtreeIfNeeded()

                XCTAssertEqual(token.minX, field.bounds.minX, accuracy: 1,
                               "The token keeps the field's leading edge")
                XCTAssertEqual(
                    field.searchButtonBounds.minX,
                    token.maxX + LauncherSearchGeometry.leadingAccessoryTextGap,
                    accuracy: 1,
                    "The magnifier follows the token"
                )
                XCTAssertGreaterThan(field.searchButtonBounds.minX, plainButtonBounds.minX)
                XCTAssertEqual(token.midY, field.searchTextBounds.midY, accuracy: 0.5)
                XCTAssertEqual(
                    field.searchTextBounds.minX - field.searchButtonBounds.maxX,
                    plainTextBounds.minX - plainButtonBounds.maxX,
                    accuracy: 1,
                    "The query keeps its gap after the magnifier"
                )
                XCTAssertEqual(tokenView.titleFrame.midY, tokenView.bounds.midY, accuracy: 0.5,
                               "\(title) must be vertically centered in its pill")
                XCTAssertEqual(tokenView.titleFrame.midX, tokenView.bounds.midX, accuracy: 0.5)
                XCTAssertEqual(
                    tokenView.bounds.width,
                    tokenView.titleFrame.width + LauncherSearchScopeTokenView.horizontalPadding * 2,
                    accuracy: 1,
                    "The pill follows its title's width"
                )
                let cell = try XCTUnwrap(field.cell as? LauncherNativeSearchFieldCell)
                XCTAssertEqual(
                    cell.searchTextRect(forBounds: field.bounds).minX,
                    field.searchTextBounds.minX,
                    accuracy: 1,
                    "The field editor and the placeholder share one text rect"
                )
            }

            field.setScope(nil)
            field.layoutSubtreeIfNeeded()
            XCTAssertNil(field.scopeTokenFrame)
            XCTAssertEqual(field.searchTextBounds, plainTextBounds)
            XCTAssertEqual(field.searchButtonBounds, plainButtonBounds)
        }
    }

    func testFileSearchModeShowsTheScopeWithoutAnyResultRow() {
        _ = NSApplication.shared
        for design in [LauncherDesign.liquidGlass, .minimal] {
            let controller = LauncherPanelController()
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            controller.applyAppearance(preferences, force: true)

            controller.setMode(.fileSearch(query: ""))
            controller.apply([])

            XCTAssertEqual(controller.searchPlaceholder, "Search names and paths")
            XCTAssertEqual(controller.searchAccessibilityLabel, "Search Files")
            XCTAssertTrue(controller.listedResultIDs.isEmpty)
            XCTAssertEqual(
                controller.currentPanelHeight,
                LauncherThemeController().descriptor(for: preferences).searchHeight
            )

            controller.setMode(.main)
            XCTAssertEqual(controller.searchAccessibilityLabel, "Search Broccoli")
        }
    }

    func testFileSearchWithNothingToSelectStaysASearchBand() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        controller.applyAppearance(preferences, force: true)
        controller.setMode(.fileSearch(query: "ninjnjs"), initialQuery: "ninjnjs")
        let noFiles = RankedResult(
            entry: SearchEntry(
                id: "status:no-files",
                kind: .status,
                title: "No files found",
                iconKey: "status:no-files",
                target: .none
            ),
            score: 0
        )

        controller.apply([noFiles])

        XCTAssertTrue(controller.listedResultIDs.isEmpty)
        XCTAssertFalse(controller.isResultViewportVisible)
        XCTAssertEqual(
            controller.currentPanelHeight,
            LauncherThemeController().descriptor(for: preferences).searchHeight
        )
        let separator = controller.visibilityIsolationWindow.contentView.flatMap { content in
            descendants(content).compactMap { $0 as? LauncherHeaderSeparatorView }.first
        }
        XCTAssertEqual(separator?.isHidden, true, "An empty file search has no result divider")
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    func testOnlySettingsPaneRowsCarryTheSystemSettingsBadge() throws {
        _ = NSApplication.shared
        let badge = NSImage(size: NSSize(width: 20, height: 20))
        let pane = SearchEntry(
            id: "setting:test.printers",
            kind: .systemSetting,
            title: "Printers & Scanners",
            iconKey: "setting:test.printers",
            target: .setting(route: nil)
        )
        let application = SearchEntry(
            id: IconCache.systemSettingsBadgeIconKey,
            kind: .application,
            title: "System Settings",
            iconKey: IconCache.systemSettingsBadgeIconKey,
            target: .application(path: IconCache.systemSettingsBadgeIconKey, bundleIdentifier: nil)
        )
        for (design, expectedSize) in [
            (LauncherDesign.liquidGlass, LauncherLiquidGlassMetrics.resultSettingsBadgeSize),
            (.minimal, LauncherMinimalMetrics.resultSettingsBadgeSize),
        ] {
            let theme = LauncherThemeController().descriptor(
                for: .defaults(design: design),
                reducedTransparency: false,
                increasedContrast: false
            )
            let row = ResultRowView()
            row.frame = NSRect(x: 0, y: 0, width: 540, height: theme.rowHeight)
            let imageViews = row.subviews.compactMap { $0 as? NSImageView }
            let iconView = try XCTUnwrap(imageViews.first)
            let badgeView = try XCTUnwrap(imageViews.dropFirst().first)

            for selected in [false, true] {
                row.configure(result: RankedResult(entry: pane, score: 1), icon: badge,
                              settingsBadge: badge, confirmation: false, row: 0,
                              selected: selected, theme: theme)
                row.layoutSubtreeIfNeeded()
                XCTAssertTrue(row.isShowingSettingsBadge)
                XCTAssertEqual(badgeView.frame.size, NSSize(width: expectedSize, height: expectedSize))
                XCTAssertEqual(badgeView.frame.maxX, iconView.frame.maxX, accuracy: 0.5)
                XCTAssertEqual(badgeView.frame.minY, iconView.frame.minY, accuracy: 0.5)
            }

            row.configure(result: RankedResult(entry: application, score: 1), icon: badge,
                          settingsBadge: badge, confirmation: false, row: 0,
                          selected: false, theme: theme)
            XCTAssertFalse(row.isShowingSettingsBadge, "The System Settings app itself is not a pane")

            row.configure(result: RankedResult(entry: pane, score: 1), icon: badge,
                          settingsBadge: nil, confirmation: false, row: 0,
                          selected: false, theme: theme)
            XCTAssertFalse(row.isShowingSettingsBadge)
        }
    }

    func testSettingsBadgeWaitsForThePaneArtwork() {
        _ = NSApplication.shared
        let cache = IconCache(startsNativeIconResolution: false)
        let pane = SearchEntry(
            id: "setting:test.unresolved",
            kind: .systemSetting,
            title: "Unresolved Pane",
            iconKey: "setting:test.unresolved",
            target: .setting(route: nil)
        )
        let pending = cache.image(for: pane)

        XCTAssertNil(cache.systemSettingsBadge(for: pending),
                     "A badge must never sit on an empty icon slot")
        XCTAssertNotNil(cache.systemSettingsBadge(for: NSImage(size: NSSize(width: 40, height: 40))))
    }

    func testGoogleTileMatchesSystemAppIconGeometryWithAProportionateMark() throws {
        _ = NSApplication.shared
        let logo = IconCache(startsNativeIconResolution: false)
            .image(for: try XCTUnwrap(WebSearch.googleEntry(for: "broccoli")))
        let systemIcon = NSWorkspace.shared.icon(forFile: IconCache.systemSettingsBadgeIconKey)
        let pixels = 512

        func render(_ image: NSImage) throws -> NSBitmapImageRep {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = NSSize(width: 64, height: 64)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            try XCTUnwrap(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance {
                image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            }
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        func tileGeometry(_ bitmap: NSBitmapImageRep) -> (minX: Int, width: Int, cornerInset: Int) {
            let row = (0..<pixels).filter { bitmap.colorAt(x: $0, y: pixels / 2)!.alphaComponent > 0.5 }
            var diagonal = 0
            while diagonal < pixels / 2,
                  bitmap.colorAt(x: diagonal, y: diagonal)!.alphaComponent <= 0.5 { diagonal += 1 }
            let minX = row.first ?? 0
            return (minX, (row.last ?? 0) - minX + 1, diagonal - minX)
        }

        let google = try render(logo)
        let tile = tileGeometry(google)
        let system = tileGeometry(try render(systemIcon))
        XCTAssertEqual(tile.width, system.width, accuracy: 2, "Same artwork size as app icons")
        XCTAssertEqual(tile.cornerInset, system.cornerInset, accuracy: 2, "Same corner curvature")

        let markColumns = (0..<pixels).filter { x in
            let color = google.colorAt(x: x, y: pixels / 2)!.usingColorSpace(.deviceRGB)!
            return color.saturationComponent > 0.4
        }
        let markWidth = Double((markColumns.last ?? 0) - (markColumns.first ?? 0) + 1)
        XCTAssertEqual(markWidth / Double(tile.width), 0.6, accuracy: 0.04,
                       "The G fills the tile like marks in system app icons")
    }

    func testGoogleResultIsAnAppearanceAdaptiveIconTile() throws {
        _ = NSApplication.shared
        let cache = IconCache(startsNativeIconResolution: false)
        let entry = try XCTUnwrap(WebSearch.googleEntry(for: "broccoli"))
        let logo = cache.image(for: entry)

        XCTAssertTrue(logo.isValid)
        XCTAssertFalse(logo.isTemplate, "Selection must not flatten the logo into a silhouette")
        XCTAssertEqual(logo.accessibilityDescription, "Google")

        func tileColor(_ name: NSAppearance.Name) throws -> NSColor {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                logo.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            }
            NSGraphicsContext.restoreGraphicsState()
            // Inside the tile, below the “G” and clear of its rounded corners.
            return try XCTUnwrap(bitmap.colorAt(x: 32, y: 10))
        }
        let light = try tileColor(.aqua)
        let dark = try tileColor(.darkAqua)
        let corner = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(logo.tiffRepresentation)))

        XCTAssertGreaterThan(light.brightnessComponent, 0.95, "Light appearance uses a white tile")
        XCTAssertLessThan(dark.brightnessComponent, 0.3, "Dark appearance uses a dark tile")
        XCTAssertEqual(light.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(corner.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01,
                       "The tile keeps the application-icon margin")
    }
}
