@preconcurrency import AppKit

/// One immutable snapshot for the launcher, native artwork, and Settings previews.
enum LauncherPreviewResolvedAppearance: String, Equatable, Hashable, Sendable {
    case light, dark
}

struct LauncherAppearanceEnvironment: Equatable, Hashable, Sendable {
    let reducesTransparency: Bool
    let increasesContrast: Bool
    let resolvedAppearance: LauncherPreviewResolvedAppearance
    let reducesMotion: Bool
    let backingScale: CGFloat

    init(reducesTransparency: Bool, increasesContrast: Bool,
         resolvedAppearance: LauncherPreviewResolvedAppearance = .light,
         reducesMotion: Bool = false, backingScale: CGFloat = 2) {
        self.reducesTransparency = reducesTransparency
        self.increasesContrast = increasesContrast
        self.resolvedAppearance = resolvedAppearance
        self.reducesMotion = reducesMotion
        self.backingScale = backingScale.isFinite ? max(1, backingScale) : 2
    }

    @MainActor static var current: Self {
        Self(
            reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            resolvedAppearance: NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light,
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            backingScale: NSScreen.main?.backingScaleFactor ?? 2
        )
    }

    func iconContext(mode: LauncherAppearanceMode, pointSize: CGFloat,
                     backingScale: CGFloat? = nil) -> IconRenderContext {
        IconRenderContext(
            appearance: mode == .system ? resolvedAppearance : (mode == .dark ? .dark : .light),
            increasesContrast: increasesContrast, pointSize: pointSize,
            backingScale: backingScale ?? self.backingScale
        )
    }
}

typealias LauncherPreviewEnvironment = LauncherAppearanceEnvironment

/// Send only these values across queues. Resolve and finish each bitmap in this appearance;
/// never mutate a published image when another window asks for a different context.
struct IconRenderContext: Hashable, Sendable {
    let appearance: LauncherPreviewResolvedAppearance
    let increasesContrast: Bool
    let pointSize: CGFloat
    let backingScale: CGFloat

    init(appearance: LauncherPreviewResolvedAppearance, increasesContrast: Bool = false,
         pointSize: CGFloat = 40, backingScale: CGFloat = 2) {
        self.appearance = appearance
        self.increasesContrast = increasesContrast
        self.pointSize = pointSize.isFinite ? min(512, max(1, pointSize)) : 40
        self.backingScale = backingScale.isFinite ? min(8, max(1, backingScale)) : 2
    }

    var drawingAppearance: NSAppearance {
        let name: NSAppearance.Name = appearance == .dark
            ? (increasesContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
            : (increasesContrast ? .accessibilityHighContrastAqua : .aqua)
        return NSAppearance(named: name)!
    }

    func cacheKey(for source: String) -> IconCacheKey {
        IconCacheKey(source: source, context: self)
    }
}

struct IconCacheKey: Hashable, Sendable {
    let source: String
    let context: IconRenderContext

    // Only Quick Look's NSCache needs an Objective-C key. Native icon lookups hash the
    // immutable values directly instead of formatting strings for every visible row.
    var thumbnailKey: NSString {
        "\(context.appearance.rawValue):\(context.increasesContrast):\(context.pointSize):\(context.backingScale):\(source)" as NSString
    }
}

extension LauncherAppearancePreferences {
    func hasSameLayout(as other: Self) -> Bool {
        var lhs = self
        var rhs = other
        lhs.mode = .system
        rhs.mode = .system
        lhs.originX = 0
        lhs.originY = 0
        rhs.originX = 0
        rhs.originY = 0
        return lhs == rhs
    }
}
