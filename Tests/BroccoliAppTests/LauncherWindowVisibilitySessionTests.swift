import AppKit
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherWindowVisibilitySessionTests: XCTestCase {
    private final class OrderingWindow: NSWindow {
        var orderFrontCount = 0
        var orderBackCount = 0

        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }

        override func orderFront(_ sender: Any?) {
            orderFrontCount += 1
            super.orderFront(sender)
        }

        override func orderBack(_ sender: Any?) {
            orderBackCount += 1
            super.orderBack(sender)
        }

        func resetOrderingCounts() {
            orderFrontCount = 0
            orderBackCount = 0
        }
    }

    func testExternalDispatchRestoresSettingsBehindForegroundApplication() {
        let launcher = BroccoliAppTestWindows.panel(
            size: NSSize(width: 100, height: 40),
            deferred: true
        )
        let settings = OrderingWindow(
            contentRect: NSRect(
                origin: BroccoliAppTestWindows.offscreenOrigin,
                size: NSSize(width: 240, height: 180)
            ),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        BroccoliAppTestWindows.placeOffscreen(settings)
        defer {
            launcher.orderOut(nil)
            settings.orderOut(nil)
        }

        launcher.orderFront(nil)
        settings.orderFront(nil)
        settings.resetOrderingCounts()

        let session = LauncherWindowVisibilitySession()
        session.suppress(windows: [settings, launcher], excluding: launcher)
        XCTAssertFalse(settings.isVisible)

        session.restore(ordering: .behindForegroundApplication)

        XCTAssertTrue(settings.isVisible)
        XCTAssertEqual(settings.orderBackCount, 1)
        XCTAssertEqual(settings.orderFrontCount, 0)
        XCTAssertEqual(session.suppressedWindowCount, 0)
    }
}
