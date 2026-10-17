@preconcurrency import AppKit

/// WindowServer's blur of whatever lies behind a non-opaque window. AppKit has no public way
/// to choose its radius, so the CoreGraphics functions are resolved at run time. Without
/// them `isAvailable` is false and the launcher keeps its opaque fill.
@MainActor
enum LauncherWindowBackdropBlur {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetBlurRadius = @convention(c) (Int32, Int32, Int32) -> Int32

    private static let functions: (connection: MainConnection, setRadius: SetBlurRadius)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connection = dlsym(handle, "CGSMainConnectionID"),
              let setRadius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return (
            unsafeBitCast(connection, to: MainConnection.self),
            unsafeBitCast(setRadius, to: SetBlurRadius.self)
        )
    }()

    static var isAvailable: Bool { functions != nil }

    /// Zero removes the blur. The window must already have a window number.
    @discardableResult
    static func apply(radius: Int, to window: NSWindow) -> Bool {
        guard let functions, window.windowNumber > 0 else { return false }
        return functions.setRadius(
            functions.connection(),
            Int32(window.windowNumber),
            Int32(max(0, radius))
        ) == 0
    }
}
