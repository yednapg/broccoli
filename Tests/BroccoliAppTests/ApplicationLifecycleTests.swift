import AppKit
import Carbon
import XCTest
@testable import BroccoliApp

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testHandLaunchOpensSettingsAndLoginLaunchStaysQuiet() {
        XCTAssertEqual(
            ApplicationLaunchRouter.presentation(arguments: ["/Applications/Broccoli.app"], launchedAsLoginItem: false),
            .settings
        )
        XCTAssertEqual(
            ApplicationLaunchRouter.presentation(arguments: ["/Applications/Broccoli.app"], launchedAsLoginItem: true),
            .none
        )
        XCTAssertEqual(
            ApplicationLaunchRouter.presentation(
                arguments: ["/Applications/Broccoli.app", "--show-launcher"],
                launchedAsLoginItem: true
            ),
            .launcher
        )
        XCTAssertEqual(
            ApplicationLaunchRouter.presentation(
                arguments: ["/Applications/Broccoli.app", "--show-settings"],
                launchedAsLoginItem: true
            ),
            .settings
        )
    }

    func testLoginItemLaunchIsTheOpenEventThatCarriesTheLoginParameter() {
        let launch = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        XCTAssertFalse(ApplicationLaunchRouter.launchedAsLoginItem(launch))
        XCTAssertFalse(ApplicationLaunchRouter.launchedAsLoginItem(nil))

        launch.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: keyAELaunchedAsLogInItem
        )
        XCTAssertTrue(ApplicationLaunchRouter.launchedAsLoginItem(launch))

        let reopen = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        reopen.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: keyAELaunchedAsLogInItem
        )
        XCTAssertFalse(
            ApplicationLaunchRouter.launchedAsLoginItem(reopen),
            "A reopen is someone opening Broccoli again, which shows Settings"
        )
    }

    func testLoginItemLaunchRecognizesTheMarkerMacOSSendsAtLogin() {
        func openEvent(propertyData: OSType) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEOpenApplication),
                targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            event.setParam(NSAppleEventDescriptor(enumCode: propertyData), forKeyword: keyAEPropData)
            return event
        }

        let login = openEvent(propertyData: OSType(keyAELaunchedAsLogInItem))
        XCTAssertTrue(ApplicationLaunchRouter.launchedAsLoginItem(login))
        XCTAssertEqual(
            ApplicationLaunchRouter.presentation(
                arguments: ["/Applications/Broccoli.app"],
                launchedAsLoginItem: ApplicationLaunchRouter.launchedAsLoginItem(login)
            ),
            .none,
            "Signing in must not open Settings"
        )
        XCTAssertFalse(ApplicationLaunchRouter.launchedAsLoginItem(
            openEvent(propertyData: OSType(keyAELaunchedAsServiceItem))
        ))
    }

    func testCommandQClosesSettingsOnlyWhileThatWindowIsKey() throws {
        let commandQ = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        ))
        XCTAssertTrue(SettingsCommandQ.closesSettings(event: commandQ, settingsWindowIsKey: true))
        XCTAssertFalse(SettingsCommandQ.closesSettings(event: commandQ, settingsWindowIsKey: false))

        let typedQ = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        ))
        XCTAssertFalse(SettingsCommandQ.closesSettings(event: typedQ, settingsWindowIsKey: true))
    }

}
