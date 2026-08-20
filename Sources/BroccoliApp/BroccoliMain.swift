@preconcurrency import AppKit

@main
@MainActor
struct BroccoliMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        _ = delegate
    }
}
