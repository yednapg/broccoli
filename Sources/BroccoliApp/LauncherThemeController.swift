@preconcurrency import AppKit
import BroccoliCore

/// Minimal keeps its authored controls and typography while using a narrower desktop shell.
/// Width is the only scaled dimension; the live panel and Settings preview share these metrics
/// so text, icons, rows, and vertical rhythm cannot shrink accidentally with the window.
enum LauncherMinimalMetrics {
    static let widthScale: CGFloat = 0.90
    static let width: CGFloat = 600 * widthScale
    static let cornerRadius: CGFloat = 5
    static let searchHeight: CGFloat = 55
    static let searchFontSize: CGFloat = 24
    static let searchHorizontalInset: CGFloat = 20
    static let searchVerticalInset: CGFloat = 11.5
    // The authored 32-point line remains 11.5 points from the shell edges, but AppKit's
    // field editor needs extra transparent headroom above it to avoid clipping ascenders.
    static let searchControlVerticalInset: CGFloat = 9
    static let searchSymbolSize: CGFloat = 24
    static let searchSymbolPointSize: CGFloat = searchFontSize
    // Keep the icon centered between two equal horizontal spaces: shell-to-icon and
    // icon-to-query.
    static let searchSymbolTextGap: CGFloat = searchHorizontalInset
    // Deliberately large diagnostic correction used to make the query shift unmistakable.
    static let nativeTextLeadingCompensation: CGFloat = -10
    // Give the SF Symbol just enough optical correction to fill its compact 24-point box.
    static let searchSymbolDrawingScale: CGFloat = 1.08
    static let searchSymbolDrawingVerticalScale: CGFloat = 1.10
    static let separatorTopInset: CGFloat = 54
    static let separatorLeadingInset: CGFloat = 16
    static let separatorTrailingInset: CGFloat = 16
    static let separatorThickness: CGFloat = 1
    static let rowHeight: CGFloat = 50
    // The Minimal selection is an edge-to-edge rectangular band. Content retains its own
    // leading inset instead of using an outer table inset that narrows the blue fill.
    static let resultHorizontalInset: CGFloat = 0
    static let resultContentLeadingInset: CGFloat = 13
    static let resultTitleLeadingInset: CGFloat = 8
    static let resultTopInset: CGFloat = 0
    static let resultBottomInset: CGFloat = 0
    static let rowSpacing: CGFloat = 0
    static let resultIconSize: CGFloat = 30
    static let resultIconOpticalSize: CGFloat = 26
    static let resultNativeIconSize: CGFloat = 35
    static let resultNativeIconOpticalSize: CGFloat = 35
    static let resultActionIconOpticalSize: CGFloat = 16.5
    static let resultTemplatePointSize: CGFloat = 22
    static let resultTitleFontSize: CGFloat = 16
    static let resultSubtitleFontSize: CGFloat = 12
    static let resultShortcutFontSize: CGFloat = 13
    static let figmaBackgroundBlur: CGFloat = 60
    // AppKit's public behind-window effect is less opaque than Figma's Ultra Thick recipe.
    // This wash brings the sampled live surface from ~85% to the reference's ~93% light fill.
    static let lightTintOpacity: CGFloat = 0.60
    static let darkTintOpacity: CGFloat = 0.92
}

/// The first "Liquid Glass" group in the Figma file is authored at 900 × 75 points. The live
/// launcher deliberately keeps its established 640 × 58 footprint, so every internal measure
/// is reduced by the same vertical scale. This preserves the designed optical rhythm instead
/// of mixing the old 58-point shell with unscaled icon, type, and inset values.
enum LauncherLiquidGlassMetrics {
    static let figmaWidth: CGFloat = 900
    static let figmaSearchHeight: CGFloat = 75
    static let figmaSearchFontSize: CGFloat = 36
    static let figmaSearchHorizontalInset: CGFloat = 25
    static let figmaSearchVerticalInset: CGFloat = 16
    static let figmaSearchSymbolSize: CGFloat = 30
    static let figmaSearchSymbolPointSize: CGFloat = 28
    static let figmaSearchTextLeading: CGFloat = 75
    static let figmaSeparatorTopInset: CGFloat = 73
    static let figmaSeparatorHorizontalInset: CGFloat = 25
    static let figmaSeparatorThickness: CGFloat = 1
    static let figmaSeparatorAngleDegrees: CGFloat = 0

    static let width: CGFloat = 640
    static let searchHeight: CGFloat = 58
    static let scale = searchHeight / figmaSearchHeight
    // Preserve the search capsule's curvature when rows expand the same glass surface.
    static let cornerRadius = searchHeight / 2
    static let searchFontSize: CGFloat = 26
    static let searchHorizontalInset: CGFloat = 20
    static let searchVerticalInset = figmaSearchVerticalInset * scale
    // Spotlight's magnifier has slightly more optical height than its 26-point query. Give the
    // symbol a real 28-point canvas instead of asking a 26-point bitmap to scale past its bounds
    // (which was clamped and therefore produced no visible size change).
    static let searchSymbolSize: CGFloat = 28
    static let searchSymbolPointSize: CGFloat = 27.8
    static let searchTextLeading = figmaSearchTextLeading * scale
    static let searchTextHorizontalOffset: CGFloat = -10
    static let searchSymbolTextGap: CGFloat = searchHorizontalInset
    // The output canvas now carries the intended optical size directly, so no ineffective
    // post-render enlargement is needed and the magnifier handle remains safely inside it.
    static let searchSymbolDrawingScale: CGFloat = 1
    static let searchSymbolDrawingVerticalScale: CGFloat = 1
    static let resultIconSize: CGFloat = 50
    static let resultActionIconOpticalSize: CGFloat = 30
    static let resultClipboardIconOpticalSize: CGFloat = 48
    static let statusIconSize: CGFloat = 22
    // Keep result selection bars clear of both the header rule and the rounded lower edge.
    // Matching top and bottom insets preserves the panel's rhythm at every result count.
    static let resultTopInset: CGFloat = 8
    static let resultBottomInset: CGFloat = 8
    // Enlarge the invisible native field equally above and below the authored inset. This
    // provides font-rendering headroom without changing either centered midY.
    static let searchControlVerticalOutset: CGFloat = 8
    // AppKit's shared field editor adds 5.5 points of leading ink only after text entry.
    // Counteract it for nonempty queries so the compact placeholder never jumps on expansion.
    static let fieldEditorTextLeadingCorrection: CGFloat = 5.5
    static let separatorTopInset = figmaSeparatorTopInset * scale
    static let separatorHorizontalInset = figmaSeparatorHorizontalInset * scale
    // A one-point divider stays one Retina point after the surrounding geometry is resized.
    static let separatorThickness = figmaSeparatorThickness
    static let separatorAngleDegrees = figmaSeparatorAngleDegrees
}

/// Motion values for transitions between launcher presentation states. The durations are
/// shared by every design and mode; Reduce Motion replaces them with the instant commit.
enum LauncherMotionMetrics {
    static let expansionAnimationDuration: TimeInterval = 0.18
    /// The window-server resize animation has no completion callback; this is how long the
    /// controller waits before settling post-motion state (viewport visibility, shadow).
    static let nativeResizeSettlement: TimeInterval = 0.3
}

/// Search retains more matches than the Appearance viewport can show at once.
/// `visibleResultCount` (3...10) is how many complete rows fit on screen; this cap is
/// the bounded result set those rows can scroll through.
enum LauncherSearchLimits {
    static let resultSetCap = 50
    /// Background application-icon warmup stays well below the result-set cap so launch
    /// does not decode every catalog app. Visible rows still promote their own loads.
    static let iconPrewarmCap = 16
}

@MainActor
struct LauncherThemeDescriptor {
    enum Surface: Equatable {
        case opaque
        case ultraThick
        case glass
    }

    let environment: LauncherAppearanceEnvironment
    let design: LauncherDesign
    let isDark: Bool
    let width: CGFloat
    let cornerRadius: CGFloat
    let searchHeight: CGFloat
    let rowHeight: CGFloat
    let searchFontSize: CGFloat
    let searchHorizontalInset: CGFloat
    let searchVerticalInset: CGFloat
    let resultHorizontalInset: CGFloat
    let resultTopInset: CGFloat
    let resultBottomInset: CGFloat
    let rowSpacing: CGFloat
    let surface: Surface
    let appearance: NSAppearance?
    let backgroundColor: NSColor
    let selectionColor: NSColor
    let selectedTextColor: NSColor
    let selectedShortcutTextColor: NSColor
    let hasShadow: Bool
    let showsSubtitles: Bool
    let showsShortcuts: Bool
    let originX: CGFloat
    let originY: CGFloat
    let visibleResultCount: Int

    var iconContext: IconRenderContext {
        environment.iconContext(mode: isDark ? .dark : .light,
            pointSize: design == .liquidGlass ? LauncherLiquidGlassMetrics.resultIconSize : LauncherMinimalMetrics.resultNativeIconSize)
    }

    var drawingAppearance: NSAppearance { iconContext.drawingAppearance }

    var searchPlaceholderColor: NSColor {
        switch design {
        case .liquidGlass:
            // Device ink, not a catalog color. Semantic labels still pick up wallpaper chroma
            // through HUD even when vibrancy is off. This is the same black/white as the glyph.
            return searchIconColor
        case .minimal:
            return .placeholderTextColor
        }
    }

    var searchMetrics: LauncherSearchMetrics {
        switch design {
        case .minimal: .figmaMinimal
        case .liquidGlass: .figmaLiquidGlass
        }
    }

    var searchControlVerticalInset: CGFloat {
        switch design {
        case .minimal: return LauncherMinimalMetrics.searchControlVerticalInset
        case .liquidGlass:
            return max(
                0,
                searchVerticalInset - LauncherLiquidGlassMetrics.searchControlVerticalOutset
            )
        }
    }

    var searchTextColor: NSColor {
        switch design {
        case .minimal:
            return isDark
                ? NSColor.white.withAlphaComponent(0.82)
                : NSColor.black
        case .liquidGlass:
            return searchIconColor
        }
    }

    var searchIconColor: NSColor {
        switch design {
        case .liquidGlass:
            return isDark
                ? NSColor(calibratedWhite: 1, alpha: 0.72)
                : NSColor(calibratedWhite: 0, alpha: 1)
        case .minimal:
            return isDark
                ? NSColor.white.withAlphaComponent(0.85)
                : NSColor.black.withAlphaComponent(0.85)
        }
    }

    var headerSeparatorColor: NSColor {
        if design == .liquidGlass {
            return searchIconColor.withAlphaComponent(0.25)
        }
        return isDark
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.black.withAlphaComponent(0.25)
    }

    var showsHeaderSeparator: Bool { true }

    /// Minimal's first selected result is a continuation of the header edge. Its blue row
    /// replaces the divider instead of leaving a one-point rule visible above the selection.
    func shouldShowHeaderSeparator(hasResults: Bool, selectedRow: Int) -> Bool {
        showsHeaderSeparator
            && hasResults
            && !(design == .minimal && selectedRow == 0)
    }

    var headerSeparatorLeadingInset: CGFloat {
        design == .liquidGlass
            ? LauncherLiquidGlassMetrics.separatorHorizontalInset
            : LauncherMinimalMetrics.separatorLeadingInset
    }

    var headerSeparatorTrailingInset: CGFloat {
        design == .liquidGlass
            ? LauncherLiquidGlassMetrics.separatorHorizontalInset
            : LauncherMinimalMetrics.separatorTrailingInset
    }

    var headerSeparatorTopInset: CGFloat {
        design == .liquidGlass
            ? LauncherLiquidGlassMetrics.separatorTopInset
            : LauncherMinimalMetrics.separatorTopInset
    }

    var headerSeparatorThickness: CGFloat {
        design == .liquidGlass
            ? LauncherLiquidGlassMetrics.separatorThickness
            : LauncherMinimalMetrics.separatorThickness
    }

    var headerSeparatorAngleDegrees: CGFloat {
        design == .liquidGlass ? LauncherLiquidGlassMetrics.separatorAngleDegrees : 0
    }

    var headerSeparatorLayoutHeight: CGFloat {
        let run = max(0, width - headerSeparatorLeadingInset - headerSeparatorTrailingInset)
        let rise = abs(tan(headerSeparatorAngleDegrees * .pi / 180) * run)
        return max(headerSeparatorThickness, rise + headerSeparatorThickness)
    }

    var resultTableStyle: NSTableView.Style {
        .fullWidth
    }

    var resultSelectionCornerRadius: CGFloat {
        switch design {
        case .minimal: 0
        case .liquidGlass: 12
        }
    }

    func displayedResultCount(for resultCount: Int) -> Int {
        min(max(0, resultCount), visibleResultCount)
    }

    func resultVerticalInsets(resultCount: Int) -> (top: CGFloat, bottom: CGFloat) {
        guard displayedResultCount(for: resultCount) > 0 else { return (0, 0) }
        return (resultTopInset, resultBottomInset)
    }

    func panelHeight(resultCount: Int) -> CGFloat {
        // The window grows in complete viewport rows so query changes do not leave an empty
        // band or make the launcher jump. Extra matches stay in the document and scroll
        // inside that fixed viewport. Status messages occupy the same row as ordinary
        // results; geometry depends on count, never result kind.
        // NSTableView reserves its vertical intercell spacing after every row, including the
        // last one. Keep the visual bottom inset outside the scroll viewport so a short list
        // still sizes the viewport to its document, and a long list scrolls in complete rows.
        let insets = resultVerticalInsets(resultCount: resultCount)
        return searchHeight + insets.top
            + resultsViewportHeight(resultCount: resultCount) + insets.bottom
    }

    func resultsDocumentHeight(resultCount: Int) -> CGFloat {
        rowStackHeight(rowCount: max(0, resultCount))
    }

    func resultsViewportHeight(resultCount: Int) -> CGFloat {
        rowStackHeight(rowCount: displayedResultCount(for: resultCount))
    }

    private func rowStackHeight(rowCount: Int) -> CGFloat {
        CGFloat(max(0, rowCount)) * (rowHeight + rowSpacing)
    }
}

@MainActor
final class LauncherThemeController {
    func descriptor(for preferences: LauncherAppearancePreferences) -> LauncherThemeDescriptor {
        descriptor(for: preferences, environment: .current)
    }

    func descriptor(for preferences: LauncherAppearancePreferences,
                    reducedTransparency: Bool, increasedContrast: Bool,
                    resolvedSystemDark: Bool? = nil) -> LauncherThemeDescriptor {
        let current = LauncherAppearanceEnvironment.current
        return descriptor(for: preferences, environment: .init(
            reducesTransparency: reducedTransparency, increasesContrast: increasedContrast,
            resolvedAppearance: resolvedSystemDark.map { $0 ? .dark : .light } ?? current.resolvedAppearance,
            reducesMotion: current.reducesMotion, backingScale: current.backingScale))
    }

    func descriptor(for preferences: LauncherAppearancePreferences,
                    environment: LauncherAppearanceEnvironment) -> LauncherThemeDescriptor {
        let context = environment.iconContext(mode: preferences.mode, pointSize: 40)
        let appearance: NSAppearance? = preferences.mode == .system ? nil : context.drawingAppearance
        let dark = context.appearance == .dark
        let reducedTransparency = environment.reducesTransparency
        let contrast = environment.increasesContrast

        switch preferences.design {
        case .minimal:
            let surface: LauncherThemeDescriptor.Surface = reducedTransparency || contrast
                ? .opaque
                : .ultraThick
            return LauncherThemeDescriptor(
                environment: environment,
                design: .minimal,
                isDark: dark,
                width: LauncherMinimalMetrics.width,
                cornerRadius: LauncherMinimalMetrics.cornerRadius,
                searchHeight: LauncherMinimalMetrics.searchHeight,
                rowHeight: LauncherMinimalMetrics.rowHeight,
                searchFontSize: LauncherMinimalMetrics.searchFontSize,
                searchHorizontalInset: LauncherMinimalMetrics.searchHorizontalInset,
                searchVerticalInset: LauncherMinimalMetrics.searchVerticalInset,
                resultHorizontalInset: LauncherMinimalMetrics.resultHorizontalInset,
                resultTopInset: LauncherMinimalMetrics.resultTopInset,
                resultBottomInset: LauncherMinimalMetrics.resultBottomInset,
                rowSpacing: LauncherMinimalMetrics.rowSpacing,
                surface: surface,
                appearance: appearance,
                backgroundColor: dark
                    ? .black
                    : NSColor(calibratedWhite: 0.93, alpha: 1),
                selectionColor: .controlAccentColor,
                selectedTextColor: .alternateSelectedControlTextColor,
                selectedShortcutTextColor: .alternateSelectedControlTextColor,
                hasShadow: false,
                showsSubtitles: preferences.showsSubtitles,
                showsShortcuts: preferences.showsShortcuts,
                originX: CGFloat(preferences.originX),
                originY: CGFloat(preferences.originY),
                visibleResultCount: preferences.visibleResultCount
            )
        case .liquidGlass:
            return LauncherThemeDescriptor(
                environment: environment,
                design: .liquidGlass,
                isDark: dark,
                width: LauncherLiquidGlassMetrics.width,
                cornerRadius: LauncherLiquidGlassMetrics.cornerRadius,
                searchHeight: LauncherLiquidGlassMetrics.searchHeight,
                // Search and results remain equal-height bands. Insets live outside the table
                // viewport so they create breathing room without stretching any result row.
                rowHeight: LauncherLiquidGlassMetrics.searchHeight,
                searchFontSize: LauncherLiquidGlassMetrics.searchFontSize,
                searchHorizontalInset: LauncherLiquidGlassMetrics.searchHorizontalInset,
                searchVerticalInset: LauncherLiquidGlassMetrics.searchVerticalInset,
                resultHorizontalInset: 10,
                resultTopInset: LauncherLiquidGlassMetrics.resultTopInset,
                resultBottomInset: LauncherLiquidGlassMetrics.resultBottomInset,
                rowSpacing: 0,
                surface: .glass,
                appearance: appearance,
                backgroundColor: dark ? NSColor(calibratedWhite: 0.035, alpha: 0.99) : NSColor(calibratedWhite: 0.99, alpha: 0.99),
                selectionColor: .controlAccentColor,
                selectedTextColor: .alternateSelectedControlTextColor,
                selectedShortcutTextColor: .alternateSelectedControlTextColor,
                // Glass supplies the backdrop; the floating panel also needs a native window
                // shadow to remain distinguishable over bright application backgrounds.
                hasShadow: true,
                showsSubtitles: preferences.showsSubtitles,
                showsShortcuts: preferences.showsShortcuts,
                originX: CGFloat(preferences.originX),
                originY: CGFloat(preferences.originY),
                visibleResultCount: preferences.visibleResultCount
            )
        }
    }
}
