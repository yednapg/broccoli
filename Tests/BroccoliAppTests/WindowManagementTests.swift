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
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    return AccessibilityAttributeRead(error: .noValue, value: nil)
                }
                return AccessibilityAttributeRead(error: .success, value: mainWindow)
            },
            retryWaiter: { _ in waitedForRetry = true }
        )

        let resolved = try operation.resolveFocusedWindow(in: application)

        XCTAssertTrue(CFEqual(resolved, mainWindow))
        XCTAssertFalse(waitedForRetry)
    }

    func testWindowLookupRetriesTransientAccessibilityServerFailure() throws {
        let application = AXUIElementCreateApplication(100)
        let focusedWindow = AXUIElementCreateApplication(200)
        var focusedReadCount = 0
        var retryCount = 0
        let operation = WindowAccessibilityOperation(
            attributeReader: { _, attribute in
                if CFEqual(attribute, kAXFocusedWindowAttribute as CFString) {
                    focusedReadCount += 1
                    return focusedReadCount == 1
                        ? AccessibilityAttributeRead(error: .cannotComplete, value: nil)
                        : AccessibilityAttributeRead(error: .success, value: focusedWindow)
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
        XCTAssertEqual(settlementWaitCount, 1)
    }

    func testFrameWriteReportsPersistentClampInsteadOfReturningSuccess() throws {
        let window = AXUIElementCreateApplication(100)
        let target = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
        var appliedPosition = target.origin
        var appliedSize = CGSize(width: target.width, height: target.height - 80)
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
                    appliedSize = CGSize(
                        width: requestedSize.width,
                        height: requestedSize.height - 80
                    )
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
            XCTAssertEqual(actual.size, appliedSize)
        }
        XCTAssertEqual(sizeWriteCount, 3)
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
            actionPerformer: { _, _ in
                lock.lock()
                observedMainThread = observedMainThread && Thread.isMainThread
                lock.unlock()
                return .success
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
        XCTAssertEqual(timeout, 0.35)
    }
}
