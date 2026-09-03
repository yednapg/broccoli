@preconcurrency import AppKit
import Combine
import BroccoliCore
import Foundation

enum LauncherPreviewResolvedAppearance: String, Equatable, Hashable, Sendable {
    case light
    case dark
}

/// The resolved system state which changes how a launcher surface is rendered.
///
/// Keeping this state in the cache key prevents a glass screenshot from being reused after
/// Reduce Transparency or Increase Contrast changes. The renderer intentionally does not add
/// result-count or feature preferences to the key: its screenshot fixture is fixed so every
/// design is compared using the same content and geometry.
struct LauncherPreviewEnvironment: Equatable, Hashable, Sendable {
    let reducesTransparency: Bool
    let increasesContrast: Bool
    let resolvedAppearance: LauncherPreviewResolvedAppearance

    init(
        reducesTransparency: Bool,
        increasesContrast: Bool,
        resolvedAppearance: LauncherPreviewResolvedAppearance = .light
    ) {
        self.reducesTransparency = reducesTransparency
        self.increasesContrast = increasesContrast
        self.resolvedAppearance = resolvedAppearance
    }

    @MainActor
    static var current: Self {
        Self(
            reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            resolvedAppearance: NSApp.effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua ? .dark : .light
        )
    }
}

struct LauncherPreviewCacheKey: Equatable, Hashable, Sendable {
    let design: LauncherDesign
    let appearance: LauncherAppearanceMode
    let reducesTransparency: Bool
    let increasesContrast: Bool
    let resolvedSystemAppearance: LauncherPreviewResolvedAppearance?

    init(
        design: LauncherDesign,
        appearance: LauncherAppearanceMode,
        environment: LauncherPreviewEnvironment
    ) {
        self.design = design
        self.appearance = appearance
        reducesTransparency = environment.reducesTransparency
        increasesContrast = environment.increasesContrast
        resolvedSystemAppearance = appearance == .system ? environment.resolvedAppearance : nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.design.rawValue == rhs.design.rawValue
            && lhs.appearance.rawValue == rhs.appearance.rawValue
            && lhs.reducesTransparency == rhs.reducesTransparency
            && lhs.increasesContrast == rhs.increasesContrast
            && lhs.resolvedSystemAppearance == rhs.resolvedSystemAppearance
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(design.rawValue)
        hasher.combine(appearance.rawValue)
        hasher.combine(reducesTransparency)
        hasher.combine(increasesContrast)
        hasher.combine(resolvedSystemAppearance)
    }
}

struct LauncherPreviewRenderIdentity: Equatable, Hashable, Sendable {
    let cacheKey: LauncherPreviewCacheKey
    let environmentRevision: UInt64
}

enum LauncherPreviewEnvironmentChange {
    case systemAppearance
    case accessibility
}

/// Layout measurements captured from the actual preview view hierarchy after AppKit has
/// completed layout. Keeping this tiny diagnostic alongside the renderer makes it possible to
/// prove that screenshot previews use the same exact-height viewport contract as the launcher.
struct LauncherPreviewRenderMetrics: Equatable {
    let resultsViewportHeight: CGFloat
    let resultsDocumentHeight: CGFloat
}

/// A stable search scene used for every Appearance screenshot.
///
/// These are real `SearchEntry`/`RankedResult` values and use the same application, setting,
/// and action icon paths as the live launcher. They are never passed to a coordinator, action
/// executor, or usage store, so a preview cannot launch anything or affect learned ranking.
struct LauncherPreviewFixture: Sendable {
    let query: String
    let results: [RankedResult]

    static let standard: Self = {
        let screenSharingPath = "/System/Applications/Utilities/Screen Sharing.app"
        let application = SearchEntry(
            id: "preview:application:screen-sharing",
            kind: .application,
            title: "Screen Sharing",
            subtitle: "Application",
            keywords: ["remote desktop", "vnc"],
            iconKey: screenSharingPath,
            target: .application(
                path: screenSharingPath,
                bundleIdentifier: "com.apple.ScreenSharing"
            )
        )
        let screenSaverBundleIdentifier = "com.apple.ScreenSaver-Settings.extension"
        let setting = SearchEntry(
            id: "setting:\(screenSaverBundleIdentifier)",
            kind: .systemSetting,
            title: "Screen Saver",
            subtitle: "System Settings → Screen Saver",
            keywords: ["screensaver", "idle"],
            iconKey: "setting:\(screenSaverBundleIdentifier)",
            target: .setting(
                route: "x-apple.systempreferences:\(screenSaverBundleIdentifier)"
            )
        )
        let action = ActionRegistry.definition(id: "screensaver.start")!.searchEntry

        return Self(
            query: "screen",
            results: [
                RankedResult(entry: application, score: 800),
                RankedResult(entry: setting, score: 650),
                RankedResult(entry: action, score: 650),
            ]
        )
    }()
}

enum LauncherPreviewInteraction {
    static func results(
        matching query: String,
        in fixture: LauncherPreviewFixture
    ) -> [RankedResult] {
        let normalized = SearchNormalizer.normalize(query)
        guard !normalized.isEmpty else { return fixture.results }
        return fixture.results.filter { result in
            let entry = result.entry
            return entry.normalizedTitle.contains(normalized)
                || SearchNormalizer.normalize(entry.subtitle).contains(normalized)
                || entry.keywords.contains(where: { $0.contains(normalized) })
        }
    }

    static func nextRow(current: Int, movingUp: Bool, resultCount: Int) -> Int? {
        guard resultCount > 0 else { return nil }
        if current < 0 { return movingUp ? resultCount - 1 : 0 }
        let candidate = current + (movingUp ? -1 : 1)
        return (0..<resultCount).contains(candidate) ? candidate : nil
    }
}

@MainActor
struct LauncherInteractivePreviewConfiguration {
    let identity: LauncherPreviewRenderIdentity
    let preferences: LauncherAppearancePreferences
    let descriptor: LauncherThemeDescriptor
    let fixture: LauncherPreviewFixture
}

/// Produces screenshot-style Appearance previews from production launcher descriptors.
///
/// The renderer is deliberately active only for the lifetime of an open Settings window.
/// Call `beginSettingsSession()` when Settings opens and `endSettingsSession()` when it closes.
/// `image(for:)` yields before an uncached render so a SwiftUI `.task` can display its placeholder
/// without blocking construction of the settings page.
@MainActor
final class LauncherPreviewRenderer: ObservableObject {
    typealias EnvironmentProvider = @MainActor () -> LauncherPreviewEnvironment

    private struct CachedImage {
        let image: NSImage
        let cost: Int
        var access: UInt64
    }

    private let fixture: LauncherPreviewFixture
    private let themeController: LauncherThemeController
    private let iconProvider: LauncherPreviewIconProvider
    private let environmentProvider: EnvironmentProvider
    private let cacheCostLimit: Int
    private var cache: [LauncherPreviewCacheKey: CachedImage] = [:]
    private var cacheCost = 0
    private var accessCounter: UInt64 = 0
    private var sessionGeneration: UInt64 = 0
    private var sampledEnvironment: LauncherPreviewEnvironment?
    private var workspaceObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private(set) var isSettingsSessionActive = false
    @Published private(set) var environmentRevision: UInt64 = 0
    private(set) var lastRenderMetrics: LauncherPreviewRenderMetrics?
    private(set) var lastRenderedSurface: LauncherThemeDescriptor.Surface?

    init(
        fixture: LauncherPreviewFixture = .standard,
        themeController: LauncherThemeController = LauncherThemeController(),
        cacheCostLimit: Int = 16 * 1_024 * 1_024,
        environmentProvider: @escaping EnvironmentProvider = { .current }
    ) {
        self.fixture = fixture
        self.themeController = themeController
        self.cacheCostLimit = max(1, cacheCostLimit)
        self.environmentProvider = environmentProvider
        let iconProvider = LauncherPreviewIconProvider()
        self.iconProvider = iconProvider
        iconProvider.onIconLoaded = { [weak self] iconKey in
            self?.nativePaneIconDidLoad(iconKey)
        }
    }

    func beginSettingsSession() {
        guard !isSettingsSessionActive else { return }
        sessionGeneration &+= 1
        sampledEnvironment = environmentProvider()
        isSettingsSessionActive = true
        startEnvironmentObservation()
    }

    func endSettingsSession() {
        guard isSettingsSessionActive || !cache.isEmpty else { return }
        sessionGeneration &+= 1
        isSettingsSessionActive = false
        stopEnvironmentObservation()
        sampledEnvironment = nil
        cache.removeAll(keepingCapacity: false)
        cacheCost = 0
        lastRenderMetrics = nil
        lastRenderedSurface = nil
    }

    /// Returns an existing image without initiating capture. Useful for SwiftUI's synchronous
    /// update pass before it starts an asynchronous render task.
    func cachedImage(for preferences: LauncherAppearancePreferences) -> NSImage? {
        guard isSettingsSessionActive else { return nil }
        let key = cacheKey(for: preferences)
        return cachedImage(for: key)
    }

    private func cachedImage(for key: LauncherPreviewCacheKey) -> NSImage? {
        guard var cached = cache[key] else { return nil }
        cached.access = nextAccess()
        cache[key] = cached
        return cached.image
    }

    func image(for preferences: LauncherAppearancePreferences) async -> NSImage? {
        guard isSettingsSessionActive, !Task.isCancelled else { return nil }
        let initialKey = cacheKey(for: preferences)
        if let image = cachedImage(for: initialKey) { return image }

        let generation = sessionGeneration
        let renderRevision = environmentRevision
        await Task.yield()
        guard isSettingsSessionActive,
              generation == sessionGeneration,
              renderRevision == environmentRevision,
              !Task.isCancelled else { return nil }

        // Read the accessibility environment exactly once for both the cache key and theme
        // descriptor. If Reduce Transparency changes between those two operations, a glass
        // image must never be filed under an opaque-image key (or vice versa).
        let environment = environmentProvider()
        let key = LauncherPreviewCacheKey(
            design: preferences.design,
            appearance: preferences.mode,
            environment: environment
        )
        if let image = cachedImage(for: key) { return image }

        let canonicalPreferences = Self.canonicalPreferences(from: preferences)
        let descriptor = themeController.descriptor(
            for: canonicalPreferences,
            reducedTransparency: environment.reducesTransparency,
            increasedContrast: environment.increasesContrast,
            resolvedSystemDark: environment.resolvedAppearance == .dark
        )
        let content = LauncherPreviewContentView(
            descriptor: descriptor,
            fixture: fixture,
            iconProvider: iconProvider
        )
        let image = Self.capture(content, descriptor: descriptor)
        guard isSettingsSessionActive,
              generation == sessionGeneration,
              renderRevision == environmentRevision,
              !Task.isCancelled else { return nil }
        lastRenderMetrics = content.renderMetrics
        lastRenderedSurface = descriptor.surface

        let cost = Self.imageCost(image)
        insert(image, for: key, cost: cost)
        return image
    }

    func invalidate(_ key: LauncherPreviewCacheKey) {
        guard let removed = cache.removeValue(forKey: key) else { return }
        cacheCost -= removed.cost
    }

    func invalidate(design: LauncherDesign, appearance: LauncherAppearanceMode? = nil) {
        let keys = cache.keys.filter { key in
            key.design.rawValue == design.rawValue
                && appearance.map { $0.rawValue == key.appearance.rawValue } != false
        }
        for key in keys { invalidate(key) }
    }

    func cacheKey(for preferences: LauncherAppearancePreferences) -> LauncherPreviewCacheKey {
        LauncherPreviewCacheKey(
            design: preferences.design,
            appearance: preferences.mode,
            environment: environmentProvider()
        )
    }

    func renderIdentity(
        for preferences: LauncherAppearancePreferences
    ) -> LauncherPreviewRenderIdentity {
        LauncherPreviewRenderIdentity(
            cacheKey: cacheKey(for: preferences),
            environmentRevision: environmentRevision
        )
    }

    func interactiveConfiguration(
        for preferences: LauncherAppearancePreferences
    ) -> LauncherInteractivePreviewConfiguration {
        let environment = environmentProvider()
        let key = LauncherPreviewCacheKey(
            design: preferences.design,
            appearance: preferences.mode,
            environment: environment
        )
        var previewPreferences = preferences
        previewPreferences.visibleResultCount = fixture.results.count
        let descriptor = themeController.descriptor(
            for: previewPreferences,
            reducedTransparency: environment.reducesTransparency,
            increasedContrast: environment.increasesContrast,
            resolvedSystemDark: environment.resolvedAppearance == .dark
        )
        return LauncherInteractivePreviewConfiguration(
            identity: LauncherPreviewRenderIdentity(
                cacheKey: key,
                environmentRevision: environmentRevision
            ),
            preferences: previewPreferences,
            descriptor: descriptor,
            fixture: fixture
        )
    }

    /// Re-samples the system state and invalidates only screenshots which could have changed.
    /// This is internal so deterministic tests can drive the same path with an injected
    /// environment provider; production calls come only from Settings-session observers.
    func refreshEnvironment(_ reason: LauncherPreviewEnvironmentChange) {
        guard isSettingsSessionActive else { return }
        let next = environmentProvider()
        guard sampledEnvironment != next else { return }
        sampledEnvironment = next

        let keysToInvalidate: [LauncherPreviewCacheKey] = switch reason {
        case .systemAppearance:
            cache.keys.filter { $0.appearance == .system }
        case .accessibility:
            Array(cache.keys)
        }
        for key in keysToInvalidate { invalidate(key) }
        environmentRevision &+= 1
    }

    var cachedImageCount: Int { cache.count }
    var cachedImageCost: Int { cacheCost }

    func nativePaneIconDidLoad(_ iconKey: String) {
        guard isSettingsSessionActive,
              fixture.results.contains(where: { $0.entry.iconKey == iconKey }) else { return }
        for key in Array(cache.keys) { invalidate(key) }
        // Published revision restarts ThemeCard tasks, while the revision guard above prevents
        // a capture already in flight from committing a fallback-icon screenshot afterward.
        environmentRevision &+= 1
    }

    private func startEnvironmentObservation() {
        guard workspaceObserver == nil, appearanceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnvironment(.accessibility) }
        }
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The distributed notification can precede NSApp's effective-appearance update by
            // one turn. Sample after yielding so the new resolved System mode reaches task IDs.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.refreshEnvironment(.systemAppearance)
            }
        }
    }

    private func stopEnvironmentObservation() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
            self.appearanceObserver = nil
        }
    }

    private static func canonicalPreferences(
        from preferences: LauncherAppearancePreferences
    ) -> LauncherAppearancePreferences {
        var canonical = LauncherAppearancePreferences.defaults(design: preferences.design)
        canonical.mode = preferences.mode
        canonical.visibleResultCount = 3
        canonical.showsSubtitles = true
        canonical.showsShortcuts = true
        return canonical
    }

    private func insert(_ image: NSImage, for key: LauncherPreviewCacheKey, cost: Int) {
        if let old = cache.removeValue(forKey: key) { cacheCost -= old.cost }
        cache[key] = CachedImage(image: image, cost: cost, access: nextAccess())
        cacheCost += cost

        while cacheCost > cacheCostLimit, cache.count > 1,
              let oldest = cache.min(by: { $0.value.access < $1.value.access }) {
            invalidate(oldest.key)
        }
    }

    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

    private static func capture(
        _ view: LauncherPreviewContentView,
        descriptor: LauncherThemeDescriptor
    ) -> NSImage {
        let size = view.frame.size
        // Do not attach the snapshot tree to a temporary NSWindow. NSVisualEffectView and
        // NSGlassEffectView keep display-cycle state tied to their window; destroying an
        // offscreen window immediately after `cacheDisplay` can leave AppKit with a dangling
        // appearance coordinator. An active effect view can render safely in this detached,
        // layer-backed tree, which also guarantees the capture never flashes onscreen.
        view.appearance = descriptor.appearance ?? NSApp.effectiveAppearance
        view.prepareForCapture()
        view.displayIfNeeded()

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelsWide = max(1, Int(ceil(size.width * scale)))
        let pixelsHigh = max(1, Int(ceil(size.height * scale)))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func imageCost(_ image: NSImage) -> Int {
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first
        else { return Int(image.size.width * image.size.height * 4) }
        return bitmap.pixelsWide * bitmap.pixelsHigh * 4
    }
}

@MainActor
final class LauncherPreviewIconProvider {
    private let productionIconCache = IconCache()
    private var applicationIcons: [String: NSImage] = [:]
    private let genericApplication = NSImage(
        systemSymbolName: "app",
        accessibilityDescription: "Application"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))

    var onIconLoaded: ((String) -> Void)? {
        didSet {
            productionIconCache.onIconLoaded = { [weak self] iconKey in
                self?.onIconLoaded?(iconKey)
            }
        }
    }

    func image(for entry: SearchEntry) -> NSImage {
        guard case .application(let path, _) = entry.target else {
            return productionIconCache.image(for: entry)
        }
        if let cached = applicationIcons[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return genericApplication }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 40, height: 40)
        applicationIcons[path] = image
        return image
    }
}

/// Descriptor-backed launcher content shared by screenshot and interactive Settings previews.
/// It reuses the production `ResultRowView`, while intentionally not embedding the permanent
/// `LauncherPanelController`: sharing that panel would couple Settings focus and fixture input
/// to the latency-sensitive global hotkey window and its execution callbacks.
@MainActor
final class LauncherPreviewContentView: NSView,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSTextFieldDelegate
{
    private let descriptor: LauncherThemeDescriptor
    private let fixture: LauncherPreviewFixture
    private let iconProvider: LauncherPreviewIconProvider
    private let isInteractive: Bool
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField: NSTextField
    private let liquidGlassSurface = LauncherLiquidGlassSurfaceView(interactive: false)
    private let headerSeparator = LauncherHeaderSeparatorView()
    private let preparedRows: [ResultRowView]
    private var displayedResults: [RankedResult]
    private var selectedRow = 0

    init(
        descriptor: LauncherThemeDescriptor,
        fixture: LauncherPreviewFixture,
        iconProvider: LauncherPreviewIconProvider,
        interactive: Bool = false
    ) {
        self.descriptor = descriptor
        self.fixture = fixture
        self.iconProvider = iconProvider
        isInteractive = interactive
        searchField = LauncherNativeSearchField()
        displayedResults = fixture.results
        preparedRows = fixture.results.map { _ in ResultRowView() }
        let size = NSSize(
            width: descriptor.width,
            height: descriptor.panelHeight(resultCount: fixture.results.count)
        )
        super.init(frame: NSRect(origin: .zero, size: size))
        autoresizingMask = []
        buildSurface()
    }

    required init?(coder: NSCoder) { nil }

    func prepareForCapture() {
        needsUpdateConstraints = true
        updateConstraintsForSubtreeIfNeeded()
        needsLayout = true
        layoutSubtreeIfNeeded()
        layoutTableDocument()
        tableView.needsLayout = true
        tableView.layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        layoutTableDocument()
    }

    var renderMetrics: LauncherPreviewRenderMetrics {
        let documentHeight: CGFloat
        if displayedResults.isEmpty {
            documentHeight = 0
        } else {
            documentHeight = tableView.rect(ofRow: displayedResults.count - 1).maxY
        }
        return LauncherPreviewRenderMetrics(
            resultsViewportHeight: scrollView.frame.height,
            resultsDocumentHeight: documentHeight
        )
    }

    var interactiveQuery: String { searchField.stringValue }
    var selectedResultID: String? {
        displayedResults.indices.contains(selectedRow) ? displayedResults[selectedRow].entry.id : nil
    }
    var displayedResultIDs: [String] { displayedResults.map(\.entry.id) }
    var tableDocumentFrame: NSRect { tableView.frame }
    var previewSearchField: NSTextField { searchField }

    func setInteractiveQuery(_ query: String) {
        guard isInteractive else { return }
        searchField.stringValue = query
        updateInteractiveResults()
    }

    @discardableResult
    func moveInteractiveSelection(up: Bool) -> Bool {
        guard isInteractive,
              let next = LauncherPreviewInteraction.nextRow(
                current: selectedRow,
                movingUp: up,
                resultCount: displayedResults.count
              ) else { return false }
        selectedRow = next
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        refreshRows()
        updateHeaderSeparatorVisibility()
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedResults.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard displayedResults.indices.contains(row), preparedRows.indices.contains(row) else {
            return nil
        }
        let view = preparedRows[row]
        let result = displayedResults[row]
        view.configure(
            result: result,
            icon: iconProvider.image(for: result.entry),
            confirmation: false,
            row: row,
            selected: row == selectedRow,
            theme: descriptor
        )
        return view
    }

    private func buildSurface() {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        // Screenshot and Settings previews are intentionally detached from a window. Preserve
        // the production surface size explicitly so AppKit cannot collapse the preview to the
        // native search field's fitting height before the surface gets its first layout pass.
        // These preview-only axes do not participate in the live panel's glass hierarchy.
        content.widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        content.heightAnchor.constraint(equalToConstant: frame.height).isActive = true

        let surface: NSView
        let surfaceManagesContent: Bool
        switch descriptor.surface {
        case .glass:
            if #available(macOS 26, *) {
                liquidGlassSurface.frame = bounds
                liquidGlassSurface.configure(
                    isDark: descriptor.isDark,
                    tintColor: descriptor.glassTintColor
                )
                liquidGlassSurface.layoutSubtreeIfNeeded()
                liquidGlassSurface.setContentView(content)
                surface = liquidGlassSurface
                surfaceManagesContent = true
            } else {
                let fallback = NSView()
                surface = fallback
                surfaceManagesContent = false
            }
        case .ultraThick:
            let material = LauncherMinimalMaterialSurfaceView(
                frame: bounds,
                isDark: descriptor.isDark
            )
            material.setContentView(content)
            surface = material
            surfaceManagesContent = true
        case .vibrancy:
            let effect = NSVisualEffectView()
            // This renderer is deliberately detached from a window, so it has no background
            // window for `.behindWindow` to sample. Use the same native material with local
            // compositing; the explicit production-height constraint below owns geometry.
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.material = .underWindowBackground
            surface = effect
            surfaceManagesContent = false
        case .opaque:
            let backdrop = NSView()
            surface = backdrop
            surfaceManagesContent = false
        }

        surface.frame = bounds
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        if descriptor.surface != .glass, descriptor.surface != .ultraThick {
            surface.wantsLayer = true
            surface.layer?.backgroundColor = descriptor.surface == .opaque
                ? descriptor.backgroundColor.cgColor
                : nil
            surface.layer?.cornerRadius = descriptor.surfaceCornerRadius(
                panelHeight: bounds.height
            )
            surface.layer?.cornerCurve = descriptor.design == .minimal ? .circular : .continuous
            surface.layer?.borderWidth = 0
            surface.layer?.borderColor = nil
            surface.layer?.masksToBounds = true
        }
        if !surfaceManagesContent {
            // Establish the detached root's production frame before adding constrained
            // descendants. Installing `content` with edge constraints while an
            // NSVisualEffectView still has its default zero frame makes that effect adopt its
            // 68-point fitting height; unlike the live panel, there is no window display cycle
            // to expand it afterward.
            content.translatesAutoresizingMaskIntoConstraints = true
            content.frame = surface.bounds
            content.autoresizingMask = [.width, .height]
            surface.addSubview(content)
        }
        addSubview(surface)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.stringValue = fixture.query
        searchField.backgroundColor = .clear
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.usesSingleLineMode = true
        searchField.focusRingType = isInteractive ? .default : .none
        if let nativeSearchField = searchField as? NSSearchField {
            LauncherNativeSearchFieldStyle.apply(
                to: nativeSearchField,
                metrics: descriptor.searchMetrics,
                iconColor: descriptor.searchIconColor
            )
            nativeSearchField.stringValue = fixture.query
        } else {
            searchField.font = .systemFont(ofSize: descriptor.searchFontSize, weight: .regular)
        }
        searchField.textColor = descriptor.searchTextColor
        // LauncherNativeSearchFieldStyle configures a live field by default. Restore the
        // preview's explicit interaction contract after applying that shared native style.
        searchField.isEditable = isInteractive
        searchField.isSelectable = isInteractive
        searchField.focusRingType = isInteractive ? .default : .none
        searchField.delegate = isInteractive ? self : nil
        searchField.setAccessibilityLabel("Preview Search")
        searchField.setAccessibilityHelp(
            isInteractive
                ? "Filters safe fixture results. Return does not execute preview items."
                : "Fixture query"
        )
        content.addSubview(searchField)

        let searchChrome: NSView = searchField
        let hasResults = !displayedResults.isEmpty
        let searchTrailingInset = descriptor.searchHorizontalInset
        var constraints = [
            searchChrome.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -searchTrailingInset
            ),
            searchChrome.centerYAnchor.constraint(
                equalTo: content.topAnchor,
                constant: descriptor.searchHeight / 2
            ),
            searchChrome.heightAnchor.constraint(
                equalToConstant:
                    descriptor.searchHeight - descriptor.searchControlVerticalInset * 2
            ),
        ]

        constraints.append(searchChrome.leadingAnchor.constraint(
            equalTo: content.leadingAnchor,
            constant: descriptor.searchHorizontalInset
        ))

        let column = NSTableColumn(identifier: .init("preview-result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = descriptor.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: descriptor.rowSpacing)
        tableView.style = descriptor.resultTableStyle
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.allowsEmptySelection = true
        tableView.setAccessibilityLabel("Preview results")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.isHidden = !hasResults
        content.addSubview(scrollView)
        let resultsChrome: NSView = scrollView
        constraints += [
            resultsChrome.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: descriptor.resultHorizontalInset
            ),
            resultsChrome.topAnchor.constraint(
                equalTo: content.topAnchor,
                constant: descriptor.searchHeight + (hasResults ? descriptor.resultTopInset : 0)
            ),
            resultsChrome.bottomAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: hasResults ? -descriptor.resultBottomInset : 0
            ),
        ]

        constraints.append(resultsChrome.trailingAnchor.constraint(
            equalTo: content.trailingAnchor,
            constant: -descriptor.resultHorizontalInset
        ))
        if descriptor.showsHeaderSeparator {
            headerSeparator.translatesAutoresizingMaskIntoConstraints = false
            headerSeparator.color = descriptor.headerSeparatorColor
            headerSeparator.lineThickness = descriptor.headerSeparatorThickness
            headerSeparator.angleDegrees = descriptor.headerSeparatorAngleDegrees
            headerSeparator.isHidden = !descriptor.shouldShowHeaderSeparator(
                hasResults: hasResults,
                selectedRow: selectedRow
            )
            content.addSubview(headerSeparator)
            constraints += [
                headerSeparator.leadingAnchor.constraint(
                    equalTo: content.leadingAnchor,
                    constant: descriptor.headerSeparatorLeadingInset
                ),
                headerSeparator.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -descriptor.headerSeparatorTrailingInset
                ),
                headerSeparator.topAnchor.constraint(
                    equalTo: content.topAnchor,
                    constant: descriptor.headerSeparatorTopInset
                ),
                headerSeparator.heightAnchor.constraint(
                    equalToConstant: descriptor.headerSeparatorLayoutHeight
                ),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        tableView.reloadData()
        if !displayedResults.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        }
        layoutSubtreeIfNeeded()
        layoutTableDocument()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard isInteractive else { return }
        updateInteractiveResults()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        (searchField as? LauncherNativeSearchField)?.configureCurrentFieldEditor()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard isInteractive else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            _ = moveInteractiveSelection(up: true)
            return true
        case #selector(NSResponder.moveDown(_:)):
            _ = moveInteractiveSelection(up: false)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Deliberately consume Return. This view has no coordinator/executor callback and
            // therefore cannot launch an app, run an action, or write learned usage.
            return true
        default:
            return false
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard isInteractive, tableView.selectedRow >= 0 else { return }
        selectedRow = tableView.selectedRow
        refreshRows()
        updateHeaderSeparatorVisibility()
        layoutTableDocument()
    }

    private func layoutTableDocument() {
        guard scrollView.frame.width > 0 else { return }
        let height = descriptor.resultsDocumentHeight(resultCount: displayedResults.count)
        let size = scrollView.contentSize
        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(0, size.width),
            height: height
        )
    }

    private func updateInteractiveResults() {
        displayedResults = LauncherPreviewInteraction.results(
            matching: searchField.stringValue,
            in: fixture
        )
        let hasResults = !displayedResults.isEmpty
        scrollView.isHidden = !hasResults
        selectedRow = displayedResults.isEmpty ? -1 : 0
        updateHeaderSeparatorVisibility()
        tableView.reloadData()
        if selectedRow >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        refreshRows()
        layoutTableDocument()
    }

    private func updateHeaderSeparatorVisibility() {
        headerSeparator.isHidden = !descriptor.shouldShowHeaderSeparator(
            hasResults: !displayedResults.isEmpty,
            selectedRow: selectedRow
        )
    }

    private func refreshRows() {
        guard tableView.numberOfColumns > 0 else { return }
        for row in displayedResults.indices {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultRowView)?
                .setSelected(row == selectedRow)
        }
    }

}
