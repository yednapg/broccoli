import ApplicationServices
import Carbon
import XCTest
@testable import BroccoliApp

@MainActor
final class WindowManagementTests: XCTestCase {
    private static let simulatedScreen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)

    func testWindowPermissionUsesCurrentSystemSettingsName() {
        XCTAssertEqual(
            WindowManagementPermissionPresentation.settingsName(forMajorVersion: 26),
            "Accessibility"
        )
        XCTAssertEqual(
            WindowManagementPermissionPresentation.settingsName(forMajorVersion: 27),
            "Device Control and Data Access"
        )
    }

    func testHalfAndMaximizeFramesUseVisibleScreenBounds() {
        let screen = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        let window = CGRect(x: -1200, y: 100, width: 800, height: 600)

        XCTAssertEqual(
            WindowGeometry.frame(for: .leftHalf, window: window, screen: screen),
            CGRect(x: -1440, y: 24, width: 720, height: 876)
        )
        XCTAssertEqual(
            WindowGeometry.frame(for: .rightHalf, window: window, screen: screen),
            CGRect(x: -720, y: 24, width: 720, height: 876)
        )
        XCTAssertEqual(
            WindowGeometry.frame(for: .topHalf, window: window, screen: screen),
            CGRect(x: -1440, y: 24, width: 1440, height: 438)
        )
        XCTAssertEqual(
            WindowGeometry.frame(for: .bottomHalf, window: window, screen: screen),
            CGRect(x: -1440, y: 462, width: 1440, height: 438)
        )
        XCTAssertEqual(
            WindowGeometry.frame(for: .maximize, window: window, screen: screen),
            screen
        )
        let minimized = WindowGeometry.frame(for: .minimized, window: window, screen: screen)
        XCTAssertEqual(minimized.minX, -1368, accuracy: 0.001)
        XCTAssertEqual(minimized.minY, 67.8, accuracy: 0.001)
        XCTAssertEqual(minimized.width, 1296, accuracy: 0.001)
        XCTAssertEqual(minimized.height, 788.4, accuracy: 0.001)
    }

    func testHiddenDockReclaimsItsReservedAreaButKeepsMenuBarClear() {
        let screen = CGRect(x: 0, y: 0, width: 1680, height: 1050)
        let visible = CGRect(x: 0, y: 90, width: 1680, height: 930)

        XCTAssertEqual(
            WindowScreenGeometry.usableAppKitFrame(
                screenFrame: screen,
                visibleFrame: visible,
                dockAutoHides: true,
                dockPosition: .bottom
            ),
            CGRect(x: 0, y: 0, width: 1680, height: 1020)
        )
    }

    func testHiddenSideDockReclaimsHorizontalSpace() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: -1350, y: 0, width: 1350, height: 876)

        XCTAssertEqual(
            WindowScreenGeometry.usableAppKitFrame(
                screenFrame: screen,
                visibleFrame: visible,
                dockAutoHides: true,
                dockPosition: .left
            ),
            CGRect(x: -1440, y: 0, width: 1440, height: 876)
        )
    }

    func testHiddenBottomDockPreservesUnrelatedSideInset() {
        let screen = CGRect(x: 0, y: 0, width: 1_680, height: 1_050)
        let visible = CGRect(x: 80, y: 90, width: 1_600, height: 930)

        XCTAssertEqual(
            WindowScreenGeometry.usableAppKitFrame(
                screenFrame: screen,
                visibleFrame: visible,
                dockAutoHides: true,
                dockPosition: .bottom
            ),
            CGRect(x: 80, y: 0, width: 1_600, height: 1_020)
        )
    }

    func testVisibleDockContinuesUsingSystemVisibleFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1680, height: 1050)
        let visible = CGRect(x: 0, y: 90, width: 1680, height: 930)

        XCTAssertEqual(
            WindowScreenGeometry.usableAppKitFrame(
                screenFrame: screen,
                visibleFrame: visible,
                dockAutoHides: false
            ),
            visible
        )
    }

    func testScreenFrameConvertsFromAppKitToAccessibilityCoordinates() {
        XCTAssertEqual(
            WindowScreenGeometry.accessibilityFrame(
                for: CGRect(x: -1440, y: 0, width: 1440, height: 876),
                primaryScreenFrame: CGRect(x: 0, y: 0, width: 1680, height: 1050)
            ),
            CGRect(x: -1440, y: 174, width: 1440, height: 876)
        )
        XCTAssertEqual(
            WindowScreenGeometry.appKitFrame(
                for: CGRect(x: -1440, y: 174, width: 1440, height: 876),
                primaryScreenFrame: CGRect(x: 0, y: 0, width: 1680, height: 1050)
            ),
            CGRect(x: -1440, y: 0, width: 1440, height: 876)
        )
    }

    func testCenterPlacesBroccoliSettingsOnItsOwnScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let screens = [primary, secondary].map {
            WindowScreenGeometry.accessibilityFrame(for: $0, primaryScreenFrame: primary)
        }
        let settings = CGRect(x: 1600, y: 40, width: 980, height: 680)

        let centered = BroccoliWindowFramePlacement.appKitFrame(
            for: .center,
            current: settings,
            accessibilityScreens: screens,
            primaryScreenFrame: primary,
            options: .standard
        )

        XCTAssertEqual(centered?.size, settings.size)
        XCTAssertEqual(centered?.midX, secondary.midX)
        XCTAssertEqual(centered?.midY, secondary.midY)
        XCTAssertNil(
            BroccoliWindowFramePlacement.appKitFrame(
                for: .tileAll,
                current: settings,
                accessibilityScreens: screens,
                primaryScreenFrame: primary,
                options: .standard
            )
        )
    }

    func testLeftHalfCentersAFixedSizeSettingsWindowInTheLeftHalf() {
        let screen = CGRect(x: 0, y: 0, width: 1_680, height: 1_050)
        let accessibilityScreens = [WindowScreenGeometry.accessibilityFrame(for: screen, primaryScreenFrame: screen)]
        func placed(width: CGFloat) -> CGRect? {
            BroccoliWindowFramePlacement.appKitFrame(
                for: .leftHalf,
                current: CGRect(x: 900, y: 200, width: width, height: 732),
                accessibilityScreens: accessibilityScreens,
                primaryScreenFrame: screen,
                options: .standard,
                keepsSize: true
            )
        }

        XCTAssertEqual(placed(width: 700), CGRect(x: 70, y: 159, width: 700, height: 732))
        XCTAssertEqual(placed(width: 980)?.minX, 0, "Wider than the half, so it stays on screen")
    }

    func testAlignedRightHalfStaysAgainstTheRightEdge() {
        let screen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let rightHalf = CGRect(x: 840, y: 30, width: 840, height: 1_020)
        XCTAssertEqual(
            WindowScreenGeometry.frame(aligning: CGSize(width: 845, height: 1_013), to: rightHalf, screen: screen).origin,
            CGPoint(x: 835, y: 30),
            "A grid-snapped window that came out wider moves back onto the screen"
        )
        XCTAssertEqual(
            WindowScreenGeometry.frame(aligning: CGSize(width: 833, height: 1_013), to: rightHalf, screen: screen).origin,
            CGPoint(x: 847, y: 30),
            "One that came out narrower stays flush with the right edge"
        )
    }

    func testAlignedMaximizeKeepsTheTopLeftCorner() {
        let screen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        XCTAssertEqual(
            WindowScreenGeometry.frame(aligning: CGSize(width: 1_681, height: 1_013), to: screen, screen: screen).origin,
            CGPoint(x: 0, y: 30)
        )
    }

    func testAlignedCenteredLayoutStaysCentered() {
        let screen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let almostMaximized = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        let placed = WindowScreenGeometry.frame(aligning: CGSize(width: 1_498, height: 910), to: almostMaximized, screen: screen)
        XCTAssertEqual(placed.midX, almostMaximized.midX)
        XCTAssertEqual(placed.midY, almostMaximized.midY)
    }

    func testAlignedStepResizeKeepsAnAxisTheApplicationWouldNotResize() {
        let screen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let current = CGRect(x: 300, y: 200, width: 740, height: 600)
        let larger = CGRect(x: 285, y: 185, width: 770, height: 630)
        XCTAssertEqual(
            WindowScreenGeometry.frame(
                aligning: CGSize(width: 740, height: 630),
                to: larger,
                keepingUnchangedAxesOf: current,
                screen: screen
            ),
            CGRect(x: 300, y: 185, width: 740, height: 630)
        )
    }

    func testCenterPreservesSizeAndClampsOversizeWindow() {
        let screen = CGRect(x: 0, y: 25, width: 1000, height: 775)
        XCTAssertEqual(
            WindowGeometry.frame(
                for: .center,
                window: CGRect(x: 10, y: 10, width: 600, height: 400),
                screen: screen
            ),
            CGRect(x: 200, y: 212.5, width: 600, height: 400)
        )
        XCTAssertEqual(
            WindowGeometry.frame(
                for: .center,
                window: CGRect(x: 0, y: 0, width: 1200, height: 900),
                screen: screen
            ),
            screen
        )
    }

    func testMoveBetweenDisplaysPreservesRelativeSizeAndPosition() {
        let source = CGRect(x: 0, y: 25, width: 1000, height: 775)
        let destination = CGRect(x: 1000, y: 0, width: 2000, height: 1200)
        let window = CGRect(x: 250, y: 218.75, width: 500, height: 387.5)

        XCTAssertEqual(
            WindowGeometry.movedFrame(window: window, from: source, to: destination),
            CGRect(x: 1500, y: 300, width: 1000, height: 600)
        )
    }

    func testDefaultPreferencesProvideEveryWindowShortcut() throws {
        let preferences = WindowManagementPreferences()
        XCTAssertFalse(preferences.shortcutsEnabled)
        XCTAssertEqual(preferences.shortcuts, [
            .leftHalf: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey)),
            .rightHalf: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey)),
            .topHalf: .init(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey)),
            .bottomHalf: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey)),
            .maximize: .init(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey)),
            .minimized: .init(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey | shiftKey)),
            .center: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)),
            .nextDisplay: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey | cmdKey)),
            .previousDisplay: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey | cmdKey)),
        ])
        let reserved = MacOSReservedShortcuts.resolve(symbolicHotKeys: nil)
        for configuration in preferences.shortcuts.values {
            XCTAssertNil(reserved.owner(of: configuration), "\(configuration.displayName) belongs to macOS")
        }

        let encoded = try PropertyListEncoder().encode(preferences)
        let decoded = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: encoded
        )
        XCTAssertEqual(decoded, preferences)
    }

    func testInterimControlOptionDefaultsMigrateWithoutChangingEnablement() {
        var preferences = WindowManagementPreferences(
            shortcutsEnabled: true,
            shortcuts: [
                .leftHalf: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey)),
                .rightHalf: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey)),
                .topHalf: .init(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey)),
                .bottomHalf: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey)),
                .maximize: .init(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey)),
                .minimized: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey)),
                .center: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)),
                .nextDisplay: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey | cmdKey)),
                .previousDisplay: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey | cmdKey)),
            ]
        )

        preferences.migrateInterimDefaultShortcuts()

        XCTAssertTrue(preferences.shortcutsEnabled)
        for action in WindowAction.allCases {
            XCTAssertEqual(preferences.shortcut(for: action), action.defaultShortcut)
        }
    }

    func testCustomizedInterimShortcutSetIsNotOverwritten() {
        var preferences = WindowManagementPreferences(
            shortcuts: [
                .leftHalf: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey)),
                .rightHalf: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey)),
                .topHalf: .init(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey)),
                .bottomHalf: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey)),
                .maximize: .init(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey)),
                .minimized: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey)),
                .center: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)),
                .nextDisplay: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey | cmdKey)),
                .previousDisplay: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey | cmdKey)),
            ]
        )
        let custom = HotKeyConfiguration(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(controlKey | optionKey)
        )
        preferences.shortcuts[.maximize] = custom

        preferences.migrateInterimDefaultShortcuts()

        XCTAssertEqual(preferences.shortcut(for: .maximize), custom)
    }

    func testWindowShortcutReadinessIncludesPermissionAndRegistrationState() {
        XCTAssertEqual(
            WindowShortcutReadiness.resolve(
                enabled: false,
                accessibilityTrusted: false,
                registrationError: nil
            ),
            .disabled
        )
        XCTAssertEqual(
            WindowShortcutReadiness.resolve(
                enabled: true,
                accessibilityTrusted: false,
                registrationError: nil
            ),
            .permissionRequired
        )
        XCTAssertEqual(
            WindowShortcutReadiness.resolve(
                enabled: true,
                accessibilityTrusted: true,
                registrationError: nil
            ),
            .ready
        )
        XCTAssertEqual(
            WindowShortcutReadiness.resolve(
                enabled: true,
                accessibilityTrusted: true,
                registrationError: "Conflict"
            ),
            .registrationFailed("Conflict")
        )
    }

    func testEveryWindowLayoutIsASearchableAccessibilityAction() {
        for action in WindowAction.available {
            let definition = ActionRegistry.definition(id: action.actionID)
            XCTAssertEqual(definition?.title, action.title)
            XCTAssertEqual(definition?.permission, .accessibility)
            XCTAssertTrue(ActionRegistry.defaultEnabledActionIDs.contains(action.actionID))
        }
    }

    /// Arranging every window, automatic tiling, custom layouts, and workspaces are hidden: not
    /// searchable, not runnable, and their saved shortcuts neither register nor block others.
    func testHiddenWindowFeaturesStayOutOfTheWay() throws {
        XCTAssertEqual(
            Set(WindowAction.allCases.filter { !WindowAction.available.contains($0) }),
            [.tileAll, .cascadeAll, .rotateLayout, .retileWindows, .toggleFloating]
        )
        XCTAssertNil(ActionRegistry.definition(id: WindowAction.tileAll.actionID))

        let manager = WindowManager()
        let layout = CustomWindowLayout(name: "Left Wide")
        manager.customLayoutProvider = { _ in layout }
        XCTAssertNil(manager.request(for: .layout(layout.id)))
        XCTAssertNil(manager.request(for: .action(.tileAll)))
        XCTAssertEqual(manager.request(for: .action(.leftHalf)), .action(.leftHalf))

        var preferences = WindowManagementPreferences()
        let shortcut = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey))
        preferences.setShortcut(shortcut, for: .tileAll)
        XCTAssertNil(preferences.owner(of: shortcut, excluding: .action(.leftHalf)))
        XCTAssertFalse(preferences.availableShortcutTargets.contains(.action(.tileAll)))
    }

    func testMacOSShortcutsIncludeDefaultsTheUserNeverChanged() {
        let reserved = MacOSReservedShortcuts.resolve(symbolicHotKeys: nil)
        let screenshot = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(shiftKey | cmdKey))
        XCTAssertEqual(reserved.owner(of: screenshot), "screenshots")
        let forceQuit = HotKeyConfiguration(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey | cmdKey))
        XCTAssertEqual(reserved.owner(of: forceQuit), "Force Quit")
        let leftHalf = HotKeyConfiguration(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey))
        XCTAssertNil(reserved.owner(of: leftHalf))
    }

    /// Keyboard settings stores only what the user changed: a turned-off shortcut is free and
    /// a moved one is reserved at its new keys.
    func testMacOSShortcutsFollowTheUsersKeyboardSettings() {
        let reserved = MacOSReservedShortcuts.resolve(symbolicHotKeys: [
            "30": ["enabled": false],
            "64": ["enabled": true, "value": ["parameters": [32, 49, 1 << 19], "type": "standard"]],
            "60": ["enabled": false, "value": ["parameters": [32, 49, 1 << 18], "type": "standard"]],
        ])
        XCTAssertNil(reserved.owner(of: HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(shiftKey | cmdKey))))
        XCTAssertEqual(reserved.owner(of: HotKeyConfiguration(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))), "Spotlight")
        XCTAssertNil(reserved.owner(of: HotKeyConfiguration(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))))
        XCTAssertNil(reserved.owner(of: HotKeyConfiguration(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey))))
        XCTAssertEqual(
            reserved.owner(of: HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(shiftKey | cmdKey))),
            "screenshots"
        )
    }

    /// The shortcuts saved on the development Mac when the plan was made: the old Command
    /// defaults plus extras on Finder's Home and Close Window keys.
    func testRecommendedShortcutsReplaceConflictingOnes() {
        func key(_ code: Int, _ modifiers: Int) -> HotKeyConfiguration {
            HotKeyConfiguration(keyCode: UInt32(code), modifiers: UInt32(modifiers))
        }
        var preferences = WindowManagementPreferences(
            shortcutsEnabled: true,
            shortcuts: [
                .leftHalf: key(kVK_LeftArrow, cmdKey),
                .rightHalf: key(kVK_RightArrow, cmdKey),
                .maximize: key(kVK_UpArrow, cmdKey),
                .minimized: key(kVK_DownArrow, cmdKey),
                .topHalf: key(kVK_UpArrow, shiftKey | cmdKey),
                .bottomHalf: key(kVK_DownArrow, shiftKey | cmdKey),
                .center: key(kVK_ANSI_C, optionKey | cmdKey),
                .nextDisplay: key(kVK_RightArrow, optionKey | cmdKey),
                .previousDisplay: key(kVK_LeftArrow, optionKey | cmdKey),
                .maximizeHeight: key(kVK_ANSI_H, shiftKey | cmdKey),
                .maximizeWidth: key(kVK_ANSI_W, shiftKey | cmdKey),
                .makeLarger: key(kVK_ANSI_Equal, shiftKey | cmdKey),
                .makeSmaller: key(kVK_ANSI_Minus, shiftKey | cmdKey),
            ],
            unassignedShortcuts: [.restore, .topLeftQuarter]
        )

        preferences.useRecommendedShortcuts(reserved: MacOSReservedShortcuts.resolve(symbolicHotKeys: nil))

        XCTAssertTrue(preferences.shortcutsEnabled)
        for action in [WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .minimized, .center, .nextDisplay, .previousDisplay] {
            XCTAssertEqual(preferences.shortcut(for: action), action.defaultShortcut, "\(action)")
        }
        XCTAssertEqual(preferences.shortcut(for: .maximizeHeight), key(kVK_UpArrow, controlKey | optionKey | shiftKey))
        XCTAssertEqual(preferences.shortcut(for: .maximizeWidth), key(kVK_RightArrow, controlKey | optionKey | shiftKey))
        XCTAssertEqual(preferences.shortcut(for: .makeLarger), key(kVK_ANSI_Equal, controlKey | optionKey))
        XCTAssertEqual(preferences.shortcut(for: .makeSmaller), key(kVK_ANSI_Minus, controlKey | optionKey))
        XCTAssertNil(preferences.shortcut(for: .restore), "Left unassigned")
        XCTAssertNil(preferences.shortcut(for: .topLeftQuarter))
    }

    func testRecommendedShortcutsRemoveOnesMacOSKeeps() {
        let screenshot = HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(shiftKey | cmdKey))
        var preferences = WindowManagementPreferences()
        preferences.setShortcut(screenshot, for: .topLeftQuarter)

        preferences.useRecommendedShortcuts(reserved: MacOSReservedShortcuts.resolve(symbolicHotKeys: nil))

        XCTAssertNil(preferences.shortcut(for: .topLeftQuarter))
    }

    func testRegistrationSummaryNamesShortcutsMacOSKeeps() {
        XCTAssertEqual(
            WindowShortcutRegistrationSummary.message(failedTitles: [], reserved: [("Maximize Height", "screenshots")]),
            "macOS keeps the Maximize Height shortcut for screenshots."
        )
        XCTAssertEqual(
            WindowShortcutRegistrationSummary.message(
                failedTitles: ["Left Half"],
                reserved: [("Maximize Height", "screenshots"), ("Restore Previous Size", "Spotlight")]
            ),
            "The Left Half shortcut is already in use or unavailable. macOS keeps 2 of these shortcuts for itself: Maximize Height, Restore Previous Size."
        )
    }

    func testMacOSTilingChoiceSurvivesSavingAndOlderSettingsDefaultToOff() throws {
        var preferences = WindowManagementPreferences()
        preferences.macOSDragTilingTurnedOffByBroccoli = true
        let decoded = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: PropertyListEncoder().encode(preferences)
        )
        XCTAssertTrue(decoded.macOSDragTilingTurnedOffByBroccoli)

        let older = try PropertyListDecoder().decode(
            WindowManagementPreferences.self,
            from: PropertyListEncoder().encode(["shortcutsEnabled": true])
        )
        XCTAssertFalse(older.macOSDragTilingTurnedOffByBroccoli)
    }

    func testVoiceOverKeysAreControlAndOptionTogether() {
        XCTAssertTrue(HotKeyConfiguration(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey)).usesVoiceOverKeys)
        XCTAssertTrue(HotKeyConfiguration(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey | shiftKey)).usesVoiceOverKeys)
        XCTAssertFalse(HotKeyConfiguration(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey | cmdKey)).usesVoiceOverKeys)
    }

    func testWindowActionTargetsFrontmostExternalApplication() {
        XCTAssertEqual(
            WindowActionTargetResolver.processIdentifier(
                frontmostBundleIdentifier: "com.apple.TextEdit",
                frontmostProcessIdentifier: 42,
                broccoliBundleIdentifier: "dev.gauravpandey.broccoli",
                lastExternalProcessIdentifier: 21
            ),
            42
        )
    }

    func testWindowActionFallsBackAfterSettingsWasFrontmost() {
        XCTAssertEqual(
            WindowActionTargetResolver.processIdentifier(
                frontmostBundleIdentifier: "dev.gauravpandey.broccoli",
                frontmostProcessIdentifier: 99,
                broccoliBundleIdentifier: "dev.gauravpandey.broccoli",
                lastExternalProcessIdentifier: 42
            ),
            42
        )
        XCTAssertEqual(
            WindowActionTargetResolver.processIdentifier(
                frontmostBundleIdentifier: nil,
                frontmostProcessIdentifier: nil,
                broccoliBundleIdentifier: "dev.gauravpandey.broccoli",
                lastExternalProcessIdentifier: 42
            ),
            42
        )
    }

    func testWindowActionSkipsTerminatedAndBroccoliCandidates() {
        XCTAssertEqual(
            WindowActionTargetResolver.processIdentifier(
                candidates: [
                    .init(
                        processIdentifier: 41,
                        bundleIdentifier: "com.example.Terminated",
                        isTerminated: true
                    ),
                    .init(
                        processIdentifier: 99,
                        bundleIdentifier: "dev.gauravpandey.broccoli",
                        isTerminated: false
                    ),
                    .init(
                        processIdentifier: 42,
                        bundleIdentifier: "com.apple.TextEdit",
                        isTerminated: false
                    ),
                ],
                broccoliBundleIdentifier: "dev.gauravpandey.broccoli",
                broccoliProcessIdentifier: 99
            ),
            42
        )
    }

    func testWindowLookupFallsBackToMainWindowWhenFocusIsTemporarilyMissing() throws {
        let application = AXUIElementCreateApplication(100)
        let mainWindow = AXUIElementCreateApplication(200)
        var waitedForRetry = false
        let operation = WindowAccessibilityOperation(
            attributeReader: { element, attribute in
                if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .noValue, value: nil)
                }
                if CFEqual(element, application),
                   CFEqual(attribute, kAXMainWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: mainWindow)
                }
                if CFEqual(element, mainWindow),
                   CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXWindowRole as CFString
                    )
                }
                if CFEqual(element, mainWindow),
                   CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXStandardWindowSubrole as CFString
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            retryWaiter: { _ in waitedForRetry = true }
        )

        let resolved = try operation.resolveFocusedWindow(in: application)

        XCTAssertTrue(CFEqual(resolved, mainWindow))
        XCTAssertFalse(waitedForRetry)
    }

    func testWindowLookupRejectsFocusedDialogWithoutResizingMainWindow() throws {
        let application = AXUIElementCreateApplication(100)
        let dialog = AXUIElementCreateApplication(200)
        let mainWindow = AXUIElementCreateApplication(300)
        var mainWindowReadCount = 0
        let operation = WindowAccessibilityOperation(
            attributeReader: { element, attribute in
                if CFEqual(element, application),
                   CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: dialog)
                }
                if CFEqual(element, application),
                   CFEqual(attribute, kAXMainWindowAttribute as CFString) {
                    mainWindowReadCount += 1
                    return AccessibilityAttributeRead(error: .success, value: mainWindow)
                }
                if CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXWindowRole as CFString
                    )
                }
                if CFEqual(element, dialog),
                   CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXDialogSubrole as CFString
                    )
                }
                if CFEqual(element, mainWindow),
                   CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXStandardWindowSubrole as CFString
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            retryWaiter: { _ in
                XCTFail("A valid main window must not require a retry")
            }
        )

        XCTAssertThrowsError(try operation.resolveFocusedWindow(in: application)) { error in
            guard case WindowManagementError.unsupported = error else {
                return XCTFail("Expected the focused dialog to be rejected, got \(error)")
            }
        }
        XCTAssertEqual(mainWindowReadCount, 0)
    }

    /// A floating panel the user is acting on, such as an inspector, is moved like a window.
    func testWindowLookupAcceptsAFocusedFloatingPanel() throws {
        let application = AXUIElementCreateApplication(100)
        let panel = AXUIElementCreateApplication(200)
        let operation = WindowAccessibilityOperation(
            attributeReader: { element, attribute in
                if CFEqual(element, application), CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: panel)
                }
                if CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: kAXWindowRole as CFString)
                }
                if CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: kAXFloatingWindowSubrole as CFString)
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            }
        )

        XCTAssertTrue(CFEqual(try operation.resolveFocusedWindow(in: application), panel))
    }

    func testAlmostMaximizeCentersBroccoliSettingsInsteadOfMinimizingIt() {
        let screen = CGRect(x: 0, y: 0, width: 1_680, height: 1_050)
        let placed = BroccoliWindowFramePlacement.appKitFrame(
            for: .minimized,
            current: CGRect(x: 100, y: 100, width: 980, height: 680),
            accessibilityScreens: [WindowScreenGeometry.accessibilityFrame(for: screen, primaryScreenFrame: screen)],
            primaryScreenFrame: screen,
            options: .standard,
            keepsSize: true
        )
        XCTAssertEqual(placed?.size, CGSize(width: 980, height: 680))
        XCTAssertEqual(placed?.midX, screen.midX)
    }

    func testWindowLookupRejectsFocusedSheetWithoutResizingMainWindow() throws {
        let application = AXUIElementCreateApplication(100)
        let sheet = AXUIElementCreateApplication(200)
        let mainWindow = AXUIElementCreateApplication(300)
        var mainWindowReadCount = 0
        let operation = WindowAccessibilityOperation(
            attributeReader: { element, attribute in
                if CFEqual(element, application),
                   CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: sheet)
                }
                if CFEqual(element, application),
                   CFEqual(attribute, kAXMainWindowAttribute as CFString) {
                    mainWindowReadCount += 1
                    return AccessibilityAttributeRead(error: .success, value: mainWindow)
                }
                if CFEqual(element, sheet),
                   CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXSheetRole as CFString
                    )
                }
                if CFEqual(element, mainWindow),
                   CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXWindowRole as CFString
                    )
                }
                if CFEqual(element, mainWindow),
                   CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXStandardWindowSubrole as CFString
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            retryWaiter: { _ in
                XCTFail("A valid main window must not require a retry")
            }
        )

        XCTAssertThrowsError(try operation.resolveFocusedWindow(in: application)) { error in
            guard case WindowManagementError.unsupported = error else {
                return XCTFail("Expected the focused sheet to be rejected, got \(error)")
            }
        }
        XCTAssertEqual(mainWindowReadCount, 0)
    }

    func testWindowLookupRetriesTransientAccessibilityServerFailure() throws {
        let application = AXUIElementCreateApplication(100)
        let focusedWindow = AXUIElementCreateApplication(200)
        var focusedReadCount = 0
        var retryCount = 0
        let operation = WindowAccessibilityOperation(
            attributeReader: { element, attribute in
                if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    focusedReadCount += 1
                    return focusedReadCount == 1
                        ? AccessibilityAttributeRead(error: .cannotComplete, value: nil)
                        : AccessibilityAttributeRead(error: .success, value: focusedWindow)
                }
                if CFEqual(element, focusedWindow),
                   CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXWindowRole as CFString
                    )
                }
                if CFEqual(element, focusedWindow),
                   CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXStandardWindowSubrole as CFString
                    )
                }
                return AccessibilityAttributeRead(error: .noValue, value: nil)
            },
            retryWaiter: { _ in retryCount += 1 }
        )

        let resolved = try operation.resolveFocusedWindow(in: application)

        XCTAssertTrue(CFEqual(resolved, focusedWindow))
        XCTAssertEqual(focusedReadCount, 2)
        XCTAssertEqual(retryCount, 1)
    }

    func testWindowLookupStopsAfterOneBoundedRetry() throws {
        let application = AXUIElementCreateApplication(100)
        var focusedReadCount = 0
        var retryCount = 0
        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    focusedReadCount += 1
                    return AccessibilityAttributeRead(error: .cannotComplete, value: nil)
                }
                return AccessibilityAttributeRead(error: .noValue, value: nil)
            },
            retryWaiter: { _ in retryCount += 1 }
        )

        XCTAssertThrowsError(try operation.resolveFocusedWindow(in: application)) { error in
            guard case WindowManagementError.operationFailed(.cannotComplete) = error else {
                return XCTFail("Expected the final Accessibility error, got \(error)")
            }
        }
        XCTAssertEqual(focusedReadCount, 2)
        XCTAssertEqual(retryCount, 1)
    }

    /// A window that is still launching can ignore the first size request. It must get the
    /// layout, not be mistaken for a fixed-size window and centered at its old size.
    func testWindowThatIgnoresOneWidthRequestStillGetsTheLayout() throws {
        let original = CGRect(x: 120, y: 90, width: 1_200, height: 800)
        let target = CGRect(x: 0, y: 30, width: 840, height: 1_020)
        var applied = original
        var sizeWriteCount = 0
        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = applied.origin
                    return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgPoint, &value))
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = applied.size
                    return AccessibilityAttributeRead(error: .success, value: AXValueCreate(.cgSize, &value))
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { _, attribute, value in
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &applied.origin)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    sizeWriteCount += 1
                    if sizeWriteCount > 1 {
                        AXValueGetValue(accessibilityValue, .cgSize, &applied.size)
                    }
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )

        try operation.setFrame(target, of: AXUIElementCreateApplication(100))

        XCTAssertEqual(applied, target)
    }

    func testFrameWriteCentersAPersistentlyClampedWindowAtItsOwnSize() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let original = CGRect(x: 120, y: 90, width: 1_200, height: 800)
        let rejectedSize = CGSize(width: target.width, height: target.height - 80)
        var appliedPosition = original.origin
        var appliedSize = original.size
        var sizeWriteCount = 0

        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = appliedPosition
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgPoint, &value)
                    )
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = appliedSize
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgSize, &value)
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { _, attribute, value in
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedPosition)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var requestedSize = CGSize.zero
                    AXValueGetValue(accessibilityValue, .cgSize, &requestedSize)
                    appliedSize = requestedSize == target.size ? rejectedSize : requestedSize
                    sizeWriteCount += 1
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )

        try operation.setFrame(target, of: window)

        XCTAssertEqual(appliedSize, original.size)
        XCTAssertEqual(appliedPosition, CGPoint(x: 240, y: 140), "Centered in the requested frame")
        XCTAssertEqual(sizeWriteCount, 4, "The layout before and after the move, then its own size the same way")
    }

    /// A newer press replaces a request that has not written anything yet.
    func testCancelledRequestWritesNothing() {
        let window = SimulatedWindow(frame: CGRect(x: 120, y: 90, width: 740, height: 600), screen: Self.simulatedScreen)
        XCTAssertThrowsError(
            try window.makeOperation().setFrame(
                CGRect(x: 0, y: 30, width: 840, height: 1_020),
                of: window.element,
                from: window.frame,
                screen: Self.simulatedScreen,
                incremental: false,
                deadline: ProcessInfo.processInfo.systemUptime + 4,
                checkCancellation: { throw CancellationError() }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(window.writes, [])
    }

    /// Once a request starts writing it finishes, so the window is never left half-placed or
    /// put back where it started.
    func testRequestThatStartedWritingFinishes() throws {
        let window = SimulatedWindow(frame: CGRect(x: 120, y: 90, width: 740, height: 600), screen: Self.simulatedScreen)
        let target = CGRect(x: 0, y: 30, width: 840, height: 1_020)
        var checks = 0
        try window.makeOperation().setFrame(
            target,
            of: window.element,
            from: window.frame,
            screen: Self.simulatedScreen,
            incremental: false,
            deadline: ProcessInfo.processInfo.systemUptime + 4,
            checkCancellation: {
                checks += 1
                if checks > 1 { throw CancellationError() }
            }
        )
        XCTAssertEqual(window.frame, target)
    }

    /// Accessibility answers for Broccoli's own windows on the worker's thread, where AppKit
    /// traps a frame change. The worker must refuse instead of crashing Broccoli.
    func testWindowWorkerNeverTargetsBroccolisOwnWindows() {
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXFocusedApplicationAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: AXUIElementCreateApplication(ownProcess))
                }
                XCTFail("Read \(attribute) from Broccoli's own process")
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { _, attribute, _ in
                XCTFail("Wrote \(attribute) to Broccoli's own process")
                return .success
            },
            messagingTimeoutSetter: { _, _ in .success },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )

        for targetPID in [ownProcess, nil] {
            XCTAssertThrowsError(
                try operation.perform(
                    .leftHalf,
                    targetPID: targetPID,
                    screens: [CGRect(x: 0, y: 30, width: 1_680, height: 1_020)],
                    checkCancellation: {}
                )
            ) { error in
                guard case WindowManagementError.noWindow = error else {
                    return XCTFail("Expected noWindow, got \(error)")
                }
            }
        }
    }

    func testFrameWriteSuspendsEnhancedUserInterfaceThenRestoresIt() throws {
        let original = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let probe = EnhancedUserInterfaceProbe(frame: original, enhancedUserInterface: true)

        try probe.makeOperation().setFrame(target, of: probe.window)

        XCTAssertEqual(probe.appliedFrame, target)
        XCTAssertEqual(probe.enhancedUserInterface, true)
        XCTAssertEqual(probe.enhancedUserInterfaceWrites, [false, true])
        XCTAssertEqual(probe.frameWritesWhileEnhanced, 0)
    }

    func testFrameWriteRestoresEnhancedUserInterfaceWhenWritesReportErrors() throws {
        let original = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let probe = EnhancedUserInterfaceProbe(frame: original, enhancedUserInterface: true)
        probe.enhancedUserInterfaceWriteError = .notImplemented

        try probe.makeOperation().setFrame(target, of: probe.window)

        XCTAssertEqual(probe.appliedFrame, target)
        XCTAssertEqual(probe.enhancedUserInterface, true)
        XCTAssertEqual(probe.enhancedUserInterfaceWrites, [false, true])
    }

    func testFrameWriteRestoresEnhancedUserInterfaceWhenFrameIsRejected() {
        let original = CGRect(x: 120, y: 90, width: 1_200, height: 800)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let probe = EnhancedUserInterfaceProbe(frame: original, enhancedUserInterface: true)
        probe.rejectsFrames = true

        XCTAssertThrowsError(try probe.makeOperation().setFrame(target, of: probe.window))
        XCTAssertEqual(probe.enhancedUserInterface, true)
        XCTAssertEqual(probe.enhancedUserInterfaceWrites, [false, true])
    }

    func testFrameWriteLeavesEnhancedUserInterfaceAloneWhenItIsOff() throws {
        let original = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let probe = EnhancedUserInterfaceProbe(frame: original, enhancedUserInterface: false)

        try probe.makeOperation().setFrame(target, of: probe.window)

        XCTAssertEqual(probe.appliedFrame, target)
        XCTAssertEqual(probe.enhancedUserInterfaceWrites, [])
    }

    func testFrameWriteAcceptsTerminalCharacterGridSnap() throws {
        let original = CGRect(x: 120, y: 90, width: 1_200, height: 800)
        let cases: [(target: CGRect, snapped: CGRect)] = [
            (
                CGRect(x: 84, y: 81, width: 1_512, height: 918),
                CGRect(x: 84, y: 81, width: 1_516, height: 921)
            ),
            (
                CGRect(x: 0, y: 30, width: 1_680, height: 1_020),
                CGRect(x: 0, y: 30, width: 1_681, height: 1_013)
            ),
            (
                CGRect(x: 840, y: 30, width: 840, height: 1_020),
                CGRect(x: 840, y: 30, width: 845, height: 1_013)
            ),
        ]
        for item in cases {
            let probe = FrameWriteProbe(frame: original, snapped: item.snapped)
            let operation = probe.makeOperation()

            XCTAssertNoThrow(try operation.setFrame(item.target, of: AXUIElementCreateApplication(100)))
            XCTAssertEqual(probe.appliedFrame, item.snapped)
            XCTAssertEqual(probe.sizeWriteCount, 2, "Before and after the move")
        }
    }

    func testFrameWriteShiftsSnappedRightHalfOntoTheScreen() throws {
        let original = CGRect(x: 120, y: 90, width: 1_200, height: 800)
        let screen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let target = CGRect(x: 840, y: 30, width: 840, height: 1_020)
        let snapped = CGRect(x: 840, y: 30, width: 845, height: 1_013)
        let probe = FrameWriteProbe(frame: original, snapped: snapped)
        let operation = probe.makeOperation()

        try operation.setFrame(target, of: AXUIElementCreateApplication(100), screen: screen)

        XCTAssertEqual(probe.appliedFrame.origin, CGPoint(x: 835, y: 30))
        XCTAssertEqual(probe.appliedFrame.size, snapped.size)
        XCTAssertEqual(probe.sizeWriteCount, 2)
    }

    func testFrameWriteKeepsCompleteSnapInsteadOfRollingBack() throws {
        let original = CGRect(x: 120, y: 90, width: 1_200, height: 800)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let snapped = CGRect(x: 0, y: 30, width: 1_650, height: 990)
        let probe = FrameWriteProbe(frame: original, snapped: snapped)
        let operation = probe.makeOperation()

        XCTAssertNoThrow(try operation.setFrame(target, of: AXUIElementCreateApplication(100)))
        XCTAssertEqual(probe.appliedFrame, snapped)
        XCTAssertEqual(probe.sizeWriteCount, 2)
    }

    func testFrameWriteSizesBeforeAndAfterTheMove() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        var appliedFrame = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        var writes: [String] = []

        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = appliedFrame.origin
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgPoint, &value)
                    )
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = appliedFrame.size
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgSize, &value)
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { _, attribute, value in
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    writes.append("position")
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedFrame.origin)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    writes.append("size")
                    AXValueGetValue(accessibilityValue, .cgSize, &appliedFrame.size)
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )

        try operation.setFrame(target, of: window)

        XCTAssertEqual(appliedFrame, target)
        XCTAssertEqual(writes, ["size", "position", "size"])
    }

    func testFrameWriteAcceptsHarmlessWindowServerPositionNormalization() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        var appliedFrame = CGRect(x: 100, y: 100, width: 900, height: 700)
        var didWriteSize = false

        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if didWriteSize {
                    appliedFrame = CGRect(
                        x: target.minX,
                        y: target.minY - 7,
                        width: target.width,
                        height: target.height
                    )
                }
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = appliedFrame.origin
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgPoint, &value)
                    )
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = appliedFrame.size
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgSize, &value)
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { _, attribute, value in
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedFrame.origin)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgSize, &appliedFrame.size)
                    didWriteSize = true
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )

        XCTAssertNoThrow(try operation.setFrame(target, of: window))
        XCTAssertEqual(appliedFrame.minY, target.minY - 7)
        XCTAssertEqual(appliedFrame.size, target.size)
    }

    func testAccessibilityWorkerRunsOffMainThreadAndConfiguresTimeout() async throws {
        let window = AXUIElementCreateApplication(200)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        let lock = NSLock()
        var appliedPosition = CGPoint(x: 100, y: 100)
        var appliedSize = CGSize(width: 900, height: 700)
        var observedMainThread = true
        var configuredTimeout: Float?

        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                lock.lock()
                defer { lock.unlock() }
                observedMainThread = observedMainThread && Thread.isMainThread
                if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .success, value: window)
                }
                if CFEqual(attribute, kAXRoleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXWindowRole as CFString
                    )
                }
                if CFEqual(attribute, kAXSubroleAttribute as CFString) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: kAXStandardWindowSubrole as CFString
                    )
                }
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = appliedPosition
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgPoint, &value)
                    )
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = appliedSize
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgSize, &value)
                    )
                }
                return AccessibilityAttributeRead(error: .noValue, value: nil)
            },
            attributeWriter: { _, attribute, value in
                lock.lock()
                defer { lock.unlock() }
                observedMainThread = observedMainThread && Thread.isMainThread
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedPosition)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgSize, &appliedSize)
                    return .success
                }
                return .attributeUnsupported
            },
            messagingTimeoutSetter: { _, timeout in
                lock.lock()
                observedMainThread = observedMainThread && Thread.isMainThread
                configuredTimeout = timeout
                lock.unlock()
                return .success
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )
        let worker = WindowAccessibilityWorker(operation: operation)

        try await worker.perform(.maximize, targetPID: 100, screens: [target])

        let (finalPosition, finalSize, ranOnMainThread, timeout) = lock.withLock {
            (appliedPosition, appliedSize, observedMainThread, configuredTimeout)
        }
        XCTAssertEqual(finalPosition, target.origin)
        XCTAssertEqual(finalSize, target.size)
        XCTAssertFalse(ranOnMainThread)
        XCTAssertEqual(timeout, 0.75)
    }
}

/// An application that, like Firefox-based browsers, accepts frame writes without applying
/// them while AXEnhancedUserInterface is on.
private final class EnhancedUserInterfaceProbe {
    let application = AXUIElementCreateApplication(100)
    var window: AXUIElement { application }
    var appliedFrame: CGRect
    var enhancedUserInterface: Bool
    var rejectsFrames = false
    /// Firefox applies the attribute but answers with this error.
    var enhancedUserInterfaceWriteError: AXError = .success
    var enhancedUserInterfaceWrites: [Bool] = []
    var frameWritesWhileEnhanced = 0

    init(frame: CGRect, enhancedUserInterface: Bool) {
        appliedFrame = frame
        self.enhancedUserInterface = enhancedUserInterface
    }

    func makeOperation() -> WindowAccessibilityOperation {
        WindowAccessibilityOperation(
            attributeReader: { [self] _, attribute in
                if CFEqual(attribute, WindowAccessibilityOperation.enhancedUserInterfaceAttribute) {
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: enhancedUserInterface ? kCFBooleanTrue : kCFBooleanFalse
                    )
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
                if CFEqual(attribute, WindowAccessibilityOperation.enhancedUserInterfaceAttribute) {
                    enhancedUserInterface = (value as? Bool) == true
                    enhancedUserInterfaceWrites.append(enhancedUserInterface)
                    return enhancedUserInterfaceWriteError
                }
                guard !enhancedUserInterface, !rejectsFrames else {
                    if enhancedUserInterface { frameWritesWhileEnhanced += 1 }
                    return .success
                }
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedFrame.origin)
                } else if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgSize, &appliedFrame.size)
                }
                return .success
            },
            messagingTimeoutSetter: { _, _ in .success },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )
    }
}

private final class FrameWriteProbe {
    let original: CGRect
    let snapped: CGRect
    var appliedFrame: CGRect
    var sizeWriteCount = 0

    init(frame: CGRect, snapped: CGRect) {
        original = frame
        self.snapped = snapped
        appliedFrame = frame
    }

    func makeOperation() -> WindowAccessibilityOperation {
        WindowAccessibilityOperation(
            attributeReader: { [self] _, attribute in
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    var value = appliedFrame.origin
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgPoint, &value)
                    )
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var value = appliedFrame.size
                    return AccessibilityAttributeRead(
                        error: .success,
                        value: AXValueCreate(.cgSize, &value)
                    )
                }
                return AccessibilityAttributeRead(error: .attributeUnsupported, value: nil)
            },
            attributeWriter: { [self] _, attribute, value in
                let accessibilityValue = unsafeDowncast(value, to: AXValue.self)
                if CFEqual(attribute, kAXPositionAttribute as CFString) {
                    AXValueGetValue(accessibilityValue, .cgPoint, &appliedFrame.origin)
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var requestedSize = CGSize.zero
                    AXValueGetValue(accessibilityValue, .cgSize, &requestedSize)
                    sizeWriteCount += 1
                    appliedFrame.size = requestedSize == original.size ? requestedSize : snapped.size
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )
    }
}
