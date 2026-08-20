import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class IconCacheTests: XCTestCase {
    func testEverySettingsEntryProducesExactlyOneNativeIconRequest() {
        let requests = SystemSettingsIconRequestMapper.requests(
            for: SettingsCatalog.searchEntries
        )

        XCTAssertEqual(requests.count, SettingsCatalog.definitions.count)
        XCTAssertEqual(
            Set(requests.map(\.iconKey)),
            Set(SettingsCatalog.definitions.map { "setting:\($0.id)" })
        )
        XCTAssertEqual(Set(requests.map(\.bundleIdentifier)).count, requests.count - 1)
    }

    func testEmptyExtensionIndexIsRetriedThenSuccessfulIndexIsReused() async {
        let builder = RetryingSettingsIndexBuilder()
        let index = SystemSettingsExtensionIndex(indexBuilder: { roots in
            builder.build(roots: roots)
        })
        let identifier = "com.example.Settings.extension"

        let first = await index.bundleURLs(for: [identifier])
        let second = await index.bundleURLs(for: [identifier])
        let third = await index.bundleURLs(for: [identifier])

        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second[identifier]?.path, "/System/example.appex")
        XCTAssertEqual(third[identifier]?.path, "/System/example.appex")
        XCTAssertEqual(builder.callCount, 2)
    }

    func testSettingsRouteParsingIgnoresSubpageAndRejectsOtherSchemes() {
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.bundleIdentifier(
                from: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
            ),
            "com.apple.Wallpaper-Settings.extension"
        )
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.bundleIdentifier(
                from: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
            ),
            "com.apple.Keyboard-Settings.extension"
        )
        XCTAssertNil(SystemSettingsIconRequestMapper.bundleIdentifier(from: nil))
        XCTAssertNil(SystemSettingsIconRequestMapper.bundleIdentifier(from: "https://apple.com"))
        XCTAssertNil(SystemSettingsIconRequestMapper.bundleIdentifier(
            from: "x-apple.systempreferences:../../not-a-bundle"
        ))
    }

    func testWallpaperEntryMapsToItsInstalledExtensionBundleIdentifier() throws {
        let wallpaper = try XCTUnwrap(
            SettingsCatalog.searchEntries.first(where: { $0.id == "setting:wallpaper" })
        )

        XCTAssertEqual(
            SystemSettingsIconRequestMapper.request(for: wallpaper),
            SystemSettingsIconRequest(
                iconKey: "setting:wallpaper",
                bundleIdentifier: "com.apple.Wallpaper-Settings.extension",
                fallbackApplicationBundleIdentifier: nil
            )
        )
    }

    func testOnlyMissingPasswordsAndScreenSaverExtensionsMapToApplicationFallbacks() throws {
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.applicationFallbacks,
            [
                "com.apple.Passwords-Settings.extension": "com.apple.Passwords",
                "com.apple.ScreenSaver-Settings.extension": "com.apple.ScreenSaver.Engine",
            ]
        )

        let entries = SettingsCatalog.searchEntries
        let passwords = try XCTUnwrap(entries.first(where: { $0.id == "setting:passwords" }))
        let screenSaver = try XCTUnwrap(entries.first(where: { $0.id == "setting:screen-saver" }))

        XCTAssertEqual(
            SystemSettingsIconRequestMapper.request(for: passwords)?
                .fallbackApplicationBundleIdentifier,
            "com.apple.Passwords"
        )
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.request(for: screenSaver)?
                .fallbackApplicationBundleIdentifier,
            "com.apple.ScreenSaver.Engine"
        )
    }

    func testInjectedApplicationMappingAndExtensionPrecedenceArePure() throws {
        let entry = SearchEntry(
            id: "setting:fixture",
            kind: .systemSetting,
            title: "Fixture",
            iconKey: "setting:fixture",
            target: .setting(route: "x-apple.systempreferences:com.example.Settings.extension")
        )
        let request = try XCTUnwrap(SystemSettingsIconRequestMapper.request(
            for: entry,
            applicationFallbacks: ["com.example.Settings.extension": "com.example.App"]
        ))

        XCTAssertEqual(request.fallbackApplicationBundleIdentifier, "com.example.App")
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.preferredSource(
                for: request,
                installedExtensionBundleIdentifiers: ["com.example.Settings.extension"],
                powerIconContentTypeIdentifier:
                    SystemSettingsPowerIconSelector.batteryContentTypeIdentifier
            ),
            .settingsExtension(bundleIdentifier: "com.example.Settings.extension")
        )
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.preferredSource(
                for: request,
                installedExtensionBundleIdentifiers: [],
                powerIconContentTypeIdentifier:
                    SystemSettingsPowerIconSelector.batteryContentTypeIdentifier
            ),
            .application(bundleIdentifier: "com.example.App")
        )
    }

    func testDuplicateKeyboardRoutesShareOneNativeSource() throws {
        let requests = SystemSettingsIconRequestMapper.requests(
            for: SettingsCatalog.searchEntries
        )
        let groups = SystemSettingsIconRequestMapper.iconKeysBySource(
            for: requests,
            installedExtensionBundleIdentifiers: Set(requests.map(\.bundleIdentifier)),
            powerIconContentTypeIdentifier:
                SystemSettingsPowerIconSelector.batteryContentTypeIdentifier
        )
        let keyboardSource = SystemSettingsNativeIconSource.settingsExtension(
            bundleIdentifier: "com.apple.Keyboard-Settings.extension"
        )

        XCTAssertEqual(
            groups[keyboardSource],
            ["setting:keyboard", "setting:keyboard-shortcuts"]
        )
    }

    func testPowerIconSelectorChoosesBatteryForLaptopSnapshot() {
        XCTAssertTrue(SystemSettingsPowerIconSelector.hasInternalBattery(
            powerSourceTypes: ["UPS Power", kIOPSInternalBatteryType]
        ))
        XCTAssertEqual(
            SystemSettingsPowerIconSelector.contentTypeIdentifier(
                powerSourceTypes: [kIOPSInternalBatteryType]
            ),
            SystemSettingsPowerIconSelector.batteryContentTypeIdentifier
        )
    }

    func testPowerIconSelectorChoosesEnergyForDesktopSnapshot() {
        XCTAssertFalse(SystemSettingsPowerIconSelector.hasInternalBattery(
            powerSourceTypes: ["UPS Power"]
        ))
        XCTAssertEqual(
            SystemSettingsPowerIconSelector.contentTypeIdentifier(powerSourceTypes: []),
            SystemSettingsPowerIconSelector.energyContentTypeIdentifier
        )
    }

    func testBatteryRequestUsesInjectedLaptopOrDesktopGraphicIcon() throws {
        let request = try XCTUnwrap(
            SystemSettingsIconRequestMapper.requests(for: SettingsCatalog.searchEntries)
                .first(where: { $0.iconKey == "setting:battery" })
        )
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.preferredSource(
                for: request,
                installedExtensionBundleIdentifiers: [request.bundleIdentifier],
                powerIconContentTypeIdentifier:
                    SystemSettingsPowerIconSelector.batteryContentTypeIdentifier
            ),
            .contentType(
                identifier: SystemSettingsPowerIconSelector.batteryContentTypeIdentifier
            )
        )
        XCTAssertEqual(
            SystemSettingsIconRequestMapper.preferredSource(
                for: request,
                installedExtensionBundleIdentifiers: [request.bundleIdentifier],
                powerIconContentTypeIdentifier:
                    SystemSettingsPowerIconSelector.energyContentTypeIdentifier
            ),
            .contentType(identifier: SystemSettingsPowerIconSelector.energyContentTypeIdentifier)
        )
    }

    func testSelectedPowerGraphicIconDiffersFromGenericExtensionCube() async throws {
        let request = try XCTUnwrap(
            SystemSettingsIconRequestMapper.requests(for: SettingsCatalog.searchEntries)
                .first(where: { $0.iconKey == "setting:battery" })
        )

        let urls = await SystemSettingsExtensionIndex.shared.bundleURLs(
            for: [request.bundleIdentifier]
        )
        let extensionURL = try XCTUnwrap(urls[request.bundleIdentifier])
        let extensionCube = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeIcon(
            at: extensionURL,
            pointSize: 40,
            backingScale: 2
        ))
        let livePowerIconIdentifier = SystemSettingsPowerIconSelector.contentTypeIdentifier(
            powerSourceTypes: SystemPowerSourceSnapshot.powerSourceTypes()
        )
        let nativePowerIcon = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeIcon(
            forContentTypeIdentifier: livePowerIconIdentifier,
            pointSize: 40,
            backingScale: 2
        ))

        XCTAssertNotEqual(pixelData(extensionCube), pixelData(nativePowerIcon))
        XCTAssertEqual(nativePowerIcon.image.representations.count, 1)
        XCTAssertEqual(nativePowerIcon.pixelsWide, 80)
        XCTAssertEqual(nativePowerIcon.pixelsHigh, 80)
    }

    func testInstalledCatalogExtensionIconsDoNotDuplicateKnownGenericCube() async throws {
        let requests = SystemSettingsIconRequestMapper.requests(for: SettingsCatalog.searchEntries)
        let urls = await SystemSettingsExtensionIndex.shared.bundleURLs(
            for: Set(requests.map(\.bundleIdentifier))
        )
        let batteryIdentifier = "com.apple.Battery-Settings.extension"
        let batteryURL = try XCTUnwrap(urls[batteryIdentifier])
        let genericCube = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeIcon(
            at: batteryURL,
            pointSize: 40,
            backingScale: 2
        ))
        let genericPixels = pixelData(genericCube)

        for request in requests where request.bundleIdentifier != batteryIdentifier {
            guard let url = urls[request.bundleIdentifier] else { continue }
            let icon = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeIcon(
                at: url,
                pointSize: 40,
                backingScale: 2
            ))
            XCTAssertNotEqual(
                pixelData(icon),
                genericPixels,
                "\(request.iconKey) resolved to the known generic ExtensionKit cube"
            )
        }
    }

    func testInstalledResolverMaterializesEverySettingsRequestOnce() async throws {
        let requests = SystemSettingsIconRequestMapper.requests(for: SettingsCatalog.searchEntries)
        let resolution = await SystemSettingsNativeIconResolver.resolve(
            requests: requests,
            backingScale: 2
        )

        XCTAssertTrue(resolution.extensionIndexSucceeded)
        XCTAssertEqual(
            Set(resolution.iconsByKey.keys),
            Set(requests.map(\.iconKey))
        )
        for icon in resolution.iconsByKey.values {
            XCTAssertEqual(icon.image.size, NSSize(width: 40, height: 40))
            XCTAssertEqual(icon.image.representations.count, 1)
            XCTAssertEqual(icon.pixelsWide, 80)
            XCTAssertEqual(icon.pixelsHigh, 80)
        }
        XCTAssertTrue(
            resolution.iconsByKey["setting:keyboard"]
                === resolution.iconsByKey["setting:keyboard-shortcuts"]
        )
    }

    func testApplicationFallbackValidationRequiresStandardSystemRoots() {
        XCTAssertEqual(
            SystemSettingsNativeIconResolver.validatedSystemApplicationURL(
                URL(fileURLWithPath: "/System/Applications/Utilities/Example.app")
            )?.path,
            "/System/Applications/Utilities/Example.app"
        )
        XCTAssertEqual(
            SystemSettingsNativeIconResolver.validatedSystemApplicationURL(
                URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            )?.path,
            "/System/Library/CoreServices/ScreenSaverEngine.app"
        )
        XCTAssertNil(SystemSettingsNativeIconResolver.validatedSystemApplicationURL(
            URL(fileURLWithPath: "/Applications/Passwords.app")
        ))
        XCTAssertNil(SystemSettingsNativeIconResolver.validatedSystemApplicationURL(
            URL(fileURLWithPath: "/System/Applications-Evil/Passwords.app")
        ))
        XCTAssertNil(SystemSettingsNativeIconResolver.validatedSystemApplicationURL(
            URL(fileURLWithPath: "/System/Applications/../../tmp/Passwords.app")
        ))
    }

    func testNonSettingEntryDoesNotCreateSettingsIconRequest() {
        let entry = SearchEntry(
            id: "action:test",
            kind: .action,
            title: "Test",
            iconKey: "action:test",
            target: .setting(route: "x-apple.systempreferences:com.apple.Test.extension")
        )

        XCTAssertNil(SystemSettingsIconRequestMapper.request(for: entry))
    }

    func testInstalledWallpaperExtensionProvidesPublicWorkspaceIcon() async throws {
        _ = NSApplication.shared
        let identifier = "com.apple.Wallpaper-Settings.extension"
        let urls = await SystemSettingsExtensionIndex.shared.bundleURLs(for: [identifier])
        guard let url = urls[identifier] else {
            throw XCTSkip("This macOS installation does not expose the Wallpaper Settings extension")
        }

        XCTAssertEqual(Bundle(url: url)?.bundleIdentifier, identifier)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        XCTAssertGreaterThan(icon.size.width, 0)
        XCTAssertGreaterThan(icon.size.height, 0)

        let materialized = try XCTUnwrap(
            SystemSettingsNativeIconResolver.materializeIcon(
                at: url,
                pointSize: 40,
                backingScale: 2
            )
        )
        XCTAssertEqual(materialized.image.size, NSSize(width: 40, height: 40))
        XCTAssertEqual(materialized.image.representations.count, 1)
        XCTAssertEqual(materialized.pixelsWide, 80)
        XCTAssertEqual(materialized.pixelsHigh, 80)
        let bitmap = try XCTUnwrap(materialized.image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(materialized.cost, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let bounds = try XCTUnwrap(nonTransparentBounds(in: bitmap))
        XCTAssertGreaterThanOrEqual(bounds.width, 60)
        XCTAssertGreaterThanOrEqual(bounds.height, 60)
    }

    func testMaterializationUsesTheEntireBackingScaleCanvas() throws {
        let source = NSImage(size: NSSize(width: 40, height: 40))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 40, height: 40)).fill()
        source.unlockFocus()

        let icon = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeImage(
            source,
            pointSize: 40,
            backingScale: 2
        ))
        let bitmap = try XCTUnwrap(icon.image.representations.first as? NSBitmapImageRep)
        let bounds = try XCTUnwrap(nonTransparentBounds(in: bitmap))

        XCTAssertGreaterThanOrEqual(bounds.width, 78)
        XCTAssertGreaterThanOrEqual(bounds.height, 78)
    }

    func testInstalledFallbackApplicationsProvidePublicWorkspaceIcons() throws {
        _ = NSApplication.shared
        for identifier in ["com.apple.Passwords", "com.apple.ScreenSaver.Engine"] {
            let discoveredURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: identifier
            )
            guard let url = SystemSettingsNativeIconResolver.validatedSystemApplicationURL(
                discoveredURL
            ) else {
                throw XCTSkip("This macOS installation does not expose \(identifier)")
            }

            XCTAssertEqual(Bundle(url: url)?.bundleIdentifier, identifier)
            let icon = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeIcon(
                at: url,
                pointSize: 40,
                backingScale: 2
            ))
            XCTAssertEqual(icon.image.representations.count, 1)
            XCTAssertEqual(icon.pixelsWide, 80)
            XCTAssertEqual(icon.pixelsHigh, 80)
        }
    }

    func testImageLookupCanUseInjectedCacheOnlyStoreWithoutStartingResolution() {
        let store = SystemSettingsNativeIconStore { _, _ in
            SystemSettingsNativeIconResolution(
                iconsByKey: [:],
                extensionIndexSucceeded: false
            )
        }
        let cache = IconCache(
            systemSettingsIconStore: store,
            startsNativeIconResolution: false
        )

        for entry in SettingsCatalog.searchEntries {
            _ = cache.image(for: entry)
        }
        XCTAssertEqual(store.resolutionAttemptCount, 0)
    }

    func testMultipleIconCachesStartOneSharedResolutionAttempt() {
        let store = SystemSettingsNativeIconStore { _, _ in
            await Task.yield()
            return SystemSettingsNativeIconResolution(
                iconsByKey: [:],
                extensionIndexSucceeded: true
            )
        }

        let first = IconCache(systemSettingsIconStore: store, backingScale: 2)
        let second = IconCache(systemSettingsIconStore: store, backingScale: 2)
        XCTAssertEqual(store.resolutionAttemptCount, 1)
        _ = first.image(for: SettingsCatalog.searchEntries[0])
        _ = second.image(for: SettingsCatalog.searchEntries[0])
        XCTAssertEqual(store.resolutionAttemptCount, 1)
    }

    func testMissingPreferredBadgeSymbolUsesOrderedSemanticFallback() throws {
        _ = NSApplication.shared
        let glyph = try XCTUnwrap(IconCache.resolvedSystemSymbol(
            preferred: "broccoli.symbol.that.does.not.exist",
            semanticFallbacks: ["gearshape", "questionmark"]
        ))

        XCTAssertGreaterThan(glyph.size.width, 0)
        XCTAssertGreaterThan(glyph.size.height, 0)
    }

    func testEveryActionUsesBoundedNativeTemplateIconFromCacheOnlyPath() throws {
        _ = NSApplication.shared
        let store = SystemSettingsNativeIconStore { _, _ in
            XCTFail("Action icon lookup must not start Settings icon resolution")
            return SystemSettingsNativeIconResolution(
                iconsByKey: [:],
                extensionIndexSucceeded: false
            )
        }
        let cache = IconCache(
            systemSettingsIconStore: store,
            startsNativeIconResolution: false
        )

        for entry in ActionRegistry.searchEntries {
            let first = cache.image(for: entry)
            let second = cache.image(for: entry)
            XCTAssertTrue(first === second, "\(entry.id) was not served from the static cache")
            XCTAssertTrue(first.isTemplate, "\(entry.id) must remain AppKit-tintable")
            XCTAssertEqual(first.size, NSSize(width: 40, height: 40), "Unexpected size for \(entry.id)")
            XCTAssertFalse(first.representations.isEmpty, "Missing representation for \(entry.id)")
            for representation in first.representations {
                XCTAssertGreaterThan(representation.pixelsWide, 0, "Empty icon for \(entry.id)")
                XCTAssertGreaterThan(representation.pixelsHigh, 0, "Empty icon for \(entry.id)")
                XCTAssertLessThanOrEqual(representation.pixelsWide, 80, "Unbounded icon for \(entry.id)")
                XCTAssertLessThanOrEqual(representation.pixelsHigh, 80, "Unbounded icon for \(entry.id)")
            }
            XCTAssertLessThanOrEqual(IconCache.boundedImageCost(first), 80 * 80 * 4)

            let bitmap = try XCTUnwrap(
                first.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
                "Could not inspect \(entry.id)"
            )
            for point in [
                NSPoint(x: 0, y: 0),
                NSPoint(x: bitmap.pixelsWide - 1, y: 0),
                NSPoint(x: 0, y: bitmap.pixelsHigh - 1),
                NSPoint(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1),
            ] {
                XCTAssertEqual(
                    bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? 1,
                    0,
                    accuracy: 0.001,
                    "\(entry.id) contains a custom tile/background"
                )
            }
        }
        XCTAssertEqual(store.resolutionAttemptCount, 0)
    }

    func testActionTemplateUsesOrderedPublicFallbackWithoutAddingAColorPalette() {
        _ = NSApplication.shared
        let icon = IconCache.actionTemplateIcon(
            symbolCandidates: ["broccoli.symbol.that.does.not.exist", "speaker"],
            accessibilityDescription: "Audio"
        )

        XCTAssertEqual(icon.size, NSSize(width: 40, height: 40))
        XCTAssertTrue(icon.isTemplate)
        XCTAssertLessThanOrEqual(IconCache.boundedImageCost(icon), 80 * 80 * 4)
    }

    func testResultRowUsesSemanticTintOnlyForTemplateIcons() throws {
        _ = NSApplication.shared
        let entry = try XCTUnwrap(ActionRegistry.definition(id: "audio.volumeUp")?.searchEntry)
        let result = RankedResult(entry: entry, score: 1_000)
        let actionIcon = IconCache(startsNativeIconResolution: false).image(for: entry)
        let row = ResultRowView()
        let iconView = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first)

        for mode in LauncherAppearanceMode.allCases {
            var preferences = LauncherAppearancePreferences.defaults(design: .minimal)
            preferences.mode = mode
            let theme = LauncherThemeController().descriptor(
                for: preferences,
                reducedTransparency: false,
                increasedContrast: false,
                resolvedSystemDark: mode == .dark
            )
            row.appearance = theme.appearance
            row.configure(
                result: result,
                icon: actionIcon,
                confirmation: false,
                row: 0,
                selected: false,
                theme: theme
            )
            XCTAssertTrue(
                iconView.contentTintColor?.isEqual(NSColor.labelColor) == true,
                "Unselected \(mode) action icon must use semantic labelColor"
            )
            row.setSelected(true)
            XCTAssertTrue(
                iconView.contentTintColor?.isEqual(NSColor.alternateSelectedControlTextColor) == true,
                "Selected \(mode) action icon must use semantic selected text color"
            )
        }

        let fullColorIcon = NSImage(size: NSSize(width: 40, height: 40))
        fullColorIcon.isTemplate = false
        let theme = LauncherThemeController().descriptor(
            for: .defaults(design: .minimal),
            reducedTransparency: false,
            increasedContrast: false
        )
        row.configure(
            result: result,
            icon: fullColorIcon,
            confirmation: false,
            row: 0,
            selected: true,
            theme: theme
        )
        XCTAssertNil(iconView.contentTintColor, "Full-color native icons must not be recolored")
    }

    func testPublicBluetoothTemplateIsAvailableForSettingsBadge() {
        _ = NSApplication.shared
        let bluetooth = NSImage(named: NSImage.bluetoothTemplateName)

        XCTAssertNotNil(bluetooth)
        XCTAssertEqual(bluetooth?.isTemplate, true)
    }

    func testFolderReceivesNativeWorkspaceIconWithoutThumbnailUpgrade() async throws {
        _ = NSApplication.shared
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BroccoliIconCacheTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let entry = SearchEntry(
            id: "file:\(folderURL.path)",
            kind: .file,
            title: folderURL.lastPathComponent,
            iconKey: folderURL.path,
            target: .file(path: folderURL.path, isDirectory: true)
        )
        let cache = IconCache()
        let loaded = expectation(description: "Native folder icon loaded")
        var callbackCount = 0
        cache.onIconLoaded = { key in
            guard key == folderURL.path else { return }
            callbackCount += 1
            loaded.fulfill()
        }

        _ = cache.image(for: entry)
        await fulfillment(of: [loaded], timeout: 3)

        let cached = cache.image(for: entry)
        XCTAssertEqual(cached.size, NSSize(width: 40, height: 40))

        // Directories intentionally stop at the native Finder icon instead of being replaced
        // later by a Quick Look representation.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(callbackCount, 1)
    }

    private func pixelData(_ icon: MaterializedSystemSettingsIcon) -> Data {
        let bitmap = icon.image.representations.first as! NSBitmapImageRep
        return Data(
            bytes: bitmap.bitmapData!,
            count: bitmap.bytesPerRow * bitmap.pixelsHigh
        )
    }

    private func nonTransparentBounds(in bitmap: NSBitmapImageRep) -> NSRect? {
        var minimumX = bitmap.pixelsWide
        var minimumY = bitmap.pixelsHigh
        var maximumX = -1
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 else {
                    continue
                }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return NSRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }
}

private final class RetryingSettingsIndexBuilder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func build(roots: [URL]) -> [String: URL] {
        lock.withLock {
            calls += 1
            guard calls > 1 else { return [:] }
            return [
                "com.example.Settings.extension": URL(
                    fileURLWithPath: "/System/example.appex"
                ),
            ]
        }
    }
}
