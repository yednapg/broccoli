import Foundation

@MainActor
final class LauncherModeController {
    private(set) var mode: LauncherMode = .main

    func reset() { mode = .main }

    func enterClipboard() { mode = .clipboard(query: "") }

    func update(query: String, fileSearchEnabled: Bool) -> LauncherMode {
        switch mode {
        case .clipboard:
            mode = .clipboard(query: query)
        case .fileSearch:
            mode = .fileSearch(query: query)
        case .main:
            if fileSearchEnabled, let value = Self.fileQuery(from: query) {
                mode = .fileSearch(query: value)
            }
        }
        return mode
    }

    @discardableResult
    func exitSubmode() -> Bool {
        guard mode != .main else { return false }
        mode = .main
        return true
    }

    static func fileQuery(from rawQuery: String) -> String? {
        let lowered = rawQuery.lowercased()
        if lowered.hasPrefix("f ") { return String(rawQuery.dropFirst(2)) }
        if lowered.hasPrefix("find ") { return String(rawQuery.dropFirst(5)) }
        return nil
    }
}
