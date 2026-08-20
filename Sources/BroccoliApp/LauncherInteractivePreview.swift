@preconcurrency import AppKit
import SwiftUI

/// A safe Settings-only host for the real descriptor-backed launcher surface.
///
/// It deliberately owns no `LauncherCoordinator`, action executor, usage store, or callbacks.
/// The embedded AppKit content can edit/filter the deterministic fixture and move selection,
/// while Return is consumed by `LauncherPreviewContentView` without dispatching anything.
@MainActor
struct LauncherInteractivePreview: View {
    let preferences: LauncherAppearancePreferences
    @ObservedObject var renderer: LauncherPreviewRenderer
    let interactive: Bool
    let fillsAvailableSpace: Bool

    init(
        preferences: LauncherAppearancePreferences,
        renderer: LauncherPreviewRenderer,
        interactive: Bool = true,
        fillsAvailableSpace: Bool = false
    ) {
        self.preferences = preferences
        self.renderer = renderer
        self.interactive = interactive
        self.fillsAvailableSpace = fillsAvailableSpace
    }

    var body: some View {
        let configuration = renderer.interactiveConfiguration(for: preferences)
        let nativeSize = NSSize(
            width: configuration.descriptor.width,
            height: configuration.descriptor.panelHeight(
                resultCount: configuration.fixture.results.count
            )
        )

        Group {
            if fillsAvailableSpace {
                widthFilledPreview(configuration: configuration)
            } else {
                preview(configuration: configuration, nativeSize: nativeSize)
                    .aspectRatio(nativeSize.width / nativeSize.height, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func preview(
        configuration: LauncherInteractivePreviewConfiguration,
        nativeSize: NSSize
    ) -> some View {
        GeometryReader { proxy in
            let fittedSize = Self.fittedSize(nativeSize, inside: proxy.size)
            LauncherInteractivePreviewRepresentable(
                configuration: configuration,
                interactive: interactive,
                fillsWidth: false
            )
            .frame(width: fittedSize.width, height: fittedSize.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    /// Appearance settings presents the launcher on a desktop-sized stage. Scale from the
    /// launcher's native width and crop only the extra result rows so its material, search
    /// field, typography, and corner geometry remain large enough to compare accurately.
    private func widthFilledPreview(
        configuration: LauncherInteractivePreviewConfiguration
    ) -> some View {
        GeometryReader { proxy in
            LauncherInteractivePreviewRepresentable(
                configuration: configuration,
                interactive: interactive,
                fillsWidth: true
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }

    private static func fittedSize(_ content: NSSize, inside available: CGSize) -> CGSize {
        guard content.width > 0, content.height > 0,
              available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / content.width, available.height / content.height)
        return CGSize(width: content.width * scale, height: content.height * scale)
    }
}

@MainActor
private struct LauncherInteractivePreviewRepresentable: NSViewRepresentable {
    let configuration: LauncherInteractivePreviewConfiguration
    let interactive: Bool
    let fillsWidth: Bool

    func makeNSView(context: Context) -> LauncherInteractivePreviewHostView {
        LauncherInteractivePreviewHostView(
            configuration: configuration,
            interactive: interactive,
            fillsWidth: fillsWidth
        )
    }

    func updateNSView(_ nsView: LauncherInteractivePreviewHostView, context: Context) {
        nsView.update(
            configuration: configuration,
            interactive: interactive,
            fillsWidth: fillsWidth
        )
    }
}

/// Maps the launcher's native coordinate space into the readable-width Settings detail pane.
/// Giving the child its production-sized bounds preserves actual row/font/corner geometry and
/// keeps AppKit event conversion working when the 820-point Classic design is scaled to fit.
@MainActor
final class LauncherInteractivePreviewHostView: NSView {
    private let iconProvider = LauncherPreviewIconProvider()
    private let scaleView = NSView()
    private var content: LauncherPreviewContentView?
    private var identity: LauncherPreviewRenderIdentity?
    private var preferences: LauncherAppearancePreferences?
    private var interactive: Bool?
    private var fillsWidth: Bool?
    private var nativeSize: NSSize = .zero

    var hostedContentFrame: NSRect? { content == nil ? nil : scaleView.frame }
    var hostedNativeSize: NSSize { nativeSize }

    init(
        configuration: LauncherInteractivePreviewConfiguration,
        interactive: Bool,
        fillsWidth: Bool
    ) {
        super.init(frame: .zero)
        scaleView.translatesAutoresizingMaskIntoConstraints = true
        scaleView.autoresizingMask = []
        addSubview(scaleView)
        update(
            configuration: configuration,
            interactive: interactive,
            fillsWidth: fillsWidth
        )
    }

    required init?(coder: NSCoder) { nil }

    func update(
        configuration: LauncherInteractivePreviewConfiguration,
        interactive: Bool,
        fillsWidth: Bool
    ) {
        guard identity != configuration.identity
                || preferences != configuration.preferences
                || self.interactive != interactive
                || self.fillsWidth != fillsWidth else { return }
        identity = configuration.identity
        preferences = configuration.preferences
        self.interactive = interactive
        self.fillsWidth = fillsWidth
        content?.removeFromSuperview()

        let content = LauncherPreviewContentView(
            descriptor: configuration.descriptor,
            fixture: configuration.fixture,
            iconProvider: iconProvider,
            interactive: interactive
        )
        nativeSize = content.frame.size
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = []
        content.frame = NSRect(origin: .zero, size: nativeSize)
        scaleView.addSubview(content)
        self.content = content
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard content != nil, nativeSize.width > 0, nativeSize.height > 0 else { return }
        let scale = fillsWidth == true
            ? bounds.width / nativeSize.width
            : min(bounds.width / nativeSize.width, bounds.height / nativeSize.height)
        let displayed = NSSize(
            width: nativeSize.width * scale,
            height: nativeSize.height * scale
        )
        scaleView.frame = NSRect(
            x: bounds.midX - displayed.width / 2,
            y: fillsWidth == true
                ? bounds.maxY - displayed.height
                : bounds.midY - displayed.height / 2,
            width: displayed.width,
            height: displayed.height
        )
        scaleView.bounds = NSRect(origin: .zero, size: nativeSize)
    }
}
