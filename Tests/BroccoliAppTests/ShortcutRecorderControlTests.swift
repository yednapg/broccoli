import AppKit
import Carbon
import XCTest
@testable import BroccoliApp

@MainActor
final class ShortcutRecorderControlTests: XCTestCase {
    func testShortcutDisplayNameUsesReadableSeparators() {
        XCTAssertEqual(HotKeyConfiguration.commandSpace.displayName, "⌘ + Space")
    }

    func testIntrinsicSizeMatchesCompactSettingsToken() {
        let recorder = ShortcutRecorderControl()

        XCTAssertEqual(recorder.intrinsicContentSize, NSSize(width: 132, height: 30))
    }

    func testBeginRecordingFailsSafelyUntilControlIsInAWindow() {
        let recorder = ShortcutRecorderControl()

        XCTAssertFalse(recorder.beginRecording())
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.accessibilityValue() as? String, HotKeyConfiguration.commandSpace.displayName)
    }

    func testBeginRecordingFocusesControlAndResigningCancels() {
        let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 132, height: 30))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(recorder)

        XCTAssertTrue(recorder.beginRecording())
        XCTAssertTrue(window.firstResponder === recorder)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.accessibilityValue() as? String, "Recording")

        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.accessibilityValue() as? String, HotKeyConfiguration.commandSpace.displayName)
    }

    func testEscapeCancelsRecordingWithoutChangingShortcut() throws {
        let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 132, height: 30))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(recorder)
        XCTAssertTrue(recorder.beginRecording())

        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))
        recorder.keyDown(with: escape)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.configuration, .commandSpace)
    }

    func testCommandArrowRecordsWithoutAPlusKey() throws {
        let recorder = ShortcutRecorderControl(
            frame: NSRect(x: 0, y: 0, width: 132, height: 30)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(recorder)
        recorder.onChange = { _ in true }
        XCTAssertTrue(recorder.beginRecording())

        let commandLeft = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            isARepeat: false,
            keyCode: UInt16(kVK_LeftArrow)
        ))

        XCTAssertTrue(recorder.performKeyEquivalent(with: commandLeft))
        XCTAssertEqual(
            recorder.configuration,
            HotKeyConfiguration(
                keyCode: UInt32(kVK_LeftArrow),
                modifiers: UInt32(cmdKey)
            )
        )
        XCTAssertEqual(recorder.configuration.displayName, "⌘ + ←")
        XCTAssertFalse(recorder.isRecording)
    }
}
