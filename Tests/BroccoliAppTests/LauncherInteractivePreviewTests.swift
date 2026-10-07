import AppKit
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherInteractivePreviewTests: XCTestCase {
    func testFixtureQueryFilteringIsDeterministicAndLocal() {
        let fixture = LauncherPreviewFixture.standard

        XCTAssertEqual(
            LauncherPreviewInteraction.results(matching: "sharing", in: fixture)
                .map(\.entry.id),
            ["preview:application:screen-sharing"]
        )
        XCTAssertEqual(
            LauncherPreviewInteraction.results(matching: "saver", in: fixture)
                .map(\.entry.id),
            [
                "setting:com.apple.ScreenSaver-Settings.extension",
                "action:screensaver.start",
            ]
        )
        XCTAssertEqual(
            LauncherPreviewInteraction.results(matching: "", in: fixture).map(\.entry.id),
            fixture.results.map(\.entry.id)
        )
    }

    func testInteractiveSurfaceUsesProductionRowsAndStopsSelectionAtBounds() throws {
        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.visibleResultCount = LauncherPreviewFixture.standard.results.count
        let descriptor = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let content = LauncherPreviewContentView(
            descriptor: descriptor,
            fixture: .standard,
            iconProvider: LauncherPreviewIconProvider(),
            interactive: true
        )
        content.prepareForCapture()

        XCTAssertEqual(content.interactiveQuery, "screen")
        XCTAssertEqual(content.displayedResultIDs.count, 3)
        XCTAssertEqual(
            content.tableDocumentFrame.height,
            descriptor.resultsDocumentHeight(resultCount: 3),
            accuracy: 0.001
        )
        XCTAssertTrue(
            try XCTUnwrap(content.tableView(NSTableView(), viewFor: nil, row: 0))
                is ResultRowView,
            "Settings preview must reuse the production launcher row"
        )
        XCTAssertTrue(content.moveInteractiveSelection(up: false))
        XCTAssertTrue(content.moveInteractiveSelection(up: false))
        XCTAssertFalse(content.moveInteractiveSelection(up: false))
        XCTAssertEqual(content.selectedResultID, "action:screensaver.start")
        XCTAssertTrue(content.moveInteractiveSelection(up: true))
        XCTAssertEqual(
            content.selectedResultID,
            "setting:com.apple.ScreenSaver-Settings.extension"
        )
    }

    func testInteractiveReturnIsConsumedWithoutAnExecutionInterface() {
        _ = NSApplication.shared
        let preferences = LauncherAppearancePreferences.defaults(design: .minimal)
        let descriptor = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let content = LauncherPreviewContentView(
            descriptor: descriptor,
            fixture: .standard,
            iconProvider: LauncherPreviewIconProvider(),
            interactive: true
        )
        let selectedBeforeReturn = content.selectedResultID

        XCTAssertTrue(content.control(
            NSTextField(),
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(content.selectedResultID, selectedBeforeReturn)
    }

    func testMinimalSelectionUsesTheFullSquareTableRowBackground() throws {
        _ = NSApplication.shared
        let descriptor = LauncherThemeController().descriptor(
            for: .defaults(design: .minimal),
            reducedTransparency: false,
            increasedContrast: false
        )
        let content = LauncherPreviewContentView(
            descriptor: descriptor,
            fixture: .standard,
            iconProvider: LauncherPreviewIconProvider(),
            interactive: true
        )
        content.prepareForCapture()

        func tableView(in view: NSView) -> NSTableView? {
            if let tableView = view as? NSTableView { return tableView }
            for child in view.subviews {
                if let tableView = tableView(in: child) { return tableView }
            }
            return nil
        }

        func headerSeparator(in view: NSView) -> LauncherHeaderSeparatorView? {
            if let separator = view as? LauncherHeaderSeparatorView { return separator }
            for child in view.subviews {
                if let separator = headerSeparator(in: child) { return separator }
            }
            return nil
        }

        func minimalSurface(in view: NSView) -> LauncherMinimalMaterialSurfaceView? {
            if let surface = view as? LauncherMinimalMaterialSurfaceView { return surface }
            for child in view.subviews {
                if let surface = minimalSurface(in: child) { return surface }
            }
            return nil
        }

        let tableView = try XCTUnwrap(tableView(in: content))
        let separator = try XCTUnwrap(headerSeparator(in: content))
        let minimalSurface = try XCTUnwrap(minimalSurface(in: content))
        let rowView = try XCTUnwrap(tableView.rowView(atRow: 0, makeIfNecessary: true))
        let cellView = try XCTUnwrap(
            tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? ResultRowView
        )
        content.layoutSubtreeIfNeeded()

        let labels = cellView.subviews.compactMap { $0 as? NSTextField }
        XCTAssertGreaterThanOrEqual(labels.count, 3)
        let titleAndSubtitleFrame = labels[0].frame.union(labels[1].frame)
        let letterCenter = cellView.bounds.midY - LauncherMinimalMetrics.resultTextOpticalLift
        XCTAssertEqual(
            titleAndSubtitleFrame.midY,
            letterCenter,
            accuracy: 0.5,
            "The title and subtitle share one group, shifted so the drawn letters meet the row center"
        )
        XCTAssertEqual(labels[2].frame.midY, letterCenter, accuracy: 0.5)
        let iconView = try XCTUnwrap(cellView.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertEqual(iconView.frame.midY, cellView.bounds.midY, accuracy: 0.5)

        XCTAssertEqual(rowView.frame.minX, tableView.bounds.minX, accuracy: 0.001)
        XCTAssertEqual(rowView.frame.width, tableView.bounds.width, accuracy: 0.001)
        XCTAssertEqual(rowView.layer?.cornerRadius, 0)
        XCTAssertEqual(rowView.layer?.borderWidth, 0)
        XCTAssertGreaterThan(NSColor(cgColor: try XCTUnwrap(rowView.layer?.backgroundColor))?.alphaComponent ?? 0, 0.9)
        XCTAssertEqual(
            NSColor(cgColor: try XCTUnwrap(cellView.layer?.backgroundColor))?.alphaComponent,
            0
        )
        XCTAssertTrue(separator.isHidden, "The first blue result replaces the header divider")

        XCTAssertTrue(content.moveInteractiveSelection(up: false))
        XCTAssertFalse(separator.isHidden, "The divider returns after selection leaves row zero")

        XCTAssertTrue(content.moveInteractiveSelection(up: false))
        content.layoutSubtreeIfNeeded()
        let rowRects = (0..<tableView.numberOfRows).map(tableView.rect(ofRow:))
        XCTAssertFalse(rowRects.isEmpty)
        for rowRect in rowRects {
            XCTAssertEqual(rowRect.height, descriptor.rowHeight, accuracy: 0.001)
        }
        XCTAssertEqual(
            try XCTUnwrap(rowRects.last).maxY,
            tableView.bounds.maxY,
            accuracy: 0.001,
            "The final regular-height result must reach the shell bottom"
        )
        XCTAssertFalse(minimalSurface.layer?.masksToBounds == true)
        let minimalRimWidth = LauncherMinimalMetrics.rimWidth(
            forBackingScale: minimalSurface.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
        )
        XCTAssertEqual(
            minimalSurface.materialClip.layer?.cornerRadius ?? 0,
            LauncherMinimalMetrics.cornerRadius - LauncherMinimalMetrics.fillInset(
                forBackingScale: minimalSurface.window?.backingScaleFactor
                    ?? NSScreen.main?.backingScaleFactor
                    ?? 2
            ),
            accuracy: 0.001
        )
        XCTAssertTrue(minimalSurface.materialClip.layer?.masksToBounds == true)
        XCTAssertEqual(minimalSurface.rim.layer?.borderWidth ?? 0, 0, accuracy: 0.001)
        XCTAssertTrue(minimalSurface.rim.isHidden)
        XCTAssertFalse(minimalSurface.rim.layer?.masksToBounds == true)
        XCTAssertEqual(
            minimalSurface.rim.frame,
            minimalSurface.bounds.insetBy(dx: minimalRimWidth / 2, dy: minimalRimWidth / 2)
        )
    }

    func testInteractiveQueryUpdatesVisibleFixtureWithoutExternalSearch() {
        _ = NSApplication.shared
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let descriptor = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let content = LauncherPreviewContentView(
            descriptor: descriptor,
            fixture: .standard,
            iconProvider: LauncherPreviewIconProvider(),
            interactive: true
        )

        content.setInteractiveQuery("sharing")
        XCTAssertEqual(content.displayedResultIDs, ["preview:application:screen-sharing"])
        XCTAssertEqual(content.selectedResultID, "preview:application:screen-sharing")
        content.setInteractiveQuery("no fixture match")
        XCTAssertTrue(content.displayedResultIDs.isEmpty)
        XCTAssertNil(content.selectedResultID)
    }

    func testLiquidInteractivePreviewUsesCorrectedNativeSearchEditorGeometry() throws {
        _ = NSApplication.shared
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let descriptor = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: false,
            increasedContrast: false
        )
        let content = LauncherPreviewContentView(
            descriptor: descriptor,
            fixture: .standard,
            iconProvider: LauncherPreviewIconProvider(),
            interactive: true
        )
        let field = try XCTUnwrap(content.previewSearchField as? LauncherNativeSearchField)
        let window = BroccoliAppTestWindows.window(size: content.bounds.size)
        window.contentView = content
        BroccoliAppTestWindows.placeOffscreen(window)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        XCTAssertTrue(window.makeFirstResponder(field))
        content.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification))

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        let textBounds = field.searchTextBounds.integral
        XCTAssertEqual(editor.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(
            editor.textContainerInset.width,
            field.searchMetrics.emptyInsertionPointLeadingGap,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(clipView.frame.minX, field.searchButtonBounds.maxX)
        XCTAssertLessThanOrEqual(clipView.frame.minX, textBounds.minX)
        XCTAssertEqual(clipView.frame.minY, textBounds.minY)
        XCTAssertEqual(clipView.frame.maxX, textBounds.maxX, accuracy: 1)
        XCTAssertEqual(clipView.frame.height, textBounds.height)
    }

    func testEveryLauncherDesignUsesOneNativeSearchControlAndOpticalSpacing() throws {
        _ = NSApplication.shared

        for design in LauncherDesign.allCases {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            let descriptor = LauncherThemeController().descriptor(
                for: preferences,
                reducedTransparency: false,
                increasedContrast: false
            )
            let content = LauncherPreviewContentView(
                descriptor: descriptor,
                fixture: .standard,
                iconProvider: LauncherPreviewIconProvider(),
                interactive: true
            )
            let field = try XCTUnwrap(
                content.previewSearchField as? LauncherNativeSearchField,
                design.title
            )

            XCTAssertEqual(field.searchMetrics.fontSize, descriptor.searchFontSize, design.title)
            let expectedTextInset = field.searchMetrics.symbolSize > 0
                ? field.searchMetrics.symbolTextGap + field.searchMetrics.textLeadingCompensation
                : field.searchMetrics.queryLeadingInset
            XCTAssertEqual(
                field.searchTextBounds.minX - field.searchButtonBounds.maxX,
                expectedTextInset,
                accuracy: 0.51,
                design.title
            )
            XCTAssertEqual(
                field.searchButtonBounds.midY,
                field.bounds.midY,
                accuracy: 0.51,
                design.title
            )
            XCTAssertEqual(
                field.searchTextBounds.midY,
                field.bounds.midY,
                accuracy: 0.51,
                design.title
            )
        }
    }

    func testAppearanceStageFitsEveryCompleteLauncherPreviewWithoutCropping() throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer()

        for design in LauncherDesign.allCases {
            let configuration = renderer.interactiveConfiguration(
                for: .defaults(design: design)
            )
            let host = LauncherInteractivePreviewHostView(
                configuration: configuration,
                interactive: false,
                fillsWidth: false
            )
            host.frame = NSRect(x: 0, y: 0, width: 424, height: 160)
            host.layoutSubtreeIfNeeded()

            let contentFrame = try XCTUnwrap(host.hostedContentFrame)
            XCTAssertGreaterThanOrEqual(contentFrame.minX, -0.001, design.title)
            XCTAssertGreaterThanOrEqual(contentFrame.minY, -0.001, design.title)
            XCTAssertLessThanOrEqual(contentFrame.maxX, host.bounds.maxX + 0.001, design.title)
            XCTAssertLessThanOrEqual(contentFrame.maxY, host.bounds.maxY + 0.001, design.title)
            XCTAssertEqual(
                contentFrame.width / contentFrame.height,
                host.hostedNativeSize.width / host.hostedNativeSize.height,
                accuracy: 0.001,
                design.title
            )
        }
    }
}
