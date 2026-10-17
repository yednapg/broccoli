@preconcurrency import AppKit
import BroccoliCore
import SwiftUI

/// Minimal keeps its authored controls and typography in a 550-point shell.
/// The live panel and Settings preview share these metrics so text, icons, rows,
/// and vertical rhythm cannot shrink accidentally with the window.
enum LauncherMinimalMetrics {
    static let width: CGFloat = 550
    static let cornerRadius: CGFloat = 3
    /// The collapsed bar stays at this height. Result rows are shorter.
    static let searchHeight: CGFloat = 55
    static let rowHeight: CGFloat = 50
    static let searchFontSize: CGFloat = 32
    static let searchFontWeight = NSFont.Weight.light
    /// Shortcuts, the clear button, and the header rule end this far from the right edge.
    static let contentHorizontalInset: CGFloat = 12
    static var searchHorizontalInset: CGFloat { contentHorizontalInset }
    /// The caret runs from the query font's ascender to its descender.
    static var searchCaretHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: searchFontSize, weight: searchFontWeight)
        return font.ascender - font.descender
    }
    /// The bar leaves this much space above and below the caret, rounded to a Retina pixel.
    /// The caret keeps the same distance from the left edge, so all three sides match.
    static var searchCaretMargin: CGFloat {
        ((searchHeight - searchCaretHeight) / 2 * 2).rounded() / 2
    }
    /// The caret's ink is this wide and centered on its insertion line.
    static let insertionPointWidth: CGFloat = 2
    /// The query's insertion line, measured from the panel's left edge. The caret is centered
    /// on it and a text selection starts on it.
    static var searchLeadingInset: CGFloat { searchCaretMargin + insertionPointWidth / 2 }
    /// The field's alignment rect is what the leading constraint positions, but AppKit draws
    /// the query two points to the left of it and the caret another half point before that.
    static let queryOriginCorrection: CGFloat = 2.5
    static var queryLeadingInset: CGFloat { queryOriginCorrection }
    /// Room the field editor keeps around the font's line box so ascenders are not clipped.
    static let searchFieldHeadroom: CGFloat = 4
    static var searchLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: searchFontSize, weight: searchFontWeight)
        return ceil(font.ascender - font.descender + font.leading)
    }
    /// Inset of the font's line box inside the shared bar.
    static var searchVerticalInset: CGFloat {
        (searchHeight - searchLineHeight) / 2
    }
    static var searchControlVerticalInset: CGFloat {
        (searchHeight - (searchLineHeight + searchFieldHeadroom * 2)) / 2
    }
    /// Gap used after a scope token. Minimal has no magnifier, so this is not the query inset.
    static let searchSymbolTextGap: CGFloat = 20
    // Deliberately large diagnostic correction used to make the query shift unmistakable.
    static let nativeTextLeadingCompensation: CGFloat = -10
    // Give the SF Symbol just enough optical correction to fill its search-size box.
    static let searchSymbolDrawingScale: CGFloat = 1.08
    static let searchSymbolDrawingVerticalScale: CGFloat = 1.10
    static var separatorLeadingInset: CGFloat { contentHorizontalInset }
    static var separatorTrailingInset: CGFloat { contentHorizontalInset }
    static let separatorThickness: CGFloat = 1
    /// The rule occupies the last point of the shared bar.
    static var separatorTopInset: CGFloat { searchHeight - separatorThickness }
    // The Minimal selection is an edge-to-edge rectangular band. Content retains its own
    // leading inset instead of using an outer table inset that narrows the blue fill.
    static let resultHorizontalInset: CGFloat = 0
    /// Visible edge of every result icon, measured from the panel's left edge. Icons start on
    /// the query's insertion line, so the query and the results share one leading edge.
    static var resultIconLeadingInset: CGFloat { searchLeadingInset }
    /// Space between a result icon's visible edge and its title.
    static let resultIconTitleGap: CGFloat = 8
    /// Where result titles and subtitles begin, measured from the panel's left edge.
    static var resultTextLeadingInset: CGFloat {
        resultIconLeadingInset + resultIconBody + resultIconTitleGap
    }
    static let resultTopInset: CGFloat = 0
    static let resultBottomInset: CGFloat = 0
    static let rowSpacing: CGFloat = 0
    static let resultNativeIconSize: CGFloat = 35
    static let resultNativeIconOpticalSize: CGFloat = 35
    /// One column for every Minimal result icon. It is wide enough that a square
    /// glyph and a wide symbol can share the same height.
    static let resultIconBox: CGFloat = 44
    static let resultIconBody: CGFloat = 34
    /// SF Symbols sit on a plate the size of a Settings icon. The glyph is smaller than the plate.
    static let resultSymbolGlyphSize: CGFloat = 18
    static let resultSymbolTileCornerRatio: CGFloat = 0.22
    /// Sampled from the dark Settings pane artwork, which reads as a plate rather than pure black.
    static let resultSymbolTileDark = NSColor(srgbRed: 28.0 / 255, green: 28.0 / 255, blue: 28.0 / 255, alpha: 1)
    static let resultSymbolTileLight = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    static let resultTemplatePointSize: CGFloat = resultNativeIconOpticalSize
    static let resultSettingsBadgeSize: CGFloat = 15
    static let resultTitleFontSize: CGFloat = 18
    static let resultSubtitleFontSize: CGFloat = 12
    static let resultShortcutFontSize: CGFloat = 16
    static let resultShortcutFontWeight = NSFont.Weight.regular
    /// Subtitles and unselected shortcuts share one ink: the label color at this opacity.
    static let secondaryInkOpacity: CGFloat = 0.40
    /// Resolved against the drawing appearance, as a semantic label color is.
    static let secondaryInk = NSColor(name: "LauncherMinimalSecondaryInk") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(secondaryInkOpacity)
    }
    /// Lowers a centered title stack so the rendered letters share the row's midpoint.
    /// The line boxes sit one point high once AppKit has drawn them.
    static let resultTextOpticalLift: CGFloat = -1
    /// `NSTableView` full-width style still insets each cell by this much on both sides.
    /// Row content is laid out inside that cell, so this margin is not added again.
    static let resultTableHorizontalInset: CGFloat = 6
    /// Leading edge of the icon box inside a row. The plate is centered in that box, so its
    /// visible edge lands on `resultIconLeadingInset`. The box may start before the cell.
    static var resultIconSlotLeadingInset: CGFloat {
        resultIconLeadingInset - resultTableHorizontalInset - (resultIconBox - resultIconBody) / 2
    }
    /// Gap between the icon box and the title that puts the title on `resultTextLeadingInset`.
    static var resultTitleSpacingAfterIconSlot: CGFloat {
        resultTextLeadingInset - resultTableHorizontalInset - resultIconSlotLeadingInset - resultIconBox
    }
    /// Trailing inset inside a row for the shortcut and for titles in rows without one.
    static var resultTrailingInset: CGFloat {
        contentHorizontalInset - resultTableHorizontalInset
    }
    // AppKit's public behind-window effect is less opaque than Figma's Ultra Thick recipe.
    // The light wash brings the sampled surface toward the reference's light fill.
    static let lightTintOpacity: CGFloat = 0.60
    /// One device pixel. A full point is two pixels on a Retina display and reads as a bold stroke.
    static func rimWidth(forBackingScale scale: CGFloat) -> CGFloat {
        1 / max(scale, 1)
    }

    /// Minimal has no hairline. The fill, including a selected row, runs to the window edge.
    static func fillInset(forBackingScale scale: CGFloat) -> CGFloat {
        _ = scale
        return 0
    }

    static let lightRimOpacity: CGFloat = 0.20
    static let lightRimOpacityIncreasedContrast: CGFloat = 0.38
    /// White at this opacity over the dark fill is only visible up close.
    static let darkRimOpacity: CGFloat = 0.06
    static let darkRimOpacityIncreasedContrast: CGFloat = 0.12
    /// The rule between the search bar and the first result. 25% white read as a gray
    /// stroke on the black fill; this sits just above that fill.
    static let darkSeparatorOpacity: CGFloat = 0.10
    static let darkSeparatorOpacityIncreasedContrast: CGFloat = 0.18
    /// The Dark fill when Reduce Transparency or Increase Contrast removes the blur.
    static let darkOpaqueBackground = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    /// The Dark fill over the window-server blur. About 15% of the blurred desktop shows through.
    static let darkBlurredBackground = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 216.0 / 255)
    /// Radius of the window-server blur behind the Dark fill.
    static let darkBackdropBlurRadius = 15

    static func rimColor(isDark: Bool, increasedContrast: Bool) -> NSColor {
        if isDark {
            let alpha = increasedContrast ? darkRimOpacityIncreasedContrast : darkRimOpacity
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
        }
        let alpha = increasedContrast ? lightRimOpacityIncreasedContrast : lightRimOpacity
        return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    }
}

/// The first "Liquid Glass" group in the Figma file is authored at 900 × 75 points. The live
/// launcher deliberately keeps its established 640 × 58 footprint, so every internal measure
/// is reduced by the same vertical scale. This preserves the designed optical rhythm instead
/// of mixing the old 58-point shell with unscaled icon, type, and inset values.
enum LauncherLiquidGlassMetrics {
    static let figmaSearchHeight: CGFloat = 75
    static let figmaSearchVerticalInset: CGFloat = 16
    static let figmaSeparatorTopInset: CGFloat = 73
    static let figmaSeparatorHorizontalInset: CGFloat = 25
    static let figmaSeparatorThickness: CGFloat = 1
    static let figmaSeparatorAngleDegrees: CGFloat = 0

    static let width: CGFloat = 640
    static let searchHeight: CGFloat = 58
    static let scale = searchHeight / figmaSearchHeight
    // Preserve the search capsule's curvature when rows expand the same glass surface.
    static let cornerRadius = searchHeight / 2
    // The glass clip and the Dark rim share this curve, so the rim follows the clipped edge.
    static let cornerCurve: CALayerCornerCurve = .continuous
    static let searchFontSize: CGFloat = 26
    static let searchHorizontalInset: CGFloat = 20
    static let searchVerticalInset = figmaSearchVerticalInset * scale
    // Spotlight's magnifier has slightly more optical height than its 26-point query. Give the
    // symbol a real 28-point canvas instead of asking a 26-point bitmap to scale past its bounds
    // (which was clamped and therefore produced no visible size change).
    static let searchSymbolSize: CGFloat = 28
    static let searchSymbolPointSize: CGFloat = 27.8
    static let searchTextHorizontalOffset: CGFloat = -10
    static let searchSymbolTextGap: CGFloat = searchHorizontalInset
    // The output canvas now carries the intended optical size directly, so no ineffective
    // post-render enlargement is needed and the magnifier handle remains safely inside it.
    static let searchSymbolDrawingScale: CGFloat = 1
    static let searchSymbolDrawingVerticalScale: CGFloat = 1
    /// Positive in the flipped search field. SF Symbols align with text through their
    /// alignment rect, which spans the cap height above the baseline; Apple centers that box
    /// on the text's cap height. The square canvas and AppKit's top-aligned button image
    /// leave the magnifier's box slightly high, so this moves it down to the query's cap
    /// height. Measured on the rendered field, not derived, because the button inset is
    /// AppKit's.
    static let searchSymbolVerticalOffset: CGFloat = 0.5
    static let resultIconSize: CGFloat = 50
    static let resultActionIconOpticalSize: CGFloat = 30
    static let resultClipboardIconOpticalSize: CGFloat = 48
    /// The Settings plate created for Minimal, at this column's size. The glyph keeps
    /// the same share of the plate.
    static let resultSymbolGlyphSize: CGFloat =
        LauncherMinimalMetrics.resultSymbolGlyphSize
            * resultIconSize
            / LauncherMinimalMetrics.resultIconBody
    // The System Settings icon that marks a Settings pane result, at its bottom-right corner.
    static let resultSettingsBadgeSize: CGFloat = 20
    static let statusIconSize: CGFloat = 22
    // Keep result selection bars clear of both the header rule and the rounded lower edge.
    // Matching top and bottom insets preserves the panel's rhythm at every result count.
    static let resultTopInset: CGFloat = 8
    static let resultBottomInset: CGFloat = 8
    // Enlarge the invisible native field equally above and below the authored inset. This
    // provides font-rendering headroom without changing either centered midY.
    static let searchControlVerticalOutset: CGFloat = 8
    static let separatorTopInset = figmaSeparatorTopInset * scale
    static let separatorHorizontalInset = figmaSeparatorHorizontalInset * scale
    // A one-point divider stays one Retina point after the surrounding geometry is resized.
    static let separatorThickness = figmaSeparatorThickness
    static let separatorAngleDegrees = figmaSeparatorAngleDegrees

    /// Dark keeps the backdrop's hue by darkening SwiftUI's regular material with neutral black
    /// instead of blending toward gray. Every Dark ink below is a neutral lift added to the
    /// surface (plus-lighter), so its color comes from the wallpaper; the rim is half the
    /// placeholder and magnifier lift.
    static let darkMaterial: Material = .regularMaterial
    static let darkShadeOpacity: Double = 0.36
    static let darkRimLift: Double = 0.125
    static let darkRimLiftIncreasedContrast: Double = 0.22
    static let darkInkLift: CGFloat = 0.50
    static let darkQueryLift: CGFloat = 0.88
    static let darkRuleLift: CGFloat = 0.12
}

/// Motion for the launcher's height change while a search is showing. Opening and closing
/// stay instant. Reduce Motion replaces these with the instant commit. Minimal is the
/// quicker of the two so a changing result count does not linger.
enum LauncherMotionMetrics {
    static let liquidGlassExpansionAnimationDuration: TimeInterval = 0.18
    static let minimalExpansionAnimationDuration: TimeInterval = 0.08
    /// A shrink waits this long so a quick burst of keystrokes that briefly narrows the
    /// results does not collapse the panel and grow it again a moment later.
    static let liquidGlassShrinkDelay: TimeInterval = 0.1
    static let minimalShrinkDelay: TimeInterval = 0.05

    static func expansionAnimationDuration(for design: LauncherDesign) -> TimeInterval {
        switch design {
        case .liquidGlass: liquidGlassExpansionAnimationDuration
        case .minimal: minimalExpansionAnimationDuration
        }
    }

    static func shrinkDelay(for design: LauncherDesign) -> TimeInterval {
        switch design {
        case .liquidGlass: liquidGlassShrinkDelay
        case .minimal: minimalShrinkDelay
        }
    }

    static func animationCurve(for design: LauncherDesign) -> NSAnimation.Curve {
        switch design {
        case .liquidGlass: .easeInOut
        case .minimal: .easeOut
        }
    }
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
        /// A translucent fill over the window-server blur of the desktop behind the panel.
        case blurredFill
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

    /// The color a Minimal surface draws in place of its material. `nil` shows the material.
    var surfaceFill: NSColor? {
        switch surface {
        case .opaque, .blurredFill: backgroundColor
        case .ultraThick, .glass: nil
        }
    }

    /// Radius of the window-server blur behind the panel. Zero turns the blur off.
    var windowBackdropBlurRadius: Int {
        surface == .blurredFill ? LauncherMinimalMetrics.darkBackdropBlurRadius : 0
    }

    /// Radius of the window's own rounded shape. `nil` keeps AppKit's shape.
    var windowCornerMaskRadius: CGFloat? {
        switch design {
        case .minimal: cornerRadius
        case .liquidGlass: nil
        }
    }

    var resultSubtitleColor: NSColor {
        switch design {
        case .minimal: minimalSecondaryInk
        case .liquidGlass: .secondaryLabelColor
        }
    }

    var resultShortcutColor: NSColor {
        switch design {
        case .minimal: minimalSecondaryInk
        case .liquidGlass: .tertiaryLabelColor
        }
    }

    /// Increase Contrast keeps the system's stronger secondary label.
    private var minimalSecondaryInk: NSColor {
        environment.increasesContrast ? .secondaryLabelColor : LauncherMinimalMetrics.secondaryInk
    }

    var searchPlaceholderColor: NSColor {
        switch design {
        case .liquidGlass:
            // Device ink, not a catalog color. Semantic labels still pick up wallpaper chroma
            // through HUD even when vibrancy is off. This is the same ink as the glyph.
            return searchIconColor
        case .minimal:
            return .placeholderTextColor
        }
    }

    /// Distance from the panel's left edge to the search field. `searchHorizontalInset`
    /// remains the right-hand inset.
    var searchLeadingInset: CGFloat {
        switch design {
        case .minimal: LauncherMinimalMetrics.searchLeadingInset
        case .liquidGlass: searchHorizontalInset
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
            // Solid ink. A translucent white is drawn lighter in the collapsed bar than
            // beside an open result row, so the same letters look like a different weight.
            return isDark ? .white : .black
        case .liquidGlass:
            return isDark
                ? Self.additiveLift(LauncherLiquidGlassMetrics.darkQueryLift)
                : searchIconColor
        }
    }

    /// Dark Liquid Glass ink is opaque neutral gray composited additively over the surface.
    var usesAdditiveInk: Bool { design == .liquidGlass && isDark }

    /// Plus-lighter adds display (sRGB) components, so the lift is specified there.
    private static func additiveLift(_ amount: CGFloat) -> NSColor {
        NSColor(srgbRed: amount, green: amount, blue: amount, alpha: 1)
    }

    var searchIconColor: NSColor {
        switch design {
        case .liquidGlass:
            return isDark
                ? Self.additiveLift(LauncherLiquidGlassMetrics.darkInkLift)
                : NSColor(calibratedWhite: 0, alpha: 1)
        case .minimal:
            return isDark
                ? NSColor.white.withAlphaComponent(0.85)
                : NSColor.black.withAlphaComponent(0.85)
        }
    }

    var headerSeparatorColor: NSColor {
        if design == .liquidGlass {
            return isDark
                ? Self.additiveLift(LauncherLiquidGlassMetrics.darkRuleLift)
                : searchIconColor.withAlphaComponent(0.25)
        }
        if isDark {
            let alpha = environment.increasesContrast
                ? LauncherMinimalMetrics.darkSeparatorOpacityIncreasedContrast
                : LauncherMinimalMetrics.darkSeparatorOpacity
            return NSColor.white.withAlphaComponent(alpha)
        }
        return NSColor.black.withAlphaComponent(0.25)
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
            // Light uses the material and Dark a black fill over the window-server blur.
            // Reduce Transparency and Increase Contrast make either one opaque.
            let surface: LauncherThemeDescriptor.Surface = if reducedTransparency || contrast {
                .opaque
            } else if dark {
                LauncherWindowBackdropBlur.isAvailable ? .blurredFill : .opaque
            } else {
                .ultraThick
            }
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
                    ? (surface == .blurredFill
                        ? LauncherMinimalMetrics.darkBlurredBackground
                        : LauncherMinimalMetrics.darkOpaqueBackground)
                    : NSColor(calibratedWhite: 0.93, alpha: 1),
                selectionColor: .controlAccentColor,
                selectedTextColor: .alternateSelectedControlTextColor,
                selectedShortcutTextColor: .alternateSelectedControlTextColor,
                hasShadow: true,
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
