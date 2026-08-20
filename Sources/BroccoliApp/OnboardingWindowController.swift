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
    static let contentSize = NSSize(width: 660, height: 440)
    static let minimumContentSize = NSSize(width: 560, height: 400)
    static let contentHorizontalPadding: CGFloat = 40
    static let contentTopPadding: CGFloat = 28
    static let contentBottomPadding: CGFloat = 16
    static let cardMaximumWidth: CGFloat = 480
    static let rowMinimumHeight: CGFloat = 52
    static let cardCornerRadius: CGFloat = 10
    static let footerHeight: CGFloat = 54
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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "Set Up Broccoli"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                Group {
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
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)
                .padding(.top, OnboardingLayout.contentTopPadding)
                .padding(.bottom, OnboardingLayout.contentBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Recreate the scrolling container for each assistant page so a page that needed
            // scrolling never leaves the next page partway down.
            .id(model.page)

            Divider()
            OnboardingFooter(model: model)
        }
        .frame(
            minWidth: OnboardingLayout.minimumContentSize.width,
            minHeight: OnboardingLayout.minimumContentSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
                .padding(.bottom, 16)

            Text("Welcome to Broccoli")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Find what you need on your Mac, without sending queries anywhere.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 6)

            HStack(spacing: 26) {
                WelcomeFeature(symbol: "square.grid.2x2", title: "Apps & Settings")
                WelcomeFeature(symbol: "folder", title: "Files & Actions")
                WelcomeFeature(symbol: "hand.raised", title: "Private by Design")
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct WelcomeFeature: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .combine)
    }
}

private struct ShortcutPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose a Shortcut")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Use it to open Broccoli from any app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 6)

            OnboardingShortcutRecorder(configuration: model.shortcut) { configuration in
                model.changeShortcut(to: configuration)
            }
            .frame(width: 260, height: 38)
            .padding(.top, 28)

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
            .padding(.top, 14)

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
                .padding(.top, 15)
            } else if model.reassignmentConflict != nil {
                Text("Record another shortcut, or continue using \(model.shortcut.displayName).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
            } else {
                Text("Select the field to record another shortcut.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 460, maxHeight: .infinity, alignment: .top)
    }
}

private struct StartAutomaticallyPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Text("Keep Broccoli Ready")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Choose how Broccoli stays available.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 6)

            OnboardingCard {
                OnboardingSettingRow(
                    symbol: "power",
                    title: "Open at Login",
                    detail: model.launchAtLoginAvailable
                        ? "Ready as soon as you sign in"
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
                Divider().padding(.leading, 33)
                OnboardingSettingRow(
                    symbol: "menubar.rectangle",
                    title: "Menu Bar Icon",
                    detail: "Open Broccoli without the shortcut"
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
            .frame(maxWidth: OnboardingLayout.cardMaximumWidth)
            .padding(.top, 24)

            Text("You can change both options later in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 12)

            if let error = model.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ReadyPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Broccoli is Ready")
                .font(.title.weight(.semibold))
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Text("Use \(model.shortcut.displayName) to open it from any app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 6)

            HStack(spacing: 24) {
                Label(model.shortcut.displayName, systemImage: "keyboard")
                Label(model.menuBarIconEnabled ? "Menu Bar On" : "Menu Bar Off", systemImage: "menubar.rectangle")
                Label(model.launchAtLogin ? "Login On" : "Login Off", systemImage: "power")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 24)

            Button("Try Broccoli", systemImage: "bolt.fill", action: model.testLauncher)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(" ", modifiers: [.command])
                .padding(.top, 26)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct OnboardingFooter: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(OnboardingModel.Page.allCases, id: \.rawValue) { page in
                    Circle()
                        .fill(page == model.page ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.page.rawValue + 1) of \(OnboardingModel.Page.allCases.count)")

            HStack(spacing: 12) {
                if model.page == .welcome {
                    Button("Quit") { NSApp.terminate(nil) }
                } else {
                    Button("Back", action: model.moveBack)
                }

                Spacer()

                Button(model.page == .ready ? "Finish" : "Continue") {
                    model.moveForward()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
            }
            .padding(.horizontal, 20)
        }
        .frame(height: OnboardingLayout.footerHeight)
        .background(.bar)
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(
                cornerRadius: OnboardingLayout.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

private struct OnboardingStaticRow: View {
    let symbol: String
    let title: String
    let detail: String
    var trailing: String? = nil
    var symbolColor: Color = .secondary

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(symbolColor)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: OnboardingLayout.rowMinimumHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingSettingRow<Accessory: View>: View {
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
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 12)
            accessory
        }
        .frame(minHeight: OnboardingLayout.rowMinimumHeight)
        .contentShape(Rectangle())
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
