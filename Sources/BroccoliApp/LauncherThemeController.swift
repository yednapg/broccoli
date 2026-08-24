@preconcurrency import AppKit

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
    static let insertionPointHeight: CGFloat = 24
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
    static let resultActionIconOpticalSize: CGFloat = 22
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
    static let figmaExpandedCornerRadius: CGFloat = 34
    static let figmaSearchFontSize: CGFloat = 36
    static let figmaSearchHorizontalInset: CGFloat = 25
    static let figmaSearchVerticalInset: CGFloat = 16
    static let figmaSearchSymbolSize: CGFloat = 30
    static let figmaSearchSymbolPointSize: CGFloat = 28
    static let figmaSearchTextLeading: CGFloat = 75
    static let figmaSeparatorTopInset: CGFloat = 73
    static let figmaSeparatorHorizontalInset: CGFloat = 25
    static let figmaSeparatorThickness: CGFloat = 1
    static let figmaSeparatorAngleDegrees: CGFloat = 0.2882782

    static let width: CGFloat = 640
    static let searchHeight: CGFloat = 58
    static let scale = searchHeight / figmaSearchHeight
    static let compactCornerRadius = searchHeight / 2
    static let expandedCornerRadius = figmaExpandedCornerRadius * scale
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
    // Keep the caret two points taller than the query without overpowering it as the old
    // 30-point insertion bar did.
    static let insertionPointHeight: CGFloat = 28
    static let resultIconSize: CGFloat = 50
    static let resultActionIconOpticalSize: CGFloat = 40
    static let resultClipboardIconOpticalSize: CGFloat = 48
    static let lightGlassTintAlpha: CGFloat = 0.30
    // Enlarge the invisible native field equally above and below the authored inset. This
    // provides font-rendering headroom without changing either centered midY.
    static let searchControlVerticalOutset: CGFloat = 8
    // Native glass paints its curved highlight and backdrop separation beyond its nominal
    // bounds. The live borderless window needs transparent breathing room for those pixels.
    static let liveCompositingOutset: CGFloat = 14
    // AppKit's shared field editor adds 5.5 points of leading ink only after text entry.
    // Counteract it for nonempty queries so the compact placeholder never jumps on expansion.
    static let fieldEditorTextLeadingCorrection: CGFloat = 5.5
    static let separatorTopInset = figmaSeparatorTopInset * scale
    static let separatorHorizontalInset = figmaSeparatorHorizontalInset * scale
    // A one-point divider stays one Retina point after the surrounding geometry is resized.
    static let separatorThickness = figmaSeparatorThickness
    static let separatorAngleDegrees = figmaSeparatorAngleDegrees
}

@MainActor
struct LauncherThemeDescriptor {
    enum Surface: Equatable {
        case opaque
        case ultraThick
        case vibrancy
        case glass
        case classic
    }

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
    let showsPreview: Bool
    let previewWidth: CGFloat
    let appearance: NSAppearance?
    let backgroundColor: NSColor
    let glassTintColor: NSColor?
    let selectionColor: NSColor
    let hasShadow: Bool
    let showsSubtitles: Bool
    let showsShortcuts: Bool
    let verticalPosition: CGFloat
    let visibleResultCount: Int

    var searchMetrics: LauncherSearchMetrics {
        switch design {
        case .minimal: .figmaMinimal
        case .liquidGlass: .figmaLiquidGlass
        case .yosemiteClassic:
            LauncherSearchMetrics(
                fontSize: searchFontSize,
                symbolSize: searchFontSize,
                symbolPointSize: searchFontSize,
                symbolTextGap: searchHorizontalInset,
                textLeadingCompensation: -10
            )
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
        case .yosemiteClassic: return searchVerticalInset
        }
    }

    var searchTextColor: NSColor {
        switch design {
        case .minimal:
            return isDark
                ? NSColor.white.withAlphaComponent(0.82)
                : NSColor.black
        case .liquidGlass:
            return isDark ? .white : .black
        case .yosemiteClassic:
            return .labelColor
        }
    }

    var searchIconColor: NSColor {
        switch design {
        case .minimal, .liquidGlass:
            return isDark
                ? NSColor.white.withAlphaComponent(0.85)
                : NSColor.black.withAlphaComponent(0.85)
        case .yosemiteClassic:
            return .labelColor
        }
    }

    var headerSeparatorColor: NSColor {
        guard design != .yosemiteClassic else { return .clear }
        return isDark
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.black.withAlphaComponent(0.25)
    }

    var showsHeaderSeparator: Bool { design != .yosemiteClassic }

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
        case .yosemiteClassic: 2
        }
    }

    func surfaceCornerRadius(panelHeight: CGFloat) -> CGFloat {
        guard design == .liquidGlass, panelHeight > searchHeight + 0.5 else {
            return cornerRadius
        }
        return LauncherLiquidGlassMetrics.expandedCornerRadius
    }

    func displayedResultCount(for resultCount: Int) -> Int {
        min(max(0, resultCount), visibleResultCount)
    }

    func panelHeight(resultCount: Int) -> CGFloat {
        // Every theme grows by exactly the rows it displays. In particular, Classic must not
        // reserve a three-row preview canvas for one result: that creates an empty viewport
        // and makes query changes look like the whole launcher is jumping.
        let displayedRows = displayedResultCount(for: resultCount)
        // NSTableView reserves its vertical intercell spacing after every row, including the
        // last one. Keep the visual bottom inset outside the scroll viewport so the viewport
        // itself is always exactly the height of its document.
        let spacing = CGFloat(displayedRows) * rowSpacing
        let hasResults = displayedRows > 0
        return searchHeight
            + (hasResults ? resultTopInset : 0)
            + CGFloat(displayedRows) * rowHeight
            + spacing
            + (hasResults ? resultBottomInset : 0)
    }

    func resultsDocumentHeight(resultCount: Int) -> CGFloat {
        let displayedRows = displayedResultCount(for: resultCount)
        return CGFloat(displayedRows) * (rowHeight + rowSpacing)
    }

    func resultsViewportHeight(resultCount: Int) -> CGFloat {
        let displayedRows = displayedResultCount(for: resultCount)
        guard displayedRows > 0 else { return 0 }
        return max(
            0,
            panelHeight(resultCount: resultCount)
                - searchHeight
                - resultTopInset
                - resultBottomInset
        )
    }
}

@MainActor
final class LauncherThemeController {
    func descriptor(for preferences: LauncherAppearancePreferences) -> LauncherThemeDescriptor {
        descriptor(
            for: preferences,
            reducedTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
    }

    /// The explicit accessibility inputs keep the layout contract testable without changing
    /// the user's system settings. Accessibility can change material and color treatment, but
    /// never any geometry.
    func descriptor(
        for preferences: LauncherAppearancePreferences,
        reducedTransparency: Bool,
        increasedContrast contrast: Bool,
        resolvedSystemDark: Bool? = nil
    ) -> LauncherThemeDescriptor {
        let appearance: NSAppearance? = switch preferences.mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        let dark = preferences.mode == .dark
            || (preferences.mode == .system
                && (resolvedSystemDark
                    ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)))

        switch preferences.design {
        case .minimal:
            let surface: LauncherThemeDescriptor.Surface = reducedTransparency || contrast
                ? .opaque
                : .ultraThick
            return LauncherThemeDescriptor(
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
                showsPreview: false,
                previewWidth: 0,
                appearance: appearance,
                backgroundColor: dark
                    ? .black
                    : NSColor(calibratedWhite: 0.93, alpha: 1),
                glassTintColor: nil,
                selectionColor: .controlAccentColor,
                hasShadow: false,
                showsSubtitles: preferences.showsSubtitles,
                showsShortcuts: preferences.showsShortcuts,
                verticalPosition: CGFloat(preferences.verticalPosition),
                visibleResultCount: preferences.visibleResultCount
            )
        case .liquidGlass:
            let liquidSurface: LauncherThemeDescriptor.Surface
            if reducedTransparency || contrast {
                liquidSurface = .opaque
            } else if #available(macOS 26, *) {
                liquidSurface = .glass
            } else {
                liquidSurface = .vibrancy
            }
            return LauncherThemeDescriptor(
                design: .liquidGlass,
                isDark: dark,
                width: LauncherLiquidGlassMetrics.width,
                cornerRadius: LauncherLiquidGlassMetrics.compactCornerRadius,
                searchHeight: LauncherLiquidGlassMetrics.searchHeight,
                rowHeight: 56,
                searchFontSize: LauncherLiquidGlassMetrics.searchFontSize,
                searchHorizontalInset: LauncherLiquidGlassMetrics.searchHorizontalInset,
                searchVerticalInset: LauncherLiquidGlassMetrics.searchVerticalInset,
                resultHorizontalInset: 10,
                resultTopInset: 6,
                resultBottomInset: 8,
                rowSpacing: 0,
                surface: liquidSurface,
                showsPreview: false,
                previewWidth: 0,
                appearance: appearance,
                backgroundColor: dark ? NSColor(calibratedWhite: 0.035, alpha: 0.99) : NSColor(calibratedWhite: 0.99, alpha: 0.99),
                // Light Spotlight glass carries a restrained white wash so black labels remain
                // legible over varied wallpaper. Keep dark glass untinted and let it derive its
                // luminosity from the content behind the launcher.
                glassTintColor: dark
                    ? nil
                    : NSColor.white.withAlphaComponent(
                        LauncherLiquidGlassMetrics.lightGlassTintAlpha
                    ),
                // The selected result is an inset adaptive glass wash, not a saturated blue
                // table selection. Semantic label color keeps it neutral in both appearances.
                selectionColor: NSColor.labelColor.withAlphaComponent(contrast ? 0.24 : 0.11),
                // NSPanel shadows are rectangular for a borderless window and showed up as
                // a dark backplate around the rounded glass. The native glass edge supplies
                // the shape-aware separation from the desktop.
                hasShadow: false,
                showsSubtitles: preferences.showsSubtitles,
                showsShortcuts: preferences.showsShortcuts,
                verticalPosition: CGFloat(preferences.verticalPosition),
                visibleResultCount: preferences.visibleResultCount
            )
        case .yosemiteClassic:
            return LauncherThemeDescriptor(
                design: .yosemiteClassic,
                isDark: dark,
                width: 820,
                cornerRadius: 10,
                searchHeight: 68,
                rowHeight: 52,
                searchFontSize: 26,
                searchHorizontalInset: 16,
                // Keep the shared native search control vertically centered in the taller
                // classic header rather than stretching the control itself.
                searchVerticalInset: 17,
                resultHorizontalInset: 0,
                resultTopInset: 0,
                resultBottomInset: 0,
                rowSpacing: 0,
                surface: reducedTransparency ? .opaque : .classic,
                showsPreview: true,
                previewWidth: 310,
                appearance: appearance,
                backgroundColor: dark ? NSColor(calibratedWhite: 0.12, alpha: 0.96) : NSColor(calibratedWhite: 0.94, alpha: 0.96),
                glassTintColor: nil,
                selectionColor: .controlAccentColor,
                hasShadow: true,
                showsSubtitles: preferences.showsSubtitles,
                showsShortcuts: preferences.showsShortcuts,
                verticalPosition: CGFloat(preferences.verticalPosition),
                visibleResultCount: preferences.visibleResultCount
            )
        }
    }
}
