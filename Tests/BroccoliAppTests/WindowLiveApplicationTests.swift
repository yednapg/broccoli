import AppKit
import ApplicationServices
import XCTest
@testable import BroccoliApp

/// Runs every offered single-window action against real applications and reports, for each
/// one, whether the window reached the layout, took a nearby snapped size, kept its own size
/// centered in the layout, or ended up somewhere it should not. It moves windows and launches
/// applications, so it runs only when `BROCCOLI_LIVE_WINDOW_APPS=1` is set. Each window's frame
/// is restored afterward, and applications the test launched are quit.
/// `BROCCOLI_LIVE_WINDOW_APPS_ONLY` limits the run to a comma-separated list of bundle identifiers.
@MainActor
final class WindowLiveApplicationTests: XCTestCase {
    private struct Target {
        let name: String
        let bundleIdentifier: String
        var opensDocument: URL? = nil
    }

    private enum Verdict: String, CaseIterable {
        case exact
        case snapped
        case ownSize = "own size"
        case stoppedShort = "stopped short"
        case wrong
        case failed
    }

    /// macOS's own applications, which cover the window kinds that matter: Finder, a fixed-width
    /// SwiftUI window, a fixed-size window, a character grid, and document windows.
    private static let targets: [Target] = [
        Target(name: "Finder", bundleIdentifier: "com.apple.finder", opensDocument: FileManager.default.homeDirectoryForCurrentUser),
        Target(name: "System Settings", bundleIdentifier: "com.apple.systempreferences"),
        Target(name: "Calculator", bundleIdentifier: "com.apple.calculator"),
        Target(name: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        Target(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit", opensDocument: LiveDocuments.text),
        Target(name: "Preview", bundleIdentifier: "com.apple.Preview", opensDocument: LiveDocuments.image),
        Target(name: "Notes", bundleIdentifier: "com.apple.Notes"),
        Target(name: "Activity Monitor", bundleIdentifier: "com.apple.ActivityMonitor"),
        Target(name: "App Store", bundleIdentifier: "com.apple.AppStore"),
        Target(name: "Calendar", bundleIdentifier: "com.apple.iCal"),
    ]

    private static let singleActions: [WindowAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter,
        .firstThird, .lastThird, .maximize, .minimized, .maximizeHeight, .maximizeWidth,
        .center, .makeLarger, .makeSmaller,
    ]

    private var lines: [String] = []

    func testEveryLayoutOnInstalledApplications() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BROCCOLI_LIVE_WINDOW_APPS"] == "1" else {
            throw XCTSkip("Set BROCCOLI_LIVE_WINDOW_APPS=1 to move real application windows.")
        }
        guard AXIsProcessTrusted() else { throw XCTSkip("The test process needs Accessibility access.") }

        let only = environment["BROCCOLI_LIVE_WINDOW_APPS_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let screens = WindowManager().screenFrames()
        try LiveDocuments.prepare()
        defer { LiveDocuments.remove() }

        // Written after every application so a stopped run keeps what it measured.
        func writeReport() throws {
            guard let path = environment["BROCCOLI_LIVE_WINDOW_APPS_REPORT"] else { return }
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        for target in Self.targets where only?.contains(target.bundleIdentifier) ?? true {
            guard let session = await LiveApplicationSession.open(
                bundleIdentifier: target.bundleIdentifier,
                document: target.opensDocument
            ) else {
                lines.append("\(target.name): not installed or did not launch")
                continue
            }
            await measure(target: target, session: session, screens: screens)
            session.close()
            try writeReport()
        }
        print("\n=== Window layouts on real applications ===\n\(lines.joined(separator: "\n"))\n")
    }

    private func measure(target: Target, session: LiveApplicationSession, screens: [CGRect]) async {
        let operation = WindowAccessibilityOperation()
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        var window: AXUIElement?
        var lookupError: Error?
        while window == nil, ProcessInfo.processInfo.systemUptime < deadline {
            do {
                window = try operation.focusedWindow(
                    targetPID: session.processIdentifier,
                    deadline: ProcessInfo.processInfo.systemUptime + 4,
                    checkCancellation: {}
                )
            } catch {
                lookupError = error
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        guard let window else {
            lines.append("\(target.name): no window Broccoli would act on (\(lookupError.map(String.init(describing:)) ?? "none"))")
            return
        }
        guard !LiveAX.isFullScreen(window) else {
            lines.append("\(target.name): window is in full screen, skipped")
            return
        }
        session.originalFrame = LiveAX.frame(of: window)
        session.window = window

        let screen = screens[Self.screenIndex(of: LiveAX.frame(of: window), in: screens)]
        let start = CGRect(x: screen.maxX - 660, y: screen.maxY - 480, width: 640, height: 460)
        var verdicts: [Verdict: Int] = [:]
        var notes: [String] = []
        var timings: [Double] = []

        func run(
            _ action: WindowAction,
            label: String,
            options: WindowLayoutOptions = .standard,
            cycleIndex: Int = 0,
            expected: CGRect? = nil
        ) async {
            let before = LiveAX.frame(of: window)
            let target = expected ?? WindowGeometry.frame(
                for: action,
                window: before,
                screen: screen,
                options: options,
                cycleFraction: WindowGeometry.cycleFractions[cycleIndex]
            )
            let began = ProcessInfo.processInfo.systemUptime
            var verdict: Verdict
            var reported: CGRect?
            do {
                reported = try operation.perform(
                    .action(action),
                    targetPID: session.processIdentifier,
                    screens: screens,
                    options: options,
                    pointerScreenIndex: nil,
                    checkCancellation: {}
                )?.result
                timings.append((ProcessInfo.processInfo.systemUptime - began) * 1_000)
                try? await Task.sleep(for: .milliseconds(150))
                let after = LiveAX.frame(of: window)
                verdict = Self.verdict(before: before, target: target, after: after, screen: screen, incremental: action.isIncremental)
                if let reported, !WindowAccessibilityOperation.framesMatch(reported, after, originTolerance: 2, sizeTolerance: 2) {
                    notes.append("  \(label): moved after Broccoli finished: saw \(reported), settled at \(after)")
                }
                if verdict == .wrong {
                    notes.append("  \(label): from \(before) asked \(target) got \(after)")
                }
            } catch {
                verdict = .failed
                notes.append("  \(label): failed: \(error)")
            }
            verdicts[verdict, default: 0] += 1
        }

        func reset() async {
            LiveAX.setFrame(start, of: window)
            try? await Task.sleep(for: .milliseconds(150))
        }

        for action in Self.singleActions {
            await reset()
            await run(action, label: action.rawValue)
        }
        var gaps = WindowLayoutOptions.standard
        gaps.screenEdgeGap = 8
        gaps.windowGap = 8
        for action in [WindowAction.leftHalf, .rightHalf, .maximize, .bottomRightQuarter] {
            await reset()
            await run(action, label: "\(action.rawValue) with gaps", options: gaps)
        }
        for action in [WindowAction.leftHalf, .rightHalf, .topLeftQuarter] {
            await reset()
            for press in 0..<3 {
                await run(action, label: "\(action.rawValue) press \(press + 1)", cycleIndex: press)
            }
        }
        await reset()
        let restoreTarget = LiveAX.frame(of: window)
        await run(.maximize, label: "maximize before restore")
        await run(.leftHalf, label: "left half before restore")
        await run(.restore, label: "restore", expected: restoreTarget)
        await reset()
        for action in [WindowAction.maximize, .leftHalf, .rightHalf, .minimized, .center, .topHalf, .bottomHalf, .maximize] {
            await run(action, label: "chain \(action.rawValue)")
        }
        if screens.count == 1 {
            let before = LiveAX.frame(of: window)
            let moved = (try? operation.perform(.nextDisplay, targetPID: session.processIdentifier, screens: screens, checkCancellation: {})) ?? nil
            if moved != nil || !WindowAccessibilityOperation.framesMatch(before, LiveAX.frame(of: window), originTolerance: 1, sizeTolerance: 1) {
                notes.append("  nextDisplay: moved the window with one display")
                verdicts[.wrong, default: 0] += 1
            }
        }

        let summary = Verdict.allCases.compactMap { verdict in verdicts[verdict].map { "\($0) \(verdict.rawValue)" } }
        lines.append("\(target.name): \(summary.joined(separator: ", ")); median \(Self.format(Self.percentile(timings, 0.5))) p95 \(Self.format(Self.percentile(timings, 0.95)))")
        lines += notes
    }

    private static func verdict(before: CGRect, target: CGRect, after: CGRect, screen: CGRect, incremental: Bool) -> Verdict {
        func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            WindowAccessibilityOperation.framesMatch(lhs, rhs, originTolerance: 2, sizeTolerance: 2)
        }
        if matches(after, target) { return .exact }
        guard after.minX >= screen.minX - 1, after.minY >= screen.minY - 1 else { return .wrong }
        if incremental {
            let kept = WindowScreenGeometry.frame(aligning: after.size, to: target, keepingUnchangedAxesOf: before, screen: screen)
            return matches(after, kept) ? .snapped : .wrong
        }
        let tookWidth = abs(after.width - target.width) <= 24
        let tookHeight = abs(after.height - target.height) <= 24
        let aligned = WindowScreenGeometry.frame(aligning: after.size, to: target, screen: screen)
        if tookWidth, tookHeight { return matches(after, aligned) ? .snapped : .wrong }
        if abs(after.width - before.width) <= 1, abs(after.height - before.height) <= 1 {
            let centered = WindowScreenGeometry.frame(centering: before.size, in: target, screen: screen)
            return matches(after, centered) ? .ownSize : .wrong
        }
        if !tookWidth, !tookHeight, matches(after, aligned) { return .stoppedShort }
        return .wrong
    }

    private static func screenIndex(of frame: CGRect, in screens: [CGRect]) -> Int {
        WindowAccessibilityOperation.screenIndex(containing: frame, in: screens)
    }

    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        guard !samples.isEmpty else { return .nan }
        let sorted = samples.sorted()
        return sorted[min(max(Int((fraction * Double(sorted.count)).rounded(.up)) - 1, 0), sorted.count - 1)]
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f ms", milliseconds)
    }
}

/// Throwaway documents for applications that need one to show a window.
private enum LiveDocuments {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BroccoliLiveDocuments", isDirectory: true)
    static let text = directory.appendingPathComponent("Broccoli Layout Check.txt")
    static let image = directory.appendingPathComponent("Broccoli Layout Check.png")

    static func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "Broccoli layout check".write(to: text, atomically: true, encoding: .utf8)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
        try bitmap?.representation(using: .png, properties: [:])?.write(to: image)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// An application window under test. Restores the window's frame afterward, closes a document
/// window the test opened, and quits the application if the test launched it.
@MainActor
private final class LiveApplicationSession {
    let processIdentifier: pid_t
    var window: AXUIElement?
    var originalFrame: CGRect?
    private let application: NSRunningApplication
    private let wasRunning: Bool
    private let openedDocument: Bool

    private init(application: NSRunningApplication, wasRunning: Bool, openedDocument: Bool) {
        self.application = application
        processIdentifier = application.processIdentifier
        self.wasRunning = wasRunning
        self.openedDocument = openedDocument
    }

    static func open(bundleIdentifier: String, document: URL?) async -> LiveApplicationSession? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        // Opened behind the frontmost application, so the run never takes keyboard focus from
        // someone using the Mac. Broccoli acts on an application's own focused window either way.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let application: NSRunningApplication?
        if let document {
            application = try? await NSWorkspace.shared.open([document], withApplicationAt: url, configuration: configuration)
        } else if wasRunning {
            application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        } else {
            application = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        guard let application else { return nil }
        return LiveApplicationSession(application: application, wasRunning: wasRunning, openedDocument: document != nil)
    }

    func close() {
        if let window, let originalFrame { LiveAX.setFrame(originalFrame, of: window) }
        if wasRunning {
            if openedDocument, let window { LiveAX.pressCloseButton(of: window) }
        } else {
            application.terminate()
        }
    }
}
