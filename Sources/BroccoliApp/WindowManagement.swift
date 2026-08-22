@preconcurrency import AppKit
import ApplicationServices
import Carbon
import Foundation

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
    case operationFailed(AXError)

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Window management needs active Broccoli access in \(WindowManagementPermissionPresentation.settingsName)."
        case .noWindow:
            "Broccoli could not find a window to move."
        case .unsupported:
            "This window does not support moving or resizing."
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

enum WindowActionTargetResolver {
    static func processIdentifier(
        frontmostBundleIdentifier: String?,
        frontmostProcessIdentifier: pid_t?,
        broccoliBundleIdentifier: String?,
        lastExternalProcessIdentifier: pid_t?
    ) -> pid_t? {
        if frontmostBundleIdentifier != nil,
           frontmostBundleIdentifier != broccoliBundleIdentifier {
            return frontmostProcessIdentifier
        }
        return lastExternalProcessIdentifier
    }
}

@MainActor
final class WindowManager {
    func perform(_ action: WindowAction, targetPID: pid_t? = nil) throws {
        guard AccessibilityPermissionChecker.isTrusted else {
            throw WindowManagementError.accessibilityRequired
        }
        let window = try focusedWindow(targetPID: targetPID)
        let currentFrame = try frame(of: window)
        let screens = screenFrames()
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
        try setFrame(targetFrame, of: window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private func focusedWindow(targetPID: pid_t?) throws -> AXUIElement {
        let application: AXUIElement
        if let targetPID {
            application = AXUIElementCreateApplication(targetPID)
        } else {
            let system = AXUIElementCreateSystemWide()
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                system,
                kAXFocusedApplicationAttribute as CFString,
                &value
            ) == .success,
            let value else { throw WindowManagementError.noWindow }
            application = unsafeDowncast(value, to: AXUIElement.self)
        }

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard error == .success, let value else {
            throw error == .success ? WindowManagementError.noWindow : .operationFailed(error)
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(
            window, kAXPositionAttribute as CFString, &positionValue
        )
        let sizeError = AXUIElementCopyAttributeValue(
            window, kAXSizeAttribute as CFString, &sizeValue
        )
        guard positionError == .success, sizeError == .success,
              let positionValue, let sizeValue else {
            throw WindowManagementError.unsupported
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else {
            throw WindowManagementError.unsupported
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagementError.unsupported
        }
        let positionError = AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, positionValue
        )
        let sizeError = AXUIElementSetAttributeValue(
            window, kAXSizeAttribute as CFString, sizeValue
        )
        if positionError != .success { throw WindowManagementError.operationFailed(positionError) }
        if sizeError != .success { throw WindowManagementError.operationFailed(sizeError) }
        // Some applications constrain size by moving an edge. Reapply the requested origin
        // after resizing so left/top anchored layouts stay flush with the visible screen.
        let finalPositionError = AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, positionValue
        )
        if finalPositionError != .success {
            throw WindowManagementError.operationFailed(finalPositionError)
        }
    }

    private func screenFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            return CGRect(
                x: visible.minX,
                y: primary.frame.maxY - visible.maxY,
                width: visible.width,
                height: visible.height
            )
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) }
}
