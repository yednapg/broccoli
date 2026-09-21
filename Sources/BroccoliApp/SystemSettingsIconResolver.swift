@preconcurrency import AppKit
import BroccoliCore
import Foundation
@preconcurrency import IOKit.ps
import UniformTypeIdentifiers

/// The minimal information needed to replace a Setting's immediately available SF-symbol
/// fallback with the icon supplied by its installed System Settings extension.
struct SystemSettingsIconRequest: Equatable, Hashable, Sendable {
    let iconKey: String
    let bundleIdentifier: String
    let fallbackApplicationBundleIdentifier: String?
}

enum SystemSettingsNativeIconSource: Equatable, Hashable, Sendable {
    case settingsExtension(bundleIdentifier: String)
    case application(bundleIdentifier: String)
    case contentType(identifier: String)
}

/// Chooses the same public graphic-icon family System Settings uses for its power pane.
///
/// The selection itself is pure so laptop and desktop behavior can be covered without querying
/// host state. `SystemPowerSourceSnapshot` supplies that state later, on the resolver's background
/// task rather than on the launcher search path.
enum SystemSettingsPowerIconSelector {
    static let settingsBundleIdentifier = "com.apple.Battery-Settings.extension"
    static let batteryContentTypeIdentifier = "com.apple.graphic-icon.battery"
    static let energyContentTypeIdentifier = "com.apple.graphic-icon.energy"

    static func hasInternalBattery(powerSourceTypes: [String]) -> Bool {
        powerSourceTypes.contains(kIOPSInternalBatteryType)
    }

    static func contentTypeIdentifier(hasInternalBattery: Bool) -> String {
        hasInternalBattery
            ? batteryContentTypeIdentifier
            : energyContentTypeIdentifier
    }

    static func contentTypeIdentifier(powerSourceTypes: [String]) -> String {
        contentTypeIdentifier(
            hasInternalBattery: hasInternalBattery(powerSourceTypes: powerSourceTypes)
        )
    }
}

/// A public IOKit power-source snapshot. Callers invoke this only from the native-icon resolver's
/// background task; route mapping and cache lookup remain pure and perform no I/O.
enum SystemPowerSourceSnapshot {
    nonisolated static func powerSourceTypes() -> [String] {
        autoreleasepool {
            let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as NSArray

            return sources.compactMap { source in
                guard let description = IOPSGetPowerSourceDescription(
                    snapshot,
                    source as CFTypeRef
                )?.takeUnretainedValue() as? [String: Any] else { return nil }
                return description[kIOPSTypeKey] as? String
            }
        }
    }
}

/// Pure mapping from public `x-apple.systempreferences:` routes to icon requests.
///
/// This deliberately does not inspect an extension's private resources or IconServices
/// configuration. The bundle identifier is only used to locate the installed `.appex`; its
/// public file icon is then requested through `NSWorkspace`.
enum SystemSettingsIconRequestMapper {
    private static let routePrefix = "x-apple.systempreferences:"
    static let applicationFallbacks: [String: String] = [
        "com.apple.Passwords-Settings.extension": "com.apple.Passwords",
        "com.apple.ScreenSaver-Settings.extension": "com.apple.ScreenSaver.Engine",
    ]

    static func bundleIdentifier(from route: String?) -> String? {
        guard let route,
              route.hasPrefix(routePrefix) else { return nil }

        let routePayload = route.dropFirst(routePrefix.count)
        let encodedIdentifier = routePayload.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )[0]
        guard !encodedIdentifier.isEmpty,
              let identifier = String(encodedIdentifier).removingPercentEncoding,
              !identifier.isEmpty,
              identifier.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics
                      .union(CharacterSet(charactersIn: ".-"))
                      .contains($0)
              }) else { return nil }

        return identifier
    }

    static func request(
        for entry: SearchEntry,
        applicationFallbacks: [String: String] = applicationFallbacks
    ) -> SystemSettingsIconRequest? {
        guard entry.kind == .systemSetting,
              case .setting(let route) = entry.target,
              let bundleIdentifier = bundleIdentifier(from: route) else { return nil }
        return SystemSettingsIconRequest(
            iconKey: entry.iconKey,
            bundleIdentifier: bundleIdentifier,
            fallbackApplicationBundleIdentifier: applicationFallbacks[bundleIdentifier]
        )
    }

    static func requests(for entries: [SearchEntry]) -> [SystemSettingsIconRequest] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let request = request(for: entry),
                  seen.insert(request.iconKey).inserted else { return nil }
            return request
        }
    }

    /// Selects the extension whenever it is installed. The application is only a public native
    /// fallback for Settings panes whose extension is absent on the running macOS release.
    static func preferredSource(
        for request: SystemSettingsIconRequest,
        installedExtensionBundleIdentifiers: Set<String>,
        powerIconContentTypeIdentifier: String
    ) -> SystemSettingsNativeIconSource? {
        if request.bundleIdentifier == SystemSettingsPowerIconSelector.settingsBundleIdentifier {
            // PowerPreferences.appex intentionally exposes a generic ExtensionKit cube. Public
            // graphic-icon UTIs return System Settings' semantic Battery or Energy artwork.
            return .contentType(identifier: powerIconContentTypeIdentifier)
        }
        if installedExtensionBundleIdentifiers.contains(request.bundleIdentifier) {
            return .settingsExtension(bundleIdentifier: request.bundleIdentifier)
        }
        return request.fallbackApplicationBundleIdentifier.map {
            .application(bundleIdentifier: $0)
        }
    }

    static func iconKeysBySource(
        for requests: [SystemSettingsIconRequest],
        installedExtensionBundleIdentifiers: Set<String>,
        powerIconContentTypeIdentifier: String
    ) -> [SystemSettingsNativeIconSource: [String]] {
        var result: [SystemSettingsNativeIconSource: [String]] = [:]
        for request in requests {
            guard let source = preferredSource(
                for: request,
                installedExtensionBundleIdentifiers: installedExtensionBundleIdentifiers,
                powerIconContentTypeIdentifier: powerIconContentTypeIdentifier
            ) else { continue }
            result[source, default: []].append(request.iconKey)
        }
        return result.mapValues { Array(Set($0)).sorted() }
    }
}

/// Process-wide index of installed System Settings extensions.
///
/// The directory walk is shallow, happens once at user-initiated priority, and is shared by
/// all `IconCache` instances. Prefetching at launch keeps the first visible Settings rows
/// from waiting on a cold index.
actor SystemSettingsExtensionIndex {
    typealias IndexBuilder = @Sendable ([URL]) -> [String: URL]

    static let shared = SystemSettingsExtensionIndex()

    static let standardRoots = [
        URL(
            fileURLWithPath: "/System/Library/ExtensionKit/Extensions",
            isDirectory: true
        ),
        URL(
            fileURLWithPath: "/System/Applications/System Settings.app/Contents/PlugIns",
            isDirectory: true
        ),
    ]

    private var cachedBundleURLs: [String: URL]?
    private var indexingTask: Task<[String: URL], Never>?
    private let indexBuilder: IndexBuilder

    init(indexBuilder: IndexBuilder? = nil) {
        self.indexBuilder = indexBuilder ?? { roots in
            Self.buildIndexSynchronously(roots: roots)
        }
    }

    /// Starts the shallow ExtensionKit walk at user-initiated priority so the first
    /// launcher expansion does not wait on a background index.
    func prefetchStandardIndex() async {
        _ = await makeOrAwaitStandardIndex()
    }

    func bundleURLs(
        for identifiers: Set<String>,
        roots: [URL] = standardRoots
    ) async -> [String: URL] {
        guard !identifiers.isEmpty else { return [:] }

        let index: [String: URL]
        if roots == Self.standardRoots {
            index = await makeOrAwaitStandardIndex()
        } else {
            index = await buildIndex(roots: roots)
        }

        return index.filter { identifiers.contains($0.key) }
    }

    private func makeOrAwaitStandardIndex() async -> [String: URL] {
        if let cachedBundleURLs { return cachedBundleURLs }
        if let indexingTask { return await indexingTask.value }

        let roots = Self.standardRoots
        let indexBuilder = self.indexBuilder
        let task = Task.detached(priority: .userInitiated) {
            indexBuilder(roots)
        }
        indexingTask = task
        let result = await task.value
        // A transient filesystem failure at cold launch must not poison the process for its
        // entire lifetime. Successful shallow scans are reused; a wholly empty scan can be
        // attempted again if another cache asks later.
        if !result.isEmpty {
            cachedBundleURLs = result
            Self.publishStandardIndex(result)
        }
        indexingTask = nil
        return result
    }

    private func buildIndex(roots: [URL]) async -> [String: URL] {
        let indexBuilder = self.indexBuilder
        return await Task.detached(priority: .userInitiated) {
            indexBuilder(roots)
        }.value
    }

    /// Snapshot of the standard ExtensionKit index for the launcher paint path. Disk-backed
    /// Settings artwork is keyed by `.appex` URL; this avoids an actor hop on each row.
    private final class PublishedStandardIndex: @unchecked Sendable {
        static let shared = PublishedStandardIndex()
        private let lock = NSLock()
        private var urls: [String: URL] = [:]

        func publish(_ urls: [String: URL]) {
            lock.lock()
            self.urls = urls
            lock.unlock()
        }

        func url(for bundleIdentifier: String) -> URL? {
            lock.lock()
            defer { lock.unlock() }
            return urls[bundleIdentifier]
        }

        var isPublished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !urls.isEmpty
        }
    }

    private static func publishStandardIndex(_ urls: [String: URL]) {
        PublishedStandardIndex.shared.publish(urls)
    }

    nonisolated static func publishedURL(for bundleIdentifier: String) -> URL? {
        if let url = PublishedStandardIndex.shared.url(for: bundleIdentifier) {
            return url
        }
        if PublishedStandardIndex.shared.isPublished { return nil }
        let index = buildIndexSynchronously(roots: standardRoots)
        if !index.isEmpty { publishStandardIndex(index) }
        return index[bundleIdentifier]
    }

    nonisolated private static func buildIndexSynchronously(roots: [URL]) -> [String: URL] {
        var result: [String: URL] = [:]

        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for candidate in children where candidate.pathExtension == "appex" {
                guard let identifier = Bundle(url: candidate)?.bundleIdentifier else { continue }
                result[identifier] = candidate
            }
        }
        return result
    }
}

/// A single, fully decoded bitmap. The wrapped `NSImage` contains exactly one bitmap
/// representation and is never mutated after initialization.
final class MaterializedSystemSettingsIcon: @unchecked Sendable {
    let image: NSImage
    let cost: Int
    let pixelsWide: Int
    let pixelsHigh: Int
    /// Content hash of the decoded pixels, used to recognize Icon Services' generic
    /// placeholder. Process-local only: `Hasher` is seeded per process and this value is
    /// never persisted or compared across launches.
    let fingerprint: Int
    /// True when Icon Services answered with its generic artwork instead of the real icon.
    /// Provisional artwork is still shown so the row is not empty, but it is never written to
    /// the disk cache and stays eligible for one later re-resolution.
    let isProvisional: Bool

    init(image: NSImage, bitmap: NSBitmapImageRep, isProvisional: Bool = false) {
        self.image = image
        pixelsWide = bitmap.pixelsWide
        pixelsHigh = bitmap.pixelsHigh
        cost = bitmap.bytesPerRow * bitmap.pixelsHigh
        fingerprint = SystemSettingsNativeIconResolver.fingerprint(of: bitmap)
        self.isProvisional = isProvisional
    }

    private init(copying other: MaterializedSystemSettingsIcon, isProvisional: Bool) {
        image = other.image
        cost = other.cost
        pixelsWide = other.pixelsWide
        pixelsHigh = other.pixelsHigh
        fingerprint = other.fingerprint
        self.isProvisional = isProvisional
    }

    func markedProvisional() -> MaterializedSystemSettingsIcon {
        isProvisional ? self : MaterializedSystemSettingsIcon(copying: self, isProvisional: true)
    }
}

/// Remembers what Icon Services' generic application artwork looks like at each drawing size.
/// Materializing it once per size is enough to recognize a placeholder answer later.
private final class GenericApplicationIconFingerprints: @unchecked Sendable {
    static let shared = GenericApplicationIconFingerprints()
    private let lock = NSLock()
    private var fingerprints: [String: Int?] = [:]

    func fingerprint(pointSize: CGFloat, backingScale: CGFloat) -> Int? {
        let key = "\(pointSize)x\(backingScale)"
        lock.lock()
        if let cached = fingerprints[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved: Int? = autoreleasepool {
            let generic = NSWorkspace.shared.icon(for: .applicationBundle)
            return SystemSettingsNativeIconResolver.materializeImage(
                generic,
                pointSize: pointSize,
                backingScale: backingScale
            )?.fingerprint
        }
        lock.lock()
        fingerprints[key] = resolved
        lock.unlock()
        return resolved
    }
}

struct SystemSettingsNativeIconResolution: Sendable {
    let iconsByKey: [String: MaterializedSystemSettingsIcon]
    let extensionIndexSucceeded: Bool
}

enum SystemSettingsNativeIconResolver {
    static let allowedApplicationRoots = [
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
    ]
    /// Icon materialization contends on shared AppKit appearance state, so more workers stop
    /// helping quickly. Measured on this class of machine, eight concurrent workers finished
    /// a 40-icon batch in about the same wall time as three while more than doubling the
    /// median per-icon cost. Keep both pools small.
    static let interactiveWorkerLimit = 4
    static let catalogWorkerLimit = 2
    static func validatedSystemApplicationURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let candidate = url.standardizedFileURL
        guard allowedApplicationRoots.contains(where: { root in
            let rootPath = root.standardizedFileURL.path
            return candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/")
        }) else { return nil }
        return candidate
    }

    static func resolve(
        requests: [SystemSettingsIconRequest],
        context: IconRenderContext,
        priority: TaskPriority = .userInitiated,
        onIcon: (@MainActor @Sendable (String, MaterializedSystemSettingsIcon) -> Void)? = nil
    ) async -> SystemSettingsNativeIconResolution {
        let identifiers = Set(requests.map(\.bundleIdentifier))
        let extensionURLs = await SystemSettingsExtensionIndex.shared.bundleURLs(
            for: identifiers
        )
        let extensionIndexSucceeded = !extensionURLs.isEmpty
        let powerIconContentTypeIdentifier =
            SystemSettingsPowerIconSelector.contentTypeIdentifier(
                powerSourceTypes: SystemPowerSourceSnapshot.powerSourceTypes()
            )
        var sourceByIconKey: [String: SystemSettingsNativeIconSource] = [:]
        var uniqueSources: [SystemSettingsNativeIconSource] = []
        var seenSources = Set<SystemSettingsNativeIconSource>()
        for request in requests {
            guard let source = SystemSettingsIconRequestMapper.preferredSource(
                for: request,
                installedExtensionBundleIdentifiers: Set(extensionURLs.keys),
                powerIconContentTypeIdentifier: powerIconContentTypeIdentifier
            ) else { continue }
            sourceByIconKey[request.iconKey] = source
            if seenSources.insert(source).inserted {
                uniqueSources.append(source)
            }
        }

        var iconsBySource: [SystemSettingsNativeIconSource: MaterializedSystemSettingsIcon] = [:]
        let workerLimit = max(1, min(
            uniqueSources.count,
            priority >= .userInitiated ? interactiveWorkerLimit : catalogWorkerLimit
        ))
        await withTaskGroup(
            of: (SystemSettingsNativeIconSource, MaterializedSystemSettingsIcon?).self
        ) { group in
            var remaining = uniqueSources.makeIterator()
            for _ in 0..<workerLimit {
                guard let source = remaining.next() else { break }
                group.addTask(priority: priority) {
                    let icon = materialize(
                        source: source,
                        extensionURLs: extensionURLs,
                        context: context
                    )
                    return (source, icon)
                }
            }
            for await (source, icon) in group {
                if let icon {
                    iconsBySource[source] = icon
                    if let onIcon {
                        for request in requests where sourceByIconKey[request.iconKey] == source {
                            await MainActor.run { onIcon(request.iconKey, icon) }
                        }
                    }
                }
                if let next = remaining.next() {
                    group.addTask(priority: priority) {
                        let icon = materialize(
                            source: next,
                            extensionURLs: extensionURLs,
                            context: context
                        )
                        return (next, icon)
                    }
                }
            }
        }

        var resolved: [String: MaterializedSystemSettingsIcon] = [:]
        for request in requests {
            guard let source = sourceByIconKey[request.iconKey],
                  let icon = iconsBySource[source] else { continue }
            resolved[request.iconKey] = icon
        }

        return SystemSettingsNativeIconResolution(
            iconsByKey: resolved,
            extensionIndexSucceeded: extensionIndexSucceeded
        )
    }

    nonisolated private static func materialize(
        source: SystemSettingsNativeIconSource,
        extensionURLs: [String: URL],
        context: IconRenderContext
    ) -> MaterializedSystemSettingsIcon? {
        switch source {
        case .contentType(let identifier):
            return materializeIcon(forContentTypeIdentifier: identifier, context: context)
        case .settingsExtension(let bundleIdentifier):
            guard let sourceURL = extensionURLs[bundleIdentifier]?.standardizedFileURL else { return nil }
            return materializeIcon(at: sourceURL, context: context)
        case .application(let bundleIdentifier):
            guard let sourceURL = validatedSystemApplicationURL(
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ) else { return nil }
            return materializeIcon(at: sourceURL, context: context)
        }
    }

    nonisolated static func materializeIcon(at url: URL, context: IconRenderContext) -> MaterializedSystemSettingsIcon? {
        let diskKey = NativeIconDiskCache.key(forFileAt: url, context: context)
        if let diskKey,
           let persisted = NativeIconDiskCache.shared.icon(for: diskKey, pointSize: context.pointSize) {
            return persisted
        }
        var result: MaterializedSystemSettingsIcon?
        context.drawingAppearance.performAsCurrentDrawingAppearance {
            result = materializeIcon(at: url, pointSize: context.pointSize, backingScale: context.backingScale)
        }
        if let result, let diskKey { NativeIconDiskCache.shared.store(result, for: diskKey) }
        return result
    }

    nonisolated static func materializeIcon(forContentTypeIdentifier identifier: String,
                                           context: IconRenderContext) -> MaterializedSystemSettingsIcon? {
        let diskKey = NativeIconDiskCache.key(forContentTypeIdentifier: identifier, context: context)
        if let persisted = NativeIconDiskCache.shared.icon(for: diskKey, pointSize: context.pointSize) {
            return persisted
        }
        var result: MaterializedSystemSettingsIcon?
        context.drawingAppearance.performAsCurrentDrawingAppearance {
            result = materializeIcon(forContentTypeIdentifier: identifier,
                pointSize: context.pointSize, backingScale: context.backingScale)
        }
        if let result { NativeIconDiskCache.shared.store(result, for: diskKey) }
        return result
    }

    /// Hashes the decoded pixels so a generic Icon Services answer can be told apart from the
    /// real artwork.
    nonisolated static func fingerprint(of bitmap: NSBitmapImageRep) -> Int {
        guard let data = bitmap.bitmapData else { return 0 }
        let count = bitmap.bytesPerRow * bitmap.pixelsHigh
        guard count > 0 else { return 0 }
        var hasher = Hasher()
        hasher.combine(bytes: UnsafeRawBufferPointer(start: data, count: count))
        return hasher.finalize()
    }

    nonisolated static func materializeIcon(
        at url: URL,
        pointSize: CGFloat,
        backingScale: CGFloat
    ) -> MaterializedSystemSettingsIcon? {
        return autoreleasepool {
            let workspaceImage = NSWorkspace.shared.icon(forFile: url.path)
            guard let icon = materializeImage(
                workspaceImage,
                pointSize: pointSize,
                backingScale: backingScale
            ) else { return nil }
            // A cold lookup can return the generic application tile before the real artwork
            // is ready. Mark that answer so it is neither persisted nor treated as final.
            guard url.pathExtension == "app",
                  let generic = GenericApplicationIconFingerprints.shared.fingerprint(
                      pointSize: pointSize,
                      backingScale: backingScale
                  ), generic == icon.fingerprint else { return icon }
            return icon.markedProvisional()
        }
    }

    nonisolated static func materializeIcon(
        forContentTypeIdentifier identifier: String,
        pointSize: CGFloat,
        backingScale: CGFloat
    ) -> MaterializedSystemSettingsIcon? {
        autoreleasepool {
            let contentType = UTType(importedAs: identifier)
            let workspaceImage = NSWorkspace.shared.icon(for: contentType)
            return materializeImage(
                workspaceImage,
                pointSize: pointSize,
                backingScale: backingScale
            )
        }
    }

    /// Converts the lazily decoded image returned by `NSWorkspace` into one bounded bitmap.
    /// `NSGraphicsContext(bitmapImageRep:)` uses pixel coordinates, even after the bitmap's
    /// logical point size is assigned. Drawing a 40×40-point rect into an 80×80 bitmap at 2×
    /// therefore occupied only one quadrant and made every Settings pane icon look half-size.
    /// Draw in device pixels, then attach the 40-point logical size to the completed rep.
    nonisolated static func materializeImage(
        _ workspaceImage: NSImage,
        pointSize: CGFloat,
        backingScale: CGFloat
    ) -> MaterializedSystemSettingsIcon? {
        let scale = max(1, backingScale)
        let pixels = max(1, Int(ceil(pointSize * scale)))
        guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        let size = NSSize(width: pointSize, height: pointSize)
        let pixelSize = NSSize(width: pixels, height: pixels)
        // Copy before changing `size`. The 32-point default often vends a small SF-symbol
        // variant; matching the destination canvas selects the native squircle instead.
        let drawable = (workspaceImage.copy() as? NSImage) ?? workspaceImage
        drawable.size = pixelSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(origin: .zero, size: pixelSize))
        drawable.draw(
            in: NSRect(origin: .zero, size: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = size

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        return MaterializedSystemSettingsIcon(image: image, bitmap: bitmap)
    }
}

/// NotificationCenter's `object` must be a class. Posting `Completion` as a struct made
/// `as? Completion` fail, so Settings rows never swapped fallback glyphs for native art.
final class SystemSettingsNativeIconCompletionBox: NSObject, @unchecked Sendable {
    let completion: SystemSettingsNativeIconStore.Completion
    init(_ completion: SystemSettingsNativeIconStore.Completion) {
        self.completion = completion
    }
}

/// Shared native artwork is cached per appearance, size and display scale. Failures remain
/// retryable, while identical in-flight requests are deduplicated across launcher and previews.
@MainActor
final class SystemSettingsNativeIconStore {
    typealias ResolutionOperation = @Sendable (
        [SystemSettingsIconRequest], IconRenderContext
    ) async -> SystemSettingsNativeIconResolution

    struct Completion: Sendable {
        let iconKey: String
        let context: IconRenderContext
        let storeIdentifier: ObjectIdentifier
    }

    static let shared = SystemSettingsNativeIconStore()
    static let didLoadNotification = Notification.Name(
        "dev.gauravpandey.broccoli.system-settings-native-icon-loaded"
    )
    private let cache: NativeIconBitmapCache
    private let resolutionOperation: ResolutionOperation
    private let streamsIncrementalIcons: Bool
    private var inFlight: Set<IconCacheKey> = []
    private var interactiveInFlight: Set<IconCacheKey> = []
    private var previousKeys: [String: IconCacheKey] = [:]
    private(set) var resolutionAttemptCount = 0
    var inFlightRequestCount: Int { inFlight.count }
    var cachedBitmapCost: Int { cache.cost }

    init(cacheCostLimit: Int = 16 * 1_024 * 1_024,
         resolutionOperation: ResolutionOperation? = nil) {
        cache = NativeIconBitmapCache(costLimit: cacheCostLimit)
        if let resolutionOperation {
            self.resolutionOperation = resolutionOperation
            streamsIncrementalIcons = false
        } else {
            self.resolutionOperation = { requests, context in
                await SystemSettingsNativeIconResolver.resolve(requests: requests, context: context)
            }
            streamsIncrementalIcons = true
        }
    }

    func cachedIcon(for iconKey: String, context: IconRenderContext? = nil) -> MaterializedSystemSettingsIcon? {
        let context = context ?? LauncherAppearanceEnvironment.current.iconContext(mode: .system, pointSize: 40)
        let key = context.cacheKey(for: iconKey)
        if let cached = cache.image(for: key) { return cached }
        // Injected stores stay cache-only so tests can observe resolution. Production reads
        // the persisted bitmap on the first paint instead of waiting for a background hop.
        guard streamsIncrementalIcons,
              let persisted = Self.persistedIcon(for: iconKey, context: context) else { return nil }
        _ = cache.insert(persisted, for: key)
        previousKeys[iconKey] = key
        return persisted
    }

    /// Settings rows are painted before `ensureResolution` returns. If this process already
    /// materialized the pane on a previous launch, show that PNG immediately.
    private static func persistedIcon(
        for iconKey: String,
        context: IconRenderContext
    ) -> MaterializedSystemSettingsIcon? {
        let bundleIdentifier = iconKey.hasPrefix("setting:")
            ? String(iconKey.dropFirst("setting:".count))
            : iconKey
        if bundleIdentifier == SystemSettingsPowerIconSelector.settingsBundleIdentifier {
            for identifier in [
                SystemSettingsPowerIconSelector.batteryContentTypeIdentifier,
                SystemSettingsPowerIconSelector.energyContentTypeIdentifier,
            ] {
                let diskKey = NativeIconDiskCache.key(
                    forContentTypeIdentifier: identifier,
                    context: context
                )
                if let icon = NativeIconDiskCache.shared.icon(
                    for: diskKey,
                    pointSize: context.pointSize
                ) {
                    return icon
                }
            }
            return nil
        }
        guard let url = SystemSettingsExtensionIndex.publishedURL(for: bundleIdentifier),
              let diskKey = NativeIconDiskCache.key(forFileAt: url, context: context) else {
            return nil
        }
        return NativeIconDiskCache.shared.icon(for: diskKey, pointSize: context.pointSize)
    }

    func previousIcon(for iconKey: String) -> MaterializedSystemSettingsIcon? {
        guard let key = previousKeys[iconKey] else { return nil }
        return cache.image(for: key)
    }

    func ensureResolution(requests: [SystemSettingsIconRequest], backingScale: CGFloat) {
        ensureResolution(requests: requests,
            context: LauncherAppearanceEnvironment.current.iconContext(mode: .system, pointSize: 40, backingScale: backingScale))
    }

    func ensureResolution(requests: [SystemSettingsIconRequest], context: IconRenderContext,
                          refresh: Bool = false, interactive: Bool = true) {
        var seen = Set<IconCacheKey>()
        let missing = requests.filter {
            let key = context.cacheKey(for: $0.iconKey)
            guard seen.insert(key).inserted else { return false }
            if !refresh, cache.image(for: key) != nil { return false }
            if interactive { return !interactiveInFlight.contains(key) }
            return !inFlight.contains(key)
        }
        guard !missing.isEmpty else { return }
        let keys = missing.map { context.cacheKey(for: $0.iconKey) }
        inFlight.formUnion(keys)
        if interactive { interactiveInFlight.formUnion(keys) }
        resolutionAttemptCount += 1
        let operation = resolutionOperation
        let shouldStream = streamsIncrementalIcons
        Task(priority: interactive ? .userInitiated : .utility) { [weak self] in
            if shouldStream {
                if interactive {
                    _ = await SystemSettingsNativeIconResolver.resolve(
                        requests: missing,
                        context: context,
                        priority: .userInitiated
                    ) { key, icon in
                        self?.publish(
                            icon,
                            iconKey: key,
                            context: context,
                            replaceExisting: refresh
                        )
                    }
                } else {
                    _ = await SystemSettingsNativeIconResolver.resolve(
                        requests: missing,
                        context: context,
                        priority: .utility
                    ) { key, icon in
                        self?.publish(
                            icon,
                            iconKey: key,
                            context: context,
                            replaceExisting: refresh
                        )
                    }
                }
                guard let self else { return }
                inFlight.subtract(keys)
                interactiveInFlight.subtract(keys)
                return
            }
            let result = await operation(missing, context)
            guard let self else { return }
            inFlight.subtract(keys)
            interactiveInFlight.subtract(keys)
            for request in missing {
                guard let icon = result.iconsByKey[request.iconKey] else { continue }
                publish(
                    icon,
                    iconKey: request.iconKey,
                    context: context,
                    replaceExisting: refresh
                )
            }
        }
    }

    private func publish(
        _ icon: MaterializedSystemSettingsIcon,
        iconKey: String,
        context: IconRenderContext,
        replaceExisting: Bool
    ) {
        let key = context.cacheKey(for: iconKey)
        if !replaceExisting, cache.image(for: key) != nil { return }
        guard cache.insert(icon, for: key) else { return }
        if previousKeys.count >= 512 { previousKeys.removeAll(keepingCapacity: true) }
        previousKeys[iconKey] = key
        let completion = Completion(
            iconKey: iconKey,
            context: context,
            storeIdentifier: ObjectIdentifier(self)
        )
        NotificationCenter.default.post(
            name: Self.didLoadNotification,
            object: SystemSettingsNativeIconCompletionBox(completion)
        )
    }
}
