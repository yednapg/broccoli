import ApplicationServices
import Carbon
import XCTest
@testable import BroccoliApp

@MainActor
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
            .minimized: .init(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey)),
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

    func testFrameWriteRetriesWhenDockTransitionTemporarilyClampsTheSize() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        var appliedPosition = CGPoint(x: 120, y: 90)
        var appliedSize = CGSize(width: 1_200, height: 800)
        var sizeWriteCount = 0
        var settlementWaitCount = 0

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
                    sizeWriteCount += 1
                    appliedSize = sizeWriteCount == 1
                        ? CGSize(width: requestedSize.width, height: requestedSize.height - 80)
                        : requestedSize
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in
                XCTFail("Successful accessibility reads and writes must not use error retries")
            },
            frameSettlementWaiter: { _ in settlementWaitCount += 1 }
        )

        try operation.setFrame(target, of: window)

        XCTAssertEqual(appliedPosition, target.origin)
        XCTAssertEqual(appliedSize, target.size)
        XCTAssertEqual(sizeWriteCount, 2)
        XCTAssertEqual(settlementWaitCount, 7)
    }

    func testFrameWriteReportsPersistentClampInsteadOfReturningSuccess() throws {
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

        XCTAssertThrowsError(try operation.setFrame(target, of: window)) { error in
            guard case let WindowManagementError.frameRejected(expected, actual) = error else {
                return XCTFail("Expected a rejected frame, got \(error)")
            }
            XCTAssertEqual(expected, target)
            XCTAssertEqual(actual.size, rejectedSize)
        }
        XCTAssertEqual(CGRect(origin: appliedPosition, size: appliedSize), original)
        XCTAssertEqual(sizeWriteCount, 4)
    }

    func testFrameWriteMovesExpandedAxisToDynamicScreenOriginBeforeSizing() throws {
        let window = AXUIElementCreateApplication(100)
        // Use a second MacBook-sized display instead of the development Mac's 1680 x 1050
        // geometry. The behavior must derive entirely from the supplied target frame.
        let target = CGRect(x: 756, y: 26, width: 756, height: 956)
        let original = CGRect(x: 76, y: 74, width: 1_360, height: 860)
        var appliedFrame = original
        var pendingPosition: CGPoint?
        var positionWrites: [CGPoint] = []

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
                    var requestedPosition = CGPoint.zero
                    AXValueGetValue(accessibilityValue, .cgPoint, &requestedPosition)
                    positionWrites.append(requestedPosition)
                    pendingPosition = requestedPosition
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var requestedSize = CGSize.zero
                    AXValueGetValue(accessibilityValue, .cgSize, &requestedSize)
                    let availableHeight = target.maxY - appliedFrame.minY
                    appliedFrame.size = CGSize(
                        width: requestedSize.width,
                        height: min(requestedSize.height, availableHeight)
                    )
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in
                if let pendingPosition {
                    appliedFrame.origin = pendingPosition
                }
                pendingPosition = nil
            }
        )

        try operation.setFrame(target, of: window)

        XCTAssertEqual(appliedFrame, target)
        XCTAssertEqual(positionWrites.first, CGPoint(x: original.minX, y: target.minY))
        XCTAssertEqual(positionWrites.last, target.origin)
    }

    func testFrameWriteShrinksBeforeApplyingFinalPosition() throws {
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
        XCTAssertEqual(writes, ["size", "position"])
    }

    func testFrameWriteAlignsLeftEdgeBeforeExpandingWidth() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 510)
        var appliedFrame = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        var pendingPosition: CGPoint?

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
                    var requestedPosition = CGPoint.zero
                    AXValueGetValue(accessibilityValue, .cgPoint, &requestedPosition)
                    pendingPosition = requestedPosition
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var requestedSize = CGSize.zero
                    AXValueGetValue(accessibilityValue, .cgSize, &requestedSize)
                    appliedFrame.size = CGSize(
                        width: min(requestedSize.width, 1_680 - appliedFrame.minX),
                        height: requestedSize.height
                    )
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in
                if let pendingPosition {
                    appliedFrame.origin = pendingPosition
                }
                pendingPosition = nil
            }
        )

        try operation.setFrame(target, of: window)

        XCTAssertEqual(appliedFrame, target)
    }

    func testFrameWriteWaitsForTargetOwnedAnimationBeforeReapplying() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 0, y: 30, width: 840, height: 1_020)
        let animatedFrames = [
            CGRect(x: 24, y: 54, width: 1_632, height: 972),
            CGRect(x: 18, y: 50, width: 1_400, height: 980),
            CGRect(x: 12, y: 46, width: 1_100, height: 988),
            CGRect(x: 24, y: 54, width: 1_632, height: 972),
            CGRect(x: 24, y: 54, width: 1_632, height: 972),
            CGRect(x: 24, y: 54, width: 1_632, height: 972),
        ]
        var appliedFrame = CGRect(x: 84, y: 81, width: 1_512, height: 918)
        var sizeWriteCount = 0
        var animationReadIndex = 0

        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXPositionAttribute as CFString),
                   sizeWriteCount == 1 {
                    appliedFrame = animatedFrames[min(animationReadIndex, animatedFrames.count - 1)]
                    animationReadIndex += 1
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
                    var position = CGPoint.zero
                    AXValueGetValue(accessibilityValue, .cgPoint, &position)
                    appliedFrame.origin = position
                    return .success
                }
                if CFEqual(attribute, kAXSizeAttribute as CFString) {
                    var size = CGSize.zero
                    AXValueGetValue(accessibilityValue, .cgSize, &size)
                    appliedFrame.size = size
                    sizeWriteCount += 1
                    return .success
                }
                return .attributeUnsupported
            },
            retryWaiter: { _ in },
            frameSettlementWaiter: { _ in }
        )

        try operation.setFrame(target, of: window)

        XCTAssertEqual(appliedFrame, target)
        XCTAssertEqual(sizeWriteCount, 2)
        XCTAssertGreaterThanOrEqual(animationReadIndex, 5)
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
