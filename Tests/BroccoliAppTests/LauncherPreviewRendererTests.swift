import AppKit
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherPreviewRendererTests: XCTestCase {
    func testCompactAndExpandedPreviewsShareCornerAndMaterialConfiguration() throws {
        _ = NSApplication.shared
        for mode in [LauncherAppearanceMode.light, .dark] {
            var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
            preferences.mode = mode
            let theme = LauncherThemeController().descriptor(for: preferences)
            var compactRadius: CGFloat?
            for count in [0, 1, 3] {
                let preview = LauncherPreviewContentView(descriptor: theme,
                    fixture: .init(query: "screen", results: Array(LauncherPreviewFixture.standard.results.prefix(count))),
                    iconProvider: quietIconProvider(), interactive: true)
                preview.prepareForCapture()
                let surface = try XCTUnwrap(preview.subviews.first as? LauncherLiquidGlassSurfaceView)
                let material = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSVisualEffectView }.first)
                if count == 0 { compactRadius = LauncherLiquidGlassSurfaceView.cornerRadius }
                XCTAssertEqual(LauncherLiquidGlassSurfaceView.cornerRadius, try XCTUnwrap(compactRadius))
                XCTAssertEqual(material.isHidden, mode == .dark)
                XCTAssertEqual(material.state, mode == .dark ? .inactive : .active)
                XCTAssertEqual(surface.usesDarkBackdrop, mode == .dark)
                XCTAssertEqual(
                    LauncherAdditiveInk.isApplied(to: preview.previewSearchField),
                    mode == .dark,
                    "The preview composites Dark ink the same way as the launcher"
                )
                XCTAssertEqual(material.blendingMode, .behindWindow)
                XCTAssertFalse(material.wantsLayer)
                XCTAssertEqual(material.maskImage?.capInsets.top, compactRadius)
                XCTAssertEqual(material.alphaValue, 1)
                XCTAssertEqual(material.frame.size, preview.frame.size)
                XCTAssertEqual(material.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                               mode == .dark ? .darkAqua : .aqua)
            }
        }
    }

    func testStatusRowPreviewAndLauncherMatchAnOrdinaryResultRow() throws {
        _ = NSApplication.shared
        let results = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .incomplete, hasVisibleQuery: true,
            noMatch: .inlineStatus, limit: 7)
        for mode in [LauncherAppearanceMode.light, .dark] {
            var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
            preferences.mode = mode
            let theme = LauncherThemeController().descriptor(for: preferences)
            let preview = LauncherPreviewContentView(descriptor: theme,
                fixture: .init(query: "unmatched", results: results),
                iconProvider: quietIconProvider(), interactive: true)
            preview.prepareForCapture()
            let normal = LauncherPreviewContentView(descriptor: theme,
                fixture: .init(query: "screen", results: Array(LauncherPreviewFixture.standard.results.prefix(1))),
                iconProvider: quietIconProvider(), interactive: true)
            normal.prepareForCapture()
            XCTAssertEqual(preview.frame, normal.frame)
            XCTAssertEqual(preview.tableDocumentFrame, normal.tableDocumentFrame)
            XCTAssertEqual(preview.renderMetrics.resultsViewportHeight, theme.rowHeight)
            let controller = LauncherPanelController()
            controller.applyAppearance(preferences)
            controller.setMode(.main, initialQuery: "1+")
            controller.apply(results)
            XCTAssertEqual(controller.currentPanelHeight, theme.searchHeight)
            XCTAssertFalse(controller.isResultViewportVisible)
        }
    }

    private func quietIconProvider() -> LauncherPreviewIconProvider {
        // Cache-lifecycle tests control icon arrivals explicitly; filesystem timing must not
        // randomly invalidate the snapshots under test.
        LauncherPreviewIconProvider(iconCache: IconCache(
            systemSettingsIconStore: SystemSettingsNativeIconStore { _, _ in
                .init(iconsByKey: [:], extensionIndexSucceeded: false)
            }, startsNativeIconResolution: false, applicationIconOperation: { _, _ in nil }))
    }

    func testFixtureUsesRealSearchModelsAcrossProductionResultKinds() {
        let fixture = LauncherPreviewFixture.standard

        XCTAssertEqual(fixture.query, "screen")
        XCTAssertEqual(fixture.results.count, 3)
        XCTAssertEqual(fixture.results.map(\.entry.kind), [.application, .systemSetting, .action])
        XCTAssertEqual(fixture.results.map(\.entry.id), [
            "preview:application:screen-sharing",
            "setting:com.apple.ScreenSaver-Settings.extension",
            "action:screensaver.start",
        ])
    }

    func testCacheKeyIncludesOnlySpecifiedThemeAndAccessibilityInputs() {
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .dark
        let normal = LauncherPreviewCacheKey(
            design: preferences.design,
            appearance: preferences.mode,
            environment: .init(reducesTransparency: false, increasesContrast: false)
        )
        let reduced = LauncherPreviewCacheKey(
            design: preferences.design,
            appearance: preferences.mode,
            environment: .init(reducesTransparency: true, increasesContrast: false)
        )
        let contrast = LauncherPreviewCacheKey(
            design: preferences.design,
            appearance: preferences.mode,
            environment: .init(reducesTransparency: false, increasesContrast: true)
        )

        XCTAssertNotEqual(normal, reduced)
        XCTAssertNotEqual(normal, contrast)

        preferences.visibleResultCount = 10
        preferences.showsSubtitles = false
        preferences.showsShortcuts = false
        XCTAssertEqual(
            normal,
            LauncherPreviewCacheKey(
                design: preferences.design,
                appearance: preferences.mode,
                environment: .init(reducesTransparency: false, increasesContrast: false)
            )
        )
    }

    func testCacheKeyTracksResolvedAppearanceOnlyForSystemMode() {
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let lightEnvironment = LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .light
        )
        let darkEnvironment = LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .dark
        )

        preferences.mode = .system
        XCTAssertNotEqual(
            LauncherPreviewCacheKey(
                design: preferences.design,
                appearance: preferences.mode,
                environment: lightEnvironment
            ),
            LauncherPreviewCacheKey(
                design: preferences.design,
                appearance: preferences.mode,
                environment: darkEnvironment
            )
        )

        preferences.mode = .dark
        XCTAssertEqual(
            LauncherPreviewCacheKey(
                design: preferences.design,
                appearance: preferences.mode,
                environment: lightEnvironment
            ),
            LauncherPreviewCacheKey(
                design: preferences.design,
                appearance: preferences.mode,
                environment: darkEnvironment
            )
        )
    }

    func testRendererOnlyCapturesDuringSettingsSessionAndClearsOnClose() async {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        let preferences = LauncherAppearancePreferences.defaults(design: .minimal)

        let imageBeforeOpening = await renderer.image(for: preferences)
        XCTAssertNil(imageBeforeOpening)
        renderer.beginSettingsSession()
        let image = await renderer.image(for: preferences)
        XCTAssertNotNil(image)
        XCTAssertEqual(renderer.cachedImageCount, 1)
        XCTAssertTrue(renderer.cachedImage(for: preferences) === image)

        renderer.endSettingsSession()
        XCTAssertFalse(renderer.isSettingsSessionActive)
        XCTAssertEqual(renderer.cachedImageCount, 0)
        XCTAssertEqual(renderer.cachedImageCost, 0)
        XCTAssertNil(renderer.cachedImage(for: preferences))
        let imageAfterClosing = await renderer.image(for: preferences)
        XCTAssertNil(imageAfterClosing)
    }

    func testRenderedScreenshotUsesProductionDescriptorDimensionsAndRetinaPixels() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        for design in LauncherDesign.allCases {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            let renderedImage = await renderer.image(for: preferences)
            let image = try XCTUnwrap(renderedImage)
            var canonical = LauncherAppearancePreferences.defaults(design: design)
            canonical.visibleResultCount = 3
            let descriptor = LauncherThemeController().descriptor(for: canonical)

            XCTAssertEqual(image.size.width, descriptor.width, accuracy: 0.001)
            XCTAssertEqual(
                image.size.height,
                descriptor.panelHeight(resultCount: LauncherPreviewFixture.standard.results.count),
                accuracy: 0.001
            )
            let bitmap = try XCTUnwrap(
                image.representations.compactMap { $0 as? NSBitmapImageRep }.first
            )
            XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(image.size.width))
            XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(image.size.height))

            if let outputDirectory = ProcessInfo.processInfo.environment["BROCCOLI_QA_CAPTURE_DIR"] {
                let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("launcher-\(design.rawValue).png"))
            }
        }
    }

    func testDesignChooserThumbnailsRenderEachProductionDesignAtTheCurrentColorMode() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        var appearance = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        appearance.mode = .dark
        appearance.visibleResultCount = 10

        for design in LauncherDesignChooserLayout.designs {
            var previewPreferences = appearance
            previewPreferences.design = design
            let renderedImage = await renderer.image(for: previewPreferences)
            let image = try XCTUnwrap(renderedImage)
            var canonical = LauncherAppearancePreferences.defaults(design: design)
            canonical.mode = .dark
            canonical.visibleResultCount = 3
            let descriptor = LauncherThemeController().descriptor(for: canonical)
            XCTAssertEqual(image.size.width, descriptor.width, accuracy: 0.001)
            XCTAssertEqual(
                image.size.height,
                descriptor.panelHeight(resultCount: LauncherPreviewFixture.standard.results.count),
                accuracy: 0.001
            )
            XCTAssertEqual(renderer.cacheKey(for: previewPreferences).appearance, .dark)
            XCTAssertEqual(renderer.cacheKey(for: previewPreferences).design, design)
        }
        XCTAssertEqual(renderer.cachedImageCount, LauncherDesignChooserLayout.designs.count)
    }

    func testLiquidLauncherUsesOneUnifiedNativeMaterialSurface() throws {
        _ = NSApplication.shared
        let surface = LauncherLiquidGlassSurfaceView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 640,
                height: LauncherLiquidGlassSurfaceView.collapsedHeight
            ),
            interactive: true
        )
        surface.appearance = NSAppearance(named: .aqua)
        let content = NSView()
        surface.setContentView(content)
        surface.layoutSubtreeIfNeeded()

        let material = try XCTUnwrap(
            surface.subviews.compactMap { $0 as? NSVisualEffectView }.first
        )
        XCTAssertEqual(
            surface.subviews.compactMap { $0 as? NSVisualEffectView }.count,
            1
        )
        XCTAssertEqual(material.material, .hudWindow)
        XCTAssertEqual(material.blendingMode, .behindWindow)
        XCTAssertFalse(material.wantsLayer)
        XCTAssertEqual(
            material.maskImage?.capInsets.top,
            LauncherLiquidGlassMetrics.cornerRadius
        )
        XCTAssertEqual(material.frame, surface.bounds)
        XCTAssertTrue(content.isDescendant(of: material))

        surface.appearance = NSAppearance(named: .darkAqua)
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(material.isHidden)
        XCTAssertEqual(material.state, .inactive)
        XCTAssertTrue(surface.usesDarkBackdrop)
        XCTAssertTrue(content.superview === surface)

        surface.appearance = NSAppearance(named: .aqua)
        surface.frame.size.height = 184
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(material.frame, surface.bounds)
        XCTAssertEqual(material.material, .hudWindow)
        XCTAssertFalse(material.wantsLayer)
        XCTAssertEqual(material.maskImage?.capInsets.top, LauncherLiquidGlassSurfaceView.cornerRadius)
    }

    func testRenderedResultsViewportMatchesProductionDocumentHeight() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        for design in LauncherDesign.allCases {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            let rendered = await renderer.image(for: preferences)
            XCTAssertNotNil(rendered)
            let metrics = try XCTUnwrap(renderer.lastRenderMetrics)
            let descriptor = LauncherThemeController().descriptor(for: preferences)
            let expectedHeight = descriptor.resultsDocumentHeight(
                resultCount: LauncherPreviewFixture.standard.results.count
            )

            XCTAssertEqual(metrics.resultsViewportHeight, expectedHeight, accuracy: 0.001)
            XCTAssertEqual(metrics.resultsDocumentHeight, expectedHeight, accuracy: 0.001)
        }
    }

    func testAccessibilityEnvironmentAtomicallyControlsCacheKeyAndRenderedSurface() async throws {
        _ = NSApplication.shared
        let actual = LauncherPreviewEnvironment.current
        let actualUsesOpaqueLiquidSurface = actual.reducesTransparency || actual.increasesContrast
        let injected = actualUsesOpaqueLiquidSurface
            ? LauncherPreviewEnvironment(
                reducesTransparency: false,
                increasesContrast: false
            )
            : LauncherPreviewEnvironment(
                reducesTransparency: true,
                increasesContrast: false
            )
        var environmentReadCount = 0
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider(), environmentProvider: {
            environmentReadCount += 1
            // The first read performs the fast cache check. Simulate accessibility changing
            // while the async renderer yields, before it commits a new cached image.
            return environmentReadCount == 1 ? actual : injected
        })
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        let preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let rendered = await renderer.image(for: preferences)
        XCTAssertNotNil(rendered)
        let expectedSurface = LauncherThemeController().descriptor(
            for: preferences,
            reducedTransparency: injected.reducesTransparency,
            increasedContrast: injected.increasesContrast
        ).surface

        XCTAssertEqual(renderer.lastRenderedSurface, expectedSurface)
        XCTAssertEqual(expectedSurface, .glass,
            "Native glass owns accessibility adaptation without replacing the surface")
    }

    func testLiveEnvironmentRefreshInvalidatesOnlyAffectedCachedPreviews() async throws {
        _ = NSApplication.shared
        let environment = PreviewEnvironmentBox(LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .light
        ))
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider(), environmentProvider: { environment.value })
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        var system = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        system.mode = .system
        var explicitDark = system
        explicitDark.mode = .dark
        let renderedSystemImage = await renderer.image(for: system)
        let systemImage = try XCTUnwrap(renderedSystemImage)
        let renderedExplicitImage = await renderer.image(for: explicitDark)
        let explicitImage = try XCTUnwrap(renderedExplicitImage)
        XCTAssertEqual(renderer.cachedImageCount, 2)

        environment.value = LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .dark
        )
        renderer.refreshEnvironment(.systemAppearance)
        XCTAssertEqual(renderer.environmentRevision, 1)
        XCTAssertEqual(renderer.cachedImageCount, 1)
        XCTAssertNil(renderer.cachedImage(for: system))
        XCTAssertTrue(renderer.cachedImage(for: explicitDark) === explicitImage)
        XCTAssertFalse(renderer.cachedImage(for: explicitDark) === systemImage)

        _ = await renderer.image(for: system)
        XCTAssertEqual(renderer.cachedImageCount, 2)
        environment.value = LauncherPreviewEnvironment(
            reducesTransparency: true,
            increasesContrast: false,
            resolvedAppearance: .dark
        )
        renderer.refreshEnvironment(.accessibility)
        XCTAssertEqual(renderer.environmentRevision, 2)
        XCTAssertEqual(renderer.cachedImageCount, 0)
    }

    func testTargetedInvalidationLeavesOtherDesignCached() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        let minimal = LauncherAppearancePreferences.defaults(design: .minimal)
        let glass = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        let renderedMinimal = await renderer.image(for: minimal)
        let firstMinimal = try XCTUnwrap(renderedMinimal)
        let renderedGlass = await renderer.image(for: glass)
        let firstGlass = try XCTUnwrap(renderedGlass)

        renderer.invalidate(design: .minimal)
        XCTAssertNil(renderer.cachedImage(for: minimal))
        XCTAssertTrue(renderer.cachedImage(for: glass) === firstGlass)

        let rerenderedMinimal = await renderer.image(for: minimal)
        let secondMinimal = try XCTUnwrap(rerenderedMinimal)
        XCTAssertFalse(firstMinimal === secondMinimal)
        XCTAssertTrue(renderer.cachedImage(for: glass) === firstGlass)
    }

    func testNativeFixtureIconArrivalInvalidatesCapturedPreviews() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        let preferences = LauncherAppearancePreferences.defaults(design: .minimal)
        let renderedFirst = await renderer.image(for: preferences)
        let first = try XCTUnwrap(renderedFirst)
        let revision = renderer.environmentRevision
        XCTAssertEqual(renderer.cachedImageCount, 1)

        renderer.nativePaneIconDidLoad("setting:com.apple.ScreenSaver-Settings.extension")
        XCTAssertEqual(renderer.cachedImageCount, 0)
        XCTAssertEqual(renderer.environmentRevision, revision + 1)

        let renderedSecond = await renderer.image(for: preferences)
        let second = try XCTUnwrap(renderedSecond)
        XCTAssertFalse(first === second)

        renderer.nativePaneIconDidLoad("setting:not-in-fixture")
        XCTAssertTrue(renderer.cachedImage(for: preferences) === second)
    }

    func testCacheIsCostBounded() async {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider(), cacheCostLimit: 1)
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        for design in LauncherDesign.allCases {
            _ = await renderer.image(for: .defaults(design: design))
        }
        XCTAssertEqual(renderer.cachedImageCount, 1)
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0 }
        return rgb.redComponent * 0.2126
            + rgb.greenComponent * 0.7152
            + rgb.blueComponent * 0.0722
    }
}

@MainActor
private final class PreviewEnvironmentBox {
    var value: LauncherPreviewEnvironment

    init(_ value: LauncherPreviewEnvironment) {
        self.value = value
    }
}
