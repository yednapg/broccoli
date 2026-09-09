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
