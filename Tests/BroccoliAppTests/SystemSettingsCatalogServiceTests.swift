import BroccoliCore
import XCTest
@testable import BroccoliApp

final class SystemSettingsCatalogServiceTests: XCTestCase {
    func testSearchTermsParserPreservesDestinationTitlesAndKeywords() {
        let propertyList: [String: Any] = [
            "Keyboard": [
                "localizableStrings": [
                    [
                        "title": "Illuminate keyboard",
                        "index": "low light, brightness, backlight",
                    ],
                ],
            ],
        ]

        XCTAssertEqual(
            SystemSettingsCatalogDiscovery.searchTerms(in: propertyList),
            [
                SystemSettingsSearchTerm(
                    id: "Keyboard:0",
                    destination: "Keyboard",
                    title: "Illuminate keyboard",
                    keywords: ["low light", "brightness", "backlight"]
                ),
            ]
        )
    }

    func testLiveKeyboardExtensionCanBeDiscoveredWhenPresent() throws {
        let url = URL(
            fileURLWithPath:
                "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("This macOS installation has no Keyboard Settings extension")
        }

        let pane = try XCTUnwrap(SystemSettingsCatalogDiscovery.pane(at: url))
        XCTAssertEqual(pane.bundleIdentifier, "com.apple.Keyboard-Settings.extension")
        XCTAssertFalse(pane.searchTerms.isEmpty)
        XCTAssertTrue(pane.searchTerms.contains { term in
            SearchNormalizer.normalize(term.title).contains("keyboard")
                && term.keywords.contains(where: {
                    SearchNormalizer.normalize($0).contains("brightness")
                })
        })
    }

    func testLiveCatalogMakesKeyboardBrightnessSearchableInEnglish() throws {
        guard Locale.preferredLanguages.first?.hasPrefix("en") == true else {
            throw XCTSkip("This assertion uses the English system search-term localization")
        }
        let entries = SystemSettingsCatalogDiscovery.discover()
        guard entries.contains(where: {
            $0.iconKey == "setting:com.apple.Keyboard-Settings.extension"
        }) else {
            throw XCTSkip("This macOS installation has no discoverable Keyboard pane")
        }

        let results = SearchEngine().search(
            query: "keyboard brightness",
            snapshot: SearchSnapshot(entries: entries),
            usage: [:]
        )

        XCTAssertTrue(results.contains {
            $0.entry.iconKey == "setting:com.apple.Keyboard-Settings.extension"
        })
    }
}
