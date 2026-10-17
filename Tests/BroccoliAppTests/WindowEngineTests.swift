import ApplicationServices
import XCTest
@testable import BroccoliApp

/// Every layout against windows that behave like real AppKit windows.
@MainActor
final class WindowEngineTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 30, width: 1_680, height: 1_020)
    private let layouts: [WindowAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .minimized, .center,
        .firstThird, .lastThird, .topLeftQuarter, .bottomRightQuarter,
    ]

    private func starts(size: CGSize) -> [CGRect] {
        [
            CGRect(origin: CGPoint(x: 500, y: 250), size: size),
            CGRect(origin: CGPoint(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 20), size: size),
            CGRect(origin: CGPoint(x: screen.maxX - size.width, y: 300), size: size),
        ]
    }

    private func perform(_ action: WindowAction, on window: SimulatedWindow, with operation: WindowAccessibilityOperation) throws {
        try operation.perform(action, targetPID: window.processIdentifier, screens: [screen], checkCancellation: {})
    }

    /// The Finder report: an ordinary window near the bottom-right corner reached only Left and
    /// Right Half. Every layout must reach its frame from every starting point, every time.
    func testOrdinaryWindowReachesEveryLayoutFromAnywhere() throws {
        for start in starts(size: CGSize(width: 600, height: 400)) + [screen] {
            let window = SimulatedWindow(frame: start, screen: screen)
            let operation = window.makeOperation()
            for action in layouts {
                let expected = WindowGeometry.frame(for: action, window: window.frame, screen: screen)
                let writesBefore = window.writes.count
                try perform(action, on: window, with: operation)
                XCTAssertEqual(window.frame, expected, "\(action) from \(start)")
                XCTAssertLessThanOrEqual(window.writes.count - writesBefore, 3, "\(action) from \(start)")
            }
            XCTAssertEqual(window.waits, 0)
        }
    }

    /// System Settings keeps a fixed width. Every layout keeps its whole size, centered in the
    /// requested area and on screen.
    func testFixedWidthWindowKeepsItsSizeCenteredInEveryLayout() throws {
        let size = CGSize(width: 740, height: 826)
        for start in starts(size: size) {
            let window = SimulatedWindow(
                frame: start,
                screen: screen,
                minimumSize: CGSize(width: 740, height: 200),
                maximumSize: CGSize(width: 740, height: 10_000)
            )
            let operation = window.makeOperation()
            for action in layouts {
                let layout = WindowGeometry.frame(for: action, window: window.frame, screen: screen)
                let expected = action == .center
                    ? layout
                    : WindowScreenGeometry.frame(centering: size, in: layout, screen: screen)
                try perform(action, on: window, with: operation)
                XCTAssertEqual(window.frame, expected, "\(action) from \(start)")
            }
            XCTAssertEqual(window.waits, 0)
        }
    }

    /// Terminal rounds its size to a character cell and keeps that size against the edges the
    /// layout touches.
    func testGridSnappingWindowStaysAgainstTheLayoutEdges() throws {
        let window = SimulatedWindow(
            frame: CGRect(x: 500, y: 250, width: 640, height: 420),
            screen: screen,
            resizeIncrement: CGSize(width: 7, height: 16)
        )
        let operation = window.makeOperation()

        try perform(.rightHalf, on: window, with: operation)
        XCTAssertEqual(window.frame.maxX, screen.maxX, accuracy: 0.5)
        XCTAssertEqual(window.frame.minY, screen.minY)
        XCTAssertEqual(window.frame.width, screen.width / 2, accuracy: 7)

        try perform(.leftHalf, on: window, with: operation)
        XCTAssertEqual(window.frame.minX, screen.minX)
        XCTAssertEqual(window.frame.minY, screen.minY)

        try perform(.maximize, on: window, with: operation)
        XCTAssertEqual(window.frame.origin, screen.origin)

        try perform(.bottomHalf, on: window, with: operation)
        XCTAssertEqual(window.frame.maxY, screen.maxY, accuracy: 0.5)
        XCTAssertEqual(window.waits, 0)
    }

    /// On a 1440 pt display a half is 720 pt, within Terminal's rounding of System Settings' fixed
    /// 740 pt width. Its width did not change at all, so it is a fixed width, not a rounded one,
    /// and the window keeps its own size instead of being stretched to full height.
    func testFixedWidthNearTheHalfIsNotStretched() throws {
        let laptop = CGRect(x: 0, y: 30, width: 1_440, height: 870)
        let size = CGSize(width: 740, height: 667)
        let window = SimulatedWindow(
            frame: CGRect(origin: CGPoint(x: 680, y: 60), size: size),
            screen: laptop,
            minimumSize: CGSize(width: 740, height: 200),
            maximumSize: CGSize(width: 740, height: 10_000)
        )
        let operation = window.makeOperation()
        let leftHalf = CGRect(x: 0, y: 30, width: 720, height: 870)

        try operation.perform(.leftHalf, targetPID: window.processIdentifier, screens: [laptop], checkCancellation: {})
        XCTAssertEqual(window.frame, WindowScreenGeometry.frame(centering: size, in: leftHalf, screen: laptop))

        try operation.perform(.maximize, targetPID: window.processIdentifier, screens: [laptop], checkCancellation: {})
        XCTAssertEqual(window.frame.size, size)
    }

    /// A terminal whose width is already the layout's width rounded to its cells still takes the
    /// layout's height; its unchanged width is not mistaken for a fixed one.
    func testGridWindowAlreadyAtTheLayoutWidthStillTakesItsHeight() throws {
        let window = SimulatedWindow(
            frame: CGRect(x: 0, y: 30, width: 837, height: 400),
            screen: screen,
            resizeIncrement: CGSize(width: 7, height: 16)
        )
        try perform(.leftHalf, on: window, with: window.makeOperation())
        XCTAssertEqual(window.frame.minX, screen.minX)
        XCTAssertEqual(window.frame.width, 837)
        XCTAssertEqual(window.frame.height, screen.height, accuracy: 16)
    }

    /// A window that changed on both axes but stopped at its maximum size keeps what it reached
    /// instead of snapping back to its old size.
    func testWindowAtItsMaximumSizeKeepsWhatItReached() throws {
        let window = SimulatedWindow(
            frame: CGRect(x: 500, y: 250, width: 600, height: 400),
            screen: screen,
            maximumSize: CGSize(width: 1_000, height: 700)
        )
        try perform(.maximize, on: window, with: window.makeOperation())
        XCTAssertEqual(window.frame, CGRect(x: 0, y: 30, width: 1_000, height: 700))
    }

    /// A refused layout is not remembered. When the window can be resized again, the next press
    /// gets the whole layout.
    func testRefusedLayoutIsNotRemembered() throws {
        let window = SimulatedWindow(
            frame: CGRect(x: 900, y: 300, width: 740, height: 600),
            screen: screen,
            minimumSize: CGSize(width: 740, height: 200),
            maximumSize: CGSize(width: 740, height: 10_000)
        )
        let operation = window.makeOperation()
        try perform(.maximize, on: window, with: operation)
        XCTAssertEqual(window.frame.size, CGSize(width: 740, height: 600))

        window.minimumSize = CGSize(width: 200, height: 150)
        window.maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        try perform(.leftHalf, on: window, with: operation)
        XCTAssertEqual(window.frame, CGRect(x: 0, y: 30, width: 840, height: 1_020))
    }

    /// Pressing a half again cycles its width, even when the window already filled that half
    /// before Broccoli placed it.
    func testPressingAHalfTheWindowAlreadyFillsCyclesItsSize() throws {
        let window = SimulatedWindow(frame: CGRect(x: 0, y: 30, width: 840, height: 1_020), screen: screen)
        let operation = window.makeOperation()

        try perform(.leftHalf, on: window, with: operation)
        XCTAssertEqual(window.writes, [], "Already in place")

        try perform(.leftHalf, on: window, with: operation)
        XCTAssertEqual(window.frame, CGRect(x: 0, y: 30, width: 560, height: 1_020))
    }

    func testNextDisplayFollowsTheArrangementLeftToRight() {
        let middle = CGRect(x: 0, y: 30, width: 1_440, height: 870)
        let right = CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
        let left = CGRect(x: -1_280, y: 100, width: 1_280, height: 800)
        let screens = [middle, right, left]

        XCTAssertEqual(WindowAccessibilityOperation.neighboringScreenIndex(of: 0, in: screens, forward: true), 1)
        XCTAssertEqual(WindowAccessibilityOperation.neighboringScreenIndex(of: 1, in: screens, forward: true), 2)
        XCTAssertEqual(WindowAccessibilityOperation.neighboringScreenIndex(of: 2, in: screens, forward: true), 0)
        XCTAssertEqual(WindowAccessibilityOperation.neighboringScreenIndex(of: 0, in: screens, forward: false), 2)
    }
}
