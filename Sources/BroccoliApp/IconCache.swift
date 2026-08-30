@preconcurrency import AppKit
import BroccoliCore
import Foundation
import QuickLookThumbnailing

private final class SendableImage: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}

/// Resolves macOS application artwork under Aqua and immediately flattens it to a bounded,
/// non-template bitmap. IconServices images can otherwise choose a dark variant later when an
/// `NSImageView` draws them inside a dark launcher, even if they were fetched in Light Mode.
enum LightModeApplicationIcon {
    nonisolated static func load(
        atPath path: String,
        pointSize: CGFloat,
        backingScale: CGFloat
    ) -> NSImage? {
        guard let lightAppearance = NSAppearance(named: .aqua) else { return nil }
        var workspaceImage: NSImage?
        lightAppearance.performAsCurrentDrawingAppearance {
            workspaceImage = NSWorkspace.shared.icon(forFile: path)
        }
        guard let workspaceImage else { return nil }
        return materialize(
            workspaceImage,
            pointSize: pointSize,
            backingScale: backingScale
        )
    }

    nonisolated static func materialize(
        _ workspaceImage: NSImage,
        pointSize: CGFloat,
        backingScale: CGFloat
    ) -> NSImage? {
        guard let lightAppearance = NSAppearance(named: .aqua) else { return nil }
        var renderedImage: NSImage?
        lightAppearance.performAsCurrentDrawingAppearance {
            renderedImage = SystemSettingsNativeIconResolver.materializeImage(
                workspaceImage,
                pointSize: pointSize,
                backingScale: backingScale
            )?.image
        }
        renderedImage?.isTemplate = false
        return renderedImage
    }
}

@MainActor
final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    private var staticIcons: [String: NSImage] = [:]
    private var installedNativeSystemSettingsIconKeys: Set<String> = []
    private let systemSettingsIconStore: SystemSettingsNativeIconStore
    private var systemSettingsIconObserver: NSObjectProtocol?
    private let interactiveQueue = DispatchQueue(
        label: "dev.gauravpandey.broccoli.icons.interactive",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let prewarmQueue = DispatchQueue(
        label: "dev.gauravpandey.broccoli.icons.prewarm",
        qos: .utility
    )
    private var interactiveLoading: Set<String> = []
    private var thumbnailLoading: Set<String> = []
    private var prewarming: Set<String> = []
    private let backingScale: CGFloat
    private let genericApplication = NSImage(
        systemSymbolName: "app",
        accessibilityDescription: "Application"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))
    private let genericFile = NSImage(
        systemSymbolName: "doc",
        accessibilityDescription: "File"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))
    private let genericFolder = NSImage(
        systemSymbolName: "folder.fill",
        accessibilityDescription: "Folder"
    ) ?? NSImage(size: NSSize(width: 40, height: 40))

    var onIconLoaded: ((String) -> Void)?

    init(
        systemSettingsIconStore: SystemSettingsNativeIconStore = .shared,
        backingScale: CGFloat? = nil,
        startsNativeIconResolution: Bool = true
    ) {
        self.systemSettingsIconStore = systemSettingsIconStore
        self.backingScale = max(2, backingScale ?? NSScreen.main?.backingScaleFactor ?? 2)
        cache.totalCostLimit = 16 * 1_024 * 1_024
        systemSettingsIconObserver = NotificationCenter.default.addObserver(
            forName: SystemSettingsNativeIconStore.didLoadNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let iconKey = notification.object as? String
            MainActor.assumeIsolated {
                guard let self,
                      let iconKey,
                      let icon = systemSettingsIconStore.cachedIcon(for: iconKey) else { return }
                self.installNativeSystemSettingsIcon(icon, for: iconKey, notify: true)
            }
        }
        prebuildStaticIcons()
        let requests = SystemSettingsIconRequestMapper.requests(for: SettingsCatalog.searchEntries)
        for request in requests {
            if let icon = systemSettingsIconStore.cachedIcon(for: request.iconKey) {
                installNativeSystemSettingsIcon(icon, for: request.iconKey, notify: false)
            }
        }
        if startsNativeIconResolution {
            systemSettingsIconStore.ensureResolution(
                requests: requests,
                backingScale: self.backingScale
            )
        }
    }

    deinit {
        if let systemSettingsIconObserver {
            NotificationCenter.default.removeObserver(systemSettingsIconObserver)
        }
    }

    func image(for entry: SearchEntry) -> NSImage {
        // This lookup is cache-only and performs no resolution, filesystem, or workspace work.
        // It also lets a cache created after process-wide resolution consume the shared bitmap
        // without relying on having observed the original notification.
        if entry.kind == .systemSetting,
           let icon = systemSettingsIconStore.cachedIcon(for: entry.iconKey) {
            if !installedNativeSystemSettingsIconKeys.contains(entry.iconKey) {
                installNativeSystemSettingsIcon(icon, for: entry.iconKey, notify: false)
            }
            return icon.image
        }
        if let cached = cache.object(forKey: entry.iconKey as NSString) { return cached }
        switch entry.kind {
        case .application:
            loadApplicationIcon(path: entry.iconKey, interactive: true)
            return genericApplication
        case .file:
            let isDirectory: Bool
            if case .file(_, let targetIsDirectory) = entry.target {
                isDirectory = targetIsDirectory
            } else {
                isDirectory = false
            }
            loadFileIcon(path: entry.iconKey, isDirectory: isDirectory)
            return isDirectory ? genericFolder : genericFile
        case .calculator:
            return NSImage(systemSymbolName: "function", accessibilityDescription: "Calculator") ?? genericApplication
        case .clipboard:
            return NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard") ?? genericApplication
        case .status:
            if entry.iconKey == "status:no-results" {
                return NSImage(
                    systemSymbolName: "questionmark",
                    accessibilityDescription: "No results"
                ) ?? genericApplication
            }
            return NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Status") ?? genericApplication
        case .systemSetting, .action:
            guard let icon = staticIcons[entry.iconKey] else { return genericApplication }
            cache.setObject(icon, forKey: entry.iconKey as NSString, cost: 40 * 40 * 4)
            return icon
        }
    }

    func prewarm(_ entries: [SearchEntry], limit: Int = 16) {
        let prioritized = entries
            .filter { $0.kind == .application && $0.isRunning }
            .sorted {
                if $0.isRunning != $1.isRunning { return $0.isRunning }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        var scheduled = 0
        for entry in prioritized {
            guard scheduled < limit else { break }
            guard cache.object(forKey: entry.iconKey as NSString) == nil else { continue }
            loadApplicationIcon(path: entry.iconKey, interactive: false)
            scheduled += 1
        }
    }

    private func prebuildStaticIcons() {
        for entry in SettingsCatalog.searchEntries {
            let icon = badgeIcon(
                symbol: NativeIconCatalog.symbolName(for: entry),
                semanticFallback: "gearshape",
                nativeTemplateName: entry.iconKey == "setting:bluetooth"
                    ? NSImage.bluetoothTemplateName
                    : nil,
                accent: settingAccent(entry.iconKey)
            )
            staticIcons[entry.iconKey] = icon
            cache.setObject(icon, forKey: entry.iconKey as NSString, cost: 40 * 40 * 4)
        }
        for entry in ActionRegistry.searchEntries {
            let icon = Self.actionTemplateIcon(
                symbolCandidates: NativeIconCatalog.actionSymbols(for: entry),
                accessibilityDescription: entry.title
            )
            staticIcons[entry.iconKey] = icon
            cache.setObject(
                icon,
                forKey: entry.iconKey as NSString,
                cost: Self.boundedImageCost(icon)
            )
        }
    }

    private func installNativeSystemSettingsIcon(
        _ icon: MaterializedSystemSettingsIcon,
        for iconKey: String,
        notify: Bool
    ) {
        installedNativeSystemSettingsIconKeys.insert(iconKey)
        staticIcons[iconKey] = icon.image
        cache.setObject(icon.image, forKey: iconKey as NSString, cost: icon.cost)
        if notify { onIconLoaded?(iconKey) }
    }

    private func badgeIcon(
        symbol name: String,
        semanticFallback: String,
        nativeTemplateName: NSImage.Name? = nil,
        accent: NSColor
    ) -> NSImage {
        let nativeGlyph = nativeTemplateName
            .flatMap { NSImage(named: $0) }
            .flatMap { Self.tintedTemplateImage($0, color: .white) }
        let symbolGlyph = nativeGlyph == nil
            ? Self.resolvedSystemSymbol(
                preferred: name,
                semanticFallbacks: [semanticFallback, "questionmark"]
            )
            : nil
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        defer { image.unlockFocus() }

        let tileRect = NSRect(x: 1, y: 1, width: 38, height: 38)
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: 9, yRadius: 9)
        accent.withAlphaComponent(0.92).setFill()
        tile.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        tile.lineWidth = 0.5
        tile.stroke()

        if let glyph = nativeGlyph {
            glyph.draw(
                in: Self.aspectFitRect(
                    imageSize: glyph.size,
                    boundingRect: NSRect(x: 8, y: 7, width: 24, height: 26)
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else if let symbol = symbolGlyph {
            symbol.size = NSSize(width: 26, height: 26)
            symbol.draw(
                in: NSRect(x: 7, y: 7, width: 26, height: 26),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            // SF Symbols are supplied by the OS and can vary by release. This last-resort
            // text glyph means even an unexpectedly absent semantic fallback cannot leave
            // behind an empty colored tile.
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 23, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let fallback = NSAttributedString(string: "?", attributes: attributes)
            let size = fallback.size()
            fallback.draw(at: NSPoint(x: 20 - size.width / 2, y: 20 - size.height / 2))
        }
        image.isTemplate = false
        return image
    }

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
            return max(current, width * height * 4)
        }
        return max(representationCost, Int(image.size.width * image.size.height * 4))
    }

    private static func tintedTemplateImage(_ source: NSImage, color: NSColor) -> NSImage? {
        guard source.size.width > 0, source.size.height > 0 else { return nil }
        let result = NSImage(size: source.size)
        result.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: source.size))
        color.setFill()
        NSRect(origin: .zero, size: source.size).fill(using: .sourceIn)
        result.unlockFocus()
        result.isTemplate = false
        return result
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

    private func settingAccent(_ key: String) -> NSColor {
        switch key.replacingOccurrences(of: "setting:", with: "") {
        case "wifi", "bluetooth", "network", "displays", "desktop-dock": .systemBlue
        case "notifications", "software-update": .systemRed
        case "sound": .systemPink
        case "focus", "siri-spotlight": .systemPurple
        case "appearance", "wallpaper", "screen-saver", "control-center": .systemCyan
        case "accessibility", "sharing", "internet-accounts": .systemBlue
        case "battery", "time-machine": .systemGreen
        case "date-time": .systemRed
        case "passwords": .systemYellow
        case "printers", "storage", "general", "lock-screen", "keyboard", "trackpad", "mouse", "privacy", "users": .systemGray
        case "login-items": .systemPurple
        case "keyboard-shortcuts": .systemBlue
        default: .systemBlue
        }
    }

    private func loadApplicationIcon(path: String, interactive: Bool) {
        guard !path.isEmpty else { return }
        if interactive {
            guard !interactiveLoading.contains(path) else { return }
            interactiveLoading.insert(path)
        } else {
            guard !prewarming.contains(path) else { return }
            prewarming.insert(path)
        }
        let queue = interactive ? interactiveQueue : prewarmQueue
        let backingScale = self.backingScale
        queue.async { [weak self] in
            // System applications such as Safari can be exposed through /Applications as
            // symlinks. Asking NSWorkspace for the link icon adds an alias badge; resolve only
            // for presentation while retaining the original launch/cache identity.
            let iconPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard let icon = LightModeApplicationIcon.load(
                atPath: iconPath,
                pointSize: 40,
                backingScale: backingScale
            ) else {
                Task { @MainActor [weak self] in
                    if interactive { self?.interactiveLoading.remove(path) }
                    else { self?.prewarming.remove(path) }
                }
                return
            }
            let box = SendableImage(icon)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cache.setObject(
                    box.image,
                    forKey: path as NSString,
                    cost: Self.boundedImageCost(box.image)
                )
                if interactive { self.interactiveLoading.remove(path) }
                else { self.prewarming.remove(path) }
                self.onIconLoaded?(path)
            }
        }
    }

    private func loadFileIcon(path: String, isDirectory: Bool) {
        guard !path.isEmpty,
              !interactiveLoading.contains(path),
              !thumbnailLoading.contains(path) else { return }
        interactiveLoading.insert(path)
        let thumbnailScale = NSScreen.main?.backingScaleFactor ?? 2
        interactiveQueue.async { [weak self] in
            // NSWorkspace supplies the same native document/folder artwork Finder uses. It is
            // intentionally obtained off-main so a cache miss can never add synchronous icon
            // work to the typing path.
            let box = SendableImage(NSWorkspace.shared.icon(forFile: path))
            Task { @MainActor [weak self] in
                guard let self else { return }
                box.image.size = NSSize(width: 40, height: 40)
                self.cache.setObject(box.image, forKey: path as NSString, cost: 40 * 40 * 4)
                self.interactiveLoading.remove(path)
                self.onIconLoaded?(path)

                // Finder's native folder icon is the final representation. Regular files can
                // subsequently receive a richer Quick Look thumbnail without delaying this
                // immediate fallback or the initial row update.
                if !isDirectory {
                    self.loadFileThumbnail(path: path, scale: thumbnailScale)
                }
            }
        }
    }

    private func loadFileThumbnail(path: String, scale: CGFloat) {
        guard !path.isEmpty, !thumbnailLoading.contains(path) else { return }
        thumbnailLoading.insert(path)
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: NSSize(width: 128, height: 128),
            scale: scale,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else {
                Task { @MainActor [weak self] in self?.thumbnailLoading.remove(path) }
                return
            }
            let box = SendableImage(representation.nsImage)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cache.setObject(box.image, forKey: path as NSString, cost: 128 * 128 * 4)
                self.thumbnailLoading.remove(path)
                self.onIconLoaded?(path)
            }
        }
    }
}
