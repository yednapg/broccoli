import AppKit
import SwiftUI

/// The reusable visual language shared by every Broccoli Settings pane.
///
/// These components intentionally mirror Cherry's Settings primitives while keeping all
/// Broccoli-specific settings state and behavior in its native SwiftUI Settings scene.
struct SpotlightSettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search settings", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .accessibilityLabel("Search Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .spotlightSettingsSearchFieldSurface()
    }
}

struct SpotlightSettingsIconBadge: View {
    let systemImage: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            Color(nsColor: .separatorColor).opacity(0.35),
                            lineWidth: 0.5
                        )
                }

            Image(systemName: systemImage)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}

private struct SpotlightSettingsGroupedSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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

private struct SpotlightSettingsSearchFieldSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
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

    func spotlightSettingsSearchFieldSurface() -> some View {
        modifier(SpotlightSettingsSearchFieldSurfaceModifier())
    }

    func spotlightSettingsRowPadding() -> some View {
        padding(.horizontal, 18).padding(.vertical, 13)
    }
}

struct SpotlightSettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
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
            .frame(maxWidth: 660, alignment: .topLeading)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        Divider().padding(.leading, 18)
    }
}

struct SpotlightSettingsEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

struct SpotlightSettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    var displayScale = 1.0

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 140, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(formattedValue)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var formattedValue: String {
        let displayValue = value * displayScale
        if step * displayScale >= 1 {
            return "\(Int(displayValue.rounded()))\(formattedSuffix)"
        }
        return "\(displayValue.formatted(.number.precision(.fractionLength(2))))\(formattedSuffix)"
    }

    private var formattedSuffix: String {
        guard !suffix.isEmpty else { return "" }
        return suffix == "pt" ? " \(suffix)" : suffix
    }
}

/// The same native Settings-scene chrome configurator Cherry uses. The callback only lets the
/// background launcher track the window SwiftUI created for the scene.
struct SpotlightSettingsNativeWindowConfigurator: NSViewRepresentable {
    let onWindowAttached: (NSWindow) -> Void

    func makeNSView(context: Context) -> SpotlightSettingsNativeWindowChromeView {
        let view = SpotlightSettingsNativeWindowChromeView()
        view.onWindowAttached = onWindowAttached
        DispatchQueue.main.async {
            view.configureWindowChrome()
        }
        return view
    }

    func updateNSView(
        _ nsView: SpotlightSettingsNativeWindowChromeView,
        context: Context
    ) {
        nsView.onWindowAttached = onWindowAttached
        DispatchQueue.main.async {
            nsView.configureWindowChrome()
        }
    }
}

@MainActor
final class SpotlightSettingsNativeWindowChromeView: NSView {
    private static let preferredSidebarWidth = SettingsShellLayout.sidebarWidth

    var onWindowAttached: (NSWindow) -> Void = { _ in }
    private weak var attachedWindow: NSWindow?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private var sidebarCleanupGeneration = 0
    private var configuredInitialSidebarWidth = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window !== attachedWindow {
            attachedWindow = window
            configuredInitialSidebarWidth = false
            registerWindowObservers()
        }
        configureWindowChrome()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configureWindowChrome() {
        guard let window else { return }
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        onWindowAttached(window)
        removeSidebarToolbarItems()
        configureInitialSidebarWidth()
        scheduleSidebarToolbarCleanup()
    }

    private func registerWindowObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }

        let names: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResizeNotification,
        ]

        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.configureWindowChrome() }
            }
        }

    }

    private func removeSidebarToolbarItems() {
        guard let toolbar = window?.toolbar else { return }
        for index in toolbar.items.indices.reversed() {
            if isSidebarToolbarItem(toolbar.items[index]) {
                toolbar.removeItem(at: index)
            }
        }
    }

    private func scheduleSidebarToolbarCleanup() {
        sidebarCleanupGeneration += 1
        let generation = sidebarCleanupGeneration
        let delays: [Duration] = [
            .milliseconds(0),
            .milliseconds(50),
            .milliseconds(150),
            .milliseconds(400),
        ]

        for delay in delays {
            Task { @MainActor [weak self] in
                if delay != .zero { try? await Task.sleep(for: delay) }
                guard let self, sidebarCleanupGeneration == generation else { return }
                removeSidebarToolbarItems()
                configureInitialSidebarWidth()
            }
        }
    }

    private func configureInitialSidebarWidth() {
        guard !configuredInitialSidebarWidth,
              let contentView = window?.contentView,
              let splitView = sidebarSplitView(in: contentView),
              splitView.bounds.width > Self.preferredSidebarWidth else {
            return
        }

        splitView.setPosition(Self.preferredSidebarWidth, ofDividerAt: 0)
        configuredInitialSidebarWidth = true
    }

    private func sidebarSplitView(in view: NSView) -> NSSplitView? {
        if let splitView = view as? NSSplitView,
           splitView.isVertical,
           splitView.subviews.count >= 2 {
            return splitView
        }

        for subview in view.subviews {
            if let splitView = sidebarSplitView(in: subview) {
                return splitView
            }
        }
        return nil
    }

    private func isSidebarToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .toggleSidebar
            || item.itemIdentifier == .sidebarTrackingSeparator {
            return true
        }

        let fields = [
            item.itemIdentifier.rawValue,
            item.label,
            item.paletteLabel,
            item.toolTip ?? "",
        ]

        return fields.contains {
            let value = $0.lowercased()
            return value.contains("sidebar") || value.contains("side bar")
        }
    }
}
