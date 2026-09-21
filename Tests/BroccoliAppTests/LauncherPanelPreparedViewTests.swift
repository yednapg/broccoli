import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherPanelPreparedViewTests: XCTestCase {
    func testOpeningDoesNotInheritAnEnclosingAnimation() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .liquidGlass))
        let window = controller.visibilityIsolationWindow
        let probe = ResizeContextProbe()
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                probe.resizeAnimationStates.append(NSAnimationContext.current.allowsImplicitAnimation)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            controller.dismiss(notify: false)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1
            context.allowsImplicitAnimation = true
            controller.showForAutomatedTests()
            XCTAssertTrue(context.allowsImplicitAnimation)
        }
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertFalse(probe.resizeAnimationStates.isEmpty)
        XCTAssertTrue(probe.resizeAnimationStates.allSatisfy { !$0 })
    }

    func testResultResizeDoesNotInheritAnEnclosingAnimation() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.setMode(.main, initialQuery: "fixture")
        let root = try XCTUnwrap(controller.visibilityIsolationWindow.contentView)
        let probe = ResizeContextProbe(frame: root.bounds)
        probe.autoresizingMask = [.width, .height]
        root.addSubview(probe)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1
            context.allowsImplicitAnimation = true
            controller.apply(LauncherPreviewFixture.standard.results)
            XCTAssertTrue(context.allowsImplicitAnimation, "The launcher must preserve its caller's context")
        }
        XCTAssertFalse(probe.resizeAnimationStates.isEmpty)
        XCTAssertTrue(probe.resizeAnimationStates.allSatisfy { !$0 },
                      "A native glass resize must not inherit an unrelated view animation")
    }

    func testVisibleResultTransitionsKeepTheirSizeAfterAppKitUpdates() async throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let noResults = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .notExpression, hasVisibleQuery: true, limit: 7)
        let fixtures = LauncherPreviewFixture.standard.results
        for mode in [LauncherAppearanceMode.light, .dark] {
            preferences.mode = mode
            controller.applyAppearance(preferences)
            let theme = LauncherThemeController().descriptor(for: preferences)
            controller.showForAutomatedTests()
            let window = controller.visibilityIsolationWindow
            let top = window.frame.maxY
            controller.setMode(.main, initialQuery: "fixture")
            for _ in 0..<4 {
                for results in [fixtures, noResults, [], Array(fixtures.prefix(1))] {
                    controller.apply(results)
                    let expectedHeight = theme.panelHeight(resultCount: results.count)
                    XCTAssertEqual(window.frame.height, expectedHeight)
                    // Give AppKit a later turn to expose deferred fitting-size changes.
                    try await Task.sleep(for: .milliseconds(10))
                    window.contentView?.layoutSubtreeIfNeeded()
                    XCTAssertEqual(window.frame.height, expectedHeight)
                    XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
                    let root = try XCTUnwrap(window.contentView)
                    let surface = try XCTUnwrap(root.subviews.first as? LauncherLiquidGlassSurfaceView)
                    XCTAssertEqual(surface.frame, root.bounds)
                    XCTAssertEqual(root.frame.size, window.frame.size)
                    XCTAssertTrue(root.layer?.masksToBounds == true)
                    XCTAssertEqual(root.layer?.cornerRadius, theme.cornerRadius)
                    XCTAssertTrue(root.layer?.animationKeys()?.isEmpty ?? true,
                                  "The window clip must not lag behind the resized glass")
                }
            }
            controller.dismiss(notify: false)
        }
    }

    func testMaximumResultRowsArePrebuiltAndStableAcrossReloads() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var appearance = LauncherAppearancePreferences.defaults(design: .minimal)
        appearance.visibleResultCount = 10
        controller.applyAppearance(appearance, force: true)
        let fixtures = (0..<12).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .status,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 0
            )
        }
        controller.apply(fixtures)

        let table = NSTableView()
        XCTAssertEqual(controller.preparedResultRowCount, LauncherSearchLimits.resultSetCap)
        XCTAssertEqual(controller.numberOfRows(in: table), 12)
        XCTAssertEqual(controller.listedResultIDs.count, 12)

        let firstPass = try (0..<12).map { row in
            try XCTUnwrap(controller.tableView(table, viewFor: nil, row: row))
        }
        let secondPass = try (0..<12).map { row in
            try XCTUnwrap(controller.tableView(table, viewFor: nil, row: row))
        }
        XCTAssertEqual(Set(firstPass.map(ObjectIdentifier.init)).count, 12)
        for row in 0..<12 {
            XCTAssertTrue(firstPass[row] === secondPass[row])
        }
        XCTAssertNil(controller.tableView(table, viewFor: nil, row: 12))
    }

    func testApplyRetainsMatchesBeyondTheVisibleViewport() {
        _ = NSApplication.shared
        let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
        var appearance = LauncherAppearancePreferences.defaults(design: .minimal)
        appearance.visibleResultCount = 3
        controller.applyAppearance(appearance, force: true)
        let theme = LauncherThemeController().descriptor(for: appearance)
        let fixtures = (0..<12).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .application,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 12 - index
            )
        }

        controller.apply(fixtures)

        XCTAssertEqual(controller.listedResultIDs.count, 12)
        XCTAssertEqual(controller.listedResultIDs, fixtures.map(\.entry.id))
        XCTAssertEqual(controller.currentPanelHeight, theme.panelHeight(resultCount: 12))
        XCTAssertEqual(controller.currentPanelHeight, theme.panelHeight(resultCount: 3))
        XCTAssertEqual(
            theme.resultsViewportHeight(resultCount: 12),
            theme.resultsViewportHeight(resultCount: 3)
        )
        XCTAssertGreaterThan(
            theme.resultsDocumentHeight(resultCount: 12),
            theme.resultsViewportHeight(resultCount: 12)
        )

        let overflow = (0..<60).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "overflow:\(index)",
                    kind: .application,
                    title: "Overflow \(index)",
                    target: .none
                ),
                score: 60 - index
            )
        }
        controller.apply(overflow)
        XCTAssertEqual(controller.listedResultIDs.count, LauncherSearchLimits.resultSetCap)
        XCTAssertEqual(controller.currentPanelHeight, theme.panelHeight(resultCount: 3))
    }

    func testArrowKeysMoveSelectionThroughTheFullListAndKeepItVisible() {
        _ = NSApplication.shared
        let controller = LauncherPanelController(expansionAnimationDuration: { 0 })
        var appearance = LauncherAppearancePreferences.defaults(design: .minimal)
        appearance.visibleResultCount = 3
        controller.applyAppearance(appearance, force: true)
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let theme = LauncherThemeController().descriptor(for: appearance)
        let fixtures = (0..<12).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .application,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 12 - index
            )
        }
        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(fixtures)
        controller.visibilityIsolationWindow.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.selectedResultID, "fixture:0")
        XCTAssertEqual(controller.resultsScrollOffset, 0, accuracy: 0.5)
        for _ in 0..<5 {
            XCTAssertTrue(controller.control(
                NSTextField(),
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.moveDown(_:))
            ))
        }
        XCTAssertEqual(controller.selectedResultID, "fixture:5")
        XCTAssertEqual(controller.selectedResultRow, 5)
        XCTAssertGreaterThan(controller.resultsScrollOffset, 0)
        let selectedFrame = NSRect(
            x: 0,
            y: CGFloat(5) * (theme.rowHeight + theme.rowSpacing),
            width: max(1, controller.resultsVisibleRect.width),
            height: theme.rowHeight
        )
        XCTAssertTrue(
            controller.resultsVisibleRect.intersects(selectedFrame.insetBy(dx: 0, dy: 1)),
            "Arrowing past the viewport must keep the selected row visible"
        )

        let scrolledOffset = controller.resultsScrollOffset
        controller.apply(fixtures, preservingSelection: true)
        XCTAssertEqual(controller.selectedResultID, "fixture:5")
        XCTAssertEqual(controller.resultsScrollOffset, scrolledOffset, accuracy: 0.5)

        controller.setMode(.main, initialQuery: "other")
        controller.apply(Array(fixtures.prefix(8)))
        XCTAssertEqual(controller.resultsScrollOffset, 0, accuracy: 0.5)
        XCTAssertEqual(controller.selectedResultID, "fixture:0")
    }

    func testLauncherSearchAndResultsExposeVoiceOverLabels() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()

        XCTAssertEqual(controller.searchAccessibilityLabel, "Search Broccoli")
        XCTAssertEqual(controller.resultsAccessibilityLabel, "Search results")
        XCTAssertFalse(controller.visibilityIsolationWindow.hidesOnDeactivate)
        XCTAssertTrue(
            controller.visibilityIsolationWindow.styleMask.contains(.nonactivatingPanel)
        )
        XCTAssertFalse(
            (controller.visibilityIsolationWindow as? NSPanel)?.becomesKeyOnlyIfNeeded ?? true
        )
    }

    func testPlaceholderSwiftUISceneCannotBecomeVisible() {
        _ = NSApplication.shared
        let window = BroccoliAppTestWindows.window(
            size: NSSize(width: 500, height: 500),
            styleMask: [.titled]
        )
        window.contentView = SuppressedLauncherSceneView()

        XCTAssertFalse(window.isRestorable)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.alphaValue, 0)

        window.orderFront(nil)
        NotificationCenter.default.post(
            name: NSWindow.didUpdateNotification,
            object: window
        )

        XCTAssertFalse(window.isVisible)
    }

    func testResigningKeyDismissesWithoutRequestingPreviousApplicationRestore() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        var didHide = false
        var requestedPreviousApplicationRestore = false
        controller.onDidHide = { didHide = true }
        controller.onDismiss = { requestedPreviousApplicationRestore = true }
        controller.showForAutomatedTests()

        controller.windowDidResignKey(Notification(
            name: NSWindow.didResignKeyNotification,
            object: controller.visibilityIsolationWindow
        ))

        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(didHide)
        XCTAssertFalse(requestedPreviousApplicationRestore)
    }

    func testRestoringVisibleSearchFocusPreservesTheMouseSelectedCaretPosition() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let editor = try XCTUnwrap(
            controller.visibilityIsolationWindow.firstResponder as? NSTextView
        )
        editor.string = "abcdef"
        editor.setSelectedRange(NSRange(location: 2, length: 0))

        controller.restoreSearchFocusIfVisible()

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testLauncherToggleDismissesOnlyAVisibleKeyPresentation() {
        XCTAssertEqual(
            LauncherToggleDecision.resolve(
                panelIsVisible: true,
                panelIsKey: true
            ),
            .dismiss
        )

        for state in [
            (false, false),
            (false, true),
            (true, false),
        ] {
            XCTAssertEqual(
                LauncherToggleDecision.resolve(
                    panelIsVisible: state.0,
                    panelIsKey: state.1
                ),
                .present,
                "A hidden or stale panel must be presented, never treated as a toggle-off"
            )
        }
    }

    func testLauncherHotKeyCanClaimFocusInsideTheCarbonCallbackTurn() {
        var delivered = false
        GlobalHotKeyActionDelivery.perform(.immediate) { delivered = true }

        XCTAssertTrue(delivered)
    }

    func testWindowHotKeyDefersWorkUntilAfterTheCarbonCallback() async {
        var delivered = false
        GlobalHotKeyActionDelivery.perform(.afterCallback) { delivered = true }

        XCTAssertFalse(delivered)
        await Task.yield()
        XCTAssertTrue(delivered)
    }

    func testLiquidGlassHierarchyRemainsWindowBackedWhileLauncherIsHidden() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .liquidGlass), force: true)

        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(controller.isContentViewAttached)
        XCTAssertTrue(controller.isSearchSurfaceWindowBacked)

        controller.showForAutomatedTests()
        XCTAssertTrue(controller.isContentViewAttached)
        XCTAssertTrue(controller.isSearchSurfaceWindowBacked)

        controller.dismiss(notify: false)
        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(controller.isContentViewAttached)
        XCTAssertTrue(controller.isSearchSurfaceWindowBacked)
    }

    func testLiquidMainLauncherStaysCollapsedForAnEmptyQuery() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .liquidGlass), force: true)
        let recent = RankedResult(
            entry: SearchEntry(
                id: "fixture:recent",
                kind: .application,
                title: "Recent App",
                target: .none
            ),
            score: 1
        )

        controller.setMode(.main)
        controller.apply([recent])
        XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 0)

        controller.setMode(.fileSearch(query: ""))
        controller.apply([recent])
        XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 1)
    }

    func testEveryLauncherDesignExposesTheSameSearchPlaceholderAndNativeControl() {
        _ = NSApplication.shared

        for design in LauncherDesign.allCases {
            let controller = LauncherPanelController()
            controller.applyAppearance(.defaults(design: design), force: true)
            controller.setMode(.main)

            XCTAssertTrue(controller.usesNativeSearchField, design.title)
            XCTAssertEqual(controller.searchPlaceholder, "Search Broccoli", design.title)
        }
    }

    func testLiquidMainImmediatelyShowsSingleAndMultipleSuggestions() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        controller.applyAppearance(preferences, force: true)
        let fixtures = (0..<2).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .application,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 1
            )
        }

        controller.setMode(.main, initialQuery: "wal")
        controller.apply(Array(fixtures.prefix(1)))
        XCTAssertTrue(controller.isResultViewportVisible)
        XCTAssertNil(controller.inlineSuggestionText)
        let oneResultHeight = controller.currentPanelHeight
        XCTAssertEqual(
            oneResultHeight,
            LauncherThemeController().descriptor(for: preferences).panelHeight(resultCount: 1)
        )

        controller.setMode(.main, initialQuery: "w")
        controller.apply(fixtures)
        XCTAssertTrue(controller.isResultViewportVisible)
        XCTAssertNil(controller.inlineSuggestionText)
        XCTAssertEqual(
            controller.currentPanelHeight,
            LauncherThemeController().descriptor(for: preferences).panelHeight(resultCount: 2)
        )

        controller.apply(Array(fixtures.prefix(1)))
        XCTAssertTrue(controller.isResultViewportVisible)
        XCTAssertEqual(controller.currentPanelHeight, oneResultHeight)
    }
}

@MainActor
private final class ResizeContextProbe: NSView {
    var resizeAnimationStates: [Bool] = []

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size {
            resizeAnimationStates.append(NSAnimationContext.current.allowsImplicitAnimation)
        }
        super.setFrameSize(newSize)
    }
}
