import AppKit
import ApplicationServices
import XCTest
@testable import BroccoliApp

/// Measures how long a window layout takes on real windows and whether the window ends up
/// where the layout asked. It moves windows on screen, so it runs only when
/// `BROCCOLI_LIVE_WINDOW_LATENCY=1` is set and the test process has Accessibility access.
@MainActor
final class WindowLiveLatencyTests: XCTestCase {
    private static let rounds = 8
    private static let actions: [WindowAction] = [
        .maximize, .leftHalf, .rightHalf, .minimized, .topHalf, .bottomHalf, .center,
    ]

    func testLayoutLatencyOnRealWindows() async throws {
        guard ProcessInfo.processInfo.environment["BROCCOLI_LIVE_WINDOW_LATENCY"] == "1" else {
            throw XCTSkip("Set BROCCOLI_LIVE_WINDOW_LATENCY=1 to move real windows and measure latency.")
        }
        guard AXIsProcessTrusted() else { throw XCTSkip("The test process needs Accessibility access.") }

        let screens = WindowManager().screenFrames()
        let fixture = try LiveWindowFixture.build()
        var lines: [String] = []
        for mode in LiveWindowFixture.Mode.allCases {
            let process = try fixture.launch(mode)
            defer { process.terminate() }
            let window = try await LiveWindowFixture.firstWindow(of: process.processIdentifier)
            lines += measure(window: window, processIdentifier: process.processIdentifier, label: mode.rawValue, screens: screens)
        }
        if let textEdit = try await LiveTextEditDocument.open() {
            defer { textEdit.close() }
            lines += measure(window: textEdit.window, processIdentifier: textEdit.processIdentifier, label: "TextEdit", screens: screens)
        }
        let report = lines.joined(separator: "\n")
        print("\n=== Window layout latency ===\n\(report)\n")
        if let path = ProcessInfo.processInfo.environment["BROCCOLI_LIVE_WINDOW_LATENCY_REPORT"] {
            try report.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Each round starts from a window that is not full height and sits near the bottom-right
    /// corner, the position that used to make an AppKit window look fixed-size.
    private func measure(window: AXUIElement, processIdentifier: pid_t, label: String, screens: [CGRect]) -> [String] {
        let operation = WindowAccessibilityOperation()
        let screen = screens[0]
        var timings: [WindowAction: [Double]] = [:]
        var matched: [WindowAction: Int] = [:]
        var firstMiss: [WindowAction: String] = [:]
        for _ in 0..<Self.rounds {
            LiveAX.setFrame(
                CGRect(x: screen.maxX - 520, y: screen.maxY - 440, width: 500, height: 400),
                of: window
            )
            for action in Self.actions {
                let before = LiveAX.frame(of: window)
                let expected = WindowGeometry.frame(for: action, window: before, screen: screen, options: .standard)
                let start = ProcessInfo.processInfo.systemUptime
                try? operation.perform(action, targetPID: processIdentifier, screens: screens, options: .standard) {}
                timings[action, default: []].append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                let after = LiveAX.frame(of: window)
                if WindowAccessibilityOperation.framesMatch(after, expected, originTolerance: 8, sizeTolerance: 24) {
                    matched[action, default: 0] += 1
                } else if firstMiss[action] == nil {
                    firstMiss[action] = "from \(before) expected \(expected) got \(after)"
                }
            }
        }
        let all = timings.values.flatMap { $0 }
        var lines = ["\(label): all actions median \(Self.format(Self.percentile(all, 0.5))) p95 \(Self.format(Self.percentile(all, 0.95)))"]
        for action in Self.actions {
            let samples = timings[action] ?? []
            lines.append(
                "  \(action.rawValue): median \(Self.format(Self.percentile(samples, 0.5))) p95 \(Self.format(Self.percentile(samples, 0.95))) reached layout \(matched[action] ?? 0)/\(samples.count)"
            )
            if let miss = firstMiss[action] { lines.append("    first miss \(miss)") }
        }
        return lines
    }

    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        guard !samples.isEmpty else { return .nan }
        let sorted = samples.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f ms", milliseconds)
    }
}

enum LiveAX {
    static func frame(of window: AXUIElement) -> CGRect {
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
        var point = CGPoint.zero
        var extent = CGSize.zero
        if let position { AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point) }
        if let size { AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) }
        return CGRect(origin: point, size: extent)
    }

    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        var size = frame.size
        var position = frame.origin
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &position)!)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    }

    static func windows(of processIdentifier: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        let application = AXUIElementCreateApplication(processIdentifier)
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return value as? String
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        return (value as? Bool) == true
    }

    static func pressCloseButton(of window: AXUIElement) {
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button else { return }
        AXUIElementPerformAction(unsafeDowncast(button, to: AXUIElement.self), kAXPressAction as CFString)
    }
}

/// A plain AppKit window in its own process, built once per test run.
private struct LiveWindowFixture {
    enum Mode: String, CaseIterable {
        case resizable
        /// Like System Settings: the width cannot change.
        case fixedWidth
        /// Like Terminal: the size snaps to a character grid.
        case grid
    }

    let executable: URL

    static func build() throws -> LiveWindowFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BroccoliLiveWindowFixture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("main.swift")
        let executable = directory.appendingPathComponent("BroccoliLiveWindowFixture")
        try Self.source.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-O", source.path, "-o", executable.path]
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            throw XCTSkip("Could not build the fixture window application.")
        }
        return LiveWindowFixture(executable: executable)
    }

    func launch(_ mode: Mode) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = [mode.rawValue]
        try process.run()
        return process
    }

    static func firstWindow(of processIdentifier: pid_t) async throws -> AXUIElement {
        for _ in 0..<50 {
            if let window = LiveAX.windows(of: processIdentifier).first { return window }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw XCTSkip("The fixture window did not appear.")
    }

    private static let source = """
    import AppKit
    let mode = CommandLine.arguments.dropFirst().first ?? "resizable"
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 640, height: 420),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    switch mode {
    case "fixedWidth":
        window.minSize = NSSize(width: 640, height: 200)
        window.maxSize = NSSize(width: 640, height: 10_000)
    case "grid":
        window.contentResizeIncrements = NSSize(width: 7, height: 14)
    default:
        break
    }
    window.title = "Broccoli Fixture (\\(mode))"
    window.makeKeyAndOrderFront(nil)
    app.activate()
    app.run()
    """
}

/// A new TextEdit document, closed again afterward. TextEdit quits too if it was not running.
@MainActor
private final class LiveTextEditDocument {
    let processIdentifier: pid_t
    let window: AXUIElement
    private let fileURL: URL
    private let application: NSRunningApplication
    private let wasRunning: Bool

    private init(processIdentifier: pid_t, window: AXUIElement, fileURL: URL, application: NSRunningApplication, wasRunning: Bool) {
        self.processIdentifier = processIdentifier
        self.window = window
        self.fileURL = fileURL
        self.application = application
        self.wasRunning = wasRunning
    }

    static func open() async throws -> LiveTextEditDocument? {
        let bundleIdentifier = "com.apple.TextEdit"
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("Broccoli Latency.txt")
        try "Broccoli window latency measurement".write(to: fileURL, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL, configuration: configuration)
        for _ in 0..<50 {
            if let window = LiveAX.windows(of: application.processIdentifier)
                .first(where: { LiveAX.title(of: $0)?.hasPrefix("Broccoli Latency") == true }) {
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return LiveTextEditDocument(
                    processIdentifier: application.processIdentifier,
                    window: window,
                    fileURL: fileURL,
                    application: application,
                    wasRunning: wasRunning
                )
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func close() {
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success, let button {
            AXUIElementPerformAction(unsafeDowncast(button, to: AXUIElement.self), kAXPressAction as CFString)
        }
        if !wasRunning { application.terminate() }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
