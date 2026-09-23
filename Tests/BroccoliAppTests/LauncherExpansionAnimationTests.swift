import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

/// The sanctioned launcher motion: a visible height change commits rows and text instantly
/// while the surface grows or shrinks through one short interruptible animation whose top
/// edge stays fixed. These tests drive that contract with a brief injected duration.
@MainActor
final class LauncherExpansionAnimationTests: XCTestCase {
    private func makeController(duration: TimeInterval) -> LauncherPanelController {
        LauncherPanelController(expansionAnimationDuration: { duration })
    }

    private func waitForExpansionToSettle(
        _ controller: LauncherPanelController,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.isExpansionAnimationInFlight, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(controller.isExpansionAnimationInFlight,
                      "Expansion animation did not complete within \(timeout)s")
    }

    func testExpansionCompletesAtExactFinalGeometry() async throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let top = window.frame.maxY
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))
        XCTAssertEqual(window.frame.height, theme.searchHeight)

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(LauncherPreviewFixture.standard.results)

        XCTAssertTrue(controller.isExpansionAnimationInFlight)
        // The in-flight token is the deterministic discriminator that the sanctioned
        // motion branch ran instead of the instant commit; the animated branch clears it
        // only from its completion handler.

        try await waitForExpansionToSettle(controller)

        XCTAssertEqual(window.frame.height,
                       theme.panelHeight(resultCount: LauncherPreviewFixture.standard.results.count),
                       accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5,
                       "Growth must extend downward from the fixed top edge")
        let root = try XCTUnwrap(window.contentView)
        let surface = try XCTUnwrap(root.subviews.first as? LauncherLiquidGlassSurfaceView)
        XCTAssertEqual(surface.frame, root.bounds)
        XCTAssertEqual(root.frame.size, window.frame.size)
        XCTAssertTrue(root.layer?.animationKeys()?.isEmpty ?? true,
                      "No animations may linger after the motion completes")
        let material = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertEqual(material.frame, surface.bounds)
        XCTAssertFalse(material.wantsLayer)
        XCTAssertEqual(material.maskImage?.capInsets.top, LauncherLiquidGlassMetrics.cornerRadius)
    }

    func testNewResultsDuringAnimationConvergeToNewestTarget() async throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let top = window.frame.maxY
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(LauncherPreviewFixture.standard.results)
        XCTAssertTrue(controller.isExpansionAnimationInFlight)
        // A newer query arrives mid-flight: rows already committed, surface retargets.
        controller.apply(Array(LauncherPreviewFixture.standard.results.prefix(1)))

        try await waitForExpansionToSettle(controller)
        XCTAssertEqual(window.frame.height, theme.panelHeight(resultCount: 1), accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
        let root = try XCTUnwrap(window.contentView)
        XCTAssertTrue(root.layer?.animationKeys()?.isEmpty ?? true,
                      "Interrupting must not leave truncated animations behind")
    }

    func testReduceMotionCollapsesToTheInstantCommit() async throws {
        _ = NSApplication.shared
        let environment = LauncherAppearanceEnvironment(
            reducesTransparency: false, increasesContrast: false,
            resolvedAppearance: .light, reducesMotion: true, backingScale: 2)
        let controller = LauncherPanelController(environmentProvider: { environment })
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let top = window.frame.maxY
        let theme = LauncherThemeController().descriptor(
            for: .defaults(design: .liquidGlass), environment: environment)

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(LauncherPreviewFixture.standard.results)

        XCTAssertFalse(controller.isExpansionAnimationInFlight)
        XCTAssertEqual(window.frame.height,
                       theme.panelHeight(resultCount: LauncherPreviewFixture.standard.results.count))
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.001)
        let root = try XCTUnwrap(window.contentView)
        XCTAssertTrue(root.layer?.animationKeys()?.isEmpty ?? true)
    }

    func testZeroDurationInjectionKeepsLegacySynchronousBehavior() throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let top = window.frame.maxY
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(LauncherPreviewFixture.standard.results)

        XCTAssertFalse(controller.isExpansionAnimationInFlight)
        XCTAssertEqual(window.frame.height,
                       theme.panelHeight(resultCount: LauncherPreviewFixture.standard.results.count))
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.001)
        let root = try XCTUnwrap(window.contentView)
        XCTAssertTrue(root.layer?.animationKeys()?.isEmpty ?? true)
    }

    func testDismissDuringAnimationClearsStateAndNextShowIsCollapsed() async throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        let window = controller.visibilityIsolationWindow

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(LauncherPreviewFixture.standard.results)
        XCTAssertTrue(controller.isExpansionAnimationInFlight)

        controller.dismiss(notify: false)
        XCTAssertFalse(controller.isExpansionAnimationInFlight)
        XCTAssertFalse(window.isVisible)

        // A stale completion handler must not resurrect or resize a hidden panel.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controller.isExpansionAnimationInFlight)
        XCTAssertFalse(window.isVisible)

        controller.showForAutomatedTests()
        XCTAssertFalse(controller.isExpansionAnimationInFlight)
        XCTAssertEqual(window.frame.height, LauncherLiquidGlassMetrics.searchHeight, accuracy: 0.5)
        controller.dismiss(notify: false)
    }

    func testSanctionedMotionIsTheOnlyAnimatedTransaction() throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))

        // The caller's context is explicitly nonanimated. The launcher's own sanctioned
        // motion is the only context in which implicit animation is ever enabled; frame
        // stepping happens outside the caller's group either way.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            controller.setMode(.main, initialQuery: "fixture")
            controller.apply(LauncherPreviewFixture.standard.results)
            XCTAssertFalse(context.allowsImplicitAnimation)
        }

        XCTAssertTrue(controller.isExpansionAnimationInFlight)
        // The window sits at its collapsed frame or the motion's committed target;
        // anything else means the resize diverged from the sanctioned geometry.
        let sanctionedHeights = [theme.searchHeight,
                                 theme.panelHeight(resultCount: LauncherPreviewFixture.standard.results.count)]
        XCTAssertTrue(sanctionedHeights.contains { abs(window.frame.height - $0) <= 1 },
                      "Unexpected mid-resize height \(window.frame.height)")
        window.layoutIfNeeded()
    }

    func testInterruptingAnInFlightShrinkNeverCollapsesThePanel() async throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))
        let full = LauncherPreviewFixture.standard.results

        // Expand fully first.
        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(full)
        try await waitForExpansionToSettle(controller)
        let expandedHeight = window.frame.height
        XCTAssertEqual(expandedHeight, theme.panelHeight(resultCount: full.count), accuracy: 0.5)

        // Clearing the query starts a shrink motion. The rows must stay mounted while the
        // bottom edge rises — hiding the viewport up front produced the "empty glass"
        // collapse flash.
        controller.setMode(.main, initialQuery: "")
        controller.apply([])
        XCTAssertTrue(controller.isExpansionAnimationInFlight)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(controller.isResultViewportVisible,
                      "Rows must ride the shrinking clip, not vanish before it")

        // New results arrive mid-shrink: the motion retargets and must land on the full
        // panel, never on the abandoned collapsed target.
        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(full)
        try await waitForExpansionToSettle(controller)
        XCTAssertEqual(window.frame.height, theme.panelHeight(resultCount: full.count),
                       accuracy: 0.5)
        XCTAssertTrue(controller.isResultViewportVisible)
    }

    /// Runs the main loop for `duration` in short turns and returns the longest single turn.
    /// A keystroke queued behind a turn waits at least that long to be handled.
    private func longestMainLoopTurn(
        over duration: TimeInterval,
        sampling window: NSWindow,
        heights: inout Set<CGFloat>
    ) -> TimeInterval {
        var longest: TimeInterval = 0
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            let start = Date()
            RunLoop.current.run(until: start.addingTimeInterval(0.001))
            longest = max(longest, Date().timeIntervalSince(start))
            heights.insert(window.frame.height)
        }
        return longest
    }

    func testHeightMotionStepsBetweenEventsInsteadOfHoldingTheMainLoop() throws {
        _ = NSApplication.shared
        let controller = makeController(duration: LauncherMotionMetrics.expansionAnimationDuration)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))
        let full = LauncherPreviewFixture.standard.results
        var heights = Set<CGFloat>()

        // The first expansion of a new panel also pays AppKit's one-time table display.
        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(full)
        _ = longestMainLoopTurn(over: 0.4, sampling: window, heights: &heights)
        controller.setMode(.main, initialQuery: "")
        controller.apply([])
        _ = longestMainLoopTurn(over: 0.5, sampling: window, heights: &heights)
        heights.removeAll()

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(full)
        let growTurn = longestMainLoopTurn(over: 0.4, sampling: window, heights: &heights)
        controller.setMode(.main, initialQuery: "")
        controller.apply([])
        let shrinkTurn = longestMainLoopTurn(over: 0.5, sampling: window, heights: &heights)

        // AppKit's blocking `setFrame(_:display:animate: true)` held this loop for ~350 ms.
        XCTAssertLessThan(growTurn, 0.1, "Growing the panel must not hold queued keystrokes")
        XCTAssertLessThan(shrinkTurn, 0.1, "Shrinking the panel must not hold queued keystrokes")
        let intermediate = heights.filter {
            $0 > theme.searchHeight + 1 && $0 < theme.panelHeight(resultCount: full.count) - 1
        }
        XCTAssertGreaterThan(intermediate.count, 2, "The height must step through the motion")
        XCTAssertFalse(controller.isExpansionAnimationInFlight)
        XCTAssertEqual(window.frame.height, theme.searchHeight, accuracy: 0.5)
    }

    func testShrinkWaitsBrieflyAndANewerGrowKeepsThePanelOpen() async throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))
        let full = LauncherPreviewFixture.standard.results
        let expandedHeight = theme.panelHeight(resultCount: full.count)

        controller.setMode(.main, initialQuery: "fixture")
        controller.apply(full)
        try await waitForExpansionToSettle(controller)

        // A keystroke briefly narrows the results, and the next one restores them.
        controller.apply(Array(full.prefix(1)))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(window.frame.height, expandedHeight, accuracy: 0.5,
                       "A shrink must wait before moving the panel")
        controller.apply(full)
        try await waitForExpansionToSettle(controller)
        XCTAssertEqual(window.frame.height, expandedHeight, accuracy: 0.5)

        // A narrowed result set that stays narrowed still shrinks the panel.
        controller.apply(Array(full.prefix(1)))
        try await waitForExpansionToSettle(controller)
        XCTAssertEqual(window.frame.height, theme.panelHeight(resultCount: 1), accuracy: 0.5)
    }

    func testNativeRowIconsSurviveTheHeightMotion() async throws {
        _ = NSApplication.shared
        let controller = makeController(duration: 0.05)
        controller.applyAppearance(.defaults(design: .liquidGlass))
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }
        let window = controller.visibilityIsolationWindow
        let finder = "/System/Library/CoreServices/Finder.app"
        let results = (0..<5).map { index in
            RankedResult(
                entry: SearchEntry(
                    id: "application:\(finder)#\(index)",
                    kind: .application,
                    title: "Finder \(index)",
                    iconKey: finder,
                    target: .application(path: finder, bundleIdentifier: "com.apple.finder")
                ),
                score: 100 - index
            )
        }

        controller.setMode(.main, initialQuery: "fi")
        controller.apply(results)
        try await waitForExpansionToSettle(controller)
        controller.apply(Array(results.prefix(2)))
        try await waitForExpansionToSettle(controller)

        let rows = resultRows(in: try XCTUnwrap(window.contentView))
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            let icon = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first)
            let image = try XCTUnwrap(icon.image, "A native row must keep its artwork after motion")
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertFalse(image.isTemplate)
            XCTAssertTrue(icon.wantsLayer, "Native artwork must stay on its own layer over the glass")
            XCTAssertFalse(icon.allowsVibrancy)
        }
    }

    private func resultRows(in view: NSView) -> [ResultRowView] {
        view.subviews.flatMap { subview -> [ResultRowView] in
            if let row = subview as? ResultRowView, !row.isHidden, row.superview != nil {
                return [row]
            }
            return resultRows(in: subview)
        }
    }
}
