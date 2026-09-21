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
    private let genericFile = NSImage(
        systemSymbolName: "doc",
        accessibilityDescription: "File"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))
    private let genericFolder = NSImage(
        systemSymbolName: "folder.fill",
        accessibilityDescription: "Folder"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))

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
                ?? pendingNativeIcon
        case .file:
            let isDirectory: Bool
            if case .file(_, let directory) = entry.target { isDirectory = directory }
            else { isDirectory = false }
            loadFileIcon(path: entry.iconKey, isDirectory: isDirectory, context: context)
            return isDirectory ? genericFolder : genericFile
        case .calculator:
            return NSImage(systemSymbolName: "function", accessibilityDescription: "Calculator") ?? genericApplication
        case .clipboard:
            return NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard") ?? genericApplication
        case .status:
            return NSImage(systemSymbolName: entry.iconKey == "status:no-results" ? "questionmark" : "magnifyingglass",
                accessibilityDescription: entry.iconKey == "status:no-results" ? "No results" : "Status") ?? genericApplication
        case .systemSetting, .action:
            return pendingNativeIcon
        }
    }

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

    private static func persistedIcon(
        at url: URL,
        context: IconRenderContext
    ) -> MaterializedSystemSettingsIcon? {
        guard let diskKey = NativeIconDiskCache.key(forFileAt: url, context: context) else { return nil }
        return NativeIconDiskCache.shared.icon(for: diskKey, pointSize: context.pointSize)
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
            let box = SendableImage(representation.nsImage)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cache.setObject(box.image, forKey: key.thumbnailKey, cost: Self.boundedImageCost(box.image))
                self.thumbnailLoading.remove(key)
                self.onIconLoaded?(path)
            }
        }
    }
}
