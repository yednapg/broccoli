@preconcurrency import AppKit
import BroccoliCore
import Foundation
import OSLog
import QuickLookThumbnailing

private final class SendableImage: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}

@MainActor
final class IconCache {
    typealias ApplicationIconOperation = @Sendable (URL, IconRenderContext) -> MaterializedSystemSettingsIcon?
    private let applicationIconOperation: ApplicationIconOperation
    private let readsPersistedApplicationIcons: Bool
    private let cache = NSCache<NSString, NSImage>()
    private var staticIcons: [String: NSImage] = [:]
    private var previousNativeKeys: [String: IconCacheKey] = [:]
    private var pendingRefresh: Task<Void, Never>?
    private var refreshEntries: [IconRenderContext: [String: SearchEntry]] = [:]
    private let systemSettingsIconStore: SystemSettingsNativeIconStore
    private var systemSettingsIconObserver: NSObjectProtocol?
    private let interactiveQueue = DispatchQueue(
        label: "dev.gauravpandey.broccoli.icons.interactive",
        qos: .userInitiated,
        attributes: .concurrent
    )
    /// Background warmup is deliberately narrow. An unbounded concurrent queue spawned a
    /// worker per catalog icon, and those workers then serialized inside AppKit's shared
    /// appearance state — so the row the user was looking at waited behind the convoy.
    private let prewarmQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.gauravpandey.broccoli.icons.prewarm"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    private var prewarmOperations: [IconCacheKey: Operation] = [:]
    private var interactiveLoading: Set<IconCacheKey> = []
    private var thumbnailLoading: Set<IconCacheKey> = []
    private var prewarming: Set<IconCacheKey> = []
    private let signposter = OSSignposter(
        subsystem: "dev.gauravpandey.broccoli",
        category: "Performance"
    )
    private var applicationIconLoadSignposts: [IconCacheKey: OSSignpostIntervalState] = [:]
    private let defaultContext: IconRenderContext
    private let nativeCache = NativeIconBitmapCache(costLimit: 16 * 1_024 * 1_024)
    private let resolvesNativeSettingsIcons: Bool
    private let genericApplication = NSImage(
        systemSymbolName: "app",
        accessibilityDescription: "Application"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))
    /// Shared wait-state for uncached application and Settings artwork. This is an empty
    /// bitmap, not a template SF Symbol: selected rows would otherwise flatten `"app"` or a
    /// pane glyph into a white silhouette that never swaps.
    private let pendingNativeIcon: NSImage = {
        let size = NSSize(width: 40, height: 40)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }()

    var onIconLoaded: ((String) -> Void)?
    var onNativeIconLoaded: ((String, IconRenderContext) -> Void)?

    init(
        systemSettingsIconStore: SystemSettingsNativeIconStore = .shared,
        backingScale: CGFloat? = nil,
        startsNativeIconResolution: Bool = true,
        applicationIconOperation: ApplicationIconOperation? = nil
    ) {
        self.applicationIconOperation = applicationIconOperation
            ?? SystemSettingsNativeIconResolver.materializeIcon
        self.readsPersistedApplicationIcons = applicationIconOperation == nil
        self.systemSettingsIconStore = systemSettingsIconStore
        defaultContext = LauncherAppearanceEnvironment.current.iconContext(mode: .system, pointSize: 40, backingScale: backingScale)
        resolvesNativeSettingsIcons = startsNativeIconResolution
        cache.totalCostLimit = 16 * 1_024 * 1_024
        systemSettingsIconObserver = NotificationCenter.default.addObserver(
            forName: SystemSettingsNativeIconStore.didLoadNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let completion = (
                notification.object as? SystemSettingsNativeIconCompletionBox
            )?.completion else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      completion.storeIdentifier == ObjectIdentifier(self.systemSettingsIconStore) else { return }
                self.onIconLoaded?(completion.iconKey)
                self.onNativeIconLoaded?(completion.iconKey, completion.context)
            }
        }
        staticIcons = Self.actionIcons
    }

    deinit {
        if let systemSettingsIconObserver {
            NotificationCenter.default.removeObserver(systemSettingsIconObserver)
        }
    }

    func image(for entry: SearchEntry, context: IconRenderContext? = nil) -> NSImage {
        // Static template actions are appearance-independent and remain a minimal hot path.
        if entry.kind == .action { return staticIcons[entry.iconKey] ?? genericApplication }
        let context = context ?? defaultContext
        if entry.kind == .systemSetting {
            if let native = systemSettingsIconStore.cachedIcon(for: entry.iconKey, context: context)?.image
                ?? systemSettingsIconStore.previousIcon(for: entry.iconKey)?.image {
                return native
            }
            if resolvesNativeSettingsIcons {
                systemSettingsIconStore.ensureResolution(
                    requests: SystemSettingsIconRequestMapper.requests(for: [entry]),
                    context: context,
                    interactive: true
                )
                if let url = SystemSettingsIconRequestMapper.request(for: entry).flatMap({
                    SystemSettingsExtensionIndex.publishedURL(for: $0.bundleIdentifier)
                }), let immediate = Self.immediateWorkspaceIcon(at: url.path) {
                    return immediate
                }
            }
            return pendingNativeIcon
        }
        let key = context.cacheKey(for: entry.iconKey)
        if entry.kind == .file, let cached = cache.object(forKey: key.thumbnailKey) { return cached }
        if let cached = nativeCache.image(for: key) { return cached.image }
        switch entry.kind {
        case .application:
            if readsPersistedApplicationIcons,
               let persisted = Self.persistedIcon(
                at: URL(fileURLWithPath: entry.iconKey),
                context: context
               ) {
                _ = nativeCache.insert(persisted, for: key)
                previousNativeKeys[entry.iconKey] = key
                return persisted.image
            }
            loadApplicationIcon(path: entry.iconKey, context: context, interactive: true)
            return previousNativeKeys[entry.iconKey].flatMap { nativeCache.image(for: $0)?.image }
                ?? immediateApplicationArtwork(path: entry.iconKey)
        case .file:
            let isDirectory: Bool
            if case .file(_, let directory) = entry.target { isDirectory = directory }
            else { isDirectory = false }
            if readsPersistedApplicationIcons,
               let persisted = Self.persistedIcon(
                at: URL(fileURLWithPath: entry.iconKey),
                context: context
               ) {
                _ = nativeCache.insert(persisted, for: key)
                previousNativeKeys[entry.iconKey] = key
                return persisted.image
            }
            loadFileIcon(path: entry.iconKey, isDirectory: isDirectory, context: context)
            return immediateApplicationArtwork(path: entry.iconKey)
        case .calculator:
            return Self.templateSymbol("function", description: "Calculator")
        case .clipboard:
            return Self.templateSymbol("clipboard", description: "Clipboard")
        case .webSearch:
            return entry.iconKey == WebSearch.duckDuckGoIconKey ? Self.duckDuckGoLogo : Self.googleLogo
        case .status:
            return Self.templateSymbol(
                entry.iconKey == "status:no-results" ? "questionmark" : "magnifyingglass",
                description: entry.iconKey == "status:no-results" ? "No results" : "Status"
            )
        case .systemSetting, .action:
            return pendingNativeIcon
        }
    }

    /// The System Settings application icon that marks a Settings pane result. It uses the
    /// ordinary application-icon cache, so it is materialized once per drawing context.
    /// Returns `nil` while the pane artwork itself is still pending: a badge must never sit
    /// on an empty icon slot.
    func systemSettingsBadge(for paneIcon: NSImage, context: IconRenderContext? = nil) -> NSImage? {
        guard paneIcon !== pendingNativeIcon else { return nil }
        let badge = image(for: Self.systemSettingsApplicationEntry, context: context)
        return badge === pendingNativeIcon ? nil : badge
    }

    /// Icon-load notifications carry this key when the badge artwork arrives.
    static let systemSettingsBadgeIconKey = "/System/Applications/System Settings.app"

    private static let systemSettingsApplicationEntry = SearchEntry(
        id: systemSettingsBadgeIconKey,
        kind: .application,
        title: "System Settings",
        iconKey: systemSettingsBadgeIconKey,
        target: .application(
            path: systemSettingsBadgeIconKey,
            bundleIdentifier: "com.apple.systempreferences"
        )
    )

    private static let googleLogo = brandTile(mark: googleMark, name: "Google")
    private static let duckDuckGoLogo = brandTile(mark: duckDuckGoMark, name: "DuckDuckGo")

    /// A search mark on an application-icon tile, so the row reads like its app neighbours.
    /// The drawing handler runs in the appearance of whichever view draws it: a white tile
    /// in Light, a dark tile in Dark, with a firmer edge under Increase Contrast.
    private static func brandTile(mark: NSImage, name: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            // Measured from the system's own macOS 26 app icons: artwork fills 824 of the
            // 1,024-point grid, with a continuous corner of about a quarter of its side.
            let tileSide = rect.width * 824 / 1_024
            let tile = NSRect(
                x: rect.midX - tileSide / 2,
                y: rect.midY - tileSide / 2,
                width: tileSide,
                height: tileSide
            )
            let layer = CALayer()
            layer.frame = CGRect(origin: .zero, size: tile.size)
            layer.cornerRadius = tileSide * 0.255
            layer.cornerCurve = .continuous
            layer.backgroundColor = (isDark ? NSColor(white: 0.17, alpha: 1) : NSColor.white).cgColor
            layer.borderWidth = 1
            layer.borderColor = (isDark ? NSColor.white : NSColor.black)
                .withAlphaComponent(increasesContrast ? 0.4 : (isDark ? 0.14 : 0.1)).cgColor
            context.saveGState()
            context.translateBy(x: tile.minX, y: tile.minY)
            layer.render(in: context)
            context.restoreGState()
            // The glyph's own extent, like the marks inside system app icons.
            let markSide = tileSide * 0.6
            mark.draw(in: NSRect(
                x: rect.midX - markSide / 2,
                y: rect.midY - markSide / 2,
                width: markSide,
                height: markSide
            ))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = name
        return image
    }

    /// Google's four-color “G”, decoded by AppKit's native SVG image representation so it
    /// stays vector at every row size and backing scale. The view box is the glyph's extent.
    private static let googleMark: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="4 4 40 40">\
        <path fill="#4285F4" d="M24 20v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C41.6 35 44 29.9 44 24c0-1.3-.1-2.7-.4-4H24z"/>\
        <path fill="#34A853" d="M12.7 28.1 6.2 33.1C9.5 39.6 16.2 44 24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9z"/>\
        <path fill="#FBBC05" d="M6.2 14.7C4.8 17.5 4 20.6 4 24s.8 6.5 2.2 9.1l6.5-5c-.4-1.3-.7-2.6-.7-4.1s.3-2.8.7-4.1l-6.5-5.2z"/>\
        <path fill="#EA4335" d="M24 12c3.1 0 5.8 1.2 8 3l5.6-5.7C34 6.1 29.3 4 24 4 16.2 4 9.5 8.4 6.2 14.7l6.5 5.2C14.4 15.3 18.8 12 24 12z"/>\
        </svg>
        """
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 40, height: 40))
        image.isTemplate = false
        image.accessibilityDescription = "Google"
        return image
    }()

    /// DuckDuckGo's orange duck, decoded by AppKit's native SVG image representation.
    private static let duckDuckGoMark: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="4 10 40 28">\
        <path fill="#DE5833" d="M14 30c0-6 6-11 14-11 1.4 0 2.8.2 4 .6C31 15 34 12 38 12c3.2 0 5 2.2 5 5 0 1.2-.4 2.2-1.1 3 2.6 1.6 4.1 4.4 4.1 7.6C46 33 41.5 37 35 37H22c-5 0-8-3-8-7z"/>\
        <circle fill="#fff" cx="37.2" cy="16.2" r="1.3"/>\
        <path fill="#F6A15A" d="M42 16.5l6 1.2-6 2.2z"/>\
        </svg>
        """
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 40, height: 28))
        image.isTemplate = false
        image.accessibilityDescription = "DuckDuckGo"
        return image
    }()

    func prewarm(
        _ entries: [SearchEntry],
        limit: Int = 16,
        context: IconRenderContext? = nil,
        resolveNativeSettings: Bool = true,
        interactiveSettings: Bool = false
    ) {
        let context = context ?? defaultContext
        let settings = entries.filter { $0.kind == .systemSetting }
        if !settings.isEmpty {
            if resolvesNativeSettingsIcons, resolveNativeSettings {
                systemSettingsIconStore.ensureResolution(
                    requests: SystemSettingsIconRequestMapper.requests(for: settings),
                    context: context,
                    interactive: interactiveSettings
                )
            }
        }
        let prioritized = entries.filter { $0.kind == .application }
            .sorted { $0.isRunning && !$1.isRunning }
        for entry in prioritized.prefix(limit) {
            guard nativeCache.image(for: context.cacheKey(for: entry.iconKey)) == nil else { continue }
            loadApplicationIcon(path: entry.iconKey, context: context, interactive: false)
        }
    }

    /// Coalesce presentation/activation bursts. Keep cached artwork visible while native
    /// sources are sampled again, without polling or consulting private appearance settings.
    func refreshNativeIcons(_ entries: [SearchEntry], context: IconRenderContext) {
        for entry in entries where entry.kind == .application || entry.kind == .systemSetting {
            refreshEntries[context, default: [:]][entry.iconKey] = entry
        }
        guard pendingRefresh == nil, !refreshEntries.isEmpty else { return }
        pendingRefresh = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            let batches = refreshEntries
            refreshEntries.removeAll(keepingCapacity: true)
            pendingRefresh = nil
            for (context, entriesByKey) in batches {
                let entries = Array(entriesByKey.values)
                if resolvesNativeSettingsIcons {
                    systemSettingsIconStore.ensureResolution(
                        requests: SystemSettingsIconRequestMapper.requests(for: entries),
                        context: context, refresh: true)
                }
                for entry in entries where entry.kind == .application {
                    loadApplicationIcon(
                        path: entry.iconKey,
                        context: context,
                        interactive: false,
                        replaceExisting: true
                    )
                }
            }
        }
    }

    // Action templates have no appearance-dependent pixels. Share these immutable canvases
    // across the live launcher and previews instead of rasterizing them for every IconCache.
    private static let actionIcons: [String: NSImage] = {
        var icons: [String: NSImage] = [:]
        for entry in ActionRegistry.searchEntries {
            icons[entry.iconKey] = actionTemplateIcon(
                symbolCandidates: NativeIconCatalog.actionSymbols(for: entry),
                accessibilityDescription: entry.title)
        }
        return icons
    }()

    /// Resolves symbols in semantic order so OS-version availability never produces a blank
    /// badge. Kept internal to make the availability behavior directly testable.
    static func resolvedSystemSymbol(
        preferred: String,
        semanticFallbacks: [String]
    ) -> NSImage? {
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: 25, weight: .medium)
        let paletteConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
        var visited = Set<String>()
        for name in [preferred] + semanticFallbacks where visited.insert(name).inserted {
            guard let configured = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(baseConfiguration.applying(paletteConfiguration)) else {
                continue
            }
            configured.isTemplate = false
            return configured
        }
        return nil
    }

    /// Produces the same kind of monochrome template image used by native AppKit controls.
    /// The transparent 40-point canvas keeps every action aligned with application and Settings
    /// icons without drawing a Broccoli-owned tile, border, palette, or background.
    static func actionTemplateIcon(
        symbolCandidates: [String],
        accessibilityDescription: String?
    ) -> NSImage {
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        var visited = Set<String>()
        var symbol: NSImage?
        for name in symbolCandidates + ["bolt", "questionmark"] where visited.insert(name).inserted {
            guard let image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: accessibilityDescription
            )?.withSymbolConfiguration(baseConfiguration) else { continue }
            image.isTemplate = true
            symbol = image
            break
        }

        let canvas = NSImage(size: NSSize(width: 40, height: 40))
        if let symbol {
            canvas.lockFocus()
            symbol.draw(
                in: aspectFitRect(
                    imageSize: symbol.size,
                    boundingRect: NSRect(x: 7, y: 7, width: 26, height: 26)
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            canvas.unlockFocus()
        }
        canvas.isTemplate = true
        return canvas
    }

    static func boundedImageCost(_ image: NSImage) -> Int {
        let representationCost = image.representations.reduce(0) { current, representation in
            let width = max(0, representation.pixelsWide)
            let height = max(0, representation.pixelsHigh)
            return current + width * height * 4
        }
        return max(representationCost, Int(image.size.width * image.size.height * 4))
    }

    private static func aspectFitRect(imageSize: NSSize, boundingRect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return boundingRect }
        let scale = min(
            boundingRect.width / imageSize.width,
            boundingRect.height / imageSize.height
        )
        let fitted = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: boundingRect.midX - fitted.width / 2,
            y: boundingRect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// `loadApplicationIcon` stores bitmaps under the resolved path. Catalog `iconKey`s
    /// are often the unresolved `/Applications` location, so look up both.
    private static func persistedIcon(
        at url: URL,
        context: IconRenderContext
    ) -> MaterializedSystemSettingsIcon? {
        var seen = Set<String>()
        for candidate in [url, url.resolvingSymlinksInPath()] {
            let path = candidate.standardizedFileURL.path
            guard seen.insert(path).inserted,
                  let diskKey = NativeIconDiskCache.key(forFileAt: candidate, context: context),
                  let icon = NativeIconDiskCache.shared.icon(
                    for: diskKey,
                    pointSize: context.pointSize
                  ) else { continue }
            return icon
        }
        return nil
    }

    private static func templateSymbol(_ name: String, description: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(size: NSSize(width: 40, height: 40))
        image.isTemplate = true
        return image
    }

    /// Apple's current file icon, not an SF Symbol or Broccoli tile. Used only while the
    /// materialized bitmap is still in flight so a disk miss cannot leave a hole.
    private static func immediateWorkspaceIcon(at path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path),
              let icon = NSWorkspace.shared.icon(forFile: path).copy() as? NSImage else {
            return nil
        }
        icon.isTemplate = false
        return icon
    }

    private func immediateApplicationArtwork(path: String) -> NSImage {
        if let icon = Self.immediateWorkspaceIcon(at: path) { return icon }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path, let icon = Self.immediateWorkspaceIcon(at: resolved) { return icon }
        return pendingNativeIcon
    }

    private func loadApplicationIcon(
        path: String,
        context: IconRenderContext,
        interactive: Bool,
        replaceExisting: Bool = false
    ) {
        let key = context.cacheKey(for: path)
        guard !path.isEmpty else { return }
        if interactive {
            guard !interactiveLoading.contains(key) else { return }
            // A warmup for this exact artwork that has not started yet is promoted rather
            // than duplicated: materializing the same icon twice is what made visible rows
            // compete with the catalog they were already waiting on. A warmup that is
            // already executing still justifies a second load, because a visible row cannot
            // wait for a call that has begun.
            if let queued = prewarmOperations[key], !queued.isExecuting, !queued.isFinished {
                queued.queuePriority = .veryHigh
                queued.qualityOfService = .userInitiated
                return
            }
            interactiveLoading.insert(key)
        } else {
            guard !interactiveLoading.contains(key), !prewarming.contains(key) else { return }
            prewarming.insert(key)
        }
        beginApplicationIconLoadSignpost(for: key, path: path)
        let operation = applicationIconOperation
        let work: @Sendable () -> Void = { [weak self] in
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let icon = operation(url, context)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if interactive {
                    self.interactiveLoading.remove(key)
                } else {
                    self.prewarming.remove(key)
                    self.prewarmOperations.removeValue(forKey: key)
                }
                self.publishApplicationIcon(
                    icon,
                    path: path,
                    key: key,
                    context: context,
                    replaceExisting: replaceExisting
                )
            }
        }
        if interactive {
            interactiveQueue.async(execute: work)
        } else {
            let queued = BlockOperation(block: work)
            prewarmOperations[key] = queued
            prewarmQueue.addOperation(queued)
        }
    }

    /// Re-resolves only artwork Icon Services answered with its generic placeholder.
    /// Fully resolved icons are never re-materialized, so presenting the launcher costs
    /// nothing when the drawing context has not changed.
    func refreshProvisionalIcons(_ entries: [SearchEntry], context: IconRenderContext) {
        for entry in entries where entry.kind == .application {
            let key = context.cacheKey(for: entry.iconKey)
            guard let cached = nativeCache.image(for: key), cached.isProvisional else { continue }
            loadApplicationIcon(
                path: entry.iconKey,
                context: context,
                interactive: true,
                replaceExisting: true
            )
        }
    }

    /// Visible rows may start an interactive load while prewarm is already in flight.
    /// The first successful insert wins so the two completions cannot double-notify.
    private func publishApplicationIcon(
        _ icon: MaterializedSystemSettingsIcon?,
        path: String,
        key: IconCacheKey,
        context: IconRenderContext,
        replaceExisting: Bool
    ) {
        let stillInFlight = interactiveLoading.contains(key) || prewarming.contains(key)
        // Never let a retry that came back generic overwrite artwork already resolved.
        if let icon, icon.isProvisional, nativeCache.image(for: key)?.isProvisional == false {
            if !stillInFlight { endApplicationIconLoadSignpost(for: key) }
            return
        }
        if let icon, replaceExisting || nativeCache.image(for: key) == nil {
            if nativeCache.insert(icon, for: key) {
                if previousNativeKeys.count >= 512 { previousNativeKeys.removeAll(keepingCapacity: true) }
                previousNativeKeys[path] = key
                onIconLoaded?(path)
                onNativeIconLoaded?(path, context)
                endApplicationIconLoadSignpost(for: key)
                return
            }
        }
        if !stillInFlight {
            endApplicationIconLoadSignpost(for: key)
        }
    }

    private func beginApplicationIconLoadSignpost(for key: IconCacheKey, path: String) {
        guard applicationIconLoadSignposts[key] == nil else { return }
        applicationIconLoadSignposts[key] = signposter.beginInterval("ApplicationIconLoad", "\(path)")
    }

    private func endApplicationIconLoadSignpost(for key: IconCacheKey) {
        guard let state = applicationIconLoadSignposts.removeValue(forKey: key) else { return }
        signposter.endInterval("ApplicationIconLoad", state)
    }

    private func loadFileIcon(path: String, isDirectory: Bool, context: IconRenderContext) {
        let key = context.cacheKey(for: path)
        guard !path.isEmpty, !interactiveLoading.contains(key), !thumbnailLoading.contains(key) else { return }
        interactiveLoading.insert(key)
        interactiveQueue.async { [weak self] in
            let icon = SystemSettingsNativeIconResolver.materializeIcon(at: URL(fileURLWithPath: path), context: context)
            Task { @MainActor [weak self] in
                guard let self else { return }
                interactiveLoading.remove(key)
                if let icon {
                    nativeCache.insert(icon, for: key)
                    onIconLoaded?(path)
                }
                if !isDirectory { loadFileThumbnail(path: path, context: context) }
            }
        }
    }

    private func loadFileThumbnail(path: String, context: IconRenderContext) {
        let key = context.cacheKey(for: path)
        guard !path.isEmpty, !thumbnailLoading.contains(key) else { return }
        thumbnailLoading.insert(key)
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: NSSize(width: 128, height: 128),
            scale: context.backingScale,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else {
                Task { @MainActor [weak self] in self?.thumbnailLoading.remove(key) }
                return
            }
            let image = representation.nsImage
            image.isTemplate = false
            let box = SendableImage(image)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cache.setObject(box.image, forKey: key.thumbnailKey, cost: Self.boundedImageCost(box.image))
                self.thumbnailLoading.remove(key)
                self.onIconLoaded?(path)
            }
        }
    }
}
