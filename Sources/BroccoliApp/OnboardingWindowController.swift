@preconcurrency import AppKit
import ServiceManagement
import SwiftUI

struct LaunchAtLoginAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let isAvailable: Bool

    init(status: SMAppService.Status) {
        isEnabled = status == .enabled
        isAvailable = status != .notFound
    }
}

private enum OnboardingLayout {
    static let contentSize = NSSize(width: 720, height: 500)
    static let minimumContentSize = NSSize(width: 620, height: 450)
    static let contentMaximumWidth: CGFloat = 570
    static let contentHorizontalPadding: CGFloat = 44
    static let navigationBottomPadding: CGFloat = 18
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onClosed: () -> Void

    init(
        preferences: AppPreferences,
        initialShortcutError: String?,
        retryShortcut: @escaping () -> String?,
        testLauncher: @escaping () -> Void,
        onFinished: @escaping () -> Void,
        onClosed: @escaping () -> Void = {}
    ) {
        self.onClosed = onClosed
        let model = OnboardingModel(
            shortcut: preferences.hotKey,
            menuBarIconEnabled: preferences.menuBarIconEnabled,
            initialShortcutError: initialShortcutError,
            retryShortcut: retryShortcut,
            changeShortcut: { configuration in
                let previousConfiguration = preferences.hotKey
                preferences.hotKey = configuration
                if let error = retryShortcut() {
                    // Registration is transactional: keep the last working preference when
                    // the newly recorded shortcut is unavailable.
                    preferences.hotKey = previousConfiguration
                    return error
                }
                return nil
            },
            changeMenuBarVisibility: { preferences.menuBarIconEnabled = $0 },
            testLauncher: testLauncher,
            onFinished: {
                preferences.onboardingCompleted = true
                onFinished()
            }
        )
        let root = OnboardingView(model: model)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingLayout.contentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Broccoli"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = OnboardingLayout.minimumContentSize
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed()
    }
}

@MainActor
private final class OnboardingModel: ObservableObject {
    struct ReassignmentConflict: Equatable {
        let attemptedShortcut: HotKeyConfiguration
        let message: String
    }

    enum Page: Int, CaseIterable {
        case welcome
        case shortcut
        case startAutomatically
        case ready

        var next: Page? { Page(rawValue: rawValue + 1) }
        var previous: Page? { Page(rawValue: rawValue - 1) }
    }

    private let retryShortcutRegistration: () -> String?
    private let changeShortcutRegistration: (HotKeyConfiguration) -> String?
    private let changeMenuBarVisibility: (Bool) -> Void
    let testLauncher: () -> Void
    let onFinished: () -> Void

    @Published var page: Page = .welcome
    @Published private(set) var shortcut: HotKeyConfiguration
    @Published var shortcutError: String?
    @Published private(set) var reassignmentConflict: ReassignmentConflict?
    @Published var launchAtLogin: Bool
    @Published var menuBarIconEnabled: Bool
    @Published var launchAtLoginError: String?
    @Published private(set) var launchAtLoginAvailable: Bool

    init(
        shortcut: HotKeyConfiguration,
        menuBarIconEnabled: Bool,
        initialShortcutError: String?,
        retryShortcut: @escaping () -> String?,
        changeShortcut: @escaping (HotKeyConfiguration) -> String?,
        changeMenuBarVisibility: @escaping (Bool) -> Void,
        testLauncher: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.shortcut = shortcut
        retryShortcutRegistration = retryShortcut
        changeShortcutRegistration = changeShortcut
        self.changeMenuBarVisibility = changeMenuBarVisibility
        self.testLauncher = testLauncher
        self.onFinished = onFinished
        shortcutError = initialShortcutError
        let launchAtLoginState = LaunchAtLoginAvailability(status: SMAppService.mainApp.status)
        launchAtLogin = launchAtLoginState.isEnabled
        self.menuBarIconEnabled = menuBarIconEnabled
        launchAtLoginAvailable = launchAtLoginState.isAvailable
    }

    var shortcutIsReady: Bool { shortcutError == nil }

    var canContinue: Bool {
        page != .shortcut || shortcutIsReady
    }

    func moveForward() {
        if page == .ready {
            onFinished()
            return
        }
        if page == .shortcut, !shortcutIsReady { return }
        if let next = page.next { page = next }
    }

    func moveBack() {
        if let previous = page.previous { page = previous }
    }

    func openKeyboardShortcuts() {
        if let route = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
        ), NSWorkspace.shared.open(route) {
            return
        }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: .init()
        )
    }

    func retryShortcut() {
        shortcutError = retryShortcutRegistration()
        if shortcutError == nil {
            reassignmentConflict = nil
        }
    }

    func changeShortcut(to configuration: HotKeyConfiguration) -> Bool {
        if let error = changeShortcutRegistration(configuration) {
            if shortcutIsReady {
                // GlobalHotKey keeps the known-good registration alive when the replacement
                // cannot be registered. Keep that state separate from the attempted conflict
                // so onboarding never claims the displayed, working shortcut is unavailable.
                reassignmentConflict = ReassignmentConflict(
                    attemptedShortcut: configuration,
                    message: error
                )
            } else {
                shortcutError = error
            }
            return false
        }
        shortcut = configuration
        shortcutError = nil
        reassignmentConflict = nil
        return true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLoginAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            refreshLaunchAtLoginAvailability()
            launchAtLoginError = launchAtLoginAvailable ? error.localizedDescription : nil
        }
    }

    func setMenuBarIconEnabled(_ enabled: Bool) {
        menuBarIconEnabled = enabled
        changeMenuBarVisibility(enabled)
    }

    private func refreshLaunchAtLoginAvailability() {
        let state = LaunchAtLoginAvailability(status: SMAppService.mainApp.status)
        launchAtLogin = state.isEnabled
        launchAtLoginAvailable = state.isAvailable
        if !state.isAvailable { launchAtLoginError = nil }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingBackdrop(page: model.page)

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    pageContent
                        .id(model.page)
                        .transition(pageTransition)
                        .frame(maxWidth: OnboardingLayout.contentMaximumWidth)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(350, proxy.size.height - 144)
                        )
                        .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)
                        .padding(.top, 58)
                        .padding(.bottom, 86)
                }
                .scrollIndicators(.hidden)
                .id(model.page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingNavigation(model: model)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 24)
                .padding(.bottom, OnboardingLayout.navigationBottomPadding)
        }
        .frame(
            minWidth: OnboardingLayout.minimumContentSize.width,
            minHeight: OnboardingLayout.minimumContentSize.height
        )
        .animation(
            reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.2),
            value: model.page
        )
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.page {
        case .welcome:
            WelcomePage()
        case .shortcut:
            ShortcutPage(model: model)
        case .startAutomatically:
            StartAutomaticallyPage(model: model)
        case .ready:
            ReadyPage(model: model)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity
        )
    }
}

private struct OnboardingBackdrop: View {
    let page: OnboardingModel.Page
    @Environment(\.colorScheme) private var colorScheme

    private var colors: (Color, Color) {
        switch page {
        case .welcome:
            (Color(red: 0.23, green: 0.48, blue: 1), Color(red: 0.54, green: 0.30, blue: 0.98))
        case .shortcut:
            (Color(red: 0.10, green: 0.62, blue: 1), Color(red: 0.20, green: 0.82, blue: 0.86))
        case .startAutomatically:
            (Color(red: 0.42, green: 0.36, blue: 0.98), Color(red: 0.94, green: 0.35, blue: 0.63))
        case .ready:
            (Color(red: 0.08, green: 0.72, blue: 0.48), Color(red: 0.17, green: 0.53, blue: 1))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                Circle()
                    .fill(colors.0)
                    .frame(width: proxy.size.width * 0.72)
                    .blur(radius: 100)
                    .opacity(colorScheme == .dark ? 0.20 : 0.12)
                    .offset(x: proxy.size.width * 0.37, y: -proxy.size.height * 0.36)

                Circle()
                    .fill(colors.1)
                    .frame(width: proxy.size.width * 0.62)
                    .blur(radius: 110)
                    .opacity(colorScheme == .dark ? 0.16 : 0.09)
                    .offset(x: -proxy.size.width * 0.40, y: proxy.size.height * 0.42)
            }
        }
        .ignoresSafeArea()
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            WelcomeProductHero()

            Text("Your Mac, at your fingertips.")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.top, 12)

            Text("Apps, files, settings, and actions—all from one private search.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WelcomeProductHero: View {
    private let symbols = ["square.grid.2x2.fill", "doc.fill", "bolt.fill"]

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.30), Color.purple.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 176, height: 176)
                .blur(radius: 20)

            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
                    .offset(
                        x: index == 0 ? -104 : (index == 1 ? 104 : 0),
                        y: index == 2 ? -70 : 22
                    )
                    .accessibilityHidden(true)
            }

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.20), radius: 18, y: 10)
                .accessibilityHidden(true)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search your Mac")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 24)
                Image(systemName: "return")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(width: 330, height: 42)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
            .offset(y: 82)
        }
        .frame(height: 206)
    }
}

private struct ShortcutPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            PageSymbol(symbol: "command", colors: [.blue, .cyan])

            Text("Open Broccoli in an instant.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.top, 14)

            Text("Press the shortcut from any app—your current window stays right where it is.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, 7)

            ShortcutKeycaps(configuration: model.shortcut)
                .padding(.top, 24)

            OnboardingShortcutRecorder(configuration: model.shortcut) { configuration in
                model.changeShortcut(to: configuration)
            }
            .frame(width: 220, height: 34)
            .padding(.top, 14)

            Group {
                if let conflict = model.reassignmentConflict {
                    VStack(spacing: 6) {
                        Label(
                            "\(conflict.attemptedShortcut.displayName) is unavailable",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        Text("\(model.shortcut.displayName) remains registered and ready.")
                            .foregroundStyle(.secondary)
                        Text(conflict.message)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                } else if model.shortcutIsReady {
                    Label(
                        "\(model.shortcut.displayName) is registered",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    VStack(spacing: 7) {
                        Label("This shortcut is unavailable", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        if let error = model.shortcutError {
                            Text(error)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.top, 10)

            if !model.shortcutIsReady {
                VStack(spacing: 9) {
                    Text("Turn off “Show Spotlight search” in Keyboard Shortcuts, then try again.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Button("Open Keyboard Shortcuts…", action: model.openKeyboardShortcuts)
                        Button("Try Again", action: model.retryShortcut)
                    }
                }
                .padding(.top, 10)
            } else if model.reassignmentConflict != nil {
                Text("Record another shortcut, or continue using \(model.shortcut.displayName).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 9)
            } else {
                Text("Select the shortcut to record another one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShortcutKeycaps: View {
    let configuration: HotKeyConfiguration

    var body: some View {
        HStack(spacing: 10) {
            Keycap("⌘", width: 54)
            Text("+")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tertiary)
            Keycap(configuration.displayName.components(separatedBy: " + ").last ?? "Space", width: 104)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current shortcut \(configuration.displayName)")
    }
}

private struct Keycap: View {
    let label: String
    let width: CGFloat

    init(_ label: String, width: CGFloat) {
        self.label = label
        self.width = width
    }

    var body: some View {
        Text(label)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(width: width, height: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
    }
}

private struct StartAutomaticallyPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            PageSymbol(symbol: "bolt.badge.clock.fill", colors: [.purple, .pink])

            Text("Always ready when you are.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)
                .padding(.top, 14)

            Text("Choose how Broccoli stays close without getting in your way.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 7)

            HStack(spacing: 14) {
                OnboardingSettingTile(
                    symbol: "power",
                    title: "Open at Login",
                    detail: model.launchAtLoginAvailable
                        ? "Ready when your Mac starts"
                        : "Unavailable in this build"
                ) {
                    Toggle(
                        "Launch Broccoli at Login",
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: model.setLaunchAtLogin
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.launchAtLoginAvailable)
                    .accessibilityValue(model.launchAtLogin ? "On" : "Off")
                }
                OnboardingSettingTile(
                    symbol: "menubar.rectangle",
                    title: "Menu Bar Icon",
                    detail: "A second way to open Broccoli"
                ) {
                    Toggle(
                        "Show Broccoli in Menu Bar",
                        isOn: Binding(
                            get: { model.menuBarIconEnabled },
                            set: model.setMenuBarIconEnabled
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityValue(model.menuBarIconEnabled ? "On" : "Off")
                }
            }
            .padding(.top, 26)

            Text("You can change these anytime in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 13)

            if let error = model.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReadyPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            MiniLauncherPreview()

            Text("Everything is one shortcut away.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1)

            Text("Try \(model.shortcut.displayName) now, then start searching your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 7)

            Button("Try Broccoli", systemImage: "magnifyingglass", action: model.testLauncher)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(" ", modifiers: [.command])
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MiniLauncherPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("finder")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 13)
            .frame(height: 39)

            Divider()

            MiniLauncherResult(symbol: "face.smiling", title: "Finder", selected: true)
            MiniLauncherResult(symbol: "folder", title: "Open Downloads", selected: false)
        }
        .padding(8)
        .frame(width: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Broccoli search preview showing Finder")
    }
}

private struct MiniLauncherResult: View {
    let symbol: String
    let title: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 26)
                .background(
                    selected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 7)
                )
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            if selected {
                Image(systemName: "return")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            selected ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct PageSymbol: View {
    let symbol: String
    let colors: [Color]

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 31, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.white)
            .frame(width: 72, height: 72)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .shadow(color: (colors.first ?? .accentColor).opacity(0.28), radius: 18, y: 10)
            .accessibilityHidden(true)
    }
}

private struct OnboardingNavigation: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if model.page == .welcome {
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else {
                    Button(action: model.moveBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(width: 86, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(OnboardingModel.Page.allCases, id: \.rawValue) { page in
                    Capsule()
                        .fill(page == model.page ? Color.accentColor : Color.secondary.opacity(0.32))
                        .frame(width: page == model.page ? 18 : 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.thinMaterial, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.page.rawValue + 1) of \(OnboardingModel.Page.allCases.count)")

            Spacer(minLength: 0)

            Button(model.page == .ready ? "Finish" : "Continue") {
                model.moveForward()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canContinue)
            .frame(width: 86, alignment: .trailing)
        }
    }
}

private struct OnboardingSettingTile<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    init(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityHidden(true)
                Spacer()
                accessory
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct OnboardingShortcutRecorder: NSViewRepresentable {
    let configuration: HotKeyConfiguration
    let onChange: (HotKeyConfiguration) -> Bool

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl(frame: .zero)
        control.configuration = configuration
        control.onChange = onChange
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.configuration = configuration
        control.onChange = onChange
    }
}
