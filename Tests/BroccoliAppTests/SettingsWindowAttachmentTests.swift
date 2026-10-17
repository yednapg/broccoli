import AppKit
import XCTest
@testable import BroccoliApp

@MainActor
final class SettingsWindowAttachmentTests: XCTestCase {
    /// Reopening Settings reuses its window without moving the chrome view again. Becoming key
    /// must report the window, or window shortcuts lose track of Settings after a reopen.
    func testSettingsWindowIsReportedAgainWhenItBecomesKey() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let view = SpotlightSettingsNativeWindowChromeView()
        var reported: [NSWindow] = []
        view.onWindowAttached = { reported.append($0) }

        window.contentView?.addSubview(view)
        XCTAssertEqual(reported.count, 1)

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(reported.count, 2)
        XCTAssertTrue(reported.allSatisfy { $0 === window })

        view.removeFromSuperview()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(reported.count, 2, "A detached view stops reporting the window")
    }
}
