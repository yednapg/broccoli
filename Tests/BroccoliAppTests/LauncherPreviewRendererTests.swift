import AppKit
import XCTest
@testable import BroccoliApp

@MainActor
final class LauncherPreviewRendererTests: XCTestCase {
    func testFixtureUsesRealSearchModelsAcrossProductionResultKinds() {
        let fixture = LauncherPreviewFixture.standard

        XCTAssertEqual(fixture.query, "screen")
        XCTAssertEqual(fixture.results.count, 3)
        XCTAssertEqual(fixture.results.map(\.entry.kind), [.application, .systemSetting, .action])
        XCTAssertEqual(fixture.results.map(\.entry.id), [
            "preview:application:screen-sharing",
            "setting:screen-saver",
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
        let renderer = LauncherPreviewRenderer()
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
        let renderer = LauncherPreviewRenderer()
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
        }
    }

    func testLiquidLauncherUsesOneUntintedNativeGlassSurface() throws {
        _ = NSApplication.shared
        let surface = LauncherLiquidGlassSurfaceView(interactive: false)
        let content = NSView()
        surface.setContentView(content)

        if #available(macOS 26, *) {
            let glass = try XCTUnwrap(
                surface.subviews.compactMap { $0 as? NSGlassEffectView }.first
            )
            XCTAssertTrue(
                surface.subviews.compactMap { $0 as? NSVisualEffectView }.isEmpty,
                "Native glass must sample the desktop directly instead of a synthetic backdrop"
            )
            XCTAssertEqual(glass.style, .regular)
            XCTAssertEqual(
                glass.cornerRadius,
                LauncherLiquidGlassSurfaceView.expandedCornerRadius
            )
            XCTAssertNil(glass.tintColor)
            XCTAssertTrue(content.superview === glass.contentView)
        } else {
            let fallback = try XCTUnwrap(
                surface.subviews.compactMap { $0 as? NSVisualEffectView }.first
            )
            XCTAssertEqual(fallback.blendingMode, .behindWindow)
            XCTAssertEqual(fallback.material, .hudWindow)
        }
    }

    func testRenderedResultsViewportMatchesProductionDocumentHeight() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer()
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
        let renderer = LauncherPreviewRenderer(environmentProvider: {
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
        XCTAssertNotEqual(
            expectedSurface,
            LauncherThemeController().descriptor(
                for: preferences,
                reducedTransparency: actual.reducesTransparency,
                increasedContrast: actual.increasesContrast
            ).surface,
            "The fixture must exercise a real accessibility-state transition"
        )
    }

    func testLiveEnvironmentRefreshInvalidatesOnlyAffectedCachedPreviews() async throws {
        _ = NSApplication.shared
        let environment = PreviewEnvironmentBox(LauncherPreviewEnvironment(
            reducesTransparency: false,
            increasesContrast: false,
            resolvedAppearance: .light
        ))
        let renderer = LauncherPreviewRenderer(environmentProvider: { environment.value })
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
        let renderer = LauncherPreviewRenderer()
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
        let renderer = LauncherPreviewRenderer()
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        let preferences = LauncherAppearancePreferences.defaults(design: .minimal)
        let renderedFirst = await renderer.image(for: preferences)
        let first = try XCTUnwrap(renderedFirst)
        let revision = renderer.environmentRevision
        XCTAssertEqual(renderer.cachedImageCount, 1)

        renderer.nativePaneIconDidLoad("setting:screen-saver")
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
        let renderer = LauncherPreviewRenderer(cacheCostLimit: 1)
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        for design in LauncherDesign.allCases {
            _ = await renderer.image(for: .defaults(design: design))
        }
        XCTAssertEqual(renderer.cachedImageCount, 1)
    }

    func testClassicScreenshotBodyContainsResultsAndContextualPreview() async throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer()
        renderer.beginSettingsSession()
        defer { renderer.endSettingsSession() }

        var preferences = LauncherAppearancePreferences.defaults(design: .yosemiteClassic)
        preferences.mode = .dark
        let rendered = await renderer.image(for: preferences)
        let image = try XCTUnwrap(rendered)
        let bitmap = try XCTUnwrap(
            image.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )

        let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
        let descriptor = LauncherThemeController().descriptor(for: preferences)
        let bodyHeight = image.size.height - descriptor.searchHeight
        let leftBody = NSRect(
            x: 4 * scaleX,
            y: 4 * scaleY,
            width: (image.size.width - descriptor.previewWidth - 12) * scaleX,
            height: (bodyHeight - 8) * scaleY
        )
        let rightBody = NSRect(
            x: (image.size.width - descriptor.previewWidth + 8) * scaleX,
            y: 4 * scaleY,
            width: (descriptor.previewWidth - 16) * scaleX,
            height: (bodyHeight - 8) * scaleY
        )

        XCTAssertGreaterThan(
            highContrastEdgeCount(in: bitmap, region: leftBody),
            100,
            "Classic results pane must render row icons, titles, and selection"
        )
        XCTAssertGreaterThan(
            highContrastEdgeCount(in: bitmap, region: rightBody),
            100,
            "Classic contextual pane must render its icon and labels"
        )
    }

    private func highContrastEdgeCount(in bitmap: NSBitmapImageRep, region: NSRect) -> Int {
        let minX = max(1, Int(region.minX))
        let maxX = min(bitmap.pixelsWide - 1, Int(region.maxX))
        let minY = max(1, Int(region.minY))
        let maxY = min(bitmap.pixelsHigh - 1, Int(region.maxY))
        var count = 0

        for y in stride(from: minY, to: maxY, by: 2) {
            for x in stride(from: minX, to: maxX, by: 2) {
                guard let pixel = bitmap.colorAt(x: x, y: y),
                      let neighbor = bitmap.colorAt(x: x + 1, y: y) else { continue }
                let delta = abs(pixel.redComponent - neighbor.redComponent)
                    + abs(pixel.greenComponent - neighbor.greenComponent)
                    + abs(pixel.blueComponent - neighbor.blueComponent)
                if delta > 0.22 { count += 1 }
            }
        }
        return count
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
