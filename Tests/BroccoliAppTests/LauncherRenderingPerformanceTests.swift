import AppKit
import BroccoliCore
import XCTest
@testable import BroccoliApp

/// Run in release mode before and after appearance work. These timings measure CPU-side
/// preparation, not WindowServer compositing or the latency of pixels reaching the display.
@MainActor
final class LauncherRenderingPerformanceTests: XCTestCase {
    func testActionAppearancePublicationMeasurements() throws {
        _ = NSApplication.shared
        let isDark = LauncherAppearanceEnvironment.current.resolvedAppearance == .dark
        let oldEntry = try XCTUnwrap(ActionRegistry.searchEntries(isDarkMode: !isDark).first)
        let staleResults = [RankedResult(entry: oldEntry, score: 500)]
        measureSamples("stateful action publication (1000)", count: 80) {
            for _ in 0..<1_000 {
                _ = ActionRegistry.resolvingSystemAppearance(in: staleResults,
                    isDarkMode: LauncherAppearanceEnvironment.current.resolvedAppearance == .dark)
            }
        }
        let normalResults = LauncherPreviewFixture.standard.results
        measureSamples("ordinary result publication check (1000)", count: 80) {
            for _ in 0..<1_000 {
                _ = ActionRegistry.resolvingSystemAppearance(in: normalResults,
                    isDarkMode: LauncherAppearanceEnvironment.current.resolvedAppearance == .dark)
            }
        }
    }

    func testResultTransitionMeasurements() {
        _ = NSApplication.shared
        let panel = LauncherPanelController()
        panel.applyAppearance(.defaults(design: .liquidGlass))
        panel.setMode(.main, initialQuery: "fixture")
        let results = LauncherPreviewFixture.standard.results
        let noResults = LauncherMainSearchResultComposer.compose(
            catalogResults: [], calculatorEvaluation: .notExpression, hasVisibleQuery: true, limit: 7)
        let transitions = [results, Array(results.prefix(1)), noResults, []]
        measureSamples("result resize cycle", count: 80) {
            for results in transitions { panel.apply(results) }
        }
    }

    func testRenderingPreparationMeasurements() throws {
        _ = NSApplication.shared
        let cache = IconCache(startsNativeIconResolution: false)
        let entry = try XCTUnwrap(ActionRegistry.searchEntries.first)
        _ = cache.image(for: entry)
        measureSamples("cached icon lookup (1000)", count: 80) {
            for _ in 0..<1_000 { _ = cache.image(for: entry) }
        }
        let path = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        measureSamples("native icon materialization", count: 60) {
            _ = SystemSettingsNativeIconResolver.materializeIcon(
                at: path, pointSize: 50, backingScale: 2
            )
        }
        let panel = LauncherPanelController()
        var preferences = LauncherAppearancePreferences.defaults(design: .liquidGlass)
        panel.applyAppearance(preferences)
        measureSamples("appearance update", count: 80) {
            preferences.mode = preferences.mode == .light ? .dark : .light
            panel.applyAppearance(preferences)
        }
        measureSamples("launcher preparation", count: 40) {
            autoreleasepool {
                let candidate = LauncherPanelController()
                candidate.applyAppearance(preferences)
                candidate.apply(LauncherPreviewFixture.standard.results)
            }
        }
    }

    func testNativeIconPipelineMeasurements() async throws {
        _ = NSApplication.shared
        let store = SystemSettingsNativeIconStore()
        let cache = IconCache(systemSettingsIconStore: store, backingScale: 2)
        let application = LauncherPreviewFixture.standard.results[0].entry
        let pane = LauncherPreviewFixture.standard.results[1].entry
        let context = LauncherAppearanceEnvironment.current.iconContext(mode: .system, pointSize: 40, backingScale: 2)
        cache.prewarm([application, pane], context: context)
        _ = cache.image(for: application, context: context)
        _ = cache.image(for: pane, context: context)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            let applicationReady = cache.image(for: application, context: context).representations.contains {
                ($0 as? NSBitmapImageRep)?.pixelsWide ?? 0 >= 70
            }
            let paneReady = store.cachedIcon(for: pane.iconKey, context: context) != nil
            if applicationReady && paneReady { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(store.cachedIcon(for: pane.iconKey, context: context))
        measureSamples("cached native application lookup (1000)", count: 80) {
            for _ in 0..<1_000 { _ = cache.image(for: application, context: context) }
        }
        measureSamples("cached native pane lookup (1000)", count: 80) {
            for _ in 0..<1_000 { _ = cache.image(for: pane, context: context) }
        }
        let requests = SystemSettingsIconRequestMapper.requests(for: [pane])
        var samples: [Double] = []
        for iteration in 0..<50 {
            let start = ContinuousClock.now
            let result = await SystemSettingsNativeIconResolver.resolve(requests: requests, context: context)
            XCTAssertNotNil(result.iconsByKey[pane.iconKey])
            let elapsed = start.duration(to: .now).components
            if iteration >= 10 {
                samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1_000_000_000_000_000)
            }
        }
        samples.sort()
        print(String(format: "RENDER background pane refresh: median %.4f ms, p95 %.4f ms",
                     samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)]))
    }

    private func measureSamples(_ label: String, count: Int, operation: () -> Void) {
        var samples: [Double] = []
        for iteration in 0..<(count + 10) {
            let start = ContinuousClock.now
            operation()
            let elapsed = start.duration(to: .now).components
            if iteration >= 10 {
                samples.append(Double(elapsed.seconds) * 1_000
                    + Double(elapsed.attoseconds) / 1_000_000_000_000_000)
            }
        }
        samples.sort()
        print(String(format: "RENDER %@: median %.4f ms, p95 %.4f ms", label,
            samples[samples.count / 2], samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]))
    }
}
