import AppKit
import XCTest
@testable import BroccoliApp

/// Hosts AppKit test windows off-screen so XCTest never flashes the launcher on the desktop.
enum BroccoliAppTestWindows {
    static let offscreenOrigin = NSPoint(x: -16_000, y: -16_000)

    @MainActor
    static func window(
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.borderless],
        backing: NSWindow.BackingStoreType = .buffered,
        deferred: Bool = false
    ) -> NSWindow {
        let window = OffscreenTestWindow(
            contentRect: NSRect(origin: offscreenOrigin, size: size),
            styleMask: styleMask,
            backing: backing,
            defer: deferred
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor
    static func panel(
        size: NSSize,
        styleMask: NSWindow.StyleMask = .borderless,
        backing: NSWindow.BackingStoreType = .buffered,
        deferred: Bool = false
    ) -> NSPanel {
        let panel = OffscreenTestPanel(
            contentRect: NSRect(origin: offscreenOrigin, size: size),
            styleMask: styleMask,
            backing: backing,
            defer: deferred
        )
        panel.isReleasedWhenClosed = false
        return panel
    }

    @MainActor
    static func placeOffscreen(_ window: NSWindow) {
        window.setFrameOrigin(offscreenOrigin)
    }
}

private final class OffscreenTestWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class OffscreenTestPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class BroccoliAppTestWindowCleanupTests: XCTestCase {
    func testAutomatedLauncherPresentationStaysOffscreen() {
        _ = NSApplication.shared
        let controller = LauncherPanelController()
        controller.applyAppearance(.defaults(design: .minimal), force: true)
        controller.showForAutomatedTests()
        defer { controller.dismiss(notify: false) }

        XCTAssertTrue(controller.isVisible)
        let frame = controller.visibilityIsolationWindow.frame
        XCTAssertEqual(frame.origin, LauncherPanelController.automatedTestOrigin)
        XCTAssertLessThanOrEqual(frame.maxX, 0)
        XCTAssertLessThanOrEqual(frame.maxY, 0)
    }
}
