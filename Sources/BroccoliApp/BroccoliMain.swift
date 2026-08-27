import AppKit
import SwiftUI

/// SwiftUI requires a primary scene to vend presentation actions such as `openSettings`, but
/// Broccoli's real launcher is an AppKit panel. Keep the placeholder scene permanently out of
/// the window server even if SwiftUI attempts to reveal it during restoration or app lifecycle
/// transitions.
struct SuppressedLauncherSceneRoot: NSViewRepresentable {
    func makeNSView(context: Context) -> SuppressedLauncherSceneView {
        SuppressedLauncherSceneView()
    }

    func updateNSView(_ nsView: SuppressedLauncherSceneView, context: Context) {}
}

@MainActor
final class SuppressedLauncherSceneView: NSView {
    private weak var suppressedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard suppressedWindow !== window else { return }

        if let suppressedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: suppressedWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didUpdateNotification,
                object: suppressedWindow
            )
        }
        suppressedWindow = window
        guard let window else { return }

        Self.quarantine(window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(suppressPlaceholderWindow(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(suppressPlaceholderWindow(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
    }

    @objc private func suppressPlaceholderWindow(_ notification: Notification) {
        guard let window = suppressedWindow, window.isVisible else { return }
        Self.quarantine(window)
    }

    private static func quarantine(_ window: NSWindow) {
        window.isRestorable = false
        window.isExcludedFromWindowsMenu = true
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        if window.isVisible { window.orderOut(nil) }
    }
}

@main
struct BroccoliMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        let _ = appDelegate.configureSettingsOpener {
            openSettings()
        }

        // Keep the AppKit launcher panel out of SwiftUI's window restoration while still
        // providing the primary SwiftUI scene context that owns environment presentation
        // actions. Cherry uses the same suppressed-launch WindowGroup pattern.
        WindowGroup("Broccoli", id: "launcher") {
            SuppressedLauncherSceneRoot()
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            BroccoliSettingsSceneRoot(appDelegate: appDelegate)
        }
    }
}
