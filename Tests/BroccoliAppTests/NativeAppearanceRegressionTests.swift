import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

@MainActor
final class NativeAppearanceRegressionTests: XCTestCase {
    func testNativeRegularGlassAcrossAppearanceAndAccessibilityMatrix() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            for transparency in [false, true] {
                for contrast in [false, true] {
                    for motion in [false, true] {
                        let environment = LauncherAppearanceEnvironment(
                            reducesTransparency: transparency, increasesContrast: contrast,
                            resolvedAppearance: dark ? .dark : .light, reducesMotion: motion,
                            backingScale: 2)
                        let theme = LauncherThemeController().descriptor(
                            for: .defaults(design: .liquidGlass), environment: environment)
                        XCTAssertEqual(theme.environment, environment)
                        XCTAssertEqual(theme.isDark, dark)
                        XCTAssertEqual(theme.surface, .glass)
                        XCTAssertTrue(theme.hasShadow)
                        XCTAssertEqual(theme.iconContext.pointSize, 50)
                        let surface = LauncherLiquidGlassSurfaceView()
                        surface.appearance = theme.drawingAppearance
                        surface.layoutSubtreeIfNeeded()
                        let glass = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSGlassEffectView }.first)
                        XCTAssertEqual(glass.style, .regular)
                        XCTAssertNil(glass.tintColor)
                        let minimal = LauncherThemeController().descriptor(
                            for: .defaults(design: .minimal), environment: environment)
                        XCTAssertEqual(minimal.surface, transparency || contrast ? .opaque : .ultraThick)
                    }
                }
            }
        }
    }

    func testVisibleAppearanceChangesPreserveEditorCompositionRowsAndScroll() throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .light
        panel.applyAppearance(preferences)
        panel.show(on: NSScreen.main)
        defer { panel.dismiss(notify: false) }
        panel.setMode(.main, initialQuery: "screen")
        panel.apply(LauncherPreviewFixture.standard.results)
        let window = panel.visibilityIsolationWindow
        let root = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(descendants(root).compactMap { $0 as? NSSearchField }.first)
        let cell = field.cell
        let nativeField = try XCTUnwrap(field as? LauncherNativeSearchField)
        let placeholder = nativeField.centeredPlaceholderAttributedString
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        _ = panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        editor.setMarkedText("入力", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: editor.selectedRange())
        let text = editor.string
        let query = panel.query
        let marked = editor.markedRange()
        let caret = editor.selectedRange()
        let selection = panel.selectedResultID
        let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
        let scrollOrigin = scroll.contentView.bounds.origin
        for mode in [LauncherAppearanceMode.dark, .light, .dark] {
            preferences.mode = mode
            panel.applyAppearance(preferences, force: true)
            XCTAssertTrue(window.contentView === root)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertTrue(field.cell === cell)
            XCTAssertEqual(nativeField.centeredPlaceholderAttributedString, placeholder)
            XCTAssertEqual(nativeField.centeredPlaceholderAttributedString?.attribute(
                .foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .placeholderTextColor)
            XCTAssertEqual(editor.string, text)
            XCTAssertEqual(panel.query, query)
            XCTAssertEqual(editor.selectedRange(), caret)
            XCTAssertEqual(editor.markedRange(), marked)
            XCTAssertEqual(panel.selectedResultID, selection)
            XCTAssertEqual(scroll.contentView.bounds.origin, scrollOrigin)
            XCTAssertEqual(field.textColor, .labelColor)
            XCTAssertTrue((field.cell as? NSSearchFieldCell)?.searchButtonCell?.image?.isTemplate == true)
        }
        editor.unmarkText()
        var executed: String?
        panel.onExecute = { executed = $0.entry.id }
        XCTAssertTrue(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(executed, selection)
        XCTAssertTrue(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    }

    func testLayerSelectionResolvesInEffectiveAppearanceAfterAChange() throws {
        _ = NSApplication.shared
        let result = LauncherPreviewFixture.standard.results[2]
        let row = ResultRowView()
        let theme = LauncherThemeController().descriptor(for: .defaults(design: .liquidGlass))
        row.configure(result: result, icon: IconCache(startsNativeIconResolution: false).image(for: result.entry),
                      confirmation: false, row: 0, selected: true, theme: theme)
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastDarkAqua] {
            row.appearance = NSAppearance(named: name)
            row.viewDidChangeEffectiveAppearance()
            row.effectiveAppearance.performAsCurrentDrawingAppearance {
                XCTAssertEqual(row.layer?.backgroundColor, NSColor.controlAccentColor.cgColor)
            }
        }
        row.setSelected(false)
        XCTAssertEqual(row.layer?.backgroundColor, NSColor.clear.cgColor)
    }

    func testInteractivePreviewKeepsContentQuerySelectionAndFocusDuringAppearanceUpdate() throws {
        _ = NSApplication.shared
        let renderer = LauncherPreviewRenderer()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .light
        let host = LauncherInteractivePreviewHostView(configuration: renderer.interactiveConfiguration(for: preferences),
                                                      interactive: true, fillsWidth: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(host.content)
        content.setInteractiveQuery("screen")
        XCTAssertTrue(content.moveInteractiveSelection(up: false))
        window.makeFirstResponder(content.previewSearchField)
        let responder = window.firstResponder
        let selected = content.selectedResultID
        for mode in [LauncherAppearanceMode.dark, .light] {
            preferences.mode = mode
            host.update(configuration: renderer.interactiveConfiguration(for: preferences), interactive: true, fillsWidth: false)
            XCTAssertTrue(host.content === content)
            XCTAssertEqual(content.interactiveQuery, "screen")
            XCTAssertEqual(content.selectedResultID, selected)
            XCTAssertTrue(window.firstResponder === responder)
            XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), mode == .dark ? .darkAqua : .aqua)
        }
    }

    func testPreviewCacheIdentityIncludesMotionAndBackingScale() {
        let standard = LauncherPreviewEnvironment(reducesTransparency: false, increasesContrast: false)
        let motion = LauncherPreviewEnvironment(reducesTransparency: false, increasesContrast: false, reducesMotion: true)
        let scale = LauncherPreviewEnvironment(reducesTransparency: false, increasesContrast: false, backingScale: 1)
        let keys = [standard, motion, scale].map {
            LauncherPreviewCacheKey(design: .liquidGlass, appearance: .light, environment: $0)
        }
        XCTAssertEqual(Set(keys).count, 3)
    }

    func testLiquidPanelWindowBoundaryMatchesGlassAcrossExpansion() throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController()
        let window = panel.visibilityIsolationWindow
        for mode in [LauncherAppearanceMode.light, .dark] {
            var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
            preferences.mode = mode
            panel.applyAppearance(preferences)
            panel.setMode(.main, initialQuery: "screen")
            for results in [[], LauncherPreviewFixture.standard.results, []] {
                panel.apply(results)
                let root = try XCTUnwrap(window.contentView)
                root.layoutSubtreeIfNeeded()
                let surface = try XCTUnwrap(descendants(root).compactMap { $0 as? LauncherLiquidGlassSurfaceView }.first)
                XCTAssertTrue(window.hasShadow)
                XCTAssertFalse(window.isOpaque)
                XCTAssertFalse(root.isOpaque)
                XCTAssertEqual(window.backgroundColor, .clear)
                XCTAssertEqual(surface.frame, root.bounds, "The shadow window must not surround an inset second glass rectangle")
                XCTAssertEqual(window.frame.size, surface.frame.size)
                XCTAssertEqual(surface.frame.width, LauncherLiquidGlassMetrics.width)
                XCTAssertEqual(surface.layer?.shadowOpacity ?? 0, 0, "Only the native window supplies the added shadow")
                let glass = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSGlassEffectView }.first)
                let boundary = try XCTUnwrap(root.layer)
                XCTAssertTrue(boundary.masksToBounds, "Window content must not paint a rectangular corner beyond rounded glass")
                XCTAssertEqual(boundary.cornerRadius, glass.cornerRadius)
                XCTAssertEqual(boundary.cornerCurve, .continuous)
                XCTAssertEqual(boundary.borderWidth, 0)
                XCTAssertEqual(boundary.shadowOpacity, 0, "Retain AppKit's window shadow, without a second layer shadow")
                try assertTransparentWindowCorners(boundary)
            }
        }
        panel.applyAppearance(.defaults(design: .minimal))
        XCTAssertFalse(window.hasShadow, "Minimal keeps its existing presentation")
    }

    func testVisibleExpansionPreservesCompactGlassConfigurationAndFocus() async throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        preferences.mode = .light
        panel.applyAppearance(preferences)
        panel.show(on: NSScreen.main)
        defer { panel.dismiss(notify: false) }
        panel.setMode(.main, initialQuery: "screen")
        panel.apply([])
        let window = panel.visibilityIsolationWindow
        let root = try XCTUnwrap(window.contentView)
        root.layoutSubtreeIfNeeded()
        let originalGlass = try XCTUnwrap(descendants(root).compactMap { $0 as? NSGlassEffectView }.first)
        let compactRadius = originalGlass.cornerRadius
        let responder = window.firstResponder
        let fixtures = LauncherPreviewFixture.standard.results
        XCTAssertEqual(compactRadius, window.frame.height / 2)

        for mode in [LauncherAppearanceMode.light, .dark, .light] {
            preferences.mode = mode
            panel.applyAppearance(preferences)
            for results in [Array(fixtures.prefix(1)), fixtures, []] {
                panel.apply(results)
                try await Task.sleep(for: .milliseconds(10))
                root.layoutSubtreeIfNeeded()
                let glasses = descendants(root).compactMap { $0 as? NSGlassEffectView }
                let glass = try XCTUnwrap(glasses.first)
                XCTAssertEqual(glasses.count, 1)
                XCTAssertTrue(window.contentView === root)
                XCTAssertTrue(glass === originalGlass, "Expansion must retain the compact bar's native surface")
                XCTAssertEqual(glass.cornerRadius, compactRadius, "Showing results must not tighten the corners")
                XCTAssertEqual(root.layer?.cornerRadius, compactRadius)
                XCTAssertEqual(glass.style, .regular)
                XCTAssertNil(glass.tintColor)
                XCTAssertEqual(glass.alphaValue, 1)
                XCTAssertEqual(glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                               mode == .dark ? .darkAqua : .aqua)
                XCTAssertTrue(window.firstResponder === responder)
                XCTAssertEqual(panel.query, "screen")
                if #available(macOS 27, *) { XCTAssertFalse(glass.effectIsInteractive) }
                XCTAssertEqual(root.layer?.borderWidth, 0)
                XCTAssertEqual(root.layer?.backgroundColor?.alpha ?? 0, 0)
            }
        }
    }

    private func assertTransparentWindowCorners(_ boundary: CALayer) throws {
        // A solid probe exercises the production window's outer clipping, independent of
        // glass sampling. This checks corner alpha, not desktop blur or native shadow fidelity.
        let probe = CALayer()
        probe.frame = boundary.bounds
        probe.backgroundColor = NSColor.red.cgColor
        boundary.addSublayer(probe)
        defer { probe.removeFromSuperlayer() }
        let width = Int(boundary.bounds.width)
        let height = Int(boundary.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            boundary.render(in: context)
        }
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            XCTAssertEqual(pixels[(y * width + x) * 4 + 3], 0, "Rounded window corners must remain transparent")
        }
        XCTAssertEqual(pixels[((height / 2) * width + width / 2) * 4 + 3], 255)
    }

    func testGlassHasOneNativeBoundaryAcrossAppearanceScaleAndExpansion() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            for contrast in [false, true] {
                for scale: CGFloat in [1, 2] {
                    let environment = LauncherAppearanceEnvironment(
                        reducesTransparency: false, increasesContrast: contrast,
                        resolvedAppearance: dark ? .dark : .light, backingScale: scale)
                    let surface = LauncherLiquidGlassSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 58))
                    surface.appearance = environment.iconContext(mode: .system, pointSize: 40).drawingAppearance
                    let content = NSView()
                    surface.setContentView(content)
                    for height: CGFloat in [58, 200, 58] {
                        surface.frame.size.height = height
                        surface.layoutSubtreeIfNeeded()
                        let glass = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSGlassEffectView }.first)
                        XCTAssertEqual(surface.subviews.count, 1, "Native glass must not acquire another stroked overlay")
                        XCTAssertEqual(glass.frame, surface.bounds)
                        XCTAssertEqual(glass.cornerRadius, LauncherLiquidGlassMetrics.cornerRadius)
                        XCTAssertTrue(glass.contentView === content.superview)
                        XCTAssertEqual(content.convert(content.bounds, to: surface), surface.bounds)
                        XCTAssertEqual(glass.style, .regular)
                        XCTAssertNil(glass.tintColor)
                    }
                }
            }
        }
    }

    func testStructuralThemeChangesRetireOldSearchHeightConstraints() throws {
        _ = NSApplication.shared
        let panel = LauncherPanelController()
        for design in [LauncherDesign.liquidGlass, .minimal, .liquidGlass] {
            let preferences = LauncherAppearancePreferences.defaults(design: design)
            panel.applyAppearance(preferences)
            let root = try XCTUnwrap(panel.visibilityIsolationWindow.contentView)
            root.layoutSubtreeIfNeeded()
            let field = try XCTUnwrap(descendants(root).compactMap { $0 as? NSSearchField }.first)
            let theme = LauncherThemeController().descriptor(for: preferences)
            XCTAssertEqual(field.frame.height, theme.searchHeight - theme.searchControlVerticalInset * 2, accuracy: 1 / panel.visibilityIsolationWindow.backingScaleFactor)
            let ownedHeights = field.constraints.filter {
                $0.isActive && $0.identifier == "Broccoli.searchHeight"
            }
            XCTAssertEqual(ownedHeights.count, 1, "Reused search controls must not accumulate incompatible heights")
        }
    }

    func testMinimalAccessibilityFallbackKeepsInteractivePreviewEditingState() throws {
        _ = NSApplication.shared
        let environment = MutableAppearanceEnvironment(.init(reducesTransparency: false, increasesContrast: false))
        let renderer = LauncherPreviewRenderer(environmentProvider: { environment.value })
        let preferences = LauncherAppearancePreferences.defaults(design: .minimal)
        let host = LauncherInteractivePreviewHostView(configuration: renderer.interactiveConfiguration(for: preferences),
                                                      interactive: true, fillsWidth: false)
        let content = try XCTUnwrap(host.content)
        content.setInteractiveQuery("screen")
        XCTAssertTrue(content.moveInteractiveSelection(up: false))
        let selection = content.selectedResultID
        for reduced in [true, false] {
            environment.value = LauncherAppearanceEnvironment(reducesTransparency: reduced, increasesContrast: reduced)
            host.update(configuration: renderer.interactiveConfiguration(for: preferences), interactive: true, fillsWidth: false)
            XCTAssertTrue(host.content === content)
            XCTAssertEqual(content.surfaceKind, reduced ? .opaque : .ultraThick)
            XCTAssertEqual(content.interactiveQuery, "screen")
            XCTAssertEqual(content.selectedResultID, selection)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }
}

@MainActor
private final class MutableAppearanceEnvironment {
    var value: LauncherAppearanceEnvironment
    init(_ value: LauncherAppearanceEnvironment) { self.value = value }
}
