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
            controller.show(on: NSScreen.main)
            XCTAssertTrue(context.allowsImplicitAnimation)
        }
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertFalse(probe.resizeAnimationStates.isEmpty)
        XCTAssertTrue(probe.resizeAnimationStates.allSatisfy { !$0 })
    }

    func testResultResizeDoesNotInheritAnEnclosingAnimation() throws {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
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
        let controller = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let noResults = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .notExpression, hasVisibleQuery: true, limit: 7)
        let fixtures = LauncherPreviewFixture.standard.results
        for mode in [LauncherAppearanceMode.light, .dark] {
            preferences.mode = mode
            controller.applyAppearance(preferences)
            let theme = LauncherThemeController().descriptor(for: preferences)
            controller.show(on: NSScreen.main)
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
        controller.apply((0..<12).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "fixture:\(index)",
                    kind: .status,
                    title: "Fixture \(index)",
                    target: .none
                ),
                score: 0
            )
        })

        let table = NSTableView()
        XCTAssertEqual(controller.preparedResultRowCount, 10)
        XCTAssertEqual(controller.numberOfRows(in: table), 10)

        let firstPass = try (0..<10).map { row in
            try XCTUnwrap(controller.tableView(table, viewFor: nil, row: row))
        }
        let secondPass = try (0..<10).map { row in
            try XCTUnwrap(controller.tableView(table, viewFor: nil, row: row))
        }
        XCTAssertEqual(Set(firstPass.map(ObjectIdentifier.init)).count, 10)
        for row in 0..<10 {
            XCTAssertTrue(firstPass[row] === secondPass[row])
        }
        XCTAssertNil(controller.tableView(table, viewFor: nil, row: 10))
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
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
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)

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
        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
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

        controller.show(on: NSScreen.main ?? NSScreen.screens.first)
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
