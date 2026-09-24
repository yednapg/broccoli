import ApplicationServices
import Carbon
import XCTest
@testable import BroccoliApp

@MainActor
final class WindowLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 30, width: 1_200, height: 900)
    private let portrait = CGRect(x: 1_200, y: 0, width: 900, height: 1_500)

    private func frame(
        _ action: WindowAction,
        window: CGRect,
        screen: CGRect? = nil,
        options: WindowLayoutOptions = .standard
    ) -> CGRect {
        WindowGeometry.frame(for: action, window: window, screen: screen ?? self.screen, options: options)
    }

    // MARK: - Grid layouts

    func testQuartersDivideTheUsableScreen() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(frame(.topLeftQuarter, window: window), CGRect(x: 0, y: 30, width: 600, height: 450))
        XCTAssertEqual(frame(.topRightQuarter, window: window), CGRect(x: 600, y: 30, width: 600, height: 450))
        XCTAssertEqual(frame(.bottomLeftQuarter, window: window), CGRect(x: 0, y: 480, width: 600, height: 450))
        XCTAssertEqual(frame(.bottomRightQuarter, window: window), CGRect(x: 600, y: 480, width: 600, height: 450))
    }

    func testLeftAndRightThirdsAreColumnsOnLandscapeDisplays() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(frame(.firstThird, window: window), CGRect(x: 0, y: 30, width: 400, height: 900))
        XCTAssertEqual(frame(.lastThird, window: window), CGRect(x: 800, y: 30, width: 400, height: 900))
    }

    func testThirdsAreRowsOnPortraitDisplays() {
        let window = CGRect(x: 1_300, y: 100, width: 400, height: 300)
        XCTAssertEqual(
            frame(.firstThird, window: window, screen: portrait),
            CGRect(x: 1_200, y: 0, width: 900, height: 500)
        )
        XCTAssertEqual(
            frame(.lastThird, window: window, screen: portrait),
            CGRect(x: 1_200, y: 1_000, width: 900, height: 500)
        )
    }

    // MARK: - Fill

    func testAlmostMaximizeUsesTheConfiguredShare() {
        var options = WindowLayoutOptions.standard
        options.almostMaximizeFraction = 0.8
        XCTAssertEqual(
            frame(.minimized, window: .zero, options: options),
            CGRect(x: 120, y: 120, width: 960, height: 720)
        )
    }

    func testMaximizeOneAxisKeepsAndClampsTheOther() {
        let window = CGRect(x: 1_000, y: 200, width: 500, height: 300)
        XCTAssertEqual(frame(.maximizeHeight, window: window), CGRect(x: 700, y: 30, width: 500, height: 900))
        XCTAssertEqual(frame(.maximizeWidth, window: window), CGRect(x: 0, y: 200, width: 1_200, height: 300))
    }

    // MARK: - Resize

    func testMakeLargerKeepsScreenEdgesThatTheWindowTouches() {
        let leftHalf = CGRect(x: 0, y: 30, width: 600, height: 900)
        XCTAssertEqual(frame(.makeLarger, window: leftHalf), CGRect(x: 0, y: 30, width: 630, height: 900))

        let rightHalf = CGRect(x: 600, y: 30, width: 600, height: 900)
        XCTAssertEqual(frame(.makeLarger, window: rightHalf), CGRect(x: 570, y: 30, width: 630, height: 900))

        let floating = CGRect(x: 300, y: 300, width: 400, height: 300)
        XCTAssertEqual(frame(.makeLarger, window: floating), CGRect(x: 285, y: 285, width: 430, height: 330))
    }

    func testMakeLargerTreatsTerminalGridSnapAsDockedToTheEdge() {
        let snappedLeft = CGRect(x: 4, y: 33, width: 596, height: 894)
        let larger = frame(.makeLarger, window: snappedLeft)
        XCTAssertEqual(larger.minX, 4)
        XCTAssertEqual(larger.width, 626)
    }

    func testMakeLargerStopsAtTheScreen() {
        let nearlyFull = CGRect(x: 10, y: 40, width: 1_180, height: 880)
        XCTAssertEqual(frame(.makeLarger, window: nearlyFull), screen)

        let maximized = screen
        XCTAssertEqual(frame(.makeLarger, window: maximized), maximized)
    }

    func testMakeSmallerKeepsAColumnFullHeight() {
        let leftHalf = CGRect(x: 0, y: 30, width: 600, height: 900)
        XCTAssertEqual(frame(.makeSmaller, window: leftHalf), CGRect(x: 0, y: 30, width: 570, height: 900))
    }

    func testMakeSmallerShrinksAMaximizedWindowOnBothAxes() {
        XCTAssertEqual(frame(.makeSmaller, window: screen), CGRect(x: 15, y: 45, width: 1_170, height: 870))
    }

    func testMakeSmallerStopsAtTheMinimumSizeWithoutGrowingSmallWindows() {
        let nearMinimum = CGRect(x: 100, y: 100, width: 310, height: 230)
        XCTAssertEqual(frame(.makeSmaller, window: nearMinimum), CGRect(x: 105, y: 102.5, width: 300, height: 225))

        let alreadySmall = CGRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertEqual(frame(.makeSmaller, window: alreadySmall), alreadySmall)
    }

    func testResizeStepFollowsPreferences() {
        var options = WindowLayoutOptions.standard
        options.resizeStep = 100
        let leftHalf = CGRect(x: 0, y: 30, width: 600, height: 900)
        XCTAssertEqual(
            frame(.makeLarger, window: leftHalf, options: options),
            CGRect(x: 0, y: 30, width: 700, height: 900)
        )
    }

    // MARK: - Edges

    // MARK: - Catalog

    func testEveryActionHasAGroupSymbolAndSearchEntry() {
        for action in WindowAction.allCases {
            XCTAssertTrue(action.group.actions.contains(action))
            XCTAssertFalse(action.aliases.isEmpty, "\(action) needs search keywords")
            XCTAssertNotEqual(
                NativeIconCatalog.resolvedActionSymbolName(forActionID: action.actionID),
                "bolt",
                "\(action) fell back to the generic action symbol"
            )
            XCTAssertEqual(WindowAction(actionID: action.actionID), action)
            XCTAssertNotNil(ActionRegistry.definition(id: action.actionID))
        }
        XCTAssertNil(WindowAction(actionID: "audio.toggleMute"))
    }

    func testOnlyTheOriginalLayoutsShipWithShortcutsAndNoneCollide() {
        let original: Set<WindowAction> = [
            .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize,
            .minimized, .center, .nextDisplay, .previousDisplay,
        ]
        let assigned = WindowAction.allCases.filter { $0.defaultShortcut != nil }
        XCTAssertEqual(Set(assigned), original)
        let combinations = assigned.compactMap(\.defaultShortcut).map { "\($0.keyCode)-\($0.modifiers)" }
        XCTAssertEqual(Set(combinations).count, assigned.count)
    }

    func testStepActionsAreIncrementalAndLayoutsAreNot() {
        XCTAssertTrue(WindowAction.makeLarger.isIncremental)
        XCTAssertTrue(WindowAction.makeSmaller.isIncremental)
        XCTAssertFalse(WindowAction.leftHalf.isIncremental)
        XCTAssertFalse(WindowAction.nextDisplay.isIncremental)
        XCTAssertFalse(WindowAction.tileAll.isIncremental)
    }

    // MARK: - Preferences

    func testRemovedDefaultShortcutStaysRemovedAfterSaving() throws {
        var preferences = WindowManagementPreferences()
        preferences.setShortcut(nil, for: .leftHalf)
        let custom = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey))
        preferences.setShortcut(custom, for: .makeLarger)

        let decoded = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: PropertyListEncoder().encode(preferences)
        )

        XCTAssertNil(decoded.shortcut(for: .leftHalf))
        XCTAssertEqual(decoded.shortcut(for: .makeLarger), custom)
        XCTAssertEqual(decoded.shortcut(for: .rightHalf), WindowAction.rightHalf.defaultShortcut)
        XCTAssertNil(decoded.shortcut(for: .makeSmaller))
        XCTAssertEqual(decoded, preferences)
    }

    func testReassigningARemovedShortcutClearsTheRemoval() {
        var preferences = WindowManagementPreferences()
        preferences.setShortcut(nil, for: .center)
        XCTAssertTrue(preferences.unassignedShortcuts.contains(.center))
        let custom = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
        preferences.setShortcut(custom, for: .center)
        XCTAssertFalse(preferences.unassignedShortcuts.contains(.center))
        XCTAssertEqual(preferences.shortcut(for: .center), custom)
    }

    func testEarlierSavedPreferencesKeepShortcutsAndGainDefaultSizes() throws {
        let custom = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
        let legacy = LegacyWindowPreferences(
            shortcutsEnabled: true,
            shortcuts: [.maximize: custom, .leftHalf: WindowAction.leftHalf.defaultShortcut!]
        )

        let decoded = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: PropertyListEncoder().encode(legacy)
        )

        XCTAssertTrue(decoded.shortcutsEnabled)
        XCTAssertEqual(decoded.shortcut(for: .maximize), custom)
        XCTAssertEqual(decoded.shortcut(for: .center), WindowAction.center.defaultShortcut)
        XCTAssertEqual(decoded.resizeStep, 30)
        XCTAssertEqual(decoded.almostMaximizeFraction, 0.9)
    }

    func testUnknownStoredActionIsSkippedWithoutLosingOtherShortcuts() throws {
        let custom = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
        let stored = ForeignWindowPreferences(
            shortcutsEnabled: true,
            shortcuts: [.retiredAction: custom, .maximize: custom]
        )

        let decoded = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: PropertyListEncoder().encode(stored)
        )

        XCTAssertTrue(decoded.shortcutsEnabled)
        XCTAssertEqual(decoded.shortcut(for: .maximize), custom)
    }

    func testSanitizeSnapsSizesToOfferedChoices() {
        var preferences = WindowManagementPreferences(resizeStep: 37, almostMaximizeFraction: .nan)
        preferences.sanitize()
        XCTAssertEqual(preferences.resizeStep, 30)
        XCTAssertEqual(preferences.almostMaximizeFraction, 0.9)

        preferences = WindowManagementPreferences(resizeStep: 5_000, almostMaximizeFraction: 0.1)
        preferences.sanitize()
        XCTAssertEqual(preferences.resizeStep, 100)
        XCTAssertEqual(preferences.almostMaximizeFraction, 0.8)
    }

    func testDuplicateShortcutLookupIgnoresTheActionBeingChanged() throws {
        let preferences = WindowManagementPreferences()
        let leftHalf = try XCTUnwrap(WindowAction.leftHalf.defaultShortcut)
        XCTAssertEqual(preferences.action(using: leftHalf, excluding: .makeLarger), .leftHalf)
        XCTAssertNil(preferences.action(using: leftHalf, excluding: .leftHalf))
    }

    func testRegistrationSummaryNamesFailedShortcuts() {
        XCTAssertNil(WindowShortcutRegistrationSummary.message(failedTitles: []))
        XCTAssertEqual(
            WindowShortcutRegistrationSummary.message(failedTitles: ["Left Half"]),
            "The Left Half shortcut is already in use or unavailable."
        )
        XCTAssertEqual(
            WindowShortcutRegistrationSummary.message(failedTitles: ["Left Half", "Make Larger"]),
            "2 shortcuts are already in use or unavailable: Left Half, Make Larger."
        )
    }

    // MARK: - Request ordering

    func testStepRequestsQueueInsteadOfCancellingEarlierOnes() {
        let state = WindowActionRequestState()
        let first = state.begin(supersedingEarlierRequests: false)
        let second = state.begin(supersedingEarlierRequests: false)
        XCTAssertNoThrow(try state.check(first))
        XCTAssertNoThrow(try state.check(second))
    }

    func testLayoutRequestSupersedesEveryEarlierRequest() {
        let state = WindowActionRequestState()
        let step = state.begin(supersedingEarlierRequests: false)
        let layout = state.begin(supersedingEarlierRequests: true)
        let laterStep = state.begin(supersedingEarlierRequests: false)
        XCTAssertThrowsError(try state.check(step))
        XCTAssertNoThrow(try state.check(layout))
        XCTAssertNoThrow(try state.check(laterStep))
    }

    func testCancellingOneQueuedRequestLeavesTheOthers() {
        let state = WindowActionRequestState()
        let first = state.begin(supersedingEarlierRequests: false)
        let second = state.begin(supersedingEarlierRequests: false)
        state.cancel(first)
        XCTAssertThrowsError(try state.check(first))
        XCTAssertNoThrow(try state.check(second))
    }

    // MARK: - Frame writes

    func testStepResizeKeepsTheAxisTheApplicationHonored() throws {
        let original = CGRect(x: 100, y: 100, width: 400, height: 300)
        let target = CGRect(x: 100, y: 100, width: 370, height: 270)
        let probe = MinimumWidthProbe(frame: original, minimumWidth: 400)

        XCTAssertNoThrow(try probe.makeOperation().setFrame(target, of: AXUIElementCreateApplication(100), acceptsPartialAxis: true))
        XCTAssertEqual(probe.appliedFrame, CGRect(x: 100, y: 100, width: 400, height: 270))
    }

    func testLayoutStillRollsBackAHalfAppliedFrame() {
        let original = CGRect(x: 100, y: 100, width: 400, height: 300)
        let target = CGRect(x: 100, y: 100, width: 370, height: 270)
        let probe = MinimumWidthProbe(frame: original, minimumWidth: 400)

        XCTAssertThrowsError(try probe.makeOperation().setFrame(target, of: AXUIElementCreateApplication(100)))
        XCTAssertEqual(probe.appliedFrame, original)
    }

    func testActionAtItsLimitDoesNotWriteToTheWindow() throws {
        let screen = CGRect(x: 0, y: 30, width: 1_200, height: 900)
        let probe = MinimumWidthProbe(frame: screen, minimumWidth: 0)
        let window = AXUIElementCreateApplication(200)
        let operation = probe.makeOperation(focusedWindow: window)

        try operation.perform(.makeLarger, targetPID: 100, screens: [screen], checkCancellation: {})

        XCTAssertEqual(probe.writeCount, 0)
    }
}

// MARK: - Fixtures

/// Mirrors the stored shape of `WindowManagementPreferences` before the sizes and removed
/// shortcuts were added.
private struct LegacyWindowPreferences: Encodable {
    let shortcutsEnabled: Bool
    let shortcuts: [WindowAction: HotKeyConfiguration]
}

private enum ForeignWindowAction: String, Codable {
    case retiredAction
    case maximize
}

/// Encodes shortcuts in the same format but with an identifier this build does not know.
private struct ForeignWindowPreferences: Encodable {
    let shortcutsEnabled: Bool
    let shortcuts: [ForeignWindowAction: HotKeyConfiguration]
}

/// A window that refuses to become narrower than `minimumWidth` but accepts any height.
private final class MinimumWidthProbe {
    var appliedFrame: CGRect
    let minimumWidth: CGFloat
    var writeCount = 0

    init(frame: CGRect, minimumWidth: CGFloat) {
        appliedFrame = frame
        self.minimumWidth = minimumWidth
    }

    func makeOperation(focusedWindow: AXUIElement? = nil) -> WindowAccessibilityOperation {
        WindowAccessibilityOperation(
            attributeReader: { [self] _, attribute in
                if let focusedWindow {
                    if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                        return AccessibilityAttributeRead(error: .success, value: focusedWindow)
                    }
                    if CFEqual(attribute, kAXRoleAttribute as CFString) {
                        return AccessibilityAttributeRead(error: .success, value: kAXWindowRole as CFString)
                    }
                    if CFEqual(attribute, kAXSubroleAttribute as CFString) {
                        return AccessibilityAttributeRead(error: .success, value: kAXStandardWindowSubrole as CFString)
                    }
                }
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = appliedFrame.origin
                    return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgPoint, &value))
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = appliedFrame.size
                    return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgSize, &value))
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { [self] _, attribute, value in
                writeCount += 1
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedFrame.origin)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var size = CGSize.zero
                    AXValueGetValue(accessibilityValue, .cgSize, &size)
                    appliedFrame.size = CGSize(width: max(size.width, minimumWidth), height: size.height)
                    return .success
                }
                return .attributeUnsupported
            },
            messagingTimeoutSetter: { _, _ in .success },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )
    }
}
