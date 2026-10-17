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
                let material = try XCTUnwrap(surface.glassClip.subviews.compactMap { $0 as? NSVisualEffectView }.first)
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
                XCTAssertEqual(surface.glassClip.layer?.cornerRadius, compactRadius)
                XCTAssertEqual(surface.rim.isHidden, mode != .dark, "The preview draws the launcher's rim")
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
            XCTAssertEqual(preview.tableDocumentFrame.height, theme.rowHeight)
            let controller = LauncherPanelController()
            controller.applyAppearance(preferences)
            controller.setMode(.main, initialQuery: "1+")
            controller.apply(results)
            XCTAssertEqual(controller.currentPanelHeight, theme.searchHeight)
            XCTAssertFalse(controller.isResultViewportVisible)
        }
    }

    private func quietIconProvider() -> LauncherPreviewIconProvider {
        // Tests control icon arrivals explicitly; filesystem timing must not publish a
        // revision the test did not cause.
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

    func testLiquidLauncherUsesOneUnifiedNativeMaterialSurface() throws {
        _ = NSApplication.shared
        let surface = LauncherLiquidGlassSurfaceView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 640,
                height: LauncherLiquidGlassMetrics.searchHeight
            ),
            interactive: true
        )
        surface.appearance = NSAppearance(named: .aqua)
        let content = NSView()
        surface.setContentView(content)
        surface.layoutSubtreeIfNeeded()

        let material = try XCTUnwrap(
            surface.glassClip.subviews.compactMap { $0 as? NSVisualEffectView }.first
        )
        XCTAssertEqual(
            surface.glassClip.subviews.compactMap { $0 as? NSVisualEffectView }.count,
            1
        )
        XCTAssertEqual(material.material, .hudWindow)
        XCTAssertEqual(material.blendingMode, .behindWindow)
        XCTAssertFalse(material.wantsLayer)
        XCTAssertEqual(
            surface.glassClip.layer?.cornerRadius,
            LauncherLiquidGlassMetrics.cornerRadius
        )
        XCTAssertEqual(material.frame, surface.bounds)
        XCTAssertTrue(content.isDescendant(of: material))

        surface.appearance = NSAppearance(named: .darkAqua)
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(material.isHidden)
        XCTAssertEqual(material.state, .inactive)
        XCTAssertTrue(surface.usesDarkBackdrop)
        XCTAssertTrue(content.superview === surface.glassClip)

        surface.appearance = NSAppearance(named: .aqua)
        surface.frame.size.height = 184
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(material.frame, surface.bounds)
        XCTAssertEqual(material.material, .hudWindow)
        XCTAssertFalse(material.wantsLayer)
        XCTAssertEqual(surface.glassClip.frame, surface.bounds)
        XCTAssertEqual(surface.glassClip.layer?.cornerRadius, LauncherLiquidGlassSurfaceView.cornerRadius)
    }

    func testEnvironmentChangesPublishARevisionOnlyDuringASession() {
        _ = NSApplication.shared
        let environment = PreviewEnvironmentBox(LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .light
        ))
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider(), environmentProvider: { environment.value })

        environment.value = LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .dark
        )
        renderer.refreshEnvironment()
        XCTAssertEqual(renderer.environmentRevision, 0)

        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }
        renderer.refreshEnvironment()
        XCTAssertEqual(renderer.environmentRevision, 0, "An unchanged environment keeps its revision")

        environment.value = LauncherPreviewEnvironment(
            reducesTransparency: true,
            increasesContrast: false,
            resolvedAppearance: .dark
        )
        renderer.refreshEnvironment()
        XCTAssertEqual(renderer.environmentRevision, 1)
    }

    func testOnlyFixtureIconArrivalsPublishARevision() {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer(iconProvider: quietIconProvider())
        renderer.nativePaneIconDidLoad("setting:com.apple.ScreenSaver-Settings.extension")
        XCTAssertEqual(renderer.environmentRevision, 0)

        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }
        let revision = renderer.environmentRevision
        renderer.nativePaneIconDidLoad("setting:not-in-fixture")
        XCTAssertEqual(renderer.environmentRevision, revision)
        renderer.nativePaneIconDidLoad("setting:com.apple.ScreenSaver-Settings.extension")
        XCTAssertEqual(renderer.environmentRevision, revision + 1)
    }
}

@MainActor
private final class PreviewEnvironmentBox {
    var value: LauncherPreviewEnvironment

    init(_ value: LauncherPreviewEnvironment) {
        self.value = value
    }
}
