import ApplicationServices
import BroccoliCore
import Carbon
import XCTest
@testable import BroccoliApp

@MainActor
final class WindowAutomationTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 30, width: 1_200, height: 900)

    // MARK: - Drag to snap

    func testSnapZonesFollowEdgesAndCorners() {
        let display = CGRect(x: 0, y: 0, width: 1_200, height: 960)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 0, y: 400), in: display), .leftHalf)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 1_199, y: 400), in: display), .rightHalf)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 600, y: 0), in: display), .maximize)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 0, y: 10), in: display), .topLeftQuarter)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 1_190, y: 0), in: display), .topRightQuarter)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 0, y: 950), in: display), .bottomLeftQuarter)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 200, y: 959), in: display), .firstThird)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 600, y: 959), in: display), .bottomHalf)
        XCTAssertEqual(WindowSnapZone.action(at: CGPoint(x: 1_000, y: 959), in: display), .lastThird)
        XCTAssertNil(WindowSnapZone.action(at: CGPoint(x: 600, y: 400), in: display))
        XCTAssertNil(WindowSnapZone.action(at: CGPoint(x: 1_500, y: 400), in: display))
    }

    // MARK: - Geometry

    func testGridHasNoEmptyCells() {
        let frames = WindowGeometry.gridFrames(count: 5, in: screen, gap: 0)
        XCTAssertEqual(frames.count, 5)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 30, width: 400, height: 450))
        XCTAssertEqual(frames[3], CGRect(x: 0, y: 480, width: 600, height: 450))
        XCTAssertEqual(frames[4], CGRect(x: 600, y: 480, width: 600, height: 450))
    }

    func testGapsSeparateNeighboursButStayFlushWithTheGappedEdge() {
        var options = WindowLayoutOptions.standard
        options.screenEdgeGap = 10
        options.windowGap = 8
        let left = WindowGeometry.frame(for: .leftHalf, window: .zero, screen: screen, options: options)
        let right = WindowGeometry.frame(for: .rightHalf, window: .zero, screen: screen, options: options)
        XCTAssertEqual(left, CGRect(x: 10, y: 40, width: 586, height: 880))
        XCTAssertEqual(right.minX - left.maxX, 8)
        XCTAssertEqual(right.maxX, 1_190)
        XCTAssertEqual(
            WindowGeometry.frame(for: .maximize, window: .zero, screen: screen, options: options),
            CGRect(x: 10, y: 40, width: 1_180, height: 880)
        )
    }

    func testAutomaticTilingRebalancesTheWholeScreen() {
        XCTAssertEqual(WindowGeometry.tiledFrames(count: 1, in: screen, gap: 0, startsSideBySide: true), [screen])
        XCTAssertEqual(WindowGeometry.tiledFrames(count: 2, in: screen, gap: 0, startsSideBySide: true), [
            CGRect(x: 0, y: 30, width: 600, height: 900),
            CGRect(x: 600, y: 30, width: 600, height: 900),
        ])
        XCTAssertEqual(WindowGeometry.tiledFrames(count: 3, in: screen, gap: 0, startsSideBySide: true), [
            CGRect(x: 0, y: 30, width: 600, height: 900),
            CGRect(x: 600, y: 30, width: 600, height: 450),
            CGRect(x: 600, y: 480, width: 600, height: 450),
        ])
        XCTAssertEqual(WindowGeometry.tiledFrames(count: 4, in: screen, gap: 0, startsSideBySide: true), [
            CGRect(x: 0, y: 30, width: 600, height: 450),
            CGRect(x: 600, y: 30, width: 600, height: 450),
            CGRect(x: 0, y: 480, width: 600, height: 450),
            CGRect(x: 600, y: 480, width: 600, height: 450),
        ])
        let five = WindowGeometry.tiledFrames(count: 5, in: screen, gap: 0, startsSideBySide: true)
        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(five.map(\.maxX).max(), screen.maxX)
        XCTAssertEqual(five.map(\.maxY).max(), screen.maxY)
        XCTAssertEqual(five[0].width, 400)
        XCTAssertEqual(five[3].width, 600)
    }

    func testEverydayActionsComeBeforeThePresetGrids() {
        XCTAssertEqual(WindowActionGroup.allCases.map(\.title), [
            "Fill & Center",
            "Resize",
            "Arrange All Windows",
            "Automatic Tiling",
            "Displays",
            "Halves & Quarters",
            "Thirds",
        ])
        let removed = [
            "centerThird", "firstTwoThirds", "lastTwoThirds", "firstFourth", "topLeftSixth",
            "makeWider", "makeNarrower", "makeTaller", "makeShorter",
        ]
        let names = WindowAction.allCases.map(\.rawValue)
        for name in removed {
            XCTAssertFalse(names.contains(name), name)
        }
    }

    func testCascadeKeepsEveryWindowOnScreen() {
        let frames = WindowGeometry.cascadeFrames(
            sizes: [CGSize(width: 1_200, height: 900), CGSize(width: 500, height: 400)],
            in: screen
        )
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 30, width: 1_170, height: 870))
        XCTAssertEqual(frames[1], CGRect(x: 30, y: 60, width: 500, height: 400))
    }

    func testCustomLayoutAnchorsItsSizeInsideTheScreen() {
        let spec = CustomWindowLayout(name: "Wide", width: .percent(50), height: .points(300), anchor: .bottomRight).frameSpec
        XCTAssertEqual(
            WindowGeometry.frame(for: spec, window: .zero, screen: screen),
            CGRect(x: 600, y: 630, width: 600, height: 300)
        )
    }

    func testWorkspaceEntriesSurviveAResolutionChange() {
        let entry = WindowGeometry.workspaceEntry(
            bundleIdentifier: "com.apple.Safari",
            frame: CGRect(x: 600, y: 30, width: 600, height: 450),
            screen: screen,
            displayIndex: 0
        )
        let larger = CGRect(x: 0, y: 25, width: 2_400, height: 1_800)
        XCTAssertEqual(WindowGeometry.frame(for: entry, screen: larger), CGRect(x: 1_200, y: 25, width: 1_200, height: 900))
    }

    // MARK: - State

    func testTilingKeepsKnownOrderAndAppendsNewWindows() {
        let state = TilingState()
        let first = WindowKey(AXUIElementCreateApplication(201))
        let second = WindowKey(AXUIElementCreateApplication(202))
        let third = WindowKey(AXUIElementCreateApplication(203))
        XCTAssertEqual(state.reconcile(with: [second, first]), [second, first])
        XCTAssertEqual(state.reconcile(with: [first, third, second]), [second, first, third])
        state.swap(second, third)
        XCTAssertEqual(state.reconcile(with: [first, second, third]), [third, first, second])
        state.removeApplication(203)
        XCTAssertEqual(state.order, [first, second])
    }

    func testHistoryIsBoundedAndForgetsQuitApplications() {
        let history = WindowHistory()
        let entry = WindowHistory.Entry(restoreFrame: .zero, lastApplied: .zero, lastAction: nil, cycleIndex: 0)
        for pid in 1...(WindowHistory.capacity + 5) {
            history.record(entry, for: WindowKey(AXUIElementCreateApplication(pid_t(1_000 + pid))))
        }
        XCTAssertNil(history.entry(for: WindowKey(AXUIElementCreateApplication(1_001))))
        let recent = WindowKey(AXUIElementCreateApplication(pid_t(1_000 + WindowHistory.capacity + 5)))
        XCTAssertNotNil(history.entry(for: recent))
        history.removeApplication(recent.processIdentifier)
        XCTAssertNil(history.entry(for: recent))
    }

    // MARK: - Preferences

    func testEarlierInstallsKeepTheirBehaviorUntilANewFeatureIsTurnedOn() throws {
        let legacy = try PropertyListSerialization.data(
            fromPropertyList: ["shortcutsEnabled": true],
            format: .binary,
            options: 0
        )
        for preferences in [
            WindowManagementPreferences(),
            try PropertyListDecoder().decode(WindowManagementPreferences.self, from: legacy),
        ] {
            XCTAssertEqual(preferences.repeatBehavior, .cycleSizes)
            XCTAssertEqual(preferences.screenEdgeGap, 0)
            XCTAssertEqual(preferences.windowGap, 0)
            XCTAssertFalse(preferences.dragToSnapEnabled)
            XCTAssertFalse(preferences.automaticTilingEnabled)
            XCTAssertTrue(preferences.ignoredBundleIdentifiers.isEmpty)
            XCTAssertTrue(preferences.customLayouts.isEmpty)
            XCTAssertTrue(preferences.workspaces.isEmpty)
            for action in WindowAction.allCases {
                XCTAssertEqual(preferences.shortcut(for: action), action.defaultShortcut, "\(action)")
            }
            let options = preferences.layoutOptions
            let window = CGRect(x: 100, y: 100, width: 500, height: 400)
            XCTAssertEqual(
                WindowGeometry.frame(for: .leftHalf, window: window, screen: screen, options: options),
                CGRect(x: 0, y: 30, width: 600, height: 900)
            )
            XCTAssertEqual(WindowGeometry.frame(for: .maximize, window: window, screen: screen, options: options), screen)
        }
    }

    func testNewWindowSettingsRoundTripAndSkipUnreadableItems() throws {
        var preferences = WindowManagementPreferences()
        preferences.repeatBehavior = .cycleSizes
        preferences.screenEdgeGap = 8
        preferences.windowGap = 12
        preferences.ignoredBundleIdentifiers = ["com.apple.Terminal"]
        preferences.dragToSnapEnabled = true
        preferences.automaticTilingEnabled = true
        preferences.customLayouts = [CustomWindowLayout(name: "Reading")]
        preferences.workspaces = [WindowWorkspace(
            name: "Desk",
            entries: [.init(bundleIdentifier: "com.apple.Safari", displayIndex: 0, x: 0, y: 0, width: 0.5, height: 1)]
        )]

        let decoded = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: PropertyListEncoder().encode(preferences)
        )
        XCTAssertEqual(decoded, preferences)
    }

    func testSanitizeClearsDuplicateShortcutsAcrossLayoutsAndActions() throws {
        var preferences = WindowManagementPreferences()
        let leftHalf = try XCTUnwrap(WindowAction.leftHalf.defaultShortcut)
        preferences.customLayouts = [CustomWindowLayout(name: "Copy", shortcut: leftHalf)]
        preferences.sanitize()
        XCTAssertEqual(preferences.shortcut(for: .leftHalf), leftHalf)
        XCTAssertNil(preferences.customLayouts[0].shortcut)
        XCTAssertEqual(preferences.owner(of: leftHalf, excluding: .layout(preferences.customLayouts[0].id)), "Left Half")
    }

    func testLauncherEntriesForCustomLayouts() {
        var preferences = WindowManagementPreferences()
        let layout = CustomWindowLayout(name: "Reading")
        preferences.customLayouts = [layout]
        let entries = WindowSearchEntries.customizations(preferences)
        XCTAssertEqual(entries.map(\.title), ["Reading"])
        XCTAssertEqual(entries.first?.target, .action(id: layout.actionID))
        XCTAssertNotEqual(NativeIconCatalog.resolvedActionSymbolName(forActionID: layout.actionID), "bolt")
    }

    func testRemovedMoveAcrossDisplaysChoiceBecomesSizeCycling() throws {
        let legacy = try PropertyListSerialization.data(
            fromPropertyList: ["repeatBehavior": "moveAcrossDisplays"],
            format: .binary,
            options: 0
        )
        let decoded = try PropertyListDecoder().decode(WindowManagementPreferences.self, from: legacy)
        XCTAssertEqual(decoded.repeatBehavior, .cycleSizes)
    }

    func testSavedDoNothingBecomesSizeCyclingOnce() {
        var preferences = WindowManagementPreferences()
        preferences.repeatBehavior = .none
        preferences.adoptRepeatedSizeCycle()
        XCTAssertEqual(preferences.repeatBehavior, .cycleSizes)

        preferences.repeatBehavior = .none
        preferences.adoptRepeatedSizeCycle()
        XCTAssertEqual(preferences.repeatBehavior, .none)
    }

    // MARK: - Engine

    func testRestoreReturnsTheWindowToWhereItStarted() throws {
        let original = CGRect(x: 200, y: 200, width: 500, height: 400)
        let server = FakeWindowServer(windows: [original])
        let operation = server.makeOperation()

        try operation.perform(.leftHalf, targetPID: server.processIdentifier, screens: [screen], checkCancellation: {})
        try operation.perform(.makeSmaller, targetPID: server.processIdentifier, screens: [screen], checkCancellation: {})
        XCTAssertNotEqual(server.frames[0], original)

        try operation.perform(.restore, targetPID: server.processIdentifier, screens: [screen], checkCancellation: {})
        XCTAssertEqual(server.frames[0], original)
    }

    func testRepeatedHalfCyclesSizesWhenChosen() throws {
        let server = FakeWindowServer(windows: [CGRect(x: 200, y: 200, width: 500, height: 400)])
        let operation = server.makeOperation()
        var options = WindowLayoutOptions.standard
        options.repeatBehavior = .cycleSizes

        for expectedWidth in [600.0, 400.0, 800.0, 600.0] {
            try operation.perform(.leftHalf, targetPID: server.processIdentifier, screens: [screen], options: options, checkCancellation: {})
            XCTAssertEqual(server.frames[0].minX, 0, accuracy: 0.5)
            XCTAssertEqual(server.frames[0].width, expectedWidth, accuracy: 0.5)
            XCTAssertEqual(server.frames[0].height, 900, accuracy: 0.5)
        }
    }

    func testRepeatedRightHalfStaysOnTheRightEdge() throws {
        let server = FakeWindowServer(windows: [CGRect(x: 200, y: 200, width: 500, height: 400)])
        let operation = server.makeOperation()
        for expectedMinX in [600.0, 800.0, 400.0] {
            try operation.perform(.rightHalf, targetPID: server.processIdentifier, screens: [screen], checkCancellation: {})
            XCTAssertEqual(server.frames[0].minX, expectedMinX, accuracy: 0.5)
            XCTAssertEqual(server.frames[0].maxX, 1_200, accuracy: 0.5)
        }
    }

    func testRepeatedHalfStaysPutWhenCyclingIsOff() throws {
        let server = FakeWindowServer(windows: [CGRect(x: 200, y: 200, width: 500, height: 400)])
        let operation = server.makeOperation()
        var options = WindowLayoutOptions.standard
        options.repeatBehavior = .none
        try operation.perform(.leftHalf, targetPID: server.processIdentifier, screens: [screen], options: options, checkCancellation: {})
        let writes = server.writeCount
        try operation.perform(.leftHalf, targetPID: server.processIdentifier, screens: [screen], options: options, checkCancellation: {})
        XCTAssertEqual(server.writeCount, writes)
    }

    func testTileAllArrangesEveryVisibleWindowOnTheDisplay() throws {
        let server = FakeWindowServer(windows: [
            CGRect(x: 100, y: 100, width: 500, height: 400),
            CGRect(x: 300, y: 300, width: 500, height: 400),
        ])
        let operation = server.makeOperation()
        try operation.perform(
            .action(.tileAll),
            targetPID: server.processIdentifier,
            screens: [screen],
            options: .standard,
            pointerScreenIndex: nil,
            checkCancellation: {}
        )
        XCTAssertEqual(Set(server.frames.map(\.minX)), [0, 600])
        XCTAssertEqual(server.frames.map(\.width), [600, 600])
        XCTAssertEqual(server.frames.map(\.height), [900, 900])
    }

    func testRotateLayoutTurnsSideBySideWindowsIntoAStack() throws {
        let server = FakeWindowServer(windows: [
            CGRect(x: 40, y: 80, width: 300, height: 200),
            CGRect(x: 700, y: 90, width: 250, height: 180),
        ])
        var options = WindowLayoutOptions.standard
        options.automaticTilingEnabled = true

        try server.makeOperation().perform(
            .action(.rotateLayout),
            targetPID: server.processIdentifier,
            screens: [screen],
            options: options,
            pointerScreenIndex: nil,
            checkCancellation: {}
        )

        XCTAssertEqual(server.frames, [
            CGRect(x: 0, y: 30, width: 1_200, height: 450),
            CGRect(x: 0, y: 480, width: 1_200, height: 450),
        ])
    }

    func testCascadeOffsetsEachWindowAndKeepsThemOnScreen() throws {
        let server = FakeWindowServer(windows: [
            CGRect(x: 100, y: 100, width: 800, height: 600),
            CGRect(x: 200, y: 200, width: 700, height: 500),
        ])
        try server.makeOperation().perform(
            .action(.cascadeAll),
            targetPID: server.processIdentifier,
            screens: [screen],
            options: .standard,
            pointerScreenIndex: nil,
            checkCancellation: {}
        )
        XCTAssertEqual(server.frames[1].minX, 0)
        XCTAssertEqual(server.frames[0].minX, 30)
        XCTAssertLessThanOrEqual(server.frames.map(\.maxX).max() ?? 0, screen.maxX)
        XCTAssertLessThanOrEqual(server.frames.map(\.maxY).max() ?? 0, screen.maxY)
    }

    func testRetilingFourWindowsDividesTheScreenIntoQuarters() throws {
        let server = FakeWindowServer(windows: [
            CGRect(x: 40, y: 80, width: 300, height: 200),
            CGRect(x: 700, y: 90, width: 250, height: 180),
            CGRect(x: 50, y: 520, width: 280, height: 220),
            CGRect(x: 680, y: 540, width: 260, height: 200),
        ])
        var options = WindowLayoutOptions.standard
        options.automaticTilingEnabled = true

        try server.makeOperation().retile(screens: [screen], options: options, checkCancellation: {})

        XCTAssertEqual(server.frames, [
            CGRect(x: 0, y: 30, width: 600, height: 450),
            CGRect(x: 600, y: 30, width: 600, height: 450),
            CGRect(x: 0, y: 480, width: 600, height: 450),
            CGRect(x: 600, y: 480, width: 600, height: 450),
        ])
    }
}

/// One application with several windows. The first window is focused.
private final class FakeWindowServer {
    let processIdentifier: pid_t = 100
    let windowElements: [AXUIElement]
    var frames: [CGRect]
    var writeCount = 0

    init(windows: [CGRect]) {
        frames = windows
        windowElements = windows.indices.map { AXUIElementCreateApplication(pid_t(500 + $0)) }
    }

    private func index(of element: AXUIElement) -> Int? {
        windowElements.firstIndex { CFEqual($0, element) }
    }

    func makeOperation() -> WindowAccessibilityOperation {
        let application = AXUIElementCreateApplication(processIdentifier)
        return WindowAccessibilityOperation(
            attributeReader: { [self] element, attribute in
                if CFEqual(element, application) {
                    if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                        return AccessibilityAttributeRead(error: .success, value: windowElements[0])
                    }
                    if CFEqual(attribute, kAXWindowsAttribute as CFString) {
                        return AccessibilityAttributeRead(error: .success, value: windowElements as CFArray)
                    }
                    return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
                }
                guard let index = index(of: element) else {
                    return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
                }
                switch attribute as String {
                case kAXRoleAttribute:
                    return AccessibilityAttributeRead(error: .success, value: kAXWindowRole as CFString)
                case kAXSubroleAttribute:
                    return AccessibilityAttributeRead(error: .success, value: kAXStandardWindowSubrole as CFString)
                case kAXMinimizedAttribute:
                    return AccessibilityAttributeRead(error: .success, value: kCFBooleanFalse)
                case kAXPositionAttribute:
                    var value = frames[index].origin
                    return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgPoint, &value))
                case kAXSizeAttribute:
                    var value = frames[index].size
                    return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgSize, &value))
                default:
                    return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
                }
            },
            attributeWriter: { [self] element, attribute, value in
                guard let index = index(of: element) else { return .success }
                writeCount += 1
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &frames[index].origin)
                } else if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgSize, &frames[index].size)
                }
                return .success
            },
            messagingTimeoutSetter: { _, _ in .success },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in },
            onScreenWindows: { [self] in
                frames.map { OnScreenWindow(processIdentifier: processIdentifier, bounds: $0) }
            },
            actionPerformer: { _, _ in .success },
            settableChecker: { _, _ in true }
        )
    }
}
