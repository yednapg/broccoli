@preconcurrency import AppKit
import Foundation

enum ActionExecutionResult: Sendable {
    case completed
    case keepPanelOpen
}

enum ActionExecutionError: LocalizedError {
    case unknownAction
    case scriptCompilation(String)
    case scriptExecution(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unknownAction: "This action is not registered."
        case .scriptCompilation(let message): "The system action could not be prepared: \(message)"
        case .scriptExecution(let message): "The system action failed: \(message)"
        case .unavailable: "This action is unavailable on this Mac."
        }
    }
}

final class ActionExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.gauravpandey.broccoli.actions", qos: .userInitiated)
    private let windowManager: WindowManager
    private let audio = AudioController()
    private var scripts: [String: NSAppleScript] = [:]
    private let lock = NSLock()

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        prepareScripts()
    }

    func execute(id: String, targetPID: pid_t? = nil) async throws -> ActionExecutionResult {
        guard let definition = ActionRegistry.definition(id: id) else {
            throw ActionExecutionError.unknownAction
        }
        if let action = WindowAction.allCases.first(where: { $0.actionID == id }) {
            try await windowManager.perform(action, targetPID: targetPID)
            return definition.keepsPanelOpen ? .keepPanelOpen : .completed
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try executeSynchronously(id: id)
                    continuation.resume(returning: definition.keepsPanelOpen ? .keepPanelOpen : .completed)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func executeSynchronously(id: String) throws {
        switch id {
        case "appearance.toggleDark", "power.sleep", "power.restart", "power.shutdown", "power.logout":
            try executeScript(id: id)
        case "audio.toggleMute":
            try audio.toggleMute()
        case "audio.volumeUp":
            try audio.adjustVolume(by: 0.1)
        case "audio.volumeDown":
            try audio.adjustVolume(by: -0.1)
        case "screensaver.start":
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            DispatchQueue.main.async { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
        case "broccoli.quit", "broccoli.preferences", "catalog.refresh":
            break // Coordinated by LauncherCoordinator on the main actor.
        default:
            throw ActionExecutionError.unknownAction
        }
    }

    private func prepareScripts() {
        let sources = [
            "appearance.toggleDark": "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
            "power.sleep": "tell application \"System Events\" to sleep",
            "power.restart": "tell application \"System Events\" to restart",
            "power.shutdown": "tell application \"System Events\" to shut down",
            "power.logout": "tell application \"System Events\" to log out",
        ]
        for (id, source) in sources {
            guard let script = NSAppleScript(source: source) else { continue }
            var error: NSDictionary?
            if script.compileAndReturnError(&error) {
                scripts[id] = script
            }
        }
    }

    private func executeScript(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let script = scripts[id] else {
            throw ActionExecutionError.scriptCompilation("The compiled script is unavailable.")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? error.description
            throw ActionExecutionError.scriptExecution(message)
        }
    }
}
