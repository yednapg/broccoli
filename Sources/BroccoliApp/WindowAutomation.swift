@preconcurrency import AppKit
import ApplicationServices
import Foundation

/// Which layout a window dragged to a display edge snaps to.
enum WindowSnapZone {
    /// How close to the display edge the pointer must be.
    static let edgeMargin: CGFloat = 4
    /// How far along an edge a corner reaches.
    static let cornerLength: CGFloat = 48

    /// `point` and `display` are in Accessibility coordinates; `display` is the full display
    /// frame, including the menu bar and Dock. The middle of the bottom edge does not snap:
    /// that is where the pointer goes to reveal a hidden Dock.
    static func action(at point: CGPoint, in display: CGRect) -> WindowAction? {
        guard display.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        let nearLeft = point.x <= display.minX + edgeMargin
        let nearRight = point.x >= display.maxX - 1 - edgeMargin
        let nearTop = point.y <= display.minY + edgeMargin
        let nearBottom = point.y >= display.maxY - 1 - edgeMargin
        let topCorner = point.y <= display.minY + cornerLength
        let bottomCorner = point.y >= display.maxY - cornerLength
        let leftCorner = point.x <= display.minX + cornerLength
        let rightCorner = point.x >= display.maxX - cornerLength

        if nearLeft {
            return topCorner ? .topLeftQuarter : bottomCorner ? .bottomLeftQuarter : .leftHalf
        }
        if nearRight {
            return topCorner ? .topRightQuarter : bottomCorner ? .bottomRightQuarter : .rightHalf
        }
        if nearTop {
            return leftCorner ? .topLeftQuarter : rightCorner ? .topRightQuarter : .maximize
        }
        if nearBottom {
            return leftCorner ? .bottomLeftQuarter : rightCorner ? .bottomRightQuarter : nil
        }
        return nil
    }
}

/// macOS's own tiling of dragged windows, from Desktop & Dock settings. Broccoli snaps a
/// dragged window only while this is off, so a window never snaps twice.
enum MacOSWindowTiling {
    private static let domain = "com.apple.WindowManager" as CFString
    /// “Drag windows to screen edges to tile” and “Drag windows to menu bar to fill screen”.
    private static let dragKeys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"] as [CFString]

    /// Both settings are on unless the user or Broccoli turned them off.
    static var tilesDraggedWindows: Bool {
        CFPreferencesAppSynchronize(domain)
        return dragKeys.contains { key in
            (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.boolValue ?? true
        }
    }

    /// Turns macOS's drag tiling off, or back to its default of on, and reports whether macOS
    /// now has that setting.
    @discardableResult
    static func setTilesDraggedWindows(_ enabled: Bool) -> Bool {
        for key in dragKeys {
            CFPreferencesSetAppValue(key, enabled ? nil : kCFBooleanFalse, domain)
        }
        CFPreferencesAppSynchronize(domain)
        return tilesDraggedWindows == enabled
    }

    static func openDesktopAndDockSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Snaps a window into a layout when the user drags it to a display edge or corner, showing
/// where it will land before the mouse button is released. It follows the window under the
/// pointer through the window server, so a drag that is not moving a window, such as selecting
/// text, costs a few window-list reads and never queries the application.
@MainActor
final class WindowDragSnapController {
    private struct Drag {
        let window: OnScreenWindow
        let startedAt: TimeInterval
        var isMovingWindow = false
    }

    /// The window server moves a dragged window a frame or two behind the pointer. A drag that
    /// has not moved the window for this long is not a window drag.
    private static let movementWait: TimeInterval = 0.3

    private let windowManager: WindowManager
    private let overlay = WindowSnapOverlay()
    private var monitors: [Any] = []
    private var mouseDownLocation: CGPoint?
    private var drag: Drag?
    private var ignoresGesture = false
    private var zone: WindowAction?
    private var displays: [(display: CGRect, usable: CGRect)] = []
    private var layoutOptions = WindowLayoutOptions.standard

    var ignoredBundleIdentifiers: Set<String> = []
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    private func start() {
        let types: [NSEvent.EventTypeMask] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        monitors = types.compactMap { type in
            NSEvent.addGlobalMonitorForEvents(matching: type) { [weak self] event in
                let eventType = event.type
                MainActor.assumeIsolated { self?.handle(eventType) }
            }
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func reset() {
        mouseDownLocation = nil
        drag = nil
        ignoresGesture = false
        zone = nil
        overlay.hide()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            reset()
            mouseDownLocation = Self.pointerLocation()
        case .leftMouseDragged:
            guard !ignoresGesture else { return }
            if drag == nil {
                beginDrag()
            } else if drag?.isMovingWindow == true {
                updateZone()
            } else {
                confirmWindowMovement()
            }
        case .leftMouseUp:
            snapDraggedWindow()
            reset()
        default:
            break
        }
    }

    /// Finds the window the button went down on. By the first drag event a fast drag can already
    /// have carried the pointer off a title bar, but the window has barely moved.
    private func beginDrag() {
        // Option-drag is macOS's own tiling gesture.
        guard !NSEvent.modifierFlags.contains(.option),
              let window = OnScreenWindow.frontmost(at: mouseDownLocation ?? Self.pointerLocation()),
              !(NSRunningApplication(processIdentifier: window.processIdentifier)?
                .bundleIdentifier.map(ignoredBundleIdentifiers.contains) ?? false) else {
            ignoresGesture = true
            return
        }
        drag = Drag(window: window, startedAt: ProcessInfo.processInfo.systemUptime)
    }

    /// The window is being dragged when it moves without changing size. Resizing it, or dragging
    /// for a moment without moving it, ends the gesture for snapping.
    private func confirmWindowMovement() {
        guard let drag, let bounds = OnScreenWindow.bounds(of: drag.window.windowID) else {
            ignoresGesture = true
            return
        }
        let start = drag.window.bounds
        let sameSize = abs(bounds.width - start.width) < 2 && abs(bounds.height - start.height) < 2
        let moved = abs(bounds.minX - start.minX) > 3 || abs(bounds.minY - start.minY) > 3
        let waited = ProcessInfo.processInfo.systemUptime - drag.startedAt
        if !sameSize || (!moved && waited > Self.movementWait) {
            ignoresGesture = true
        } else if moved {
            guard !MacOSWindowTiling.tilesDraggedWindows else {
                ignoresGesture = true
                return
            }
            self.drag?.isMovingWindow = true
            displays = Self.displays(usable: windowManager.screenFrames())
            layoutOptions = windowManager.layoutOptionsProvider()
            updateZone()
        }
    }

    private func updateZone() {
        guard let drag else { return }
        let pointer = Self.pointerLocation()
        let match = displays.first { $0.display.insetBy(dx: -1, dy: -1).contains(pointer) }
        let newZone = NSEvent.modifierFlags.contains(.option)
            ? nil
            : match.flatMap { WindowSnapZone.action(at: pointer, in: $0.display) }
        guard newZone != zone else { return }
        zone = newZone
        guard let newZone, let match, let primary = NSScreen.screens.first else {
            overlay.hide()
            return
        }
        let target = WindowGeometry.frame(
            for: newZone,
            window: drag.window.bounds,
            screen: match.usable,
            options: layoutOptions
        )
        overlay.show(appKitFrame: WindowScreenGeometry.appKitFrame(for: target, primaryScreenFrame: primary.frame))
    }

    private func snapDraggedWindow() {
        guard let drag, drag.isMovingWindow, let zone, !NSEvent.modifierFlags.contains(.option) else { return }
        let frame = OnScreenWindow.bounds(of: drag.window.windowID)
        Task { [windowManager] in
            try? await windowManager.perform(
                .action(zone),
                targetPID: drag.window.processIdentifier,
                windowFrame: frame
            )
        }
    }

    private static func pointerLocation() -> CGPoint {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: location.x, y: primaryHeight - location.y)
    }

    private static func displays(usable: [CGRect]) -> [(display: CGRect, usable: CGRect)] {
        guard let primary = NSScreen.screens.first else { return [] }
        return zip(NSScreen.screens, usable).map { screen, usable in
            (WindowScreenGeometry.accessibilityFrame(for: screen.frame, primaryScreenFrame: primary.frame), usable)
        }
    }
}

/// The footprint shown where a dragged window will snap: an accent tint with a window's
/// corners that fades in and follows the zone.
@MainActor
final class WindowSnapOverlay {
    private static let animationDuration: TimeInterval = 0.12
    private static let cornerRadius: CGFloat = 16

    private var panel: NSPanel?
    /// Counts presentations so a fade-out that finishes after the overlay was shown again
    /// does not hide it.
    private var presentation = 0

    func show(appKitFrame frame: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        presentation += 1
        applyStyle(to: panel)
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            panel.setFrame(frame, display: true)
            panel.alphaValue = animates ? 0 : 1
            panel.orderFrontRegardless()
        }
        guard animates else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        let hiding = presentation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard self?.presentation == hiding else { return }
                panel?.orderOut(nil)
            }
        }
    }

    private func applyStyle(to panel: NSPanel) {
        guard let view = panel.contentView, let layer = view.layer else { return }
        let increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        // Resolve the accent color for the current appearance on every presentation.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(increasesContrast ? 0.3 : 0.2).cgColor
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(increasesContrast ? 1 : 0.8).cgColor
        }
        layer.borderWidth = increasesContrast ? 3 : 2
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = Self.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.setAccessibilityElement(false)
        panel.contentView = view
        return panel
    }
}

/// Watches applications for windows opening, closing, and changing focus, and retiles the
/// displays shortly afterward. It is event-driven and does no work while windows are idle.
@MainActor
final class WindowTilingController {
    private let windowManager: WindowManager
    private var observers: [pid_t: AXObserver] = [:]
    private var notificationObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var retileTask: Task<Void, Never>?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func scheduleRetile() {
        guard isEnabled else { return }
        retileTask?.cancel()
        retileTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            await self.windowManager.refreshTiling()
        }
    }

    private func start() {
        guard AccessibilityPermissionChecker.isTrusted else { return }
        NSWorkspace.shared.runningApplications.forEach(observe)
        let workspace = NSWorkspace.shared.notificationCenter
        addObserver(workspace, NSWorkspace.didLaunchApplicationNotification) { controller, application in
            if let application { controller.observe(application) }
        }
        addObserver(workspace, NSWorkspace.didTerminateApplicationNotification) { controller, application in
            if let application { controller.forget(application.processIdentifier) }
        }
        // Focusing an application must not rearrange windows. Tiling follows windows
        // opening, closing, hiding, and showing.
        for name in [
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            addObserver(workspace, name) { _, _ in }
        }
        addObserver(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { _, _ in }
        scheduleRetile()
    }

    private func stop() {
        retileTask?.cancel()
        retileTask = nil
        for (center, observer) in notificationObservers { center.removeObserver(observer) }
        notificationObservers = []
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers = [:]
    }

    private func addObserver(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (WindowTilingController, NSRunningApplication?) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, application)
                self.scheduleRetile()
            }
        }
        notificationObservers.append((center, observer))
    }

    private func observe(_ application: NSRunningApplication) {
        let processIdentifier = application.processIdentifier
        guard application.activationPolicy == .regular,
              processIdentifier != ProcessInfo.processInfo.processIdentifier,
              observers[processIdentifier] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(processIdentifier, windowTilingObserverCallback, &created) == .success,
              let observer = created else { return }
        let element = AXUIElementCreateApplication(processIdentifier)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXApplicationHiddenNotification,
            kAXApplicationShownNotification,
        ] {
            AXObserverAddNotification(observer, element, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[processIdentifier] = observer
    }

    private func forget(_ processIdentifier: pid_t) {
        if let observer = observers.removeValue(forKey: processIdentifier) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        windowManager.forgetApplication(processIdentifier)
    }
}

/// Runs on the main run loop, where every observer's source is scheduled.
private func windowTilingObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let controller = Unmanaged<WindowTilingController>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { controller.scheduleRetile() }
}
