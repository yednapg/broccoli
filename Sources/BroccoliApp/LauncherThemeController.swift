@preconcurrency import AppKit

@MainActor
struct LauncherThemeDescriptor {
    enum Surface: Equatable {
        case opaque
        case vibrancy
        case glass
        case classic
    }

    let design: LauncherDesign
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
    let borderColor: NSColor
    let selectionColor: NSColor
    let hasShadow: Bool
    let showsSubtitles: Bool
    let showsShortcuts: Bool
    let verticalPosition: CGFloat
    let visibleResultCount: Int

    var resultTableStyle: NSTableView.Style {
        .fullWidth
    }

    var resultSelectionCornerRadius: CGFloat {
        switch design {
        case .minimal: 8
        case .liquidGlass: 12
        case .yosemiteClassic: 2
        }
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
            return LauncherThemeDescriptor(
                design: .minimal,
                width: 560,
                cornerRadius: 14,
                searchHeight: 58,
                rowHeight: 44,
                searchFontSize: 20,
                searchHorizontalInset: 14,
                searchVerticalInset: 12,
                resultHorizontalInset: 8,
                resultTopInset: 4,
                resultBottomInset: 8,
                rowSpacing: 2,
                surface: .opaque,
                showsPreview: false,
                previewWidth: 0,
                appearance: appearance,
                backgroundColor: dark
                    ? NSColor(calibratedWhite: 0.09, alpha: 0.98)
                    : NSColor(calibratedWhite: 0.97, alpha: 0.98),
                glassTintColor: nil,
                borderColor: contrast ? .separatorColor : NSColor.separatorColor.withAlphaComponent(0.62),
                selectionColor: .controlAccentColor,
                hasShadow: true,
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
                width: 640,
                cornerRadius: 29,
                searchHeight: 58,
                rowHeight: 56,
                // Match Spotlight's 58-point capsule as one optical system: a 26-point
                // query, a 24-point magnifier, and a 44-point native editing control.
                searchFontSize: 26,
                searchHorizontalInset: 22,
                searchVerticalInset: 7,
                resultHorizontalInset: 10,
                resultTopInset: 6,
                resultBottomInset: 8,
                rowSpacing: 0,
                surface: liquidSurface,
                showsPreview: false,
                previewWidth: 0,
                appearance: appearance,
                backgroundColor: dark ? NSColor(calibratedWhite: 0.035, alpha: 0.99) : NSColor(calibratedWhite: 0.99, alpha: 0.99),
                // Let regular Liquid Glass derive its luminosity and color from the content
                // behind the launcher. Tinting the entire surface turns it into a dark HUD and
                // prevents the adaptive material from reading as glass.
                glassTintColor: nil,
                borderColor: contrast ? .labelColor : NSColor.white.withAlphaComponent(dark ? 0.22 : 0.62),
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
                width: 820,
                cornerRadius: 10,
                searchHeight: 68,
                rowHeight: 52,
                searchFontSize: 29,
                searchHorizontalInset: 12,
                searchVerticalInset: 10,
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
                borderColor: contrast ? .labelColor : NSColor.separatorColor.withAlphaComponent(0.7),
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
