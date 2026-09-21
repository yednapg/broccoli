import XCTest
@testable import BroccoliApp

final class SettingsCopyLayoutTests: XCTestCase {
    func testGlobalShortcutSearchStillFindsTroubleshooting() throws {
        let shortcut = try XCTUnwrap(SettingsSearchItem.all.first { $0.id == "shortcut" })
        let troubleshooting = try XCTUnwrap(SettingsSearchItem.all.first { $0.id == "shortcut-help" })

        XCTAssertEqual(shortcut.title, "Global Shortcut")
        XCTAssertEqual(shortcut.destination, .section(.general))
        XCTAssertEqual(troubleshooting.title, "Shortcut Troubleshooting")
        XCTAssertEqual(troubleshooting.destination, .shortcutTroubleshooting)

        XCTAssertTrue(troubleshooting.matches("trouble"))
        XCTAssertTrue(troubleshooting.matches("having shortcut"))
        XCTAssertTrue(troubleshooting.matches("recover"))
        XCTAssertTrue(troubleshooting.matches("conflict"))
        XCTAssertTrue(troubleshooting.matches("unavailable"))

        XCTAssertFalse(shortcut.title.localizedCaseInsensitiveContains("Change"))
        XCTAssertFalse(troubleshooting.title.localizedCaseInsensitiveContains("Having shortcut trouble"))
        XCTAssertFalse(shortcut.terms.localizedCaseInsensitiveContains("change"))
        XCTAssertFalse(troubleshooting.terms.localizedCaseInsensitiveContains("change"))
    }

    func testShortcutTroubleshootingIsErrorOnly() {
        XCTAssertEqual(
            GeneralShortcutPresentation.rowSubtitle(status: GeneralShortcutPresentation.registeredStatus),
            "Shortcut registered"
        )
        XCTAssertFalse(
            GeneralShortcutPresentation.showsTroubleshooting(
                status: GeneralShortcutPresentation.registeredStatus
            )
        )
        XCTAssertFalse(GeneralShortcutPresentation.showsTroubleshooting(status: ""))
        XCTAssertEqual(
            GeneralShortcutPresentation.rowSubtitle(status: ""),
            "Checking the current shortcut"
        )

        let failure = "Command-Space is already used by Spotlight."
        XCTAssertEqual(GeneralShortcutPresentation.rowSubtitle(status: failure), failure)
        XCTAssertTrue(GeneralShortcutPresentation.showsTroubleshooting(status: failure))
        XCTAssertEqual(
            GeneralShortcutPresentation.troubleshootingActionTitle,
            "Troubleshoot…"
        )
    }

    func testPowerActionCopyUsesSentenceCaseReturn() throws {
        XCTAssertEqual(
            ActionSettingsCopy.powerWarning,
            "These commands require a second return within five seconds."
        )
        XCTAssertEqual(
            ActionSettingsCopy.disruptiveDetail,
            "Requires a second return within five seconds"
        )

        let sleep = try XCTUnwrap(ActionRegistry.definitions.first { $0.id == "power.sleep" })
        let volumeUp = try XCTUnwrap(ActionRegistry.definitions.first { $0.id == "audio.volumeUp" })
        XCTAssertEqual(
            ActionSettingsCopy.detail(for: sleep),
            "Requires a second return within five seconds"
        )
        XCTAssertEqual(
            ActionSettingsCopy.detail(for: volumeUp),
            "Increase output volume by 10%; repeat with return"
        )
        XCTAssertFalse(ActionSettingsCopy.powerWarning.contains("Return"))
        XCTAssertFalse(ActionSettingsCopy.disruptiveDetail.contains("Return"))
        XCTAssertFalse(ActionSettingsCopy.detail(for: volumeUp).contains("Return"))
    }
}
