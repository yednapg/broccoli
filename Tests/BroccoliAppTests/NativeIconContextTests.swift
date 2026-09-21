import AppKit
import BroccoliCore
import Synchronization
import XCTest
@testable import BroccoliApp

private actor PendingPaneResolutions {
    private var pending: [IconRenderContext: CheckedContinuation<SystemSettingsNativeIconResolution, Never>] = [:]
    func resolve(_ context: IconRenderContext) async -> SystemSettingsNativeIconResolution {
        await withCheckedContinuation { pending[context] = $0 }
    }
    func contains(_ context: IconRenderContext) -> Bool { pending[context] != nil }
    func finish(_ context: IconRenderContext, icons: [String: MaterializedSystemSettingsIcon]) {
        pending.removeValue(forKey: context)?.resume(returning: .init(iconsByKey: icons, extensionIndexSucceeded: true))
    }
}

@MainActor
final class NativeIconContextTests: XCTestCase {
    private let light = IconRenderContext(appearance: .light, pointSize: 50, backingScale: 2)
    private let dark = IconRenderContext(appearance: .dark, pointSize: 50, backingScale: 2)

    func testPaneRequestsDeduplicatePerContextAndLateLightCompletionCannotReplaceDark() async throws {
        _ = NSApplication.shared
        let pending = PendingPaneResolutions()
        let store = SystemSettingsNativeIconStore { _, context in await pending.resolve(context) }
        let entry = SystemSettingsTestFixtures.entries[0]
        let requests = SystemSettingsIconRequestMapper.requests(for: [entry])
        let cache = IconCache(systemSettingsIconStore: store)
        let lightIcon = try bitmap(.red)
        let darkIcon = try bitmap(.blue)
        store.ensureResolution(requests: requests, context: light)
        store.ensureResolution(requests: requests, context: light)
        store.ensureResolution(requests: requests, context: dark)
        XCTAssertEqual(store.resolutionAttemptCount, 2)
        XCTAssertEqual(store.inFlightRequestCount, 2)
        try await waitUntil {
            let hasLight = await pending.contains(self.light)
            let hasDark = await pending.contains(self.dark)
            return hasLight && hasDark
        }
        await pending.finish(dark, icons: [entry.iconKey: darkIcon])
        try await waitUntil { store.cachedIcon(for: entry.iconKey, context: self.dark) != nil }
        XCTAssertTrue(cache.image(for: entry, context: dark) === darkIcon.image)
        await pending.finish(light, icons: [entry.iconKey: lightIcon])
        try await waitUntil { store.inFlightRequestCount == 0 }
        XCTAssertTrue(cache.image(for: entry, context: light) === lightIcon.image)
        XCTAssertTrue(cache.image(for: entry, context: dark) === darkIcon.image)
        store.ensureResolution(requests: requests, context: dark)
        XCTAssertEqual(store.resolutionAttemptCount, 2)
    }

    func testFailedPaneResolutionRemainsRetryableWithoutDiscardingCachedArtwork() async throws {
        let pending = PendingPaneResolutions()
        let store = SystemSettingsNativeIconStore { _, context in await pending.resolve(context) }
        let entry = SystemSettingsTestFixtures.entries[0]
        let requests = SystemSettingsIconRequestMapper.requests(for: [entry])
        let icon = try bitmap(.green)
        store.ensureResolution(requests: requests, context: light)
        try await waitUntil { await pending.contains(self.light) }
        await pending.finish(light, icons: [:])
        try await waitUntil { store.inFlightRequestCount == 0 }
        XCTAssertNil(store.cachedIcon(for: entry.iconKey, context: light))
        store.ensureResolution(requests: requests, context: light)
        try await waitUntil { await pending.contains(self.light) }
        await pending.finish(light, icons: [entry.iconKey: icon])
        try await waitUntil { store.inFlightRequestCount == 0 }
        store.ensureResolution(requests: requests, context: light, refresh: true)
        XCTAssertTrue(store.cachedIcon(for: entry.iconKey, context: light) === icon)
        try await waitUntil { await pending.contains(self.light) }
        await pending.finish(light, icons: [:])
        try await waitUntil { store.inFlightRequestCount == 0 }
        XCTAssertTrue(store.cachedIcon(for: entry.iconKey, context: light) === icon)
        XCTAssertEqual(store.resolutionAttemptCount, 3)
    }

    func testApplicationContextsDeduplicateInFlightAndRefreshWithoutReplacingNewerContext() async throws {
        let lightIcon = try bitmap(.red)
        let darkIcon = try bitmap(.blue)
        let lightGate = DispatchSemaphore(value: 0)
        defer { lightGate.signal() }
        let counts = Mutex<[IconRenderContext: Int]>([:])
        let cache = IconCache(startsNativeIconResolution: false, applicationIconOperation: { _, context in
            counts.withLock { $0[context, default: 0] += 1 }
            if context.appearance == .light {
                _ = lightGate.wait(timeout: .now() + 5)
                return lightIcon
            }
            return darkIcon
        })
        let entry = LauncherPreviewFixture.standard.results[0].entry
        let darkLoaded = expectation(description: "Dark artwork completes first")
        let lightLoaded = expectation(description: "Late light artwork")
        cache.onNativeIconLoaded = { key, context in
            guard key == entry.iconKey else { return }
            if context.appearance == .dark { darkLoaded.fulfill() } else { lightLoaded.fulfill() }
        }
        for _ in 0..<10 {
            _ = cache.image(for: entry, context: light)
            cache.prewarm([entry], context: light)
        }
        _ = cache.image(for: entry, context: dark)
        await fulfillment(of: [darkLoaded], timeout: 5)
        XCTAssertTrue(cache.image(for: entry, context: dark) === darkIcon.image)
        lightGate.signal()
        await fulfillment(of: [lightLoaded], timeout: 5)
        XCTAssertTrue(cache.image(for: entry, context: dark) === darkIcon.image)
        XCTAssertTrue(cache.image(for: entry, context: light) === lightIcon.image)
        XCTAssertEqual(counts.withLock { $0[light] }, 1)
        XCTAssertEqual(counts.withLock { $0[dark] }, 1)
        let refreshed = expectation(description: "One coalesced refresh")
        cache.onNativeIconLoaded = { key, _ in
            if key == entry.iconKey { refreshed.fulfill() }
        }
        for _ in 0..<5 { cache.refreshNativeIcons([entry], context: dark) }
        XCTAssertTrue(cache.image(for: entry, context: dark) === darkIcon.image)
        await fulfillment(of: [refreshed], timeout: 5)
        XCTAssertEqual(counts.withLock { $0[dark] }, 2)
    }

    func testInteractiveApplicationLookupPromotesInFlightPrewarmAndPublishesOnce() async throws {
        let prewarmIcon = try bitmap(.red)
        let interactiveIcon = try bitmap(.blue)
        let prewarmGate = DispatchSemaphore(value: 0)
        defer { prewarmGate.signal() }
        let started = Mutex(0)
        let published = Mutex(0)
        let cache = IconCache(startsNativeIconResolution: false, applicationIconOperation: { _, _ in
            let count = started.withLock { $0 += 1; return $0 }
            if count == 1 {
                _ = prewarmGate.wait(timeout: .now() + 5)
                return prewarmIcon
            }
            return interactiveIcon
        })
        let entry = applicationEntry(path: "/Applications/Promote.app")
        cache.onNativeIconLoaded = { key, _ in
            guard key == entry.iconKey else { return }
            published.withLock { $0 += 1 }
        }

        cache.prewarm([entry], context: light)
        try await waitUntil { started.withLock { $0 == 1 } }
        let start = ContinuousClock.now
        _ = cache.image(for: entry, context: light)
        try await waitUntil { cache.image(for: entry, context: self.light) === interactiveIcon.image }
        let elapsed = start.duration(to: .now)
        let elapsedMilliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        print(String(
            format: "ICON promoted application load: %.2f ms (prewarm still gated)",
            elapsedMilliseconds
        ))
        XCTAssertEqual(started.withLock { $0 }, 2)
        XCTAssertEqual(published.withLock { $0 }, 1)
        XCTAssertLessThan(elapsedMilliseconds, 400)

        prewarmGate.signal()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(cache.image(for: entry, context: light) === interactiveIcon.image)
        XCTAssertEqual(published.withLock { $0 }, 1)
    }

    func testVisibleApplicationLoadDoesNotWaitForAGatedCatalogPrewarm() async throws {
        let blockedIcon = try bitmap(.red)
        let visibleIcon = try bitmap(.blue)
        let blockedGate = DispatchSemaphore(value: 0)
        defer { blockedGate.signal() }
        let started = Mutex<[String]>([])
        let cache = IconCache(startsNativeIconResolution: false, applicationIconOperation: { url, _ in
            started.withLock { $0.append(url.path) }
            if url.path == "/Applications/Blocked.app" {
                _ = blockedGate.wait(timeout: .now() + 5)
                return blockedIcon
            }
            return visibleIcon
        })
        let blocked = applicationEntry(path: "/Applications/Blocked.app")
        let visible = applicationEntry(path: "/Applications/Visible.app")
        let visibleLoaded = expectation(description: "Visible row loaded while catalog prewarm is gated")
        cache.onNativeIconLoaded = { key, _ in
            if key == visible.iconKey { visibleLoaded.fulfill() }
        }

        cache.prewarm([blocked, visible], context: light)
        try await waitUntil { started.withLock { $0.contains("/Applications/Blocked.app") } }
        let start = ContinuousClock.now
        _ = cache.image(for: visible, context: light)
        await fulfillment(of: [visibleLoaded], timeout: 2)
        let elapsed = start.duration(to: .now)
        let elapsedMilliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        print(String(
            format: "ICON visible application load behind gated prewarm: %.2f ms",
            elapsedMilliseconds
        ))
        XCTAssertTrue(cache.image(for: visible, context: light) === visibleIcon.image)
        XCTAssertFalse(cache.image(for: blocked, context: light) === blockedIcon.image)
        XCTAssertLessThan(elapsedMilliseconds, 400)
        blockedGate.signal()
    }

    func testProductionSettingsPaneNotifiesWhenNativeIconLoads() async throws {
        _ = NSApplication.shared
        let entry = SearchEntry(
            id: "setting:com.apple.LoginItems-Settings.extension",
            kind: .systemSetting,
            title: "Login Items",
            iconKey: "setting:com.apple.LoginItems-Settings.extension",
            target: .setting(
                route: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            )
        )
        let context = IconRenderContext(appearance: .dark, pointSize: 50, backingScale: 2)
        let store = SystemSettingsNativeIconStore()
        let cache = IconCache(systemSettingsIconStore: store, backingScale: 2)
        _ = cache.image(for: entry, context: context)
        try await waitUntil {
            cache.image(for: entry, context: context).size == NSSize(width: 50, height: 50)
        }
        let native = cache.image(for: entry, context: context)
        XCTAssertFalse(native.isTemplate)
        XCTAssertEqual(native.size, NSSize(width: 50, height: 50))
    }

    func testNativeMaterializationUsesRequestedSizeScaleAndAppearance() throws {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        for appearance in [LauncherPreviewResolvedAppearance.light, .dark] {
            for pointSize: CGFloat in [35, 50] {
                for scale: CGFloat in [1, 2] {
                    let context = IconRenderContext(appearance: appearance, pointSize: pointSize, backingScale: scale)
                    let icon = try XCTUnwrap(SystemSettingsNativeIconResolver.materializeIcon(at: url, context: context))
                    XCTAssertEqual(icon.image.size.width, pointSize)
                    XCTAssertEqual(icon.pixelsWide, Int(pointSize * scale))
                    XCTAssertEqual(icon.pixelsHigh, Int(pointSize * scale))
                    XCTAssertFalse(icon.image.isTemplate)
                    XCTAssertEqual(icon.image.representations.count, 1)
                    XCTAssertEqual(icon.cost, (icon.image.representations[0] as? NSBitmapImageRep).map { $0.bytesPerRow * $0.pixelsHigh })
                }
            }
        }
        XCTAssertNotEqual(light.cacheKey(for: "app"), dark.cacheKey(for: "app"))
        XCTAssertNotEqual(light.cacheKey(for: "app"), IconRenderContext(appearance: .light, pointSize: 40).cacheKey(for: "app"))
    }

    func testBitmapCacheUsesActualCostAndEvictsLeastRecentlyUsedContext() throws {
        let icon = try bitmap(.purple)
        let cache = NativeIconBitmapCache(costLimit: icon.cost * 2)
        cache.insert(icon, for: light.cacheKey(for: "one"))
        cache.insert(icon, for: light.cacheKey(for: "two"))
        XCTAssertTrue(cache.image(for: light.cacheKey(for: "one")) === icon)
        cache.insert(icon, for: light.cacheKey(for: "three"))
        XCTAssertNil(cache.image(for: light.cacheKey(for: "two")))
        XCTAssertNotNil(cache.image(for: light.cacheKey(for: "one")))
        XCTAssertNotNil(cache.image(for: light.cacheKey(for: "three")))
        XCTAssertEqual(cache.cost, icon.cost * 2)
        let tiny = NativeIconBitmapCache(costLimit: icon.cost - 1)
        tiny.insert(icon, for: light.cacheKey(for: "oversize"))
        XCTAssertEqual(tiny.cost, 0)
        XCTAssertNil(tiny.image(for: light.cacheKey(for: "oversize")))
    }

    /// The convoy fix: a warmup that has not started yet is promoted, not duplicated. Before
    /// this, a visible row materialized artwork the catalog warmup was already going to
    /// produce, so both competed for the same shared AppKit appearance state.
    func testVisibleRowPromotesAQueuedWarmupInsteadOfMaterializingTwice() async throws {
        let icon = try bitmap(.green)
        let gate = DispatchSemaphore(value: 0)
        defer { for _ in 0..<8 { gate.signal() } }
        let started = Mutex<[String]>([])
        let cache = IconCache(startsNativeIconResolution: false, applicationIconOperation: { url, _ in
            started.withLock { $0.append(url.path) }
            // Occupy both warmup workers so the entry under test stays queued.
            if url.path.hasPrefix("/Applications/Filler") { _ = gate.wait(timeout: .now() + 5) }
            return icon
        })
        let fillers = (0..<4).map { applicationEntry(path: "/Applications/Filler\($0).app") }
        let queued = applicationEntry(path: "/Applications/Queued.app")
        let loaded = expectation(description: "Promoted artwork published")
        cache.onNativeIconLoaded = { key, _ in if key == queued.iconKey { loaded.fulfill() } }

        cache.prewarm(fillers + [queued], context: light)
        try await waitUntil { started.withLock { $0.count >= 2 } }
        XCTAssertFalse(started.withLock { $0.contains(queued.iconKey) })

        _ = cache.image(for: queued, context: light)
        for _ in 0..<8 { gate.signal() }
        await fulfillment(of: [loaded], timeout: 5)

        XCTAssertEqual(
            started.withLock { $0.filter { $0 == queued.iconKey }.count },
            1,
            "A queued warmup must be promoted, never materialized a second time"
        )
    }

    /// Icon Services can answer a cold lookup with its generic application tile. That answer
    /// must not be persisted or treated as final, and a resolved icon must never be replaced
    /// by a later generic one.
    func testGenericPlaceholderArtworkIsRetriedAndNeverOverwritesResolvedArtwork() async throws {
        let placeholder = try bitmap(.gray).markedProvisional()
        let resolved = try bitmap(.blue)
        let attempt = Mutex(0)
        let cache = IconCache(startsNativeIconResolution: false, applicationIconOperation: { _, _ in
            let count = attempt.withLock { $0 += 1; return $0 }
            return count == 1 ? placeholder : resolved
        })
        let entry = applicationEntry(path: "/Applications/Provisional.app")

        _ = cache.image(for: entry, context: light)
        try await waitUntil { cache.image(for: entry, context: self.light) === placeholder.image }

        cache.refreshProvisionalIcons([entry], context: light)
        try await waitUntil { cache.image(for: entry, context: self.light) === resolved.image }

        // A further generic answer must not undo the resolved artwork.
        let regressed = try bitmap(.gray).markedProvisional()
        let regressingCache = IconCache(startsNativeIconResolution: false, applicationIconOperation: { _, _ in
            regressed
        })
        _ = regressingCache.image(for: entry, context: light)
        try await waitUntil { regressingCache.image(for: entry, context: self.light) === regressed.image }
        regressingCache.refreshProvisionalIcons([entry], context: light)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(regressingCache.image(for: entry, context: light) === regressed.image)
        XCTAssertFalse(placeholder.isProvisional == false)
    }

    func testPersistedArtworkSurvivesAColdCacheAndIgnoresPlaceholders() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("broccoli-icon-disk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = NativeIconDiskCache(directory: directory)
        let key = NativeIconDiskCache.key(
            forContentTypeIdentifier: "com.apple.graphic-icon.battery",
            context: light
        )
        XCTAssertNil(disk.icon(for: key, pointSize: light.pointSize))

        let resolved = try bitmap(.blue)
        disk.store(resolved, for: key)
        let restored = try XCTUnwrap(disk.icon(for: key, pointSize: light.pointSize))
        XCTAssertEqual(restored.pixelsWide, resolved.pixelsWide)
        XCTAssertEqual(restored.image.size.width, light.pointSize)
        XCTAssertFalse(restored.isProvisional)

        let placeholderKey = NativeIconDiskCache.key(
            forContentTypeIdentifier: "com.apple.graphic-icon.energy",
            context: light
        )
        disk.store(try bitmap(.gray).markedProvisional(), for: placeholderKey)
        XCTAssertNil(
            disk.icon(for: placeholderKey, pointSize: light.pointSize),
            "Generic placeholder artwork must never be persisted"
        )
    }

    func testColdApplicationLookupReadsDiskWithoutCallingIconServices() throws {
        _ = NSApplication.shared
        let path = "/System/Library/CoreServices/Finder.app"
        let context = IconRenderContext(appearance: .dark, pointSize: 50, backingScale: 2)
        XCTAssertNotNil(
            SystemSettingsNativeIconResolver.materializeIcon(
                at: URL(fileURLWithPath: path),
                context: context
            )
        )

        let cache = IconCache(startsNativeIconResolution: false)
        let entry = applicationEntry(path: path)

        let started = ContinuousClock.now
        let image = cache.image(for: entry, context: context)
        let elapsed = started.duration(to: .now)
        let elapsedMilliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        print(String(format: "ICON cold disk-backed Finder lookup: %.2f ms", elapsedMilliseconds))

        XCTAssertEqual(image.size, NSSize(width: 50, height: 50))
        XCTAssertFalse(image.isTemplate)
        XCTAssertLessThan(elapsedMilliseconds, 25)
        XCTAssertTrue(cache.image(for: entry, context: context) === image)
    }

    private func applicationEntry(path: String) -> SearchEntry {
        SearchEntry(
            id: "app:\(path)",
            kind: .application,
            title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            iconKey: path,
            target: .application(path: path, bundleIdentifier: nil)
        )
    }

    private func bitmap(_ color: NSColor) throws -> MaterializedSystemSettingsIcon {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 50, height: 50).fill()
        image.unlockFocus()
        return try XCTUnwrap(SystemSettingsNativeIconResolver.materializeImage(image, pointSize: 50, backingScale: 2))
    }

    private func waitUntil(_ predicate: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { XCTFail("Timed out waiting for native icon work"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
