import XCTest
@testable import BroccoliApp

/// A keychain prompt for the clipboard key must appear at most once per attempt, never once per
/// settings change.
final class ClipboardKeyRequestGateTests: XCTestCase {
    func testAsksOnlyWhileHistoryIsOnAndNotRunning() {
        var gate = ClipboardKeyRequestGate()
        XCTAssertFalse(gate.beginRequest(historyEnabled: false, historyRunning: false))
        XCTAssertFalse(gate.beginRequest(historyEnabled: true, historyRunning: true))
        XCTAssertTrue(gate.beginRequest(historyEnabled: true, historyRunning: false))
    }

    func testOneRequestAtATime() {
        var gate = ClipboardKeyRequestGate()
        XCTAssertTrue(gate.beginRequest(historyEnabled: true, historyRunning: false))
        XCTAssertFalse(gate.beginRequest(historyEnabled: true, historyRunning: false), "A settings change while the prompt waits")
    }

    func testRefusedRequestIsNotRepeatedOnEverySettingsChange() {
        var gate = ClipboardKeyRequestGate()
        XCTAssertTrue(gate.beginRequest(historyEnabled: true, historyRunning: false))
        gate.finish(succeeded: false)
        for _ in 0..<3 {
            XCTAssertFalse(gate.beginRequest(historyEnabled: true, historyRunning: false))
        }
    }

    func testTurningHistoryOffAndOnAsksAgain() {
        var gate = ClipboardKeyRequestGate()
        XCTAssertTrue(gate.beginRequest(historyEnabled: true, historyRunning: false))
        gate.finish(succeeded: false)
        XCTAssertFalse(gate.beginRequest(historyEnabled: false, historyRunning: false))
        XCTAssertTrue(gate.beginRequest(historyEnabled: true, historyRunning: false))
    }
}
