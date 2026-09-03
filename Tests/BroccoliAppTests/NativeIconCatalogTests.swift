import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class NativeIconCatalogTests: XCTestCase {
    func testEveryBuiltInActionHasAnAvailableSemanticSystemSymbol() {
        XCTAssertEqual(
            Set(NativeIconCatalog.actionSymbolCandidates.keys),
            Set(ActionRegistry.definitions.map(\.id))
        )

        for entry in ActionRegistry.searchEntries {
            let symbols = NativeIconCatalog.actionSymbols(for: entry)
            XCTAssertFalse(symbols.isEmpty, "Missing candidates for \(entry.id)")
            for symbol in symbols {
                XCTAssertNotNil(
                    NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                    "Missing public macOS system symbol \(symbol) for \(entry.id)"
                )
            }
        }
    }

    func testActionsUseNativeActionOrientedPrimarySymbols() {
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["audio.volumeUp"]?.first,
            "speaker.plus.fill"
        )
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["audio.volumeDown"]?.first,
            "speaker.minus.fill"
        )
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["audio.toggleMute"]?.first,
            "speaker.slash.fill"
        )
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["screensaver.start"]?.first,
            "tv.fill"
        )
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["power.sleep"]?.first,
            "powersleep"
        )
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["power.shutdown"]?.first,
            "poweroff"
        )
        XCTAssertEqual(
            NativeIconCatalog.actionSymbolCandidates["power.logout"]?.first,
            "rectangle.portrait.and.arrow.forward"
        )
    }

    func testSettingsActionRowsAndRecoveryDeriveFromCentralCatalog() {
        for definition in ActionRegistry.definitions {
            let expected = NativeIconCatalog.resolvedActionSymbolName(
                forActionID: definition.id
            )
            XCTAssertEqual(SettingsActionIconSource.symbolName(for: definition), expected)
            XCTAssertTrue(
                NativeIconCatalog.actionSymbols(forActionID: definition.id).contains(expected),
                "Settings did not resolve a catalog candidate for \(definition.id)"
            )
        }

        let recoveryDefinitions = ActionRegistry.definitions.filter {
            ActionRegistry.recoveryActionIDs.contains($0.id)
        }
        XCTAssertEqual(
            Set(recoveryDefinitions.map { SettingsActionIconSource.symbolName(for: $0) }),
            Set(["gearshape", "xmark.circle"])
        )
    }

    func testEverySystemSettingHasAnAvailableSemanticSystemSymbol() {
        for entry in SystemSettingsTestFixtures.entries {
            let symbol = NativeIconCatalog.symbolName(for: entry)
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                "Missing macOS system symbol \(symbol) for \(entry.id)"
            )
        }

        let discovered = SearchEntry(
            id: "setting:com.example.NewSettings",
            kind: .systemSetting,
            title: "New Settings",
            iconKey: "setting:com.example.NewSettings",
            target: .setting(
                route: "x-apple.systempreferences:com.example.NewSettings"
            )
        )
        XCTAssertEqual(NativeIconCatalog.symbolName(for: discovered), "gearshape")
    }
}
