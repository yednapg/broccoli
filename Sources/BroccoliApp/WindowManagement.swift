@preconcurrency import AppKit
import ApplicationServices
import BroccoliCore
import Foundation
import OSLog

enum WindowManagementPermissionPresentation {
    static var settingsName: String {
        settingsName(forMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    static func settingsName(forMajorVersion majorVersion: Int) -> String {
        majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
}

enum AccessibilityPermissionChecker {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func request() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum WindowShortcutReadiness: Equatable, Sendable {
    case disabled
    case permissionRequired
    case ready
    case registrationFailed(String)

    static func resolve(
        enabled: Bool,
        accessibilityTrusted: Bool,
        registrationError: String?
    ) -> Self {
        if let registrationError, !registrationError.isEmpty {
            return .registrationFailed(registrationError)
        }
        guard enabled else { return .disabled }
        guard accessibilityTrusted else { return .permissionRequired }
        return .ready
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .disabled: "pause.circle.fill"
        case .permissionRequired, .registrationFailed: "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .disabled: "Shortcuts off"
        case .permissionRequired: "Access not active"
        case .ready: "Shortcuts ready"
        case .registrationFailed: "Shortcut unavailable"
        }
    }

    var subtitle: String {
        switch self {
        case .disabled: "Enable shortcuts to use them from other applications"
        case .permissionRequired:
            "Refresh window-control access before using global shortcuts"
        case .ready: "Available globally"
        case .registrationFailed(let message): message
        }
    }

}

enum WindowManagementError: LocalizedError {
    case accessibilityRequired
    case noWindow
    case unsupported
    case timedOut
    case frameRejected(expected: CGRect, actual: CGRect)
    case operationFailed(AXError)

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Window management needs active Broccoli access in \(WindowManagementPermissionPresentation.settingsName)."
        case .noWindow:
            "Broccoli could not find a window to move."
        case .unsupported:
            "This window does not support moving or resizing."
        case .timedOut:
            "The application did not respond to the window request in time."
        case .frameRejected:
            "The application kept a different window size than Broccoli requested."
        case .operationFailed(let error):
            "macOS could not update this window (Accessibility error \(error.rawValue))."
        }
    }
}

enum WindowScreenGeometry {
    enum DockPosition: String, Sendable {
        case bottom
        case left
        case right
    }

    static func usableAppKitFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        dockAutoHides: Bool,
        dockPosition: DockPosition = .bottom
    ) -> CGRect {
        guard dockAutoHides else { return visibleFrame }

        // visibleFrame can temporarily retain the auto-hidden Dock's last onscreen inset.
        // Reclaim only the configured Dock edge; preserving every other inset avoids covering
        // the menu bar, Stage Manager strip, or other system-reserved screen space.
        switch dockPosition {
        case .bottom:
            return CGRect(
                x: visibleFrame.minX,
                y: screenFrame.minY,
                width: visibleFrame.width,
                height: max(0, visibleFrame.maxY - screenFrame.minY)
            )
        case .left:
            return CGRect(
                x: screenFrame.minX,
                y: visibleFrame.minY,
                width: max(0, visibleFrame.maxX - screenFrame.minX),
                height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: max(0, screenFrame.maxX - visibleFrame.minX),
                height: visibleFrame.height
            )
        }
    }

    static func accessibilityFrame(
        for appKitFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: primaryScreenFrame.maxY - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    static func originFittingSnappedFrame(
        applied: CGRect,
        screen: CGRect
    ) -> CGPoint {
        var origin = applied.origin
        // A terminal-style resize increment can grow a right-aligned window past the screen
        // edge. Shift inward only when that move stays on the opposite edge; do not push a
        // left-aligned maximize one pixel offscreen to chase a one-pixel overflow, and do not
        // fight window-server origin normalization of a few points.
        if applied.maxX > screen.maxX, applied.minX > screen.minX {
            origin.x = max(screen.minX, screen.maxX - applied.width)
        }
        if applied.maxY > screen.maxY, applied.minY > screen.minY {
            origin.y = max(screen.minY, screen.maxY - applied.height)
        }
        return origin
    }
}

struct DockPreferenceSnapshot: Sendable {
    let autoHides: Bool
    let position: WindowScreenGeometry.DockPosition

    static var current: Self {
        // Read both values for every action so Dock changes take effect without restarting this
        // always-running accessory application.
        let applicationID = "com.apple.dock" as CFString
        let autoHides = (
            CFPreferencesCopyAppValue("autohide" as CFString, applicationID) as? NSNumber
        )?.boolValue ?? false
        let rawPosition = (
            CFPreferencesCopyAppValue("orientation" as CFString, applicationID) as? String
        ) ?? WindowScreenGeometry.DockPosition.bottom.rawValue
        return Self(
            autoHides: autoHides,
            position: WindowScreenGeometry.DockPosition(rawValue: rawPosition) ?? .bottom
        )
    }
}

struct WindowActionTargetCandidate: Equatable, Sendable {
    let processIdentifier: pid_t?
    let bundleIdentifier: String?
    let isTerminated: Bool
}

enum WindowActionTargetResolver {
    static func processIdentifier(
        candidates: [WindowActionTargetCandidate],
        broccoliBundleIdentifier: String?,
        broccoliProcessIdentifier: pid_t?
    ) -> pid_t? {
        candidates.lazy.compactMap { candidate -> pid_t? in
            guard !candidate.isTerminated,
                  let processIdentifier = candidate.processIdentifier,
                  processIdentifier > 0,
                  processIdentifier != broccoliProcessIdentifier,
                  candidate.bundleIdentifier != broccoliBundleIdentifier else { return nil }
            return processIdentifier
        }.first
    }

    // Retained for deterministic compatibility tests and callers that only have PID metadata.
    static func processIdentifier(
        frontmostBundleIdentifier: String?,
        frontmostProcessIdentifier: pid_t?,
        broccoliBundleIdentifier: String?,
        lastExternalProcessIdentifier: pid_t?
    ) -> pid_t? {
        processIdentifier(
            candidates: [
                WindowActionTargetCandidate(
                    processIdentifier: frontmostProcessIdentifier,
                    bundleIdentifier: frontmostBundleIdentifier,
                    isTerminated: false
                ),
                WindowActionTargetCandidate(
                    processIdentifier: lastExternalProcessIdentifier,
                    bundleIdentifier: nil,
                    isTerminated: false
                ),
            ],
            broccoliBundleIdentifier: broccoliBundleIdentifier,
            broccoliProcessIdentifier: nil
        )
    }
}

struct AccessibilityAttributeRead {
    let error: AXError
    let value: CFTypeRef?
}

final class WindowAccessibilityOperation: @unchecked Sendable {
    typealias AttributeReader = (AXUIElement, CFString) -> AccessibilityAttributeRead
    typealias AttributeWriter = (AXUIElement, CFString, CFTypeRef) -> AXError
    typealias MessagingTimeoutSetter = (AXUIElement, Float) -> AXError
    typealias RetryWaiter = (Int) -> Void
    typealias FrameSettlementWaiter = (Int) -> Void
    typealias UptimeProvider = () -> TimeInterval

    private static let maximumAccessibilityAttempts = 2
    private static let maximumFrameApplicationAttempts = 3
    private static let maximumFrameStabilityPolls = 10
    private static let requiredStableFrameSamples = 2
    private static let frameOriginTolerance: CGFloat = 8
    // Terminal, iTerm, and similar grid-snapping windows round to a character cell. A typical
    // cell is about 7–16 pt; keep this large enough to accept that rounding without treating an
    // 80 pt one-axis clamp as success.
    private static let frameSizeTolerance: CGFloat = 24
    private static let frameStabilityTolerance: CGFloat = 1

    enum WindowCandidateResolution {
        case accepted
        case rejected
        case failed(AXError)
    }

    typealias OnScreenWindowProvider = () -> [OnScreenWindow]
    typealias ActionPerformer = (AXUIElement, CFString) -> AXError
    typealias SettableChecker = (AXUIElement, CFString) -> Bool

    let attributeReader: AttributeReader
    let attributeWriter: AttributeWriter
    let messagingTimeoutSetter: MessagingTimeoutSetter
    private let retryWaiter: RetryWaiter
    let frameSettlementWaiter: FrameSettlementWaiter
    let uptimeProvider: UptimeProvider
    let messagingTimeout: Float
    let actionTimeout: TimeInterval
    let onScreenWindows: OnScreenWindowProvider
    let actionPerformer: ActionPerformer
    let settableChecker: SettableChecker
    /// Only touched on the worker's serial queue.
    let history = WindowHistory()
    let tiling = TilingState()

    init(
        attributeReader: @escaping AttributeReader = { element, attribute in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute, &value)
            return AccessibilityAttributeRead(error: error, value: value)
        },
        attributeWriter: @escaping AttributeWriter = { element, attribute, value in
            AXUIElementSetAttributeValue(element, attribute, value)
        },
        messagingTimeoutSetter: @escaping MessagingTimeoutSetter = { element, timeout in
            AXUIElementSetMessagingTimeout(element, timeout)
        },
        retryWaiter: @escaping RetryWaiter = { attempt in
            Thread.sleep(forTimeInterval: 0.04 * Double(attempt))
        },
        frameSettlementWaiter: @escaping FrameSettlementWaiter = { _ in
            Thread.sleep(forTimeInterval: 0.08)
        },
        uptimeProvider: @escaping UptimeProvider = { ProcessInfo.processInfo.systemUptime },
        messagingTimeout: Float = 0.75,
        actionTimeout: TimeInterval = 4,
        onScreenWindows: @escaping OnScreenWindowProvider = OnScreenWindow.current,
        actionPerformer: @escaping ActionPerformer = { element, action in
            AXUIElementPerformAction(element, action)
        },
        settableChecker: @escaping SettableChecker = { element, attribute in
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
        }
    ) {
        self.attributeReader = attributeReader
        self.attributeWriter = attributeWriter
        self.messagingTimeoutSetter = messagingTimeoutSetter
        self.retryWaiter = retryWaiter
        self.frameSettlementWaiter = frameSettlementWaiter
        self.uptimeProvider = uptimeProvider
        self.messagingTimeout = messagingTimeout
        self.actionTimeout = actionTimeout
        self.onScreenWindows = onScreenWindows
        self.actionPerformer = actionPerformer
        self.settableChecker = settableChecker
    }

    func perform(
        _ action: WindowAction,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions = .standard,
        checkCancellation: () throws -> Void
    ) throws {
        try perform(
            .action(action),
            targetPID: targetPID,
            screens: screens,
            options: options,
            pointerScreenIndex: nil,
            checkCancellation: checkCancellation
        )
    }

    func perform(
        _ request: WindowRequest,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions,
        pointerScreenIndex: Int?,
        checkCancellation: () throws -> Void
    ) throws {
        guard !screens.isEmpty else { throw WindowManagementError.unsupported }
        switch request {
        case .workspace(let workspace):
            try applyWorkspace(workspace, screens: screens, checkCancellation: checkCancellation)
            return
        case .action(let action):
            switch action.group {
            case .arrange:
                try arrange(
                    action,
                    targetPID: targetPID,
                    screens: screens,
                    options: options,
                    pointerScreenIndex: pointerScreenIndex,
                    checkCancellation: checkCancellation
                )
                return
            case .tiling:
                try performTilingCommand(
                    action,
                    targetPID: targetPID,
                    screens: screens,
                    options: options,
                    checkCancellation: checkCancellation
                )
                return
            case .halvesAndQuarters, .thirds, .fillAndCenter,
                 .resize, .displays:
                break
            }
        case .frame:
            break
        }

        let deadline = uptimeProvider() + actionTimeout
        let window = try focusedWindow(
            targetPID: targetPID,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        let currentFrame = try frame(
            of: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        let currentScreenIndex = Self.screenIndex(containing: currentFrame, in: screens)
        let key = WindowKey(window)
        let stored = history.entry(for: key)
        // A window the user moved by hand since Broccoli last placed it starts a new history,
        // so a repeated press or Restore never acts on a stale frame.
        let continuing = stored.map {
            Self.framesMatch($0.lastApplied, currentFrame, originTolerance: 2, sizeTolerance: 2)
        } ?? false

        var targetFrame: CGRect
        var layoutScreen = screens[currentScreenIndex]
        var appliedAction: WindowAction?
        var cycleIndex = 0
        switch request {
        case .frame(let spec):
            targetFrame = WindowGeometry.frame(for: spec, window: currentFrame, screen: layoutScreen, options: options)
        case .workspace:
            return
        case .action(let action):
            appliedAction = action
            switch action {
            case .restore:
                guard let stored else { return }
                targetFrame = stored.restoreFrame
                layoutScreen = screens[Self.screenIndex(containing: targetFrame, in: screens)]
            case .nextDisplay, .previousDisplay:
                guard screens.count > 1 else { return }
                let offset = action == .nextDisplay ? 1 : -1
                let destinationIndex = (currentScreenIndex + offset + screens.count) % screens.count
                layoutScreen = screens[destinationIndex]
                targetFrame = WindowGeometry.movedFrame(
                    window: currentFrame,
                    from: screens[currentScreenIndex],
                    to: layoutScreen
                )
            default:
                if continuing, let stored, stored.lastAction == action,
                   options.repeatBehavior == .cycleSizes, action.cyclesSize {
                    cycleIndex = (stored.cycleIndex + 1) % WindowGeometry.cycleFractions.count
                }
                appliedAction = action
                targetFrame = WindowGeometry.frame(
                    for: action,
                    window: currentFrame,
                    screen: layoutScreen,
                    options: options,
                    cycleFraction: WindowGeometry.cycleFractions[cycleIndex]
                )
            }
        }

        // A step action at its limit, or a layout the window already has, needs no write.
        guard !Self.framesMatch(
            targetFrame,
            currentFrame,
            originTolerance: 0.5,
            sizeTolerance: 0.5
        ) else { return }
        try setFrame(
            targetFrame,
            of: window,
            screen: layoutScreen,
            acceptsPartialAxis: request.isIncremental,
            deadline: deadline,
            checkCancellation: checkCancellation
        )

        if appliedAction == .restore {
            history.remove(key)
            return
        }
        let applied = (try? frame(of: window, deadline: deadline, checkCancellation: {})) ?? targetFrame
        history.record(
            WindowHistory.Entry(
                restoreFrame: continuing ? (stored?.restoreFrame ?? currentFrame) : currentFrame,
                lastApplied: applied,
                lastAction: appliedAction,
                cycleIndex: cycleIndex
            ),
            for: key
        )
    }

    static func screenIndex(containing frame: CGRect, in screens: [CGRect]) -> Int {
        screens.indices.max { left, right in
            frame.intersection(screens[left]).area < frame.intersection(screens[right]).area
        } ?? 0
    }

    func focusedWindow(
        targetPID: pid_t?,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> AXUIElement {
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let system = AXUIElementCreateSystemWide()
        let timeoutError = messagingTimeoutSetter(system, messagingTimeout)
        guard timeoutError == .success else {
            throw WindowManagementError.operationFailed(timeoutError)
        }
        return try focusedWindow(
            targetPID: targetPID,
            systemElement: system,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
    }

    private func focusedWindow(
        targetPID: pid_t?,
        systemElement: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> AXUIElement {
        let application: AXUIElement
        if let targetPID {
            application = AXUIElementCreateApplication(targetPID)
        } else {
            let value: CFTypeRef
            do {
                value = try readRequiredAttribute(
                    kAXFocusedApplicationAttribute as CFString,
                    from: systemElement,
                    deadline: deadline,
                    checkCancellation: checkCancellation
                )
            } catch WindowManagementError.unsupported {
                throw WindowManagementError.noWindow
            }
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                throw WindowManagementError.noWindow
            }
            application = unsafeDowncast(value, to: AXUIElement.self)
        }

        return try resolveFocusedWindow(
            in: application,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
    }

    func resolveFocusedWindow(in application: AXUIElement) throws -> AXUIElement {
        try resolveFocusedWindow(
            in: application,
            deadline: uptimeProvider() + actionTimeout,
            checkCancellation: {}
        )
    }

    private func resolveFocusedWindow(
        in application: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> AXUIElement {
        // Launcher dismissal and application activation can briefly clear AXFocusedWindow or
        // make the target's accessibility server report that it cannot complete a request.
        // AXMainWindow remains the safest fallback; the worker performs one bounded retry.
        var finalErrors: [AXError] = []

        for attempt in 1...Self.maximumAccessibilityAttempts {
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            finalErrors.removeAll(keepingCapacity: true)
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                try checkReady(deadline: deadline, checkCancellation: checkCancellation)
                let read = attributeReader(application, attribute as CFString)
                try checkReady(deadline: deadline, checkCancellation: checkCancellation)
                if read.error == .success,
                   let value = read.value,
                   CFGetTypeID(value) == AXUIElementGetTypeID() {
                    let candidate = unsafeDowncast(value, to: AXUIElement.self)
                    switch try windowCandidateResolution(
                        candidate,
                        deadline: deadline,
                        checkCancellation: checkCancellation
                    ) {
                    case .accepted:
                        return candidate
                    case .rejected:
                        // Sheets, dialogs, popovers, and other transient surfaces can expose
                        // writable position and size attributes while still enforcing their own
                        // geometry. Do not resize the main window behind a modal surface: AppKit
                        // can accept only one dimension and leave the window half-resized.
                        if attribute == kAXFocusedWindowAttribute {
                            throw WindowManagementError.unsupported
                        }
                        finalErrors.append(.attributeUnsupported)
                    case .failed(let error):
                        finalErrors.append(error)
                    }
                    continue
                }
                finalErrors.append(read.error == .success ? .noValue : read.error)
            }

            guard attempt < Self.maximumAccessibilityAttempts,
                  finalErrors.contains(where: Self.isRetryable) else { break }
            retryWaiter(attempt)
        }

        if let error = finalErrors.first(where: { !Self.representsMissingWindow($0) }) {
            throw WindowManagementError.operationFailed(error)
        }
        throw WindowManagementError.noWindow
    }

    func windowCandidateResolution(
        _ window: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> WindowCandidateResolution {
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let role = attributeReader(window, kAXRoleAttribute as CFString)
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        guard role.error == .success else {
            return Self.representsMissingWindow(role.error) ? .rejected : .failed(role.error)
        }
        guard let roleValue = role.value,
              CFGetTypeID(roleValue) == CFStringGetTypeID(),
              CFEqual(roleValue, kAXWindowRole as CFString) else {
            return .rejected
        }

        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let subrole = attributeReader(window, kAXSubroleAttribute as CFString)
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        guard subrole.error == .success else {
            // AXWindow is sufficient for applications that do not publish a subrole. Known
            // transient AppKit surfaces do publish AXDialog/AXSystemDialog/AXFloatingWindow.
            return Self.representsMissingWindow(subrole.error) ? .accepted : .failed(subrole.error)
        }
        guard let subroleValue = subrole.value,
              CFGetTypeID(subroleValue) == CFStringGetTypeID() else {
            return .accepted
        }
        return CFEqual(subroleValue, kAXStandardWindowSubrole as CFString)
            ? .accepted
            : .rejected
    }

    func frame(
        of window: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> CGRect {
        let positionValue = try readRequiredAttribute(
            kAXPositionAttribute as CFString,
            from: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        let sizeValue = try readRequiredAttribute(
            kAXSizeAttribute as CFString,
            from: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        var position = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else {
            throw WindowManagementError.unsupported
        }
        return CGRect(origin: position, size: size)
    }

    func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        screen: CGRect? = nil,
        acceptsPartialAxis: Bool = false
    ) throws {
        try setFrame(
            frame,
            of: window,
            screen: screen ?? frame,
            acceptsPartialAxis: acceptsPartialAxis,
            deadline: uptimeProvider() + actionTimeout,
            checkCancellation: {}
        )
    }

    /// `acceptsPartialAxis` keeps a result where the application honored only one axis. A
    /// step resize at an application's minimum width should still change the height; a
    /// layout such as Left Half must not be left half-applied.
    func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        screen: CGRect,
        acceptsPartialAxis: Bool,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagementError.unsupported
        }

        let originalFrame = try self.frame(
            of: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        var finalAppliedFrame = originalFrame
        var previousAttemptFrame: CGRect?
        for attempt in 1...Self.maximumFrameApplicationAttempts {
            let expandsWidth = frame.width > finalAppliedFrame.width + Self.frameSizeTolerance
            let expandsHeight = frame.height > finalAppliedFrame.height + Self.frameSizeTolerance
            if expandsWidth || expandsHeight {
                // AX size changes grow from the current top-left corner. Move each expanding
                // axis to its destination edge first so the target application measures the
                // available space from the actual screen boundary. Keep a shrinking axis where
                // it is until after the size change to avoid temporarily pushing it offscreen.
                var stagingPosition = CGPoint(
                    x: expandsWidth ? frame.minX : finalAppliedFrame.minX,
                    y: expandsHeight ? frame.minY : finalAppliedFrame.minY
                )
                guard let stagingPositionValue = AXValueCreate(.cgPoint, &stagingPosition) else {
                    throw WindowManagementError.unsupported
                }
                try writeAttribute(
                    kAXPositionAttribute as CFString,
                    value: stagingPositionValue,
                    to: window,
                    deadline: deadline,
                    checkCancellation: checkCancellation
                )
                frameSettlementWaiter(0)
                try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            }
            try writeAttribute(
                kAXSizeAttribute as CFString,
                value: sizeValue,
                to: window,
                deadline: deadline,
                checkCancellation: checkCancellation
            )
            // Size changes can preserve a different edge depending on the target application.
            // Always finish with the requested top-left origin after the new size is in place.
            try writeAttribute(
                kAXPositionAttribute as CFString,
                value: positionValue,
                to: window,
                deadline: deadline,
                checkCancellation: checkCancellation
            )

            // A successful AX write only means that the target accepted the message. AppKit or
            // the target can still animate or restore a different frame on a later run-loop
            // turn, so confirm the result twice instead of trusting an immediate readback.
            frameSettlementWaiter(0)
            finalAppliedFrame = try self.frame(
                of: window,
                deadline: deadline,
                checkCancellation: checkCancellation
            )
            if Self.framesApproximatelyMatch(finalAppliedFrame, frame) {
                frameSettlementWaiter(1)
                finalAppliedFrame = try self.frame(
                    of: window,
                    deadline: deadline,
                    checkCancellation: checkCancellation
                )
                if Self.framesApproximatelyMatch(finalAppliedFrame, frame) {
                    applyFittedOrigin(
                        applied: finalAppliedFrame,
                        screen: screen,
                        of: window,
                        deadline: deadline,
                        checkCancellation: checkCancellation
                    )
                    return
                }
            }
            guard attempt < Self.maximumFrameApplicationAttempts else { break }

            // Do not fight a target-owned launch or layout animation with rapid writes. Wait
            // until its frame is quiet, then reapply the user's newest requested layout.
            finalAppliedFrame = try waitForStableFrame(
                of: window,
                startingAt: finalAppliedFrame,
                deadline: deadline,
                checkCancellation: checkCancellation
            )
            if let previousAttemptFrame,
               Self.framesMatch(
                finalAppliedFrame,
                previousAttemptFrame,
                originTolerance: Self.frameStabilityTolerance,
                sizeTolerance: Self.frameStabilityTolerance
               ) {
                // The target is rounding or clamping to the same frame on every write. Further
                // attempts only jitter the window.
                break
            }
            previousAttemptFrame = finalAppliedFrame
        }

        if Self.framesApproximatelyMatch(finalAppliedFrame, frame) {
            applyFittedOrigin(
                applied: finalAppliedFrame,
                screen: screen,
                of: window,
                deadline: deadline,
                checkCancellation: checkCancellation
            )
            return
        }
        if Self.framesMatch(
            finalAppliedFrame,
            originalFrame,
            originTolerance: Self.frameStabilityTolerance,
            sizeTolerance: Self.frameStabilityTolerance
        ) {
            throw WindowManagementError.frameRejected(expected: frame, actual: finalAppliedFrame)
        }
        if !acceptsPartialAxis, Self.isPartialAxisFailure(expected: frame, actual: finalAppliedFrame) {
            restoreFrame(
                originalFrame,
                of: window,
                deadline: deadline,
                checkCancellation: checkCancellation
            )
            throw WindowManagementError.frameRejected(expected: frame, actual: finalAppliedFrame)
        }
        applyFittedOrigin(
            applied: finalAppliedFrame,
            screen: screen,
            of: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
    }

    private func applyFittedOrigin(
        applied: CGRect,
        screen: CGRect,
        of window: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) {
        let origin = WindowScreenGeometry.originFittingSnappedFrame(
            applied: applied,
            screen: screen
        )
        guard abs(origin.x - applied.minX) > 0.5 || abs(origin.y - applied.minY) > 0.5 else {
            return
        }
        var position = origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else { return }
        try? writeAttribute(
            kAXPositionAttribute as CFString,
            value: positionValue,
            to: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        frameSettlementWaiter(0)
    }

    private func restoreFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }

        // A failed target frame may still have changed one dimension. Best-effort rollback keeps
        // that partial result from becoming the user's new window geometry.
        try? writeAttribute(
            kAXSizeAttribute as CFString,
            value: sizeValue,
            to: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        try? writeAttribute(
            kAXPositionAttribute as CFString,
            value: positionValue,
            to: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
    }

    private func waitForStableFrame(
        of window: AXUIElement,
        startingAt initialFrame: CGRect,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> CGRect {
        var previousFrame = initialFrame
        var stableSampleCount = 0

        for poll in 1...Self.maximumFrameStabilityPolls {
            frameSettlementWaiter(poll)
            let currentFrame = try frame(
                of: window,
                deadline: deadline,
                checkCancellation: checkCancellation
            )
            if Self.framesMatch(
                currentFrame,
                previousFrame,
                originTolerance: Self.frameStabilityTolerance,
                sizeTolerance: Self.frameStabilityTolerance
            ) {
                stableSampleCount += 1
                if stableSampleCount >= Self.requiredStableFrameSamples { return currentFrame }
            } else {
                stableSampleCount = 0
            }
            previousFrame = currentFrame
        }
        return previousFrame
    }

    private static func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        framesMatch(
            lhs,
            rhs,
            originTolerance: frameOriginTolerance,
            sizeTolerance: frameSizeTolerance
        )
    }

    private static func isPartialAxisFailure(expected: CGRect, actual: CGRect) -> Bool {
        let widthMatches = abs(actual.width - expected.width) <= frameSizeTolerance
        let heightMatches = abs(actual.height - expected.height) <= frameSizeTolerance
        return widthMatches != heightMatches
    }

    static func framesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        originTolerance: CGFloat,
        sizeTolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= originTolerance
            && abs(lhs.minY - rhs.minY) <= originTolerance
            && abs(lhs.width - rhs.width) <= sizeTolerance
            && abs(lhs.height - rhs.height) <= sizeTolerance
    }

    func readRequiredAttribute(
        _ attribute: CFString,
        from element: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> CFTypeRef {
        var finalError = AXError.noValue
        for attempt in 1...Self.maximumAccessibilityAttempts {
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            let read = attributeReader(element, attribute)
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            if read.error == .success, let value = read.value { return value }
            finalError = read.error == .success ? .noValue : read.error
            guard attempt < Self.maximumAccessibilityAttempts,
                  Self.isRetryable(finalError) else { break }
            retryWaiter(attempt)
        }
        if Self.representsMissingWindow(finalError) { throw WindowManagementError.unsupported }
        throw WindowManagementError.operationFailed(finalError)
    }

    func writeAttribute(
        _ attribute: CFString,
        value: CFTypeRef,
        to element: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws {
        var finalError = AXError.failure
        for attempt in 1...Self.maximumAccessibilityAttempts {
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            finalError = attributeWriter(element, attribute, value)
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            if finalError == .success { return }
            guard attempt < Self.maximumAccessibilityAttempts,
                  Self.isRetryable(finalError) else { break }
            retryWaiter(attempt)
        }
        throw WindowManagementError.operationFailed(finalError)
    }

    func checkReady(
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws {
        try checkCancellation()
        guard uptimeProvider() < deadline else { throw WindowManagementError.timedOut }
    }

    private static func isRetryable(_ error: AXError) -> Bool {
        switch error {
        case .cannotComplete, .failure, .noValue:
            true
        default:
            false
        }
    }

    private static func representsMissingWindow(_ error: AXError) -> Bool {
        switch error {
        case .success, .noValue, .attributeUnsupported:
            true
        default:
            false
        }
    }

}

/// Tracks which queued window requests may still run. A layout supersedes every earlier
/// request; a step action queues behind them so repeated presses each apply. All state is
/// read and written only while holding `lock`.
final class WindowActionRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var latestRequest: UInt64 = 0
    private var supersededThrough: UInt64 = 0
    private var cancelledRequests: Set<UInt64> = []

    func begin(supersedingEarlierRequests: Bool) -> UInt64 {
        lock.withLock {
            latestRequest += 1
            if supersedingEarlierRequests {
                supersededThrough = latestRequest - 1
                cancelledRequests = cancelledRequests.filter { $0 > supersededThrough }
            }
            return latestRequest
        }
    }

    func cancel(_ request: UInt64) {
        lock.withLock {
            guard request > supersededThrough else { return }
            _ = cancelledRequests.insert(request)
        }
    }

    func finish(_ request: UInt64) {
        lock.withLock { _ = cancelledRequests.remove(request) }
    }

    func check(_ request: UInt64) throws {
        let isActive = lock.withLock {
            request > supersededThrough && !cancelledRequests.contains(request)
        }
        guard isActive else { throw CancellationError() }
    }
}

final class WindowAccessibilityWorker: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "dev.gauravpandey.broccoli.window-accessibility",
        qos: .userInteractive
    )
    private let operation: WindowAccessibilityOperation
    private let state = WindowActionRequestState()

    init(operation: WindowAccessibilityOperation) {
        self.operation = operation
    }

    func perform(
        _ action: WindowAction,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions = .standard
    ) async throws {
        try await perform(
            .action(action),
            targetPID: targetPID,
            screens: screens,
            options: options,
            pointerScreenIndex: nil
        )
    }

    func perform(
        _ request: WindowRequest,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions,
        pointerScreenIndex: Int?
    ) async throws {
        try await run(superseding: !request.isIncremental) { [operation] checkCancellation in
            try operation.perform(
                request,
                targetPID: targetPID,
                screens: screens,
                options: options,
                pointerScreenIndex: pointerScreenIndex,
                checkCancellation: checkCancellation
            )
        }
    }

    func focusedFrame(targetPID: pid_t?) async -> CGRect? {
        try? await run(superseding: false) { [operation] checkCancellation in
            try operation.focusedFrame(targetPID: targetPID, checkCancellation: checkCancellation)
        }
    }

    func captureWorkspace(screens: [CGRect], options: WindowLayoutOptions) async throws -> [WindowWorkspace.Entry] {
        try await run(superseding: false) { [operation] checkCancellation in
            try operation.captureWorkspaceEntries(
                screens: screens,
                options: options,
                checkCancellation: checkCancellation
            )
        }
    }

    /// Automatic tiling refreshes queue behind user requests instead of cancelling them.
    func refreshTiling(screens: [CGRect], options: WindowLayoutOptions) async {
        try? await run(superseding: false) { [operation] checkCancellation in
            try operation.retile(screens: screens, options: options, checkCancellation: checkCancellation)
        }
    }

    func forgetApplication(_ processIdentifier: pid_t) {
        queue.async { [operation] in
            operation.history.removeApplication(processIdentifier)
            operation.tiling.removeApplication(processIdentifier)
        }
    }

    private func run<Result: Sendable>(
        superseding: Bool,
        _ body: @escaping @Sendable (_ checkCancellation: () throws -> Void) throws -> Result
    ) async throws -> Result {
        let request = state.begin(supersedingEarlierRequests: superseding)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    defer { state.finish(request) }
                    do {
                        try state.check(request)
                        let result = try body { try self.state.check(request) }
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [state] in
            state.cancel(request)
        }
    }
}

@MainActor
final class WindowManager {
    private static let logger = Logger(
        subsystem: "dev.gauravpandey.broccoli",
        category: "WindowManagement"
    )

    private let worker: WindowAccessibilityWorker
    var layoutOptionsProvider: @MainActor () -> WindowLayoutOptions = { .standard }
    var customLayoutProvider: @MainActor (UUID) -> CustomWindowLayout? = { _ in nil }
    var workspaceProvider: @MainActor (UUID) -> WindowWorkspace? = { _ in nil }

    init(operation: WindowAccessibilityOperation = WindowAccessibilityOperation()) {
        worker = WindowAccessibilityWorker(operation: operation)
    }

    /// Resolves a launcher or hot-key identifier such as `window.leftHalf` or
    /// `window.layout.<UUID>`.
    func request(forActionID id: String) -> WindowRequest? {
        WindowShortcutTarget(actionID: id).flatMap(request(for:))
    }

    func request(for target: WindowShortcutTarget) -> WindowRequest? {
        switch target {
        case .action(let action): .action(action)
        case .layout(let id): customLayoutProvider(id).map { .frame($0.frameSpec) }
        case .workspace(let id): workspaceProvider(id).map(WindowRequest.workspace)
        }
    }

    func perform(_ action: WindowAction, targetPID: pid_t? = nil) async throws {
        try await perform(.action(action), targetPID: targetPID)
    }

    func perform(_ request: WindowRequest, targetPID: pid_t? = nil) async throws {
        guard AccessibilityPermissionChecker.isTrusted else {
            throw WindowManagementError.accessibilityRequired
        }
        if case .workspace(let workspace) = request {
            launchMissingApplications(for: workspace)
        }
        let screens = screenFrames()
        let options = layoutOptionsProvider()
        let target = targetPID ?? -1
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            try await worker.perform(
                request,
                targetPID: targetPID,
                screens: screens,
                options: options,
                pointerScreenIndex: pointerScreenIndex()
            )
            let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            Self.logger.debug(
                "Window action \(request.logName, privacy: .public) target \(target, privacy: .public) completed in \(milliseconds, privacy: .public) ms"
            )
        } catch {
            let description = Self.diagnosticDescription(for: error)
            Self.logger.error(
                "Window action \(request.logName, privacy: .public) target \(target, privacy: .public) failed: \(description, privacy: .public)"
            )
            throw error
        }
    }

    func focusedWindowFrame(targetPID: pid_t?) async -> CGRect? {
        guard AccessibilityPermissionChecker.isTrusted else { return nil }
        return await worker.focusedFrame(targetPID: targetPID)
    }

    func captureWorkspace() async throws -> [WindowWorkspace.Entry] {
        guard AccessibilityPermissionChecker.isTrusted else {
            throw WindowManagementError.accessibilityRequired
        }
        return try await worker.captureWorkspace(screens: screenFrames(), options: layoutOptionsProvider())
    }

    func refreshTiling() async {
        guard AccessibilityPermissionChecker.isTrusted else { return }
        await worker.refreshTiling(screens: screenFrames(), options: layoutOptionsProvider())
    }

    func forgetApplication(_ processIdentifier: pid_t) {
        worker.forgetApplication(processIdentifier)
    }

    private func launchMissingApplications(for workspace: WindowWorkspace) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for bundleIdentifier in Set(workspace.entries.map(\.bundleIdentifier)) where !running.contains(bundleIdentifier) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    private func pointerScreenIndex() -> Int? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.firstIndex { NSMouseInRect(location, $0.frame, false) }
    }

    private static func diagnosticDescription(for error: Error) -> String {
        guard let error = error as? WindowManagementError else {
            return String(describing: error)
        }
        switch error {
        case .accessibilityRequired:
            return "accessibilityRequired"
        case .noWindow:
            return "noWindow"
        case .unsupported:
            return "unsupported"
        case .timedOut:
            return "timedOut"
        case .frameRejected(let expected, let actual):
            return "frameRejected(expected: \(expected), actual: \(actual))"
        case .operationFailed(let accessibilityError):
            return "operationFailed(axError: \(accessibilityError.rawValue))"
        }
    }

    func screenFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        let dock = DockPreferenceSnapshot.current
        return NSScreen.screens.map { screen in
            let usable = WindowScreenGeometry.usableAppKitFrame(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                dockAutoHides: dock.autoHides,
                dockPosition: dock.position
            )
            return WindowScreenGeometry.accessibilityFrame(
                for: usable,
                primaryScreenFrame: primary.frame
            )
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) }
}
