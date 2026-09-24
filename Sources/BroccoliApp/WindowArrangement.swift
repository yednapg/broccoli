@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// A normal, visible window as reported by the window server. Only the owner and bounds are
/// read, which does not require Screen Recording access.
struct OnScreenWindow: Equatable, Sendable {
    let processIdentifier: pid_t
    /// Accessibility coordinates, front-most window first.
    let bounds: CGRect

    static func current() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let processIdentifier = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  processIdentifier != ownProcess,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 40, rect.height >= 40 else { return nil }
            return OnScreenWindow(processIdentifier: processIdentifier, bounds: rect)
        }
    }
}

/// Identifies an Accessibility window element for as long as its application runs.
struct WindowKey: Hashable {
    let element: AXUIElement
    let processIdentifier: pid_t

    init(_ element: AXUIElement) {
        self.element = element
        var processIdentifier: pid_t = 0
        AXUIElementGetPid(element, &processIdentifier)
        self.processIdentifier = processIdentifier
    }

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

/// Frames Broccoli applied, so Restore and repeated presses know where a window came from.
/// Lives only in memory and only on the window worker's queue.
final class WindowHistory {
    struct Entry: Equatable {
        var restoreFrame: CGRect
        var lastApplied: CGRect
        var lastAction: WindowAction?
        var cycleIndex: Int
    }

    static let capacity = 64
    private var entries: [(key: WindowKey, entry: Entry)] = []

    func entry(for key: WindowKey) -> Entry? {
        entries.first { $0.key == key }?.entry
    }

    func record(_ entry: Entry, for key: WindowKey) {
        entries.removeAll { $0.key == key }
        entries.append((key, entry))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    func remove(_ key: WindowKey) {
        entries.removeAll { $0.key == key }
    }

    func removeApplication(_ processIdentifier: pid_t) {
        entries.removeAll { $0.key.processIdentifier == processIdentifier }
    }
}

/// Automatic tiling order and choices. Lives only on the window worker's queue.
final class TilingState {
    /// First window is the main tile; later windows split the remaining space.
    private(set) var order: [WindowKey] = []
    private(set) var floating: Set<WindowKey> = []
    var startsSideBySide = true

    /// Keeps the known order for windows that are still visible and appends new ones.
    func reconcile(with visible: [WindowKey]) -> [WindowKey] {
        let visibleSet = Set(visible)
        order = order.filter(visibleSet.contains) + visible.filter { !order.contains($0) }
        floating = floating.intersection(visibleSet)
        return order
    }

    func toggleFloating(_ key: WindowKey) {
        if floating.remove(key) == nil { floating.insert(key) }
    }

    func swap(_ first: WindowKey, _ second: WindowKey) {
        guard let firstIndex = order.firstIndex(of: first),
              let secondIndex = order.firstIndex(of: second) else { return }
        order.swapAt(firstIndex, secondIndex)
    }

    func removeApplication(_ processIdentifier: pid_t) {
        order.removeAll { $0.processIdentifier == processIdentifier }
        floating = floating.filter { $0.processIdentifier != processIdentifier }
    }
}

struct ManagedWindow {
    let element: AXUIElement
    let key: WindowKey
    let frame: CGRect
    /// Position in the window server's front-to-back order.
    let depth: Int
}

extension WindowAccessibilityOperation {
    /// Every multi-window action waits on several applications, so it gets a longer budget
    /// than a single frame change.
    private var arrangementTimeout: TimeInterval { actionTimeout * 3 }

    // MARK: - Enumeration

    /// Standard, unminimized windows on the current Space, front-most first. Windows from
    /// applications in `excludedBundleIdentifiers` are left out.
    func visibleWindows(
        excludedBundleIdentifiers: Set<String>,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) throws -> [ManagedWindow] {
        let onScreen = onScreenWindows()
        var processOrder: [pid_t] = []
        for window in onScreen where !processOrder.contains(window.processIdentifier) {
            processOrder.append(window.processIdentifier)
        }

        var result: [ManagedWindow] = []
        for processIdentifier in processOrder {
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            if !excludedBundleIdentifiers.isEmpty,
               let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier,
               excludedBundleIdentifiers.contains(bundleIdentifier) {
                continue
            }
            var unmatched = onScreen.enumerated().filter { $0.element.processIdentifier == processIdentifier }
            for element in applicationWindows(processIdentifier) {
                guard (try? windowCandidateResolution(element, deadline: deadline, checkCancellation: checkCancellation))
                        .map({ if case .accepted = $0 { true } else { false } }) == true,
                      !isMinimized(element),
                      let frame = try? frame(of: element, deadline: deadline, checkCancellation: checkCancellation),
                      let match = unmatched.firstIndex(where: {
                          Self.framesMatch($0.element.bounds, frame, originTolerance: 4, sizeTolerance: 4)
                      }) else { continue }
                result.append(ManagedWindow(
                    element: element,
                    key: WindowKey(element),
                    frame: frame,
                    depth: unmatched[match].offset
                ))
                unmatched.remove(at: match)
            }
        }
        return result.sorted { $0.depth < $1.depth }
    }

    func applicationWindows(_ processIdentifier: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = messagingTimeoutSetter(application, messagingTimeout)
        let read = attributeReader(application, kAXWindowsAttribute as CFString)
        guard read.error == .success, let windows = read.value as? [AXUIElement] else { return [] }
        return windows
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        let read = attributeReader(window, kAXMinimizedAttribute as CFString)
        return read.error == .success && (read.value as? Bool) == true
    }

    /// Applies each frame independently. One application refusing a frame must not stop the
    /// rest of the arrangement; only a complete failure is reported.
    private func apply(
        _ placements: [(window: ManagedWindow, frame: CGRect, screen: CGRect)],
        recordsHistory: Bool,
        checkCancellation: () throws -> Void
    ) throws {
        var lastError: Error?
        var applied = 0
        for placement in placements {
            try checkCancellation()
            guard !Self.framesMatch(placement.frame, placement.window.frame, originTolerance: 2, sizeTolerance: 2) else {
                applied += 1
                continue
            }
            do {
                try setFrame(
                    placement.frame,
                    of: placement.window.element,
                    screen: placement.screen,
                    acceptsPartialAxis: true,
                    deadline: uptimeProvider() + actionTimeout,
                    checkCancellation: checkCancellation
                )
                applied += 1
                if recordsHistory {
                    let stored = history.entry(for: placement.window.key)
                    history.record(
                        WindowHistory.Entry(
                            restoreFrame: stored?.restoreFrame ?? placement.window.frame,
                            lastApplied: placement.frame,
                            lastAction: nil,
                            cycleIndex: 0
                        ),
                        for: placement.window.key
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        if applied == 0, let lastError { throw lastError }
    }

    /// The display that owns the focused window, falling back to the display under the
    /// pointer when nothing is focused.
    private func activeScreenIndex(
        targetPID: pid_t?,
        screens: [CGRect],
        pointerScreenIndex: Int?,
        deadline: TimeInterval,
        checkCancellation: () throws -> Void
    ) -> Int {
        if let window = try? focusedWindow(targetPID: targetPID, deadline: deadline, checkCancellation: checkCancellation),
           let frame = try? frame(of: window, deadline: deadline, checkCancellation: checkCancellation) {
            return Self.screenIndex(containing: frame, in: screens)
        }
        return min(pointerScreenIndex ?? 0, screens.count - 1)
    }

    func focusedFrame(targetPID: pid_t?, checkCancellation: () throws -> Void) throws -> CGRect {
        let deadline = uptimeProvider() + actionTimeout
        let window = try focusedWindow(targetPID: targetPID, deadline: deadline, checkCancellation: checkCancellation)
        return try frame(of: window, deadline: deadline, checkCancellation: checkCancellation)
    }

    // MARK: - Tile and cascade

    func arrange(
        _ action: WindowAction,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions,
        pointerScreenIndex: Int?,
        checkCancellation: () throws -> Void
    ) throws {
        let deadline = uptimeProvider() + arrangementTimeout
        let screenIndex = activeScreenIndex(
            targetPID: targetPID,
            screens: screens,
            pointerScreenIndex: pointerScreenIndex,
            deadline: deadline,
            checkCancellation: checkCancellation
        )
        let screen = screens[screenIndex]
        let windows = try visibleWindows(
            excludedBundleIdentifiers: options.ignoredBundleIdentifiers,
            deadline: deadline,
            checkCancellation: checkCancellation
        ).filter { Self.screenIndex(containing: $0.frame, in: screens) == screenIndex }
        guard !windows.isEmpty else { throw WindowManagementError.noWindow }

        let bounds = WindowGeometry.inset(screen, by: options.screenEdgeGap)
        let placements: [(window: ManagedWindow, frame: CGRect, screen: CGRect)]
        switch action {
        case .tileAll:
            let ordered = windows.sorted(by: Self.readingOrder)
            let frames = WindowGeometry.gridFrames(count: ordered.count, in: bounds, gap: options.windowGap)
            placements = zip(ordered, frames).map { ($0, $1, screen) }
        case .cascadeAll:
            let backToFront = Array(windows.reversed())
            let frames = WindowGeometry.cascadeFrames(sizes: backToFront.map(\.frame.size), in: bounds)
            placements = zip(backToFront, frames).map { ($0, $1, screen) }
        default:
            return
        }
        try apply(placements, recordsHistory: true, checkCancellation: checkCancellation)
    }

    /// Top-to-bottom, then left-to-right, with a small band so windows that are almost level
    /// count as one row.
    static func readingOrder(_ lhs: ManagedWindow, _ rhs: ManagedWindow) -> Bool {
        if abs(lhs.frame.minY - rhs.frame.minY) > 40 { return lhs.frame.minY < rhs.frame.minY }
        return lhs.frame.minX < rhs.frame.minX
    }

    // MARK: - Automatic tiling

    func performTilingCommand(
        _ action: WindowAction,
        targetPID: pid_t?,
        screens: [CGRect],
        options: WindowLayoutOptions,
        checkCancellation: () throws -> Void
    ) throws {
        switch action {
        case .rotateLayout:
            tiling.startsSideBySide.toggle()
        case .toggleFloating:
            let deadline = uptimeProvider() + actionTimeout
            let focused = try focusedWindow(targetPID: targetPID, deadline: deadline, checkCancellation: checkCancellation)
            tiling.toggleFloating(WindowKey(focused))
            guard options.automaticTilingEnabled else { return }
        default:
            break
        }
        // Retile Windows and Rotate also arrange the display once when automatic tiling is off.
        try retile(screens: screens, options: options, force: true, checkCancellation: checkCancellation)
    }

    func retile(
        screens: [CGRect],
        options: WindowLayoutOptions,
        force: Bool = false,
        checkCancellation: () throws -> Void
    ) throws {
        guard options.automaticTilingEnabled || force else { return }
        let deadline = uptimeProvider() + arrangementTimeout
        let windows = try visibleWindows(
            excludedBundleIdentifiers: options.ignoredBundleIdentifiers,
            deadline: deadline,
            checkCancellation: checkCancellation
        ).filter { settableChecker($0.element, kAXSizeAttribute as CFString) }
        let byKey = Dictionary(windows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let order = tiling.reconcile(with: windows.sorted(by: Self.readingOrder).map(\.key))
            .filter { !tiling.floating.contains($0) }

        var placements: [(window: ManagedWindow, frame: CGRect, screen: CGRect)] = []
        for (screenIndex, screen) in screens.enumerated() {
            let tiles = order.compactMap { byKey[$0] }.filter {
                Self.screenIndex(containing: $0.frame, in: screens) == screenIndex
            }
            guard !tiles.isEmpty else { continue }
            let bounds = WindowGeometry.inset(screen, by: options.screenEdgeGap)
            let landscape = screen.width >= screen.height
            let frames = WindowGeometry.tiledFrames(
                count: tiles.count,
                in: bounds,
                gap: options.windowGap,
                startsSideBySide: landscape == tiling.startsSideBySide
            )
            placements += zip(tiles, frames).map { ($0, $1, screen) }
        }
        guard !placements.isEmpty else { return }
        try apply(placements, recordsHistory: false, checkCancellation: checkCancellation)
    }

    // MARK: - Workspaces

    func captureWorkspaceEntries(
        screens: [CGRect],
        options: WindowLayoutOptions,
        checkCancellation: () throws -> Void
    ) throws -> [WindowWorkspace.Entry] {
        let deadline = uptimeProvider() + arrangementTimeout
        let entries: [WindowWorkspace.Entry] = try visibleWindows(
            excludedBundleIdentifiers: [],
            deadline: deadline,
            checkCancellation: checkCancellation
        ).compactMap { window in
            guard let bundleIdentifier = NSRunningApplication(
                processIdentifier: window.key.processIdentifier
            )?.bundleIdentifier else { return nil }
            let displayIndex = Self.screenIndex(containing: window.frame, in: screens)
            return WindowGeometry.workspaceEntry(
                bundleIdentifier: bundleIdentifier,
                frame: window.frame,
                screen: screens[displayIndex],
                displayIndex: displayIndex
            )
        }
        guard !entries.isEmpty else { throw WindowManagementError.noWindow }
        return Array(entries.prefix(WindowWorkspace.maximumEntries))
    }

    /// Places each saved window of every application in the workspace. Applications that
    /// were just launched get a few seconds to open their first windows.
    func applyWorkspace(
        _ workspace: WindowWorkspace,
        screens: [CGRect],
        checkCancellation: () throws -> Void
    ) throws {
        let deadline = uptimeProvider() + arrangementTimeout
        var remaining: [String: [WindowWorkspace.Entry]] = [:]
        var bundleOrder: [String] = []
        for entry in workspace.entries {
            if remaining[entry.bundleIdentifier] == nil { bundleOrder.append(entry.bundleIdentifier) }
            remaining[entry.bundleIdentifier, default: []].append(entry)
        }

        var placements: [(window: ManagedWindow, frame: CGRect, screen: CGRect)] = []
        var poll = 0
        while !bundleOrder.isEmpty {
            try checkReady(deadline: deadline, checkCancellation: checkCancellation)
            for bundleIdentifier in bundleOrder {
                guard let entries = remaining[bundleIdentifier] else { continue }
                let windows = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                    .flatMap { applicationWindows($0.processIdentifier) }
                    .filter {
                        guard case .accepted? = try? windowCandidateResolution(
                            $0,
                            deadline: deadline,
                            checkCancellation: checkCancellation
                        ) else { return false }
                        return !isMinimized($0)
                    }
                guard windows.count >= entries.count || (poll > 0 && !windows.isEmpty && poll >= 20) else { continue }
                for (entry, element) in zip(entries, windows) {
                    guard let current = try? frame(of: element, deadline: deadline, checkCancellation: checkCancellation) else {
                        continue
                    }
                    let screen = screens[min(entry.displayIndex, screens.count - 1)]
                    placements.append((
                        ManagedWindow(element: element, key: WindowKey(element), frame: current, depth: 0),
                        WindowGeometry.frame(for: entry, screen: screen),
                        screen
                    ))
                }
                remaining[bundleIdentifier] = nil
            }
            bundleOrder.removeAll { remaining[$0] == nil }
            guard !bundleOrder.isEmpty, poll < 40 else { break }
            poll += 1
            frameSettlementWaiter(poll)
        }
        guard !placements.isEmpty else { throw WindowManagementError.noWindow }
        try apply(placements, recordsHistory: true, checkCancellation: checkCancellation)
    }
}
