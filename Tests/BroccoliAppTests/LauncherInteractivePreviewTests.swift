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
            ["setting:screen-saver", "action:screensaver.start"]
        )
        XCTAssertEqual(
            LauncherPreviewInteraction.results(matching: "", in: fixture).map(\.entry.id),
            fixture.results.map(\.entry.id)
        )
    }

    func testInteractiveSurfaceUsesProductionRowsAndStopsSelectionAtBounds() throws {
        _ = NSApplication.shared
        var preferences = LauncherAppearancePreferences.defaults(design: .yosemiteClassic)
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
        XCTAssertEqual(content.selectedResultID, "setting:screen-saver")
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
        let window = NSWindow(
            contentRect: content.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        XCTAssertTrue(window.makeFirstResponder(field))
        content.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification))

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        XCTAssertEqual(clipView.frame, field.searchTextBounds.integral)
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
