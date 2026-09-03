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
/// The directory walk is shallow, happens once at background priority, and is shared by all
/// `IconCache` instances. This keeps every filesystem read and bundle lookup away from the
/// launcher's keystroke-to-results path.
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
        let task = Task.detached(priority: .background) {
            indexBuilder(roots)
        }
        indexingTask = task
        let result = await task.value
        // A transient filesystem failure at cold launch must not poison the process for its
        // entire lifetime. Successful shallow scans are reused; a wholly empty scan can be
        // attempted again if another cache asks later.
        if !result.isEmpty { cachedBundleURLs = result }
        indexingTask = nil
        return result
    }

    private func buildIndex(roots: [URL]) async -> [String: URL] {
        let indexBuilder = self.indexBuilder
        return await Task.detached(priority: .background) {
            indexBuilder(roots)
        }.value
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

    init(image: NSImage, bitmap: NSBitmapImageRep) {
        self.image = image
        pixelsWide = bitmap.pixelsWide
        pixelsHigh = bitmap.pixelsHigh
        cost = bitmap.bytesPerRow * bitmap.pixelsHigh
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
        backingScale: CGFloat
    ) async -> SystemSettingsNativeIconResolution {
        let identifiers = Set(requests.map(\.bundleIdentifier))
        let extensionURLs = await SystemSettingsExtensionIndex.shared.bundleURLs(
            for: identifiers
        )
        let extensionIndexSucceeded = !extensionURLs.isEmpty

        return await Task.detached(priority: .background) {
            let powerIconContentTypeIdentifier =
                SystemSettingsPowerIconSelector.contentTypeIdentifier(
                    powerSourceTypes: SystemPowerSourceSnapshot.powerSourceTypes()
                )
            let sources = SystemSettingsIconRequestMapper.iconKeysBySource(
                for: requests,
                installedExtensionBundleIdentifiers: Set(extensionURLs.keys),
                powerIconContentTypeIdentifier: powerIconContentTypeIdentifier
            )
            var resolved: [String: MaterializedSystemSettingsIcon] = [:]

            // Duplicate routes such as Keyboard and Keyboard Shortcuts share one materialized
            // bitmap, then publish the same immutable object under both icon keys.
            for (source, iconKeys) in sources {
                let sourceURL: URL?
                switch source {
                case .settingsExtension(let bundleIdentifier):
                    sourceURL = extensionURLs[bundleIdentifier]?.standardizedFileURL
                case .application(let bundleIdentifier):
                    sourceURL = validatedSystemApplicationURL(
                        NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: bundleIdentifier
                        )
                    )
                case .contentType:
                    sourceURL = nil
                }
                let icon: MaterializedSystemSettingsIcon?
                if case .contentType(let identifier) = source {
                    icon = materializeIcon(
                        forContentTypeIdentifier: identifier,
                        pointSize: 40,
                        backingScale: backingScale
                    )
                } else if let sourceURL {
                    icon = materializeIcon(
                        at: sourceURL,
                        pointSize: 40,
                        backingScale: backingScale
                    )
                } else {
                    icon = nil
                }
                guard let icon else { continue }
                for iconKey in iconKeys { resolved[iconKey] = icon }
            }

            return SystemSettingsNativeIconResolution(
                iconsByKey: resolved,
                extensionIndexSucceeded: extensionIndexSucceeded
            )
        }.value
    }

    nonisolated static func materializeIcon(
        at url: URL,
        pointSize: CGFloat,
        backingScale: CGFloat
    ) -> MaterializedSystemSettingsIcon? {
        return autoreleasepool {
            let workspaceImage = NSWorkspace.shared.icon(forFile: url.path)
            return materializeImage(
                workspaceImage,
                pointSize: pointSize,
                backingScale: backingScale
            )
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
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(origin: .zero, size: pixelSize))
        workspaceImage.draw(
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

/// Process-wide, bounded native pane-icon cache. Resolution is started once after an
/// `IconCache` is constructed, never by `image(for:)`, so cache misses during typing can only
/// return the prebuilt SF-symbol fallback.
@MainActor
final class SystemSettingsNativeIconStore {
    typealias ResolutionOperation = @Sendable (
        [SystemSettingsIconRequest],
        CGFloat
    ) async -> SystemSettingsNativeIconResolution

    static let shared = SystemSettingsNativeIconStore()
    static let didLoadNotification = Notification.Name(
        "dev.gauravpandey.broccoli.system-settings-native-icon-loaded"
    )

    private let cache = NSCache<NSString, MaterializedSystemSettingsIcon>()
    private let resolutionOperation: ResolutionOperation
    private var isResolving = false
    private var completedSuccessfulResolution = false
    private(set) var resolutionAttemptCount = 0

    init(
        cacheCostLimit: Int = 16 * 1_024 * 1_024,
        resolutionOperation: @escaping ResolutionOperation = SystemSettingsNativeIconResolver.resolve
    ) {
        cache.totalCostLimit = max(1, cacheCostLimit)
        self.resolutionOperation = resolutionOperation
    }

    func cachedIcon(for iconKey: String) -> MaterializedSystemSettingsIcon? {
        cache.object(forKey: iconKey as NSString)
    }

    func ensureResolution(
        requests: [SystemSettingsIconRequest],
        backingScale: CGFloat
    ) {
        guard !requests.isEmpty,
              !isResolving,
              !completedSuccessfulResolution else { return }
        isResolving = true
        resolutionAttemptCount += 1
        let operation = resolutionOperation

        Task { [weak self] in
            let result = await operation(requests, backingScale)
            guard let self else { return }
            for (iconKey, icon) in result.iconsByKey {
                cache.setObject(icon, forKey: iconKey as NSString, cost: icon.cost)
                NotificationCenter.default.post(
                    name: Self.didLoadNotification,
                    object: iconKey
                )
            }
            isResolving = false
            completedSuccessfulResolution = result.extensionIndexSucceeded
        }
    }
}
