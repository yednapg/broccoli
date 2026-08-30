@preconcurrency import AppKit
import ApplicationServices
import Carbon
import Foundation
import OSLog

enum WindowAction: String, Codable, CaseIterable, Hashable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case minimized
    case center
    case nextDisplay
    case previousDisplay

    var actionID: String { "window.\(rawValue)" }
    var hotKeyBindingID: String { actionID }

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .maximize: "Maximize Window"
        case .minimized: "Minimized"
        case .center: "Center Window"
        case .nextDisplay: "Move to Next Display"
        case .previousDisplay: "Move to Previous Display"
        }
    }

    var aliases: [String] {
        switch self {
        case .leftHalf: ["window left", "snap left", "tile left"]
        case .rightHalf: ["window right", "snap right", "tile right"]
        case .topHalf: ["window top", "snap top", "tile top"]
        case .bottomHalf: ["window bottom", "snap bottom", "tile bottom"]
        case .maximize: ["window full", "fill screen", "zoom window"]
        case .minimized: ["window minimized", "minimize window", "shrink window", "restore down"]
        case .center: ["window center", "recenter"]
        case .nextDisplay: ["window next monitor", "move display", "next screen"]
        case .previousDisplay: ["window previous monitor", "previous screen"]
        }
    }

    var defaultShortcut: HotKeyConfiguration {
        let command = UInt32(cmdKey)
        let commandOption = UInt32(cmdKey | optionKey)
        switch self {
        case .leftHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_LeftArrow), modifiers: command)
        case .rightHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_RightArrow), modifiers: command)
        case .topHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_UpArrow), modifiers: commandOption)
        case .bottomHalf:
            return HotKeyConfiguration(keyCode: UInt32(kVK_DownArrow), modifiers: commandOption)
        case .maximize:
            return HotKeyConfiguration(keyCode: UInt32(kVK_UpArrow), modifiers: command)
        case .minimized:
            return HotKeyConfiguration(keyCode: UInt32(kVK_DownArrow), modifiers: command)
        case .center:
            return HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_C), modifiers: commandOption)
        case .nextDisplay:
            return HotKeyConfiguration(
                keyCode: UInt32(kVK_RightArrow),
                modifiers: commandOption
            )
        case .previousDisplay:
            return HotKeyConfiguration(
                keyCode: UInt32(kVK_LeftArrow),
                modifiers: commandOption
            )
        }
    }
}

struct WindowManagementPreferences: Codable, Equatable, Sendable {
    var shortcutsEnabled: Bool
    var shortcuts: [WindowAction: HotKeyConfiguration]

    init(
        shortcutsEnabled: Bool = false,
        shortcuts: [WindowAction: HotKeyConfiguration] = [:]
    ) {
        self.shortcutsEnabled = shortcutsEnabled
        self.shortcuts = shortcuts
        for action in WindowAction.allCases where self.shortcuts[action] == nil {
            self.shortcuts[action] = action.defaultShortcut
        }
    }

    func shortcut(for action: WindowAction) -> HotKeyConfiguration {
        shortcuts[action] ?? action.defaultShortcut
    }

    mutating func migrateInterimDefaultShortcuts() {
        guard shortcuts == Self.interimDefaultShortcuts else { return }
        shortcuts = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map {
            ($0, $0.defaultShortcut)
        })
    }

    // These defaults shipped briefly during development. Migrate only an exact match so
    // user-customized shortcuts are never overwritten.
    private static let interimDefaultShortcuts: [WindowAction: HotKeyConfiguration] = [
        .leftHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .rightHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .topHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .bottomHalf: HotKeyConfiguration(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .maximize: HotKeyConfiguration(
            keyCode: UInt32(kVK_Return),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .minimized: HotKeyConfiguration(
            keyCode: UInt32(kVK_DownArrow),
            modifiers: UInt32(cmdKey)
        ),
        .center: HotKeyConfiguration(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey | optionKey)
        ),
        .nextDisplay: HotKeyConfiguration(
            keyCode: UInt32(kVK_RightArrow),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
        .previousDisplay: HotKeyConfiguration(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ),
    ]

    private enum CodingKeys: String, CodingKey { case shortcutsEnabled, shortcuts }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shortcutsEnabled: try container.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? false,
            shortcuts: try container.decodeIfPresent(
                [WindowAction: HotKeyConfiguration].self,
                forKey: .shortcuts
            ) ?? [:]
        )
    }
}

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

enum WindowGeometry {
    static func frame(for action: WindowAction, window: CGRect, screen: CGRect) -> CGRect {
        switch action {
        case .leftHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case .rightHalf:
            return CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case .topHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2)
        case .bottomHalf:
            return CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2)
        case .maximize:
            return screen
        case .minimized:
            // “Minimized” is a restore-down layout, not Dock minimization. Match the supplied
            // browser reference with a centered window that retains a comfortable desktop
            // margin on every edge while remaining large enough for productive work.
            let width = screen.width * 0.9
            let height = screen.height * 0.9
            return CGRect(
                x: screen.midX - width / 2,
                y: screen.midY - height / 2,
                width: width,
                height: height
            )
        case .center:
            let width = min(window.width, screen.width)
            let height = min(window.height, screen.height)
            return CGRect(
                x: screen.midX - width / 2,
                y: screen.midY - height / 2,
                width: width,
                height: height
            )
        case .nextDisplay, .previousDisplay:
            return window
        }
    }

    static func movedFrame(window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let widthRatio = source.width > 0 ? window.width / source.width : 1
        let heightRatio = source.height > 0 ? window.height / source.height : 1
        let xRatio = source.width > window.width
            ? (window.minX - source.minX) / (source.width - window.width)
            : 0.5
        let yRatio = source.height > window.height
            ? (window.minY - source.minY) / (source.height - window.height)
            : 0.5
        let width = min(destination.width, destination.width * widthRatio)
        let height = min(destination.height, destination.height * heightRatio)
        return CGRect(
            x: destination.minX + max(0, destination.width - width) * min(1, max(0, xRatio)),
            y: destination.minY + max(0, destination.height - height) * min(1, max(0, yRatio)),
            width: width,
            height: height
        )
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
    private static let frameSizeTolerance: CGFloat = 2
    private static let frameStabilityTolerance: CGFloat = 1

    private enum WindowCandidateResolution {
        case accepted
        case rejected
        case failed(AXError)
    }

    private let attributeReader: AttributeReader
    private let attributeWriter: AttributeWriter
    private let messagingTimeoutSetter: MessagingTimeoutSetter
    private let retryWaiter: RetryWaiter
    private let frameSettlementWaiter: FrameSettlementWaiter
    private let uptimeProvider: UptimeProvider
    private let messagingTimeout: Float
    private let actionTimeout: TimeInterval

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
        actionTimeout: TimeInterval = 4
    ) {
        self.attributeReader = attributeReader
        self.attributeWriter = attributeWriter
        self.messagingTimeoutSetter = messagingTimeoutSetter
        self.retryWaiter = retryWaiter
        self.frameSettlementWaiter = frameSettlementWaiter
        self.uptimeProvider = uptimeProvider
        self.messagingTimeout = messagingTimeout
        self.actionTimeout = actionTimeout
    }

    func perform(
        _ action: WindowAction,
        targetPID: pid_t?,
        screens: [CGRect],
        checkCancellation: () throws -> Void
    ) throws {
        let deadline = uptimeProvider() + actionTimeout
        try checkReady(deadline: deadline, checkCancellation: checkCancellation)
        let system = AXUIElementCreateSystemWide()
        let timeoutError = messagingTimeoutSetter(system, messagingTimeout)
        guard timeoutError == .success else {
            throw WindowManagementError.operationFailed(timeoutError)
        }

        let window = try focusedWindow(
            targetPID: targetPID,
            systemElement: system,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        let currentFrame = try frame(
            of: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        guard !screens.isEmpty else { throw WindowManagementError.unsupported }
        let currentScreenIndex = screens.indices.max { left, right in
            currentFrame.intersection(screens[left]).area < currentFrame.intersection(screens[right]).area
        } ?? 0

        let targetFrame: CGRect
        switch action {
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1 else { return }
            let offset = action == .nextDisplay ? 1 : -1
            let destinationIndex = (currentScreenIndex + offset + screens.count) % screens.count
            targetFrame = WindowGeometry.movedFrame(
                window: currentFrame,
                from: screens[currentScreenIndex],
                to: screens[destinationIndex]
            )
        default:
            targetFrame = WindowGeometry.frame(
                for: action,
                window: currentFrame,
                screen: screens[currentScreenIndex]
            )
        }
        try setFrame(
            targetFrame,
            of: window,
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

    private func windowCandidateResolution(
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

    private func frame(
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

    func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        try setFrame(
            frame,
            of: window,
            deadline: uptimeProvider() + actionTimeout,
            checkCancellation: {}
        )
    }

    private func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
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
                if Self.framesApproximatelyMatch(finalAppliedFrame, frame) { return }
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
        }
        let rejectedFrame = finalAppliedFrame
        restoreFrame(
            originalFrame,
            of: window,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        throw WindowManagementError.frameRejected(expected: frame, actual: rejectedFrame)
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

    private static func framesMatch(
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

    private func readRequiredAttribute(
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

    private func writeAttribute(
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

    private func checkReady(
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

private final class WindowActionRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func cancel(_ request: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if generation == request { generation &+= 1 }
    }

    func check(_ request: UInt64) throws {
        lock.lock()
        let isCurrent = generation == request
        lock.unlock()
        guard isCurrent else { throw CancellationError() }
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

    func perform(_ action: WindowAction, targetPID: pid_t?, screens: [CGRect]) async throws {
        let request = state.begin()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        try state.check(request)
                        try operation.perform(
                            action,
                            targetPID: targetPID,
                            screens: screens,
                            checkCancellation: { try self.state.check(request) }
                        )
                        continuation.resume(returning: ())
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

    init(operation: WindowAccessibilityOperation = WindowAccessibilityOperation()) {
        worker = WindowAccessibilityWorker(operation: operation)
    }

    func perform(_ action: WindowAction, targetPID: pid_t? = nil) async throws {
        guard AccessibilityPermissionChecker.isTrusted else {
            throw WindowManagementError.accessibilityRequired
        }
        let screens = screenFrames()
        let target = targetPID ?? -1
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            try await worker.perform(action, targetPID: targetPID, screens: screens)
            let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            Self.logger.debug(
                "Window action \(action.rawValue, privacy: .public) target \(target, privacy: .public) completed in \(milliseconds, privacy: .public) ms"
            )
        } catch {
            let description = Self.diagnosticDescription(for: error)
            Self.logger.error(
                "Window action \(action.rawValue, privacy: .public) target \(target, privacy: .public) failed: \(description, privacy: .public)"
            )
            throw error
        }
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

    private func screenFrames() -> [CGRect] {
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
