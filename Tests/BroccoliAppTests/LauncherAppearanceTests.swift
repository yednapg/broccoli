import AppKit
import ServiceManagement
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherAppearanceTests: XCTestCase {
    func testThemeGeometryAtSupportedResultCounts() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            for visibleCount in [3, 7, 10] {
                var preferences = LauncherAppearancePreferences.defaults(design: design)
                preferences.visibleResultCount = visibleCount
                let descriptor = controller.descriptor(for: preferences)

                for resultCount in 0...(visibleCount + 2) {
                    let displayedRows = min(resultCount, visibleCount)
                    let documentHeight = CGFloat(displayedRows)
                        * (descriptor.rowHeight + descriptor.rowSpacing)
                    let expectedHeight = descriptor.searchHeight
                        + (displayedRows > 0 ? descriptor.resultTopInset : 0)
                        + documentHeight
                        + (displayedRows > 0 ? descriptor.resultBottomInset : 0)

                    XCTAssertEqual(
                        descriptor.panelHeight(resultCount: resultCount),
                        expectedHeight,
                        accuracy: 0.001,
                        "\(design) must size exactly to \(displayedRows) visible rows"
                    )
                    XCTAssertEqual(
                        descriptor.resultsViewportHeight(resultCount: resultCount),
                        descriptor.resultsDocumentHeight(resultCount: resultCount),
                        accuracy: 0.001,
                        "\(design) must not leave an empty table viewport"
                    )
                }
            }
        }
    }

    func testAppKitTableGeometryMatchesThemeWithoutScrollableOverflow() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            for count in [3, 7, 10] {
                var preferences = LauncherAppearancePreferences.defaults(design: design)
                preferences.visibleResultCount = count
                let descriptor = controller.descriptor(for: preferences)
                let rows = TableRows(count: count)
                let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 500, height: 1_000))
                table.addTableColumn(NSTableColumn(identifier: .init("result")))
                table.headerView = nil
                table.style = .fullWidth
                table.rowSizeStyle = .custom
                table.usesAutomaticRowHeights = false
                table.rowHeight = descriptor.rowHeight
                table.intercellSpacing = NSSize(width: 0, height: descriptor.rowSpacing)
                table.dataSource = rows
                table.reloadData()

                let actualDocumentHeight = table.rect(ofRow: count - 1).maxY
                XCTAssertEqual(
                    actualDocumentHeight,
                    descriptor.resultsDocumentHeight(resultCount: count),
                    accuracy: 0.001,
                    "\(design) AppKit row geometry must match the fixed viewport"
                )
                XCTAssertEqual(
                    actualDocumentHeight,
                    descriptor.resultsViewportHeight(resultCount: count),
                    accuracy: 0.001
                )
            }
        }
    }

    func testLockedThemeGeometry() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()
        let minimal = controller.descriptor(for: .defaults(design: .minimal))
        let glass = controller.descriptor(for: .defaults(design: .liquidGlass))
        let classic = controller.descriptor(for: .defaults(design: .yosemiteClassic))

        XCTAssertEqual(minimal.width, 560)
        XCTAssertEqual(minimal.rowHeight, 44)
        XCTAssertEqual(minimal.cornerRadius, 14)
        XCTAssertEqual(minimal.searchFontSize, 20)
        XCTAssertEqual(minimal.resultSelectionCornerRadius, 8)
        XCTAssertEqual(minimal.resultTableStyle, .fullWidth)
        XCTAssertEqual(glass.width, 640)
        XCTAssertEqual(glass.searchHeight, 58)
        XCTAssertEqual(glass.searchFontSize, 26)
        XCTAssertEqual(glass.searchHorizontalInset, 22)
        XCTAssertEqual(glass.searchVerticalInset, 7)
        XCTAssertEqual(glass.searchHeight - glass.searchVerticalInset * 2, 44)
        XCTAssertEqual(LauncherLiquidGlassSurfaceView.collapsedHeight, 58)
        XCTAssertEqual(LauncherLiquidGlassSurfaceView.expandedCornerRadius, 29)
        XCTAssertEqual(glass.rowHeight, 56)
        XCTAssertEqual(glass.rowSpacing, 0)
        XCTAssertEqual(glass.cornerRadius, 29)
        XCTAssertFalse(glass.hasShadow)
        XCTAssertEqual(glass.resultSelectionCornerRadius, 12)
        XCTAssertEqual(glass.resultTableStyle, .fullWidth)
        XCTAssertEqual(classic.width, 820)
        XCTAssertEqual(classic.rowHeight, 52)
        XCTAssertEqual(classic.panelHeight(resultCount: 0), classic.searchHeight)
        XCTAssertEqual(classic.panelHeight(resultCount: 1), classic.searchHeight + classic.rowHeight)
        XCTAssertEqual(classic.panelHeight(resultCount: 20), classic.searchHeight + 7 * classic.rowHeight)
    }

    func testBorderlessNativeSearchEditorUsesAppKitSearchTextBounds() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 58),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let field = LauncherNativeSearchField(
            frame: NSRect(x: 22, y: 7, width: 596, height: 44)
        )
        LauncherNativeSearchFieldStyle.apply(to: field)
        field.isBezeled = false
        field.drawsBackground = false
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        XCTAssertTrue(window.makeFirstResponder(field))
        field.alignFieldEditorToSearchTextBounds()

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let clipView = try XCTUnwrap(editor.superview as? NSClipView)
        XCTAssertEqual(clipView.frame, field.searchTextBounds.integral)
        XCTAssertEqual(editor.frame.origin, .zero)
        XCTAssertEqual(editor.frame.size, field.searchTextBounds.integral.size)
        XCTAssertGreaterThan(clipView.frame.minX, field.searchButtonBounds.minX)
        XCTAssertEqual(field.searchButtonBounds.size, NSSize(width: 24, height: 24))
        XCTAssertEqual(
            field.searchTextBounds.minX - field.searchButtonBounds.maxX,
            LauncherSearchGeometry.symbolTextGap
        )
        XCTAssertEqual(field.font?.pointSize, 26)
        XCTAssertTrue(field.cell is LauncherNativeSearchFieldCell)
    }

    func testResultCountChangesPreservePanelTopEdge() {
        _ = NSApplication.shared
        let descriptor = LauncherThemeController().descriptor(
            for: .defaults(design: .liquidGlass)
        )
        let screen = NSRect(x: 0, y: 48, width: 1_920, height: 1_032)
        var frame = LauncherPanelGeometry.positionedFrame(
            in: screen,
            preferredWidth: descriptor.width,
            height: descriptor.panelHeight(resultCount: 0),
            verticalPosition: descriptor.verticalPosition
        )
        let fixedTopEdge = frame.maxY

        for resultCount in [1, 7, 2, 10, 0, 3] {
            frame = LauncherPanelGeometry.resizing(
                frame,
                toHeight: descriptor.panelHeight(resultCount: resultCount)
            )
            XCTAssertEqual(frame.maxY, fixedTopEdge, accuracy: 0.001)
        }
    }

    func testReduceTransparencyChangesMaterialWithoutChangingGeometry() {
        _ = NSApplication.shared
        let controller = LauncherThemeController()

        for design in LauncherDesign.allCases {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            let standard = controller.descriptor(
                for: preferences,
                reducedTransparency: false,
                increasedContrast: false
            )
            let reduced = controller.descriptor(
                for: preferences,
                reducedTransparency: true,
                increasedContrast: false
            )

            assertSameGeometry(standard, reduced, design: design)
            if design == .liquidGlass || design == .yosemiteClassic {
                XCTAssertEqual(reduced.surface, .opaque)
                XCTAssertNotEqual(standard.surface, reduced.surface)
            }
        }
    }

    func testFreshAndExistingInstallDesignMigration() {
        let freshDefaults = makeDefaults()
        let fresh = AppPreferences(defaults: freshDefaults)
        XCTAssertEqual(fresh.appearance.design, .liquidGlass)

        let existingDefaults = makeDefaults()
        existingDefaults.set(true, forKey: "onboarding.completed")
        let existing = AppPreferences(defaults: existingDefaults)
        XCTAssertEqual(existing.appearance.design, .minimal)
    }

    func testAppearanceSanitizationMatchesSettingsVerticalPositionRange() {
        var preferences = LauncherAppearancePreferences.defaults()
        preferences.verticalPosition = -1
        preferences.sanitize()
        XCTAssertEqual(preferences.verticalPosition, 0.05)

        preferences.verticalPosition = 0.8
        preferences.sanitize()
        XCTAssertEqual(preferences.verticalPosition, 0.5)
    }

    func testAppDefaultsShowRecentSelectionsForAnEmptyQuery() {
        let preferences = AppPreferences(defaults: makeDefaults())
        XCTAssertTrue(preferences.recentItemsEnabled)
        XCTAssertTrue(preferences.searchPreferences.recentItemsEnabled)
    }

    func testMenuBarVisibilityDefaultsOnAndPersistsUserChoice() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.menuBarIconEnabled)

        preferences.menuBarIconEnabled = false

        XCTAssertFalse(AppPreferences(defaults: defaults).menuBarIconEnabled)
    }

    func testOnboardingNeutralizesUnavailableLaunchAtLogin() {
        let unavailable = LaunchAtLoginAvailability(status: .notFound)
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertFalse(unavailable.isAvailable)

        let notRegistered = LaunchAtLoginAvailability(status: .notRegistered)
        XCTAssertFalse(notRegistered.isEnabled)
        XCTAssertTrue(notRegistered.isAvailable)

        let enabled = LaunchAtLoginAvailability(status: .enabled)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.isAvailable)

        let requiresApproval = LaunchAtLoginAvailability(status: .requiresApproval)
        XCTAssertFalse(requiresApproval.isEnabled)
        XCTAssertTrue(requiresApproval.isAvailable)
    }

    func testAppearancePersistsWithoutRestart() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)
        var changed = preferences.appearance
        changed.design = .yosemiteClassic
        changed.mode = .dark
        changed.visibleResultCount = 10
        preferences.appearance = changed

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, changed)
    }

    func testCalculatorPreferenceMigrationPreservesOldEnablement() throws {
        let defaults = makeDefaults()
        let oldValue = try PropertyListSerialization.data(
            fromPropertyList: ["enabled": false],
            format: .binary,
            options: 0
        )
        defaults.set(oldValue, forKey: "calculator.configuration.v1")

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.calculator.enabled)
        XCTAssertEqual(preferences.calculator.significantDigits, 12)
        XCTAssertFalse(preferences.calculator.usesGroupingSeparator)
    }

    func testSettingsSearchMatchesNavigationTerms() {
        XCTAssertTrue(PreferencesSection.appearance.matches(settingsQuery: "liquid"))
        XCTAssertTrue(PreferencesSection.general.matches(settingsQuery: "hotkey"))
        let menuBar = SettingsSearchItem.all.first { $0.id == "menu-bar" }
        XCTAssertEqual(menuBar?.destination, .section(.general))
        XCTAssertTrue(menuBar?.matches("menu bar") == true)
        XCTAssertTrue(menuBar?.matches("hide") == true)
        XCTAssertTrue(PreferencesSection.privacy.matches(settingsQuery: "automation"))
        XCTAssertFalse(PreferencesSection.about.matches(settingsQuery: "clipboard"))
    }

    func testSettingsToolbarTitleTracksSearchState() {
        XCTAssertEqual(
            SettingsToolbarPresentation.title(destinationTitle: "Appearance", searchQuery: ""),
            "Appearance"
        )
        XCTAssertEqual(
            SettingsToolbarPresentation.title(destinationTitle: "Appearance", searchQuery: "   \n"),
            "Appearance"
        )
        XCTAssertEqual(
            SettingsToolbarPresentation.title(destinationTitle: "Appearance", searchQuery: "preview"),
            "Search"
        )
    }

    func testSettingsSearchFieldUsesLargeNativeSystemGeometry() {
        let searchField = SettingsSearchField(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        SettingsSearchFieldStyle.apply(to: searchField)

        XCTAssertEqual(SettingsSearchFieldStyle.height, 30)
        XCTAssertEqual(SettingsSearchFieldStyle.cornerRadius, 15)
        XCTAssertEqual(SettingsSearchFieldStyle.horizontalInset, 6)
        XCTAssertEqual(SettingsSearchFieldStyle.topInset, 8)
        XCTAssertEqual(SettingsSearchFieldStyle.bottomInset, 8)
        XCTAssertEqual(searchField.controlSize, .large)
        XCTAssertFalse(searchField.isBezeled)
        XCTAssertFalse(searchField.drawsBackground)
        XCTAssertTrue(searchField.isEditable)
        XCTAssertTrue(searchField.isSelectable)
        XCTAssertEqual(searchField.focusRingType, .none)
        XCTAssertEqual(searchField.font?.pointSize, 13)
        guard let cell = searchField.cell as? NSSearchFieldCell else {
            return XCTFail("NSSearchField must keep its native search cell")
        }
        let geometry = SettingsSearchGeometry(bounds: searchField.bounds)
        XCTAssertEqual(geometry.searchSymbolInkRect, NSRect(x: 10, y: 8.5, width: 13, height: 13))
        XCTAssertEqual(geometry.searchButtonRect, NSRect(x: 12, y: 7, width: 13, height: 13))
        XCTAssertEqual(SettingsSearchGeometry.textLineHeight, 16)
        XCTAssertEqual(geometry.searchTextRect, NSRect(x: 30, y: 7, width: 121, height: 16))
        XCTAssertEqual(geometry.cancelSymbolInkRect, NSRect(x: 157, y: 8.5, width: 13, height: 13))
        XCTAssertEqual(geometry.cancelButtonRect, NSRect(x: 155, y: 7, width: 13, height: 13))
        XCTAssertEqual(cell.searchButtonRect(forBounds: searchField.bounds), geometry.searchButtonRect)
        XCTAssertEqual(cell.searchTextRect(forBounds: searchField.bounds), geometry.searchTextRect)
        XCTAssertEqual(cell.cancelButtonRect(forBounds: searchField.bounds), geometry.cancelButtonRect)
        XCTAssertEqual(cell.titleRect(forBounds: searchField.bounds), geometry.searchTextRect)
        XCTAssertEqual(searchField.searchButtonBounds, geometry.searchButtonRect)
        XCTAssertEqual(searchField.searchTextBounds, geometry.searchTextRect)
        XCTAssertEqual(searchField.cancelButtonBounds, geometry.cancelButtonRect)
        XCTAssertEqual(cell.searchButtonCell?.image?.size, NSSize(width: 13, height: 13))
        XCTAssertEqual(searchField.accessibilitySubrole(), .searchField)
        XCTAssertTrue(searchField.sendsSearchStringImmediately)
        XCTAssertFalse(searchField.sendsWholeSearchString)
    }

    func testSettingsSearchGeometryUsesOneCenteredGridAtEveryWidth() {
        for width in [180.0, 204.0, 320.0] {
            let bounds = NSRect(x: 0, y: 0, width: width, height: SettingsSearchGeometry.height)
            let geometry = SettingsSearchGeometry(bounds: bounds)

            XCTAssertEqual(geometry.searchSymbolInkRect.minX, SettingsSearchGeometry.leadingInset)
            XCTAssertEqual(geometry.searchSymbolInkRect.midY, bounds.midY)
            XCTAssertEqual(
                geometry.searchTextRect.minX,
                geometry.searchSymbolInkRect.maxX
                    + SettingsSearchGeometry.symbolTextGap
                    + SettingsSearchGeometry.textCellLeadingBearing
            )
            XCTAssertEqual(geometry.searchTextRect.midY, bounds.midY)
            XCTAssertEqual(geometry.cancelSymbolInkRect.midY, bounds.midY)
            XCTAssertEqual(
                bounds.maxX - geometry.cancelSymbolInkRect.maxX,
                SettingsSearchGeometry.trailingInset
            )
            XCTAssertEqual(
                geometry.cancelSymbolInkRect.minX - geometry.searchTextRect.maxX,
                SettingsSearchGeometry.symbolTextGap
            )
        }
    }

    @MainActor
    func testSettingsSearchContainerOwnsFullHeightSurfaceAndNativeField() {
        let container = SettingsSearchFieldContainerView(
            frame: NSRect(x: 0, y: 0, width: 204, height: SettingsSearchFieldStyle.height)
        )

        XCTAssertEqual(container.searchField.controlSize, .large)
        XCTAssertFalse(container.searchField.isBezeled)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertEqual(container.layer?.cornerRadius, SettingsSearchFieldStyle.cornerRadius)
        XCTAssertEqual(container.intrinsicContentSize.height, SettingsSearchFieldStyle.height)
        container.setFocusAppearance(focused: false)
        XCTAssertEqual(container.surfaceBorderWidth, 1)
        container.setFocusAppearance(focused: true)
        XCTAssertEqual(container.surfaceBorderWidth, 1)
    }

    func testSettingsShellUsesFixedNativeSplitGeometry() {
        XCTAssertEqual(SettingsShellLayout.sidebarWidth, 256)
        XCTAssertEqual(SettingsShellLayout.contentWidth, 760)
        XCTAssertEqual(SettingsShellLayout.detailMinimumWidth, 503)
        XCTAssertEqual(
            SettingsShellLayout.sidebarWidth
                + SettingsShellLayout.splitDividerWidth
                + SettingsShellLayout.detailMinimumWidth,
            SettingsShellLayout.contentWidth
        )
        XCTAssertEqual(SettingsWindowGeometry.initialContentSize.width, 760)
        XCTAssertEqual(SettingsWindowGeometry.minimumContentSize.width, 760)
        XCTAssertEqual(SettingsWindowGeometry.maximumContentSize.width, 760)
        XCTAssertTrue(SettingsWindowGeometry.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(SettingsWindowGeometry.collectionBehavior.contains(.fullScreenDisallowsTiling))

        let detailItem = NSSplitViewItem(viewController: NSViewController())
        SettingsShellLayout.lockDetailWidth(detailItem)
        XCTAssertEqual(detailItem.minimumThickness, 503)
        XCTAssertEqual(detailItem.maximumThickness, 503)
    }

    func testSettingsWindowGeometryPinsLiveAndZoomResizeWidth() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowGeometry.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        for proposedFrameSize in [
            NSSize(width: 520, height: 700),
            NSSize(width: 1_400, height: 900),
        ] {
            let constrainedFrameSize = SettingsWindowGeometry.constrainedFrameSize(
                proposedFrameSize,
                for: window
            )
            let constrainedContentSize = window.contentRect(
                forFrameRect: NSRect(origin: .zero, size: constrainedFrameSize)
            ).size

            XCTAssertEqual(constrainedContentSize.width, SettingsShellLayout.contentWidth)
        }
    }

    func testSettingsWindowGeometryPreservesVerticalResizingWithinBounds() {
        XCTAssertEqual(
            SettingsWindowGeometry.constrainedContentSize(NSSize(width: 1_400, height: 725)),
            NSSize(width: SettingsShellLayout.contentWidth, height: 725)
        )
        XCTAssertEqual(
            SettingsWindowGeometry.constrainedContentSize(NSSize(width: 520, height: 320)),
            SettingsWindowGeometry.minimumContentSize
        )
    }

    func testLauncherVisibilitySessionTemporarilySuppressesOnlyOtherVisibleWindows() {
        let launcher = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        let settings = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        let alreadyHidden = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        defer {
            launcher.orderOut(nil)
            settings.orderOut(nil)
            alreadyHidden.orderOut(nil)
        }

        launcher.orderFront(nil)
        settings.orderFront(nil)
        XCTAssertTrue(launcher.isVisible)
        XCTAssertTrue(settings.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)

        let session = LauncherWindowVisibilitySession()
        session.suppress(
            windows: [settings, alreadyHidden, launcher],
            excluding: launcher
        )

        XCTAssertTrue(launcher.isVisible)
        XCTAssertFalse(settings.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)
        XCTAssertEqual(session.suppressedWindowCount, 1)

        session.restore()
        XCTAssertTrue(settings.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)
        XCTAssertEqual(session.suppressedWindowCount, 0)
    }

    func testLauncherVisibilitySessionKeepsTheForegroundBroccoliWindowVisible() {
        let launcher = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        let foregroundSettings = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        let backgroundBroccoliWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 140),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        defer {
            launcher.orderOut(nil)
            foregroundSettings.orderOut(nil)
            backgroundBroccoliWindow.orderOut(nil)
        }

        launcher.orderFront(nil)
        backgroundBroccoliWindow.orderFront(nil)
        foregroundSettings.orderFront(nil)

        let session = LauncherWindowVisibilitySession()
        session.suppress(
            windows: [foregroundSettings, backgroundBroccoliWindow, launcher],
            excluding: launcher,
            preserving: foregroundSettings
        )

        XCTAssertTrue(launcher.isVisible)
        XCTAssertTrue(foregroundSettings.isVisible)
        XCTAssertFalse(backgroundBroccoliWindow.isVisible)
        XCTAssertEqual(session.suppressedWindowCount, 1)

        session.restore()
        XCTAssertTrue(foregroundSettings.isVisible)
        XCTAssertTrue(backgroundBroccoliWindow.isVisible)
    }

    func testSettingsFindShortcutAllowsCapsLockButRejectsOtherModifiers() {
        XCTAssertTrue(SettingsKeyboardShortcut.isFind(
            modifierFlags: .command,
            charactersIgnoringModifiers: "f"
        ))
        XCTAssertTrue(SettingsKeyboardShortcut.isFind(
            modifierFlags: [.command, .capsLock],
            charactersIgnoringModifiers: "F"
        ))

        for flags: NSEvent.ModifierFlags in [
            [.command, .shift],
            [.command, .option],
            [.command, .control],
            [.command, .function],
        ] {
            XCTAssertFalse(SettingsKeyboardShortcut.isFind(
                modifierFlags: flags,
                charactersIgnoringModifiers: "f"
            ))
        }
        XCTAssertFalse(SettingsKeyboardShortcut.isFind(
            modifierFlags: .command,
            charactersIgnoringModifiers: "g"
        ))
    }

    func testIgnoredApplicationSelectionCopyPluralizesImmediateResult() {
        XCTAssertNil(IgnoredApplicationsCopy.invalidSelectionMessage(count: 0))
        XCTAssertEqual(
            IgnoredApplicationsCopy.invalidSelectionMessage(count: 1),
            "1 selected application did not provide a valid bundle identifier and was not added."
        )
        XCTAssertEqual(
            IgnoredApplicationsCopy.invalidSelectionMessage(count: 2),
            "2 selected applications did not provide a valid bundle identifier and were not added."
        )
    }

    func testClipboardConsentUsesConfiguredRetentionCopy() {
        XCTAssertEqual(ClipboardConsentCopy.retentionTitle(days: 1), "1-Day Retention")
        XCTAssertEqual(ClipboardConsentCopy.retentionTitle(days: 7), "7-Day Retention")
        XCTAssertEqual(ClipboardConsentCopy.retentionTitle(days: 30), "30-Day Retention")
    }

    func testSettingsShellKeepsToolbarHistoryAndSelectionSynchronized() {
        let shell = SettingsShellModel()

        XCTAssertEqual(shell.selection, .general)
        XCTAssertEqual(shell.destination, .section(.general))
        XCTAssertEqual(shell.toolbarTitle, "General")
        XCTAssertFalse(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)

        shell.navigate(to: .launcherPreview)
        XCTAssertEqual(shell.selection, .appearance)
        XCTAssertEqual(shell.destination, .launcherPreview)
        XCTAssertEqual(shell.toolbarTitle, "Launcher Preview")
        XCTAssertTrue(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)

        shell.goBack()
        XCTAssertEqual(shell.destination, .section(.general))
        XCTAssertFalse(shell.canGoBack)
        XCTAssertTrue(shell.canGoForward)

        shell.goForward()
        XCTAssertEqual(shell.destination, .launcherPreview)
        XCTAssertTrue(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)
    }

    func testSettingsShellSearchOwnsToolbarTitleAndSectionReset() {
        let shell = SettingsShellModel()
        let initialFocusRequest = shell.searchFocusRequest

        shell.searchQuery = "preview"
        XCTAssertEqual(shell.toolbarTitle, "Search")

        shell.focusSearch()
        XCTAssertEqual(shell.searchFocusRequest, initialFocusRequest + 1)

        shell.navigate(to: .launcherPreview)
        shell.selectSection(.files)
        XCTAssertEqual(shell.searchQuery, "")
        XCTAssertEqual(shell.selection, .files)
        XCTAssertEqual(shell.destination, .section(.files))
        XCTAssertEqual(shell.toolbarTitle, "Files")
        XCTAssertFalse(shell.canGoBack)
        XCTAssertFalse(shell.canGoForward)
    }

    func testSettingsShellNativeSearchClearsSidebarSelectionAndCancelsInTwoStages() {
        let shell = SettingsShellModel()

        XCTAssertEqual(shell.sidebarSelection, .general)
        XCTAssertFalse(shell.cancelSearch())

        shell.searchQuery = "preview"
        XCTAssertNil(shell.sidebarSelection)
        XCTAssertEqual(shell.toolbarTitle, "Search")
        XCTAssertTrue(shell.cancelSearch())

        XCTAssertEqual(shell.searchQuery, "")
        XCTAssertEqual(shell.sidebarSelection, .general)
        XCTAssertEqual(shell.toolbarTitle, "General")
        XCTAssertFalse(shell.cancelSearch())
    }

    func testApplicationMenuClosesSettingsWithoutQuittingBackgroundLauncher() {
        _ = NSApplication.shared
        let menu = BroccoliApplicationMenu.make(target: NSObject())
        let applicationMenu = menu.items.first?.submenu
        let close = applicationMenu?.items.first(where: { $0.title == "Close Settings" })
        let settings = applicationMenu?.items.first(where: { $0.title == "Settings…" })

        XCTAssertNil(applicationMenu?.items.first(where: { $0.title == "Quit Broccoli" }))
        XCTAssertEqual(close?.keyEquivalent, "q")
        XCTAssertEqual(close?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(settings?.keyEquivalent, ",")
        XCTAssertEqual(settings?.keyEquivalentModifierMask, .command)
    }

    func testSettingsCloseDoesNotRestoreAccessoryPolicyDuringTermination() {
        var lifecycle = ApplicationLifecycleState()
        XCTAssertTrue(lifecycle.shouldReturnToAccessoryAfterSettingsClose)

        lifecycle.beginTermination()

        XCTAssertTrue(lifecycle.isTerminating)
        XCTAssertFalse(lifecycle.shouldReturnToAccessoryAfterSettingsClose)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "BroccoliAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func assertSameGeometry(
        _ lhs: LauncherThemeDescriptor,
        _ rhs: LauncherThemeDescriptor,
        design: LauncherDesign,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.width, rhs.width, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.cornerRadius, rhs.cornerRadius, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchHeight, rhs.searchHeight, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.rowHeight, rhs.rowHeight, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchHorizontalInset, rhs.searchHorizontalInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.searchVerticalInset, rhs.searchVerticalInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.resultHorizontalInset, rhs.resultHorizontalInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.resultTopInset, rhs.resultTopInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.resultBottomInset, rhs.resultBottomInset, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.rowSpacing, rhs.rowSpacing, "\(design)", file: file, line: line)
        XCTAssertEqual(lhs.previewWidth, rhs.previewWidth, "\(design)", file: file, line: line)
    }
}

private final class TableRows: NSObject, NSTableViewDataSource {
    let count: Int
    init(count: Int) { self.count = count }
    func numberOfRows(in tableView: NSTableView) -> Int { count }
}
