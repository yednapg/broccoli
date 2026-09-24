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
    /// frame, including the menu bar and Dock.
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
            if leftCorner { return .bottomLeftQuarter }
            if rightCorner { return .bottomRightQuarter }
            let share = (point.x - display.minX) / max(1, display.width)
            return share < 1.0 / 3.0 ? .firstThird : share < 2.0 / 3.0 ? .bottomHalf : .lastThird
        }
        return nil
    }
}

/// Snaps a window into a layout when the user drags it to a display edge or corner, showing
/// where it will land before the mouse button is released.
@MainActor
final class WindowDragSnapController {
    private let windowManager: WindowManager
    private let overlay = WindowSnapOverlay()
    private var monitors: [Any] = []
    private var dragEventCount = 0
    private var targetPID: pid_t?
    private var baseline: CGRect?
    private var isSampling = false
    private var isMovingWindow = false
    private var zone: WindowAction?

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
        dragEventCount = 0
        targetPID = nil
        baseline = nil
        isSampling = false
        isMovingWindow = false
        zone = nil
        overlay.hide()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            reset()
        case .leftMouseDragged:
            dragEventCount += 1
            if !isMovingWindow {
                confirmWindowMovement()
            } else {
                updateZone()
            }
        case .leftMouseUp:
            if isMovingWindow, let zone, let targetPID {
                Task { [windowManager] in
                    try? await windowManager.perform(.action(zone), targetPID: targetPID)
                }
            }
            reset()
        default:
            break
        }
    }

    /// A drag only snaps when it is moving the focused window: its origin changes while its
    /// size stays the same. Selecting text or resizing a window never snaps.
    private func confirmWindowMovement() {
        guard !isSampling, dragEventCount >= 2 else { return }
        if targetPID == nil {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !(application.bundleIdentifier.map(ignoredBundleIdentifiers.contains) ?? false) else {
                dragEventCount = -.max
                return
            }
            targetPID = application.processIdentifier
        }
        guard baseline == nil || dragEventCount >= 6 else { return }
        isSampling = true
        let processIdentifier = targetPID
        Task { [weak self, windowManager] in
            let frame = await windowManager.focusedWindowFrame(targetPID: processIdentifier)
            guard let self, self.targetPID == processIdentifier else { return }
            self.isSampling = false
            guard let frame else { return }
            guard let baseline = self.baseline else {
                self.baseline = frame
                return
            }
            let moved = abs(frame.minX - baseline.minX) > 3 || abs(frame.minY - baseline.minY) > 3
            let sameSize = abs(frame.width - baseline.width) < 2 && abs(frame.height - baseline.height) < 2
            if moved && sameSize {
                self.isMovingWindow = true
                self.updateZone()
            } else if !sameSize {
                self.dragEventCount = -.max
            }
        }
    }

    private func updateZone() {
        guard let primary = NSScreen.screens.first else { return }
        let location = NSEvent.mouseLocation
        let point = CGPoint(x: location.x, y: primary.frame.maxY - location.y)
        let usableFrames = windowManager.screenFrames()
        for (index, screen) in NSScreen.screens.enumerated() where index < usableFrames.count {
            let display = WindowScreenGeometry.accessibilityFrame(for: screen.frame, primaryScreenFrame: primary.frame)
            guard display.insetBy(dx: -1, dy: -1).contains(point) else { continue }
            zone = WindowSnapZone.action(at: point, in: display)
            guard let zone, let baseline else {
                overlay.hide()
                return
            }
            let target = WindowGeometry.frame(
                for: zone,
                window: baseline,
                screen: usableFrames[index],
                options: windowManager.layoutOptionsProvider()
            )
            overlay.show(appKitFrame: WindowScreenGeometry.accessibilityFrame(
                for: target,
                primaryScreenFrame: primary.frame
            ))
            return
        }
        zone = nil
        overlay.hide()
    }
}

/// The translucent footprint shown where a dragged window will snap.
@MainActor
final class WindowSnapOverlay {
    private var panel: NSPanel?

    func show(appKitFrame frame: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let layer = panel.contentView?.layer {
            // Resolve the accent color for the current appearance on every presentation.
            panel.contentView?.effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            }
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
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
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 2
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
