import Carbon
import XCTest
@testable import BroccoliApp

final class WindowManagementTests: XCTestCase {
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
            .leftHalf: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey)),
            .rightHalf: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey)),
            .topHalf: .init(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey | cmdKey)),
            .bottomHalf: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(optionKey | cmdKey)),
            .maximize: .init(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey)),
            .center: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | cmdKey)),
            .nextDisplay: .init(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | cmdKey)),
            .previousDisplay: .init(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey | cmdKey)),
        ])

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
        for action in WindowAction.allCases {
            let definition = ActionRegistry.definition(id: action.actionID)
            XCTAssertEqual(definition?.title, action.title)
            XCTAssertEqual(definition?.permission, .accessibility)
            XCTAssertTrue(ActionRegistry.defaultEnabledActionIDs.contains(action.actionID))
        }
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
}
