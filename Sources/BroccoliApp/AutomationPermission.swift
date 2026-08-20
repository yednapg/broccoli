@preconcurrency import AppKit
import CoreServices

enum AutomationPermissionState: Equatable, Sendable {
    case checking
    case allowed
    case notRequested
    case denied
    case targetUnavailable
    case unknown(OSStatus)

    static func from(status: OSStatus, targetIsInstalled: Bool) -> Self {
        switch status {
        case noErr: .allowed
        case OSStatus(errAEEventWouldRequireUserConsent): .notRequested
        case OSStatus(errAEEventNotPermitted): .denied
        // AEDeterminePermissionToAutomateTarget returns procNotFound when an installed target is
        // not running. System Events is launch-on-demand, so this is an indeterminate first-use
        // state rather than evidence that the audited target is unavailable.
        case OSStatus(procNotFound): targetIsInstalled ? .notRequested : .targetUnavailable
        default: .unknown(status)
        }
    }
}

enum AutomationPermissionChecker {
    private static let systemEventsBundleIdentifier = "com.apple.systemevents"
    private static let systemEventsURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/System Events.app",
        isDirectory: true
    )

    static func current() async -> AutomationPermissionState {
        await Task.detached(priority: .utility) {
            let targetIsInstalled = systemEventsIsInstalled()
            let target = NSAppleEventDescriptor(bundleIdentifier: systemEventsBundleIdentifier)
            guard let descriptor = target.aeDesc else {
                return .targetUnavailable
            }
            // Apple explicitly requires this preflight to stay off the main thread. Passing
            // false reports the current state without displaying a consent prompt.
            return AutomationPermissionState.from(
                status: AEDeterminePermissionToAutomateTarget(
                    descriptor,
                    typeWildCard,
                    typeWildCard,
                    false
                ),
                targetIsInstalled: targetIsInstalled
            )
        }.value
    }

    nonisolated private static func systemEventsIsInstalled() -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: systemEventsURL.path) { return true }
        guard let discoveredURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: systemEventsBundleIdentifier
        ) else { return false }
        return fileManager.fileExists(atPath: discoveredURL.path)
    }
}
