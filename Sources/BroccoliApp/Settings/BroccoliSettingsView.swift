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
    }
}

@available(macOS 26.0, *)
private struct BroccoliSettingsNativeTabView: View {
    let context: BroccoliSettingsContext
    @Bindable var shell: SettingsShellModel

    private var visibleSections: [PreferencesSection] {
        PreferencesSection.allCases.filter { $0.matches(settingsQuery: shell.searchQuery) }
    }

    var body: some View {
        TabView(selection: selection) {
            if visibleSections.isEmpty {
                Tab(
                    "No Results",
                    systemImage: "magnifyingglass",
                    value: shell.selection
                ) {
                    SettingsEmptySearchPane(query: shell.searchQuery)
                }
            } else {
                TabSection("Settings") {
                    ForEach(visibleSections) { section in
                        Tab(section.title, systemImage: section.symbol, value: section) {
                            tabDetail(for: section)
                        }
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .searchable(
            text: $shell.searchQuery,
            isPresented: $shell.isSearchPresented,
            placement: .sidebar,
            prompt: Text("Search settings")
        )
        .onChange(of: shell.searchQuery) { _, _ in
            keepSelectionVisible()
        }
        .background(SpotlightSettingsNativeWindowConfigurator(
            onWindowAttached: context.onWindowAttached
        ))
        .frame(
            width: SettingsWindowGeometry.initialContentSize.width,
            height: SettingsWindowGeometry.initialContentSize.height
        )
    }

    private var selection: Binding<PreferencesSection> {
        Binding(
            get: { shell.selection },
            set: { shell.selectSection($0, clearingSearch: false) }
        )
    }

    private func tabDetail(for section: PreferencesSection) -> some View {
        BroccoliSettingsTabDetail(
            context: context,
            shell: shell,
            section: section
        )
    }

    private func keepSelectionVisible() {
        guard let firstVisibleSection = visibleSections.first else { return }
        guard !visibleSections.contains(shell.selection) else { return }
        shell.selectSection(firstVisibleSection, clearingSearch: false)
    }

}

private struct BroccoliSettingsTabDetail: View {
    let context: BroccoliSettingsContext
    let shell: SettingsShellModel
    let section: PreferencesSection

    private var destination: SettingsDestination {
        shell.selection == section ? shell.destination : .section(section)
    }

    @ViewBuilder
    var body: some View {
        if shell.canGoBack || shell.canGoForward {
            detail
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: shell.goBack) {
                            Image(systemName: "chevron.backward")
                        }
                        .help("Back")
                        .disabled(!shell.canGoBack)

                        Button(action: shell.goForward) {
                            Image(systemName: "chevron.forward")
                        }
                        .help("Forward")
                        .disabled(!shell.canGoForward)
                    }
                }
        } else {
            detail
        }
    }

    private var detail: some View {
        SettingsDetailView(
            destination: destination,
            context: context,
            onNavigate: shell.navigate
        )
    }
}

private struct SettingsEmptySearchPane: View {
    let query: String

    var body: some View {
        SpotlightSettingsPane(
            title: "No Results"
        ) {
            SpotlightSettingsCard {
                SpotlightSettingsEmptyState(
                    title: "No settings found",
                    message: "Try searching for a section, feature, or preference.",
                    systemImage: "magnifyingglass"
                )
            }
        }
    }
}

private struct SettingsSidebarView: View {
    let shell: SettingsShellModel
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            sidebarSearchField
                .padding(.horizontal, SettingsShellLayout.searchHorizontalInset)
                .padding(.top, SettingsShellLayout.searchTopInset)
                .padding(.bottom, 14)

            SettingsSidebarList(
                shell: shell,
                onSelectionChanged: { isSidebarFocused = true }
            )
            .focused($isSidebarFocused)
            .onAppear {
                isSidebarFocused = true
            }
        }
    }

    @ViewBuilder private var sidebarSearchField: some View {
        if #available(macOS 26.0, *) {
            SettingsSidebarSearchField(shell: shell, usesGlassSurface: true)
                .frame(height: SettingsShellLayout.searchFieldHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            SettingsSidebarSearchField(shell: shell, usesGlassSurface: false)
                .frame(height: SettingsShellLayout.searchFieldHeight)
        }
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
                    Image(systemName: section.symbol)
                        .symbolVariant(.none)
                        .frame(
                            width: SettingsShellLayout.sidebarIconCanvasSize,
                            height: SettingsShellLayout.sidebarIconCanvasSize
                        )
                        .padding(.trailing, SettingsShellLayout.sidebarIconTrailingPadding)
                }
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: SettingsShellLayout.sidebarRowContentHeight)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        // Source-list selection otherwise starts inactive grey because the Settings scene is
        // born during Broccoli's accessory-to-regular activation transition. The selected
        // section is persistent navigation state and should always use the user's accent.
        .environment(\.controlActiveState, .active)
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

private struct SettingsSidebarSearchField: NSViewRepresentable {
    let shell: SettingsShellModel
    let usesGlassSurface: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shell: shell)
    }

    func makeNSView(context: Context) -> SettingsSearchFieldContainerView {
        let container = SettingsSearchFieldContainerView()
        let searchField = container.searchField
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 15)
        searchField.placeholderString = "Search"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        if usesGlassSurface {
            searchField.isBezeled = false
            searchField.drawsBackground = false
        }
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchFieldChanged(_:))
        searchField.setAccessibilityLabel("Search Settings")
        searchField.setAccessibilityHelp("Search Broccoli settings. Press Escape to clear.")
        return container
    }

    func updateNSView(_ container: SettingsSearchFieldContainerView, context: Context) {
        let searchField = container.searchField
        context.coordinator.shell = shell
        if searchField.stringValue != shell.searchQuery {
            searchField.stringValue = shell.searchQuery
        }
        guard shell.isSearchPresented, searchField.currentEditor() == nil else { return }
        DispatchQueue.main.async { [weak searchField] in
            guard let searchField, let window = searchField.window else { return }
            window.makeFirstResponder(searchField)
            searchField.selectText(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var shell: SettingsShellModel

        init(shell: SettingsShellModel) {
            self.shell = shell
        }

        @objc func searchFieldChanged(_ sender: NSSearchField) {
            updateQuery(from: sender)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            updateQuery(from: searchField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            shell.isSearchPresented = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  let searchField = control as? NSSearchField else {
                return false
            }

            if shell.cancelSearch() {
                searchField.stringValue = ""
            } else {
                searchField.window?.makeFirstResponder(nil)
            }
            return true
        }

        private func updateQuery(from searchField: NSSearchField) {
            guard shell.searchQuery != searchField.stringValue else { return }
            shell.searchQuery = searchField.stringValue
        }
    }
}

@MainActor
final class SettingsSearchFieldContainerView: NSView {
    let searchField = NSSearchField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(searchField)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: SettingsShellLayout.searchFieldHeight)
    }

    override func layout() {
        super.layout()
        searchField.frame = SettingsSearchFieldGeometry.nativeControlFrame(
            in: bounds,
            intrinsicHeight: searchField.intrinsicContentSize.height
        )
    }
}

enum SettingsSearchFieldGeometry {
    static func nativeControlFrame(in bounds: NSRect, intrinsicHeight: CGFloat) -> NSRect {
        let height = min(bounds.height, max(0, intrinsicHeight))
        return NSRect(
            x: bounds.minX,
            y: bounds.midY - (height / 2),
            width: bounds.width,
            height: height
        )
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
