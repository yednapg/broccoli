import SwiftUI

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
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)

        Settings {
            BroccoliSettingsSceneRoot(appDelegate: appDelegate)
        }
    }
}
