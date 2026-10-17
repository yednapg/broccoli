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

    /// Accessibility and AppKit frames meet at the primary display's top edge, so the same
    /// conversion turns either coordinate space back into the other.
    static func appKitFrame(
        for accessibilityFrame: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        self.accessibilityFrame(for: accessibilityFrame, primaryScreenFrame: primaryScreenFrame)
    }

    /// Where a window that took a different size than a layout asked for belongs, such as a
    /// terminal rounded to its character grid. On each axis it starts where a layout spanning
    /// the whole screen starts, keeps to the side of the screen the layout leans toward, or stays
    /// centered when the layout is centered, and its top-left corner stays on screen. `current`
    /// keeps a step resize from moving the window along an axis the application would not resize.
    static func frame(
        aligning size: CGSize,
        to target: CGRect,
        keepingUnchangedAxesOf current: CGRect? = nil,
        screen: CGRect
    ) -> CGRect {
        func origin(
            length: CGFloat,
            target: (start: CGFloat, length: CGFloat),
            current: (start: CGFloat, length: CGFloat)?,
            screen: (start: CGFloat, length: CGFloat)
        ) -> CGFloat {
            let targetMid = target.start + target.length / 2
            let screenMid = screen.start + screen.length / 2
            let spansScreen = abs(target.start - screen.start) <= 1
                && abs(target.start + target.length - (screen.start + screen.length)) <= 1
            let proposed: CGFloat
            if let current, abs(length - current.length) <= 1 {
                proposed = current.start
            } else if spansScreen {
                proposed = target.start
            } else if abs(targetMid - screenMid) <= 1 {
                proposed = targetMid - length / 2
            } else if targetMid < screenMid {
                proposed = target.start
            } else {
                proposed = target.start + target.length - length
            }
            return max(screen.start, min(proposed, screen.start + screen.length - length))
        }
        return CGRect(
            x: origin(
                length: size.width,
                target: (target.minX, target.width),
                current: current.map { ($0.minX, $0.width) },
                screen: (screen.minX, screen.width)
            ),
            y: origin(
                length: size.height,
                target: (target.minY, target.height),
                current: current.map { ($0.minY, $0.height) },
                screen: (screen.minY, screen.height)
            ),
            width: size.width,
            height: size.height
        )
    }

    /// A window that keeps its own size is centered in the frame a layout asked for, so Left
    /// Half puts it in the middle of the left half. Its top and leading edges stay on screen.
    static func frame(centering size: CGSize, in target: CGRect, screen: CGRect) -> CGRect {
        func origin(length: CGFloat, targetMid: CGFloat, screenMin: CGFloat, screenMax: CGFloat) -> CGFloat {
            max(screenMin, min(targetMid - length / 2, screenMax - length))
        }
        return CGRect(
            x: origin(length: size.width, targetMid: target.midX, screenMin: screen.minX, screenMax: screen.maxX),
            y: origin(length: size.height, targetMid: target.midY, screenMin: screen.minY, screenMax: screen.maxY),
            width: size.width,
            height: size.height
        )
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

/// Places a window Broccoli itself owns, such as Settings, through AppKit on the main thread.
/// Accessibility would answer for this process on the window worker's thread, where AppKit
/// cannot change a frame.
enum BroccoliWindowFramePlacement {
    /// `keepsSize` is for a window that cannot be resized: it keeps its size and is centered
    /// in the layout's frame, the same as an application window that refuses a size.
    static func appKitFrame(
        for action: WindowAction,
        current: CGRect,
        accessibilityScreens: [CGRect],
        primaryScreenFrame: CGRect,
        options: WindowLayoutOptions,
        keepsSize: Bool = false
    ) -> CGRect? {
        switch action {
        case .nextDisplay, .previousDisplay, .restore, .tileAll, .cascadeAll,
             .rotateLayout, .retileWindows, .toggleFloating:
            return nil
        default:
            break
        }
        guard !accessibilityScreens.isEmpty else { return nil }
        let currentAccessibilityFrame = WindowScreenGeometry.accessibilityFrame(
            for: current,
            primaryScreenFrame: primaryScreenFrame
        )
        let screenIndex = WindowAccessibilityOperation.screenIndex(
            containing: currentAccessibilityFrame,
            in: accessibilityScreens
        )
        let screen = accessibilityScreens[screenIndex]
        let layout = WindowGeometry.frame(
            for: action,
            window: currentAccessibilityFrame,
            screen: screen,
            options: options
        )
        let placed = keepsSize
            ? WindowScreenGeometry.frame(centering: currentAccessibilityFrame.size, in: layout, screen: screen)
            : layout
        return WindowScreenGeometry.appKitFrame(
            for: placed,
            primaryScreenFrame: primaryScreenFrame
        )
    }
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
}

struct AccessibilityAttributeRead {
    let error: AXError
    let value: CFTypeRef?
}

/// What a single-window request did, for diagnostics.
struct WindowActionOutcome: Sendable {
    let processIdentifier: pid_t
    let requested: CGRect
    let result: CGRect
}

final class WindowAccessibilityOperation: @unchecked Sendable {
    typealias AttributeReader = (AXUIElement, CFString) -> AccessibilityAttributeRead
    typealias AttributeWriter = (AXUIElement, CFString, CFTypeRef) -> AXError
    typealias MessagingTimeoutSetter = (AXUIElement, Float) -> AXError
    typealias RetryWaiter = (Int) -> Void
    typealias FrameSettlementWaiter = (Int) -> Void
    typealias UptimeProvider = () -> TimeInterval

    private static let logger = Logger(subsystem: "dev.gauravpandey.broccoli", category: "WindowManagement")
    private static let maximumAccessibilityAttempts = 2
    // Terminal, iTerm, and similar grid-snapping windows round to a character cell. A typical
    // cell is about 7–16 pt; within this distance a window took the size it was asked for.
    private static let frameSizeTolerance: CGFloat = 24
    // A window whose width did not change at all, when the layout asked for a width this much
    // different, refused it even if its own width is near the layout's, like System Settings at
    // 740 pt in a 720 pt half. Character cells are narrower, so a terminal already at the
    // layout's width is not mistaken for a fixed one.
    private static let fixedWidthTolerance: CGFloat = 12
    private static let frameTolerance: CGFloat = 1
    static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString

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
    /// Waits between polls while a workspace's applications open their windows.
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

    @discardableResult
    func perform(
        _ action: WindowAction,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions = .standard,
        checkCancellation: () throws -> Void
    ) throws -> WindowActionOutcome? {
        try perform(
            .action(action),
            targetPID: targetPID,
            screens: screens,
            options: options,
            pointerScreenIndex: nil,
            checkCancellation: checkCancellation
        )
    }

    /// `windowFrame` names the window by where it is on screen, such as one the user just
    /// dragged. Without it, the request acts on the application's focused window.
    @discardableResult
    func perform(
        _ request: WindowRequest,
        targetPID: pid_t?,
        windowFrame: CGRect? = nil,
        screens: [CGRect],
        options: WindowLayoutOptions,
        pointerScreenIndex: Int?,
        checkCancellation: () throws -> Void
    ) throws -> WindowActionOutcome? {
        guard !screens.isEmpty else { throw WindowManagementError.unsupported }
        switch request {
        case .workspace(let workspace):
            try applyWorkspace(workspace, screens: screens, checkCancellation: checkCancellation)
            return nil
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
                return nil
            case .tiling:
                try performTilingCommand(
                    action,
                    targetPID: targetPID,
                    screens: screens,
                    options: options,
                    checkCancellation: checkCancellation
                )
                return nil
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
            windowFrame: windowFrame,
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
            return nil
        case .action(let action):
            appliedAction = action
            switch action {
            case .restore:
                guard let stored else { return nil }
                targetFrame = stored.restoreFrame
                layoutScreen = screens[Self.screenIndex(containing: targetFrame, in: screens)]
            case .nextDisplay, .previousDisplay:
                guard screens.count > 1 else { return nil }
                layoutScreen = screens[Self.neighboringScreenIndex(
                    of: currentScreenIndex,
                    in: screens,
                    forward: action == .nextDisplay
                )]
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
        let result = Self.framesMatch(targetFrame, currentFrame, originTolerance: 0.5, sizeTolerance: 0.5)
            ? currentFrame
            : try setFrame(
                targetFrame,
                of: window,
                from: currentFrame,
                screen: layoutScreen,
                incremental: request.isIncremental,
                deadline: deadline,
                checkCancellation: checkCancellation
            )

        if appliedAction == .restore {
            history.remove(key)
        } else {
            // Recorded even when nothing moved, so pressing a half the window already fills
            // still cycles to the next size.
            history.record(
                WindowHistory.Entry(
                    restoreFrame: continuing ? (stored?.restoreFrame ?? currentFrame) : currentFrame,
                    lastApplied: result,
                    lastAction: appliedAction,
                    cycleIndex: cycleIndex
                ),
                for: key
            )
        }
        return WindowActionOutcome(
            processIdentifier: key.processIdentifier,
            requested: targetFrame,
            result: result
        )
    }

    static func screenIndex(containing frame: CGRect, in screens: [CGRect]) -> Int {
        screens.indices.max { left, right in
            frame.intersection(screens[left]).area < frame.intersection(screens[right]).area
        } ?? 0
    }

    /// The display after or before `index` in the order the displays are arranged: left to
    /// right, and top to bottom for displays that share a left edge.
    static func neighboringScreenIndex(of index: Int, in screens: [CGRect], forward: Bool) -> Int {
        let order = screens.indices.sorted { left, right in
            screens[left].minX != screens[right].minX
                ? screens[left].minX < screens[right].minX
                : screens[left].minY < screens[right].minY
        }
        guard let position = order.firstIndex(of: index) else { return index }
        return order[(position + (forward ? 1 : -1) + order.count) % order.count]
    }

    func focusedWindow(
        targetPID: pid_t?,
        windowFrame: CGRect? = nil,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> AXUIElement {
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let system = AXUIElementCreateSystemWide()
        let timeoutError = messagingTimeoutSetter(system, messagingTimeout)
        guard timeoutError == .success else {
            throw WindowManagementError.operationFailed(timeoutError)
        }
        let application = try targetApplication(
            targetPID: targetPID,
            systemElement: system,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        if let windowFrame,
           let window = try window(
            in: application,
            at: windowFrame,
            deadline: deadline,
            checkCancellation: checkCancellation
           ) {
            return window
        }
        return try resolveFocusedWindow(
            in: application,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
    }

    private func targetApplication(
        targetPID: pid_t?,
        systemElement: AXUIElement,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> AXUIElement {
        // Accessibility answers a request for this process's own windows on the calling
        // thread, and AppKit traps a frame change off the main thread. Broccoli places its
        // own windows through AppKit instead.
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let application: AXUIElement
        if let targetPID {
            guard targetPID != ownProcess else { throw WindowManagementError.noWindow }
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
            var focusedProcess: pid_t = 0
            if AXUIElementGetPid(application, &focusedProcess) == .success,
               focusedProcess == ownProcess {
                throw WindowManagementError.noWindow
            }
        }
        return application
    }

    /// The application's window at `frame`, for a window known by where it is on screen.
    private func window(
        in application: AXUIElement,
        at frame: CGRect,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> AXUIElement? {
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let read = attributeReader(application, kAXWindowsAttribute as CFString)
        guard read.error == .success, let windows = read.value as? [AXUIElement] else { return nil }
        for window in windows {
            guard let candidateFrame = try? self.frame(of: window, deadline: deadline, checkCancellation: checkCancellation),
                  Self.framesMatch(candidateFrame, frame, originTolerance: 4, sizeTolerance: 4) else { continue }
            if case .accepted = try windowCandidateResolution(
                window,
                acceptsPanels: true,
                deadline: deadline,
                checkCancellation: checkCancellation
            ) {
                return window
            }
        }
        return nil
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
                        acceptsPanels: true,
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
                            Self.logger.notice(
                                "Focused window refused: \(self.kindDescription(of: candidate), privacy: .public)"
                            )
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

    /// Standard windows are always candidates. `acceptsPanels` also takes floating panels and
    /// windows with an unusual subrole, for a window the user acts on directly, but never a
    /// dialog or alert, which keeps the geometry its application gives it.
    func windowCandidateResolution(
        _ window: AXUIElement,
        acceptsPanels: Bool = false,
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
        if CFEqual(subroleValue, kAXStandardWindowSubrole as CFString) { return .accepted }
        guard acceptsPanels else { return .rejected }
        let isModal = [kAXDialogSubrole, kAXSystemDialogSubrole].contains {
            CFEqual(subroleValue, $0 as CFString)
        }
        return isModal ? .rejected : .accepted
    }

    /// The window's role and subrole, for logging why a window was refused.
    private func kindDescription(of window: AXUIElement) -> String {
        func string(_ attribute: String) -> String {
            (attributeReader(window, attribute as CFString).value as? String) ?? "none"
        }
        return "role \(string(kAXRoleAttribute)), subrole \(string(kAXSubroleAttribute))"
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

    @discardableResult
    func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        screen: CGRect? = nil,
        incremental: Bool = false
    ) throws -> CGRect {
        let deadline = uptimeProvider() + actionTimeout
        let current = try self.frame(of: window, deadline: deadline, checkCancellation: {})
        return try setFrame(
            frame,
            of: window,
            from: current,
            screen: screen ?? frame,
            incremental: incremental,
            deadline: deadline,
            checkCancellation: {}
        )
    }

    /// Writes the size, the position, and the size again, then keeps what the application
    /// accepted and returns where the window ended up. A window that will not take a layout's
    /// size keeps its own size, centered in the requested area, rather than being stretched on
    /// the axis it did accept. `incremental` instead keeps whatever a step resize achieved, so
    /// a window at its minimum width still changes height.
    @discardableResult
    func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        from current: CGRect,
        screen: CGRect,
        incremental: Bool,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> CGRect {
        // A newer request can replace this one only before the first write. The writes take a
        // few milliseconds, and stopping between them would leave the window half-placed.
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let restoreEnhancedUserInterface = suspendEnhancedUserInterface(of: window)
        defer { restoreEnhancedUserInterface() }

        let writeError = write(frame, to: window, resizing: !Self.sizesMatch(frame.size, current.size, tolerance: 0.5))
        if let writeError { throw WindowManagementError.operationFailed(writeError) }
        var result = try self.frame(of: window, deadline: .infinity, checkCancellation: {})

        // The window refused the layout when it took the size on one axis but not the other,
        // like System Settings with its fixed width, or did not change size at all. A window
        // that changed on both axes but stopped short, such as one at its maximum size, keeps
        // what it reached.
        let keptFixedWidth = abs(result.width - current.width) <= Self.frameTolerance
            && abs(frame.width - current.width) > Self.fixedWidthTolerance
        let tookWidth = abs(result.width - frame.width) <= Self.frameSizeTolerance && !keptFixedWidth
        let tookHeight = abs(result.height - frame.height) <= Self.frameSizeTolerance
        let refused = tookWidth != tookHeight
            || (!tookWidth && Self.sizesMatch(result.size, current.size, tolerance: Self.frameTolerance))
        let placed: CGRect
        if Self.sizesMatch(result.size, frame.size, tolerance: 0.5) {
            placed = CGRect(origin: frame.origin, size: result.size)
        } else if incremental {
            placed = WindowScreenGeometry.frame(
                aligning: result.size,
                to: frame,
                keepingUnchangedAxesOf: current,
                screen: screen
            )
        } else if refused {
            placed = WindowScreenGeometry.frame(centering: current.size, in: frame, screen: screen)
        } else {
            placed = WindowScreenGeometry.frame(aligning: result.size, to: frame, screen: screen)
        }
        if !Self.framesMatch(result, placed, originTolerance: Self.frameTolerance, sizeTolerance: Self.frameTolerance) {
            _ = write(placed, to: window, resizing: !Self.sizesMatch(result.size, placed.size, tolerance: Self.frameTolerance))
            result = try self.frame(of: window, deadline: .infinity, checkCancellation: {})
        }
        // Nothing changed and the window is not where this layout puts it: the application
        // refused the request outright.
        if Self.framesMatch(result, current, originTolerance: Self.frameTolerance, sizeTolerance: Self.frameTolerance),
           !Self.framesMatch(result, placed, originTolerance: Self.frameTolerance, sizeTolerance: Self.frameTolerance) {
            throw WindowManagementError.frameRejected(expected: frame, actual: result)
        }
        return result
    }

    /// Writes the size, the position, and the size again, and returns an error only when
    /// neither the size nor the position could be written. An application keeps a window on
    /// screen from where it is, so a size written before the move can be cut short near an
    /// edge; writing it again after the move applies it in full, and writing it first keeps a
    /// shrinking window from being pushed off screen.
    private func write(_ frame: CGRect, to window: AXUIElement, resizing: Bool) -> AXError? {
        let sizeError = resizing ? write(frame.size, to: window) : .success
        let positionError = write(frame.origin, to: window)
        guard sizeError == .success || positionError == .success else { return positionError }
        if resizing, sizeError == .success { _ = write(frame.size, to: window) }
        return nil
    }

    private func write(_ size: CGSize, to window: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .illegalArgument }
        return write(kAXSizeAttribute as CFString, value, to: window)
    }

    private func write(_ origin: CGPoint, to window: AXUIElement) -> AXError {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return .illegalArgument }
        return write(kAXPositionAttribute as CFString, value, to: window)
    }

    private func write(_ attribute: CFString, _ value: CFTypeRef, to element: AXUIElement) -> AXError {
        var error = AXError.failure
        for attempt in 1...Self.maximumAccessibilityAttempts {
            error = attributeWriter(element, attribute, value)
            guard error != .success,
                  attempt < Self.maximumAccessibilityAttempts,
                  Self.isRetryable(error) else { break }
            retryWaiter(attempt)
        }
        return error
    }

    /// Chromium- and Firefox-based applications report frame writes as successful but ignore
    /// or animate them while AXEnhancedUserInterface is on. The attribute belongs to assistive
    /// clients such as VoiceOver, so it is turned back on as soon as the frame is applied.
    /// Firefox applies writes to this attribute while returning an error, so the write result
    /// cannot decide whether it needs restoring.
    private func suspendEnhancedUserInterface(of window: AXUIElement) -> () -> Void {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(window, &processIdentifier) == .success,
              processIdentifier > 0 else { return {} }
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = messagingTimeoutSetter(application, messagingTimeout)
        let attribute = Self.enhancedUserInterfaceAttribute
        let read = attributeReader(application, attribute)
        guard read.error == .success, (read.value as? Bool) == true else { return {} }
        _ = attributeWriter(application, attribute, kCFBooleanFalse)
        return { [attributeWriter] in
            _ = attributeWriter(application, attribute, kCFBooleanTrue)
        }
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
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

    @discardableResult
    func perform(
        _ request: WindowRequest,
        targetPID: pid_t?,
        windowFrame: CGRect? = nil,
        screens: [CGRect],
        options: WindowLayoutOptions,
        pointerScreenIndex: Int?
    ) async throws -> WindowActionOutcome? {
        try await run(superseding: !request.isIncremental) { [operation] checkCancellation in
            try operation.perform(
                request,
                targetPID: targetPID,
                windowFrame: windowFrame,
                screens: screens,
                options: options,
                pointerScreenIndex: pointerScreenIndex,
                checkCancellation: checkCancellation
            )
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
        guard target.isAvailable else { return nil }
        return switch target {
        case .action(let action): .action(action)
        case .layout(let id): customLayoutProvider(id).map { .frame($0.frameSpec) }
        case .workspace(let id): workspaceProvider(id).map(WindowRequest.workspace)
        }
    }

    func perform(_ action: WindowAction, targetPID: pid_t? = nil) async throws {
        try await perform(.action(action), targetPID: targetPID)
    }

    /// `windowFrame` names the window by where it is on screen, such as one the user just
    /// dragged. Without it, the request acts on the target application's focused window.
    func perform(_ request: WindowRequest, targetPID: pid_t? = nil, windowFrame: CGRect? = nil) async throws {
        guard AccessibilityPermissionChecker.isTrusted else {
            throw WindowManagementError.accessibilityRequired
        }
        if case .workspace(let workspace) = request {
            launchMissingApplications(for: workspace)
        }
        let screens = screenFrames()
        let options = layoutOptionsProvider()
        let startedAt = ProcessInfo.processInfo.systemUptime
        func elapsed() -> Double { (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000 }
        do {
            let outcome = try await worker.perform(
                request,
                targetPID: targetPID,
                windowFrame: windowFrame,
                screens: screens,
                options: options,
                pointerScreenIndex: pointerScreenIndex()
            )
            let application = Self.applicationName(outcome?.processIdentifier ?? targetPID)
            if let outcome {
                Self.logger.info(
                    "Window action \(request.logName, privacy: .public) for \(application, privacy: .public) took \(elapsed(), format: .fixed(precision: 1), privacy: .public) ms: requested \(String(describing: outcome.requested), privacy: .public), got \(String(describing: outcome.result), privacy: .public)"
                )
            } else {
                Self.logger.info(
                    "Window action \(request.logName, privacy: .public) took \(elapsed(), format: .fixed(precision: 1), privacy: .public) ms"
                )
            }
        } catch let error as CancellationError {
            Self.logger.debug("Window action \(request.logName, privacy: .public) was replaced by a newer one")
            throw error
        } catch {
            Self.logger.error(
                "Window action \(request.logName, privacy: .public) for \(Self.applicationName(targetPID), privacy: .public) failed after \(elapsed(), format: .fixed(precision: 1), privacy: .public) ms: \(Self.diagnosticDescription(for: error), privacy: .public)"
            )
            throw error
        }
    }

    private static func applicationName(_ processIdentifier: pid_t?) -> String {
        guard let processIdentifier else { return "the focused application" }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
            ?? "process \(processIdentifier)"
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
