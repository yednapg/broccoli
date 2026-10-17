@preconcurrency import AppKit
import SwiftUI

struct BroccoliSettingsSceneRoot: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        if let context = appDelegate.settingsContext {
            BroccoliSettingsShellView(context: context)
        } else {
            ProgressView()
                .frame(
                    width: SettingsWindowGeometry.initialContentSize.width,
                    height: SettingsWindowGeometry.initialContentSize.height
                )
        }
    }
}

private struct BroccoliSettingsShellView: View {
    let context: BroccoliSettingsContext
    private var shell: SettingsShellModel { context.shell }

    var body: some View {
        BroccoliSettingsNativeSearchSplitView(
            context: context,
            shell: shell
        )
    }
}

private struct BroccoliSettingsNativeSearchSplitView: View {
    let context: BroccoliSettingsContext
    @Bindable var shell: SettingsShellModel
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsNativeSearchSidebarView(
                shell: shell,
                onSelectionChanged: { isSidebarFocused = true }
            )
                .navigationSplitViewColumnWidth(
                    min: SettingsShellLayout.sidebarWidth,
                    ideal: SettingsShellLayout.sidebarWidth,
                    max: SettingsShellLayout.sidebarWidth
                )
                .focused($isSidebarFocused)
                .toolbar(removing: .sidebarToggle)
                .onAppear {
                    isSidebarFocused = true
                }
        } detail: {
            BroccoliSettingsDetailView(
                context: context,
                shell: shell
            )
        }
        .navigationSplitViewStyle(.balanced)
        .background(SpotlightSettingsNativeWindowConfigurator(
            onWindowAttached: context.onWindowAttached
        ))
        .frame(
            width: SettingsWindowGeometry.initialContentSize.width,
            height: SettingsWindowGeometry.initialContentSize.height
        )
    }
}

private struct SettingsNativeSearchSidebarView: View {
    @Bindable var shell: SettingsShellModel
    let onSelectionChanged: () -> Void

    var body: some View {
        SettingsSidebarList(
            shell: shell,
            onSelectionChanged: onSelectionChanged
        )
            .searchable(
                text: $shell.searchQuery,
                isPresented: $shell.isSearchPresented,
                placement: .sidebar,
                prompt: Text("Search settings")
            )
            .background(SettingsNativeSearchFieldConfigurator())
    }
}

private struct SettingsNativeSearchFieldConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsNativeSearchFieldConfigurationView {
        SettingsNativeSearchFieldConfigurationView()
    }

    func updateNSView(
        _ nsView: SettingsNativeSearchFieldConfigurationView,
        context: Context
    ) {
        nsView.configureSearchFieldIfAvailable()
    }
}

@MainActor
private final class SettingsNativeSearchFieldConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureSearchFieldIfAvailable()
        DispatchQueue.main.async { [weak self] in
            self?.configureSearchFieldIfAvailable()
        }
    }

    override func layout() {
        super.layout()
        configureSearchFieldIfAvailable()
    }

    func configureSearchFieldIfAvailable() {
        guard let contentView = window?.contentView,
              let searchField = SettingsNativeSearchFieldAppearance.searchField(in: contentView) else {
            return
        }
        SettingsNativeSearchFieldAppearance.apply(to: searchField)
    }
}

@MainActor
enum SettingsNativeSearchFieldAppearance {
    static func apply(to searchField: NSSearchField) {
        guard searchField.controlSize != SettingsShellLayout.searchFieldControlSize
                || searchField.font?.pointSize != SettingsShellLayout.searchFieldFontSize else {
            return
        }
        searchField.controlSize = SettingsShellLayout.searchFieldControlSize
        searchField.font = .systemFont(ofSize: SettingsShellLayout.searchFieldFontSize)
        searchField.invalidateIntrinsicContentSize()
        searchField.superview?.invalidateIntrinsicContentSize()
        searchField.superview?.needsLayout = true
    }

    static func searchField(in view: NSView) -> NSSearchField? {
        if let searchField = view as? NSSearchField,
           searchField.placeholderString == "Search settings" {
            return searchField
        }
        for subview in view.subviews {
            if let searchField = searchField(in: subview) {
                return searchField
            }
        }
        return nil
    }
}

private struct SettingsSidebarList: View {
    let shell: SettingsShellModel
    let onSelectionChanged: () -> Void

    var body: some View {
        List(selection: sidebarSelection) {
            ForEach(PreferencesSection.allCases) { section in
                Label {
                    Text(section.title)
                } icon: {
                    // A template symbol is redrawn when the sidebar cell receives its tint,
                    // so the icon flashes once as the row appears. Draw the finished glyph
                    // instead and keep the cell from tinting it again.
                    SettingsSidebarSymbol(
                        symbol: section.symbol,
                        isSelected: shell.sidebarSelection == section
                    )
                        .frame(
                            width: SettingsShellLayout.sidebarIconCanvasSize,
                            height: SettingsShellLayout.sidebarIconCanvasSize
                        )
                        .padding(.trailing, SettingsShellLayout.sidebarIconTrailingPadding)
                }
                    .font(.system(size: SettingsShellLayout.sidebarLabelFontSize, weight: .medium))
                    .frame(height: SettingsShellLayout.sidebarRowContentHeight)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Settings Sections")
    }

    private var sidebarSelection: Binding<PreferencesSection?> {
        Binding(
            get: { shell.sidebarSelection },
            set: { section in
                guard let section else { return }
                shell.selectSection(section)
                onSelectionChanged()
            }
        )
    }
}

enum SettingsSidebarSymbolImage {
    static func image(symbol: String, isSelected: Bool, windowIsKey: Bool) -> NSImage {
        let canvas = SettingsShellLayout.sidebarIconCanvasSize
        let configuration = NSImage.SymbolConfiguration(
            pointSize: SettingsShellLayout.sidebarLabelFontSize,
            weight: .medium
        )
        guard let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: canvas, height: canvas))
        }
        let color: NSColor = if isSelected {
            windowIsKey ? .white : .labelColor
        } else {
            .controlAccentColor
        }
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
            let fitted = symbolImage.size
            let destination = NSRect(
                x: (rect.width - fitted.width) / 2,
                y: (rect.height - fitted.height) / 2,
                width: fitted.width,
                height: fitted.height
            )
            let drawn = symbolImage.copy() as? NSImage ?? symbolImage
            drawn.isTemplate = true
            drawn.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct SettingsSidebarSymbol: NSViewRepresentable {
    let symbol: String
    let isSelected: Bool

    func makeNSView(context: Context) -> SettingsSidebarSymbolView {
        let view = SettingsSidebarSymbolView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: SettingsSidebarSymbolView, context: Context) {
        view.symbol = symbol
        view.isSelected = isSelected
    }
}

private final class SettingsSidebarSymbolView: NSImageView {
    var symbol = "" {
        didSet {
            guard symbol != oldValue else { return }
            renderedKey = nil
            needsDisplay = true
        }
    }
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            renderedKey = nil
            needsDisplay = true
        }
    }
    private var renderedKey: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleNone
        imageAlignment = .alignCenter
    }

    required init?(coder: NSCoder) { nil }

    override var allowsVibrancy: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderedKey = nil
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderedKey = nil
        needsDisplay = true
    }

    override func viewWillDraw() {
        redrawIfNeeded()
        super.viewWillDraw()
    }

    private func redrawIfNeeded() {
        let windowIsKey = window?.isKeyWindow ?? false
        let key = "\(symbol)|\(isSelected)|\(windowIsKey)|\(effectiveAppearance.name.rawValue)"
        image?.isTemplate = false
        cell?.backgroundStyle = .normal
        contentTintColor = nil
        guard key != renderedKey else { return }
        renderedKey = key
        effectiveAppearance.performAsCurrentDrawingAppearance {
            image = SettingsSidebarSymbolImage.image(
                symbol: symbol,
                isSelected: isSelected,
                windowIsKey: windowIsKey
            )
        }
        image?.isTemplate = false
    }
}

private struct BroccoliSettingsDetailView: View {
    let context: BroccoliSettingsContext
    let shell: SettingsShellModel

    var body: some View {
        detail
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: shell.goBack) {
                        Image(systemName: "chevron.backward")
                    }
                    .help("Back")
                    .accessibilityLabel("Back")
                    .disabled(!shell.canGoBack)

                    Button(action: shell.goForward) {
                        Image(systemName: "chevron.forward")
                    }
                    .help("Forward")
                    .accessibilityLabel("Forward")
                    .disabled(!shell.canGoForward)
                }
            }
    }

    @ViewBuilder private var detail: some View {
        if !shell.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SettingsSearchResultsView(query: shell.searchQuery) { destination in
                shell.searchQuery = ""
                shell.navigate(to: destination)
            }
            .navigationTitle("Search")
        } else {
            SettingsDetailView(
                destination: shell.destination,
                context: context,
                onNavigate: shell.navigate
            )
        }
    }
}
