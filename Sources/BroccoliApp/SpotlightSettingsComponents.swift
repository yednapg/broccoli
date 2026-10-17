import AppKit
import SwiftUI

/// The reusable visual language shared by every Broccoli Settings pane.
///
/// These components intentionally mirror Cherry's Settings primitives while keeping all
/// Broccoli-specific settings state and behavior in its native SwiftUI Settings scene.
private struct SpotlightSettingsGroupedSurfaceModifier: ViewModifier {
    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: Self.shape)
            .clipShape(Self.shape)
            .overlay {
                Self.shape
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(0.32),
                        lineWidth: 0.6
                    )
            }
    }
}

private struct SpotlightSettingsGlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
        }
    }
}

private struct SpotlightSettingsProminentGlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
        }
    }
}

extension View {
    func spotlightSettingsGroupedSurface() -> some View {
        modifier(SpotlightSettingsGroupedSurfaceModifier())
    }

    func spotlightSettingsGlassButtonStyle() -> some View {
        modifier(SpotlightSettingsGlassButtonModifier())
    }

    func spotlightSettingsProminentGlassButtonStyle() -> some View {
        modifier(SpotlightSettingsProminentGlassButtonModifier())
    }
}

struct SpotlightSettingsPane<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(width: 660, alignment: .topLeading)
            .frame(
                maxWidth: .infinity,
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
    }
}

struct SpotlightSettingsCard<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
                    .padding(.bottom, 7)
            }

            dividedContent
        }
        .spotlightSettingsGroupedSurface()
    }

    @ViewBuilder
    private var dividedContent: some View {
        if #available(macOS 26.0, *) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index]

                    if index < subviews.endIndex - 1 {
                        SpotlightSettingsDivider()
                    }
                }
            }
        } else {
            content
        }
    }
}

struct SpotlightSettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessoryMinimumWidth: CGFloat
    let accessory: Accessory

    /// `symbol` and `symbolColor` remain accepted so the existing Broccoli panes can retain
    /// their semantic call sites. Cherry's cleaner row treatment deliberately omits leading
    /// glyphs; cards and sidebar items carry the visual hierarchy instead.
    init(
        symbol: String? = nil,
        symbolColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        accessoryMinimumWidth: CGFloat = 150,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessoryMinimumWidth = accessoryMinimumWidth
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            accessory
                .frame(minWidth: accessoryMinimumWidth, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

extension SpotlightSettingsRow where Accessory == EmptyView {
    init(
        symbol: String? = nil,
        symbolColor: Color? = nil,
        title: String,
        subtitle: String? = nil
    ) {
        self.init(
            symbol: symbol,
            symbolColor: symbolColor,
            title: title,
            subtitle: subtitle,
            accessoryMinimumWidth: 0
        ) { EmptyView() }
    }
}

struct SpotlightSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.20))
            .frame(height: 0.5)
            .padding(.leading, 18)
    }
}

/// Applies Cherry's native Settings-scene chrome once per attached window. Ordinary SwiftUI
/// updates only refresh the window reference so split-view animations stay on the native path.
struct SpotlightSettingsNativeWindowConfigurator: NSViewRepresentable {
    let onWindowAttached: (NSWindow) -> Void

    func makeNSView(context: Context) -> SpotlightSettingsNativeWindowChromeView {
        let view = SpotlightSettingsNativeWindowChromeView()
        view.onWindowAttached = onWindowAttached
        return view
    }

    func updateNSView(
        _ nsView: SpotlightSettingsNativeWindowChromeView,
        context: Context
    ) {
        nsView.onWindowAttached = onWindowAttached
        nsView.reportAttachedWindow()
    }
}

@MainActor
final class SpotlightSettingsNativeWindowChromeView: NSView {
    var onWindowAttached: (NSWindow) -> Void = { _ in }
    private weak var attachedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window !== attachedWindow else { return }
        if let attachedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: attachedWindow
            )
        }
        attachedWindow = window
        configureWindowChrome()
        // Reopening Settings reuses this window and view without moving the view again, so
        // report the window each time it becomes key as well.
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        reportAttachedWindow()
    }

    private func configureWindowChrome() {
        guard let window else { return }
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        onWindowAttached(window)
        // The Settings split view keeps its sidebar permanently visible and removes SwiftUI's
        // generated sidebar item; navigation history owns the leading toolbar group instead.
    }

    func reportAttachedWindow() {
        guard let window else { return }
        onWindowAttached(window)
    }

}
