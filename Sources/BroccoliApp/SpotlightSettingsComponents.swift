import AppKit
import SwiftUI

/// The reusable visual language shared by every Broccoli Settings pane.
///
/// These components intentionally mirror Cherry's Settings primitives while keeping all
/// Broccoli-specific settings state and behavior in its native SwiftUI Settings scene.
struct SpotlightSettingsSearchField: View {
    @Binding var text: String
    let onCancel: () -> Bool

    init(
        text: Binding<String>,
        onCancel: @escaping () -> Bool
    ) {
        _text = text
        self.onCancel = onCancel
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            SpotlightSettingsTextField(
                text: $text,
                onCancel: onCancel
            )
            .frame(height: 22)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .spotlightSettingsSearchFieldSurface()
    }
}

private struct SpotlightSettingsTextField: NSViewRepresentable {
    @Binding var text: String
    let onCancel: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> SpotlightSettingsNativeTextField {
        let textField = SpotlightSettingsNativeTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = "Search settings"
        textField.font = .systemFont(ofSize: 15)
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.setAccessibilityLabel("Search Settings")
        return textField
    }

    func updateNSView(
        _ textField: SpotlightSettingsNativeTextField,
        context: Context
    ) {
        context.coordinator.text = $text
        context.coordinator.onCancel = onCancel

        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.makeCurrentEditorTransparent()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCancel: () -> Bool

        init(
            text: Binding<String>,
            onCancel: @escaping () -> Bool
        ) {
            self.text = text
            self.onCancel = onCancel
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? SpotlightSettingsNativeTextField else {
                return
            }
            textField.makeCurrentEditorTransparent()
            DispatchQueue.main.async { [weak textField] in
                textField?.makeCurrentEditorTransparent()
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? SpotlightSettingsNativeTextField else {
                return
            }
            textField.makeCurrentEditorTransparent()
            if text.wrappedValue != textField.stringValue {
                text.wrappedValue = textField.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  let textField = control as? SpotlightSettingsNativeTextField else {
                return false
            }

            if onCancel() {
                textField.stringValue = text.wrappedValue
            } else {
                textField.window?.makeFirstResponder(nil)
            }
            return true
        }
    }
}

@MainActor
final class SpotlightSettingsNativeTextField: NSTextField {
    override func layout() {
        super.layout()
        makeCurrentEditorTransparent()
    }

    func makeCurrentEditorTransparent() {
        drawsBackground = false
        backgroundColor = .clear

        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = false
        editor.backgroundColor = .clear

        if let clipView = editor.superview as? NSClipView {
            if let scrollView = clipView.superview as? NSScrollView {
                scrollView.drawsBackground = false
                scrollView.backgroundColor = .clear
            } else {
                clipView.drawsBackground = false
                clipView.backgroundColor = .clear
            }
        }
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
            content.glassEffect(.regular, in: Capsule())
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
        attachedWindow = window
        configureWindowChrome()
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
