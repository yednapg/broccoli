import AppKit
import Carbon
import Foundation

@MainActor
enum GlobalHotKeyActionDelivery {
    enum Timing: Sendable {
        case immediate
        case afterCallback
    }

    static func perform(
        _ timing: Timing,
        action: @escaping @MainActor () -> Void
    ) {
        switch timing {
        case .immediate:
            action()
        case .afterCallback:
            Task { @MainActor in action() }
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let commandSpace = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey)
    )

    /// VoiceOver uses Control-Option for its own commands.
    var usesVoiceOverKeys: Bool {
        let voiceOverKeys = UInt32(controlKey | optionKey)
        return modifiers & voiceOverKeys == voiceOverKeys
    }

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined(separator: " + ")
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Escape"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let layoutDataPointer = TISGetInputSourceProperty(
                    source,
                    kTISPropertyUnicodeKeyLayoutData
                  ) else { return "Key \(keyCode)" }
            let data = unsafeBitCast(layoutDataPointer, to: CFData.self)
            let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )
            guard status == noErr, actualLength > 0 else { return "Key \(keyCode)" }
            return String(utf16CodeUnits: chars, count: actualLength).uppercased()
        }
    }
}

/// Keyboard shortcuts macOS keeps for itself, such as screenshots and Spotlight. A window
/// shortcut on one of them would either never reach Broccoli or take the shortcut from macOS.
struct MacOSReservedShortcuts: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let configuration: HotKeyConfiguration
        let title: String
    }

    let entries: [Entry]

    func owner(of configuration: HotKeyConfiguration) -> String? {
        entries.first { $0.configuration == configuration }?.title
    }

    /// The current user's macOS shortcuts. Keyboard settings stores only the shortcuts the user
    /// changed, so each built-in default applies unless that store turns it off or moves it.
    static var current: Self {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        return resolve(
            symbolicHotKeys: CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        )
    }

    static func resolve(symbolicHotKeys: [String: Any]?) -> Self {
        var symbolic = Dictionary(uniqueKeysWithValues: defaultSymbolicHotKeys.map { ($0.identifier, $0) })
        for (key, value) in symbolicHotKeys ?? [:] {
            guard let identifier = Int(key), let settings = value as? [String: Any] else { continue }
            let enabled = (settings["enabled"] as? NSNumber)?.boolValue ?? false
            let parameters = ((settings["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue)
            guard enabled else {
                symbolic[identifier] = nil
                continue
            }
            guard let parameters, parameters.count >= 3, parameters[1] != 65_535 else { continue }
            symbolic[identifier] = SymbolicHotKey(
                identifier: identifier,
                keyCode: parameters[1],
                eventModifiers: parameters[2],
                title: symbolic[identifier]?.title ?? "a macOS shortcut"
            )
        }
        let symbolicEntries = symbolic.values
            .sorted { $0.identifier < $1.identifier }
            .map { Entry(configuration: $0.configuration, title: $0.title) }
        return Self(entries: symbolicEntries + menuShortcuts)
    }

    private struct SymbolicHotKey {
        let identifier: Int
        let keyCode: Int
        /// AppKit modifier flags, as Keyboard settings stores them.
        let eventModifiers: Int
        let title: String

        var configuration: HotKeyConfiguration {
            var modifiers = 0
            if eventModifiers & (1 << 17) != 0 { modifiers |= shiftKey }
            if eventModifiers & (1 << 18) != 0 { modifiers |= controlKey }
            if eventModifiers & (1 << 19) != 0 { modifiers |= optionKey }
            if eventModifiers & (1 << 20) != 0 { modifiers |= cmdKey }
            return HotKeyConfiguration(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }
    }

    private static let shift = 1 << 17
    private static let control = 1 << 18
    private static let option = 1 << 19
    private static let command = 1 << 20

    private static let defaultSymbolicHotKeys: [SymbolicHotKey] = [
        SymbolicHotKey(identifier: 28, keyCode: kVK_ANSI_3, eventModifiers: shift | command, title: "screenshots"),
        SymbolicHotKey(identifier: 29, keyCode: kVK_ANSI_3, eventModifiers: control | shift | command, title: "screenshots"),
        SymbolicHotKey(identifier: 30, keyCode: kVK_ANSI_4, eventModifiers: shift | command, title: "screenshots"),
        SymbolicHotKey(identifier: 31, keyCode: kVK_ANSI_4, eventModifiers: control | shift | command, title: "screenshots"),
        SymbolicHotKey(identifier: 32, keyCode: kVK_UpArrow, eventModifiers: control, title: "Mission Control"),
        SymbolicHotKey(identifier: 33, keyCode: kVK_DownArrow, eventModifiers: control, title: "Application Windows"),
        SymbolicHotKey(identifier: 52, keyCode: kVK_ANSI_D, eventModifiers: option | command, title: "Dock hiding"),
        SymbolicHotKey(identifier: 60, keyCode: kVK_Space, eventModifiers: control, title: "input sources"),
        SymbolicHotKey(identifier: 61, keyCode: kVK_Space, eventModifiers: control | option, title: "input sources"),
        SymbolicHotKey(identifier: 64, keyCode: kVK_Space, eventModifiers: command, title: "Spotlight"),
        SymbolicHotKey(identifier: 65, keyCode: kVK_Space, eventModifiers: option | command, title: "Spotlight"),
        SymbolicHotKey(identifier: 79, keyCode: kVK_LeftArrow, eventModifiers: control, title: "switching Spaces"),
        SymbolicHotKey(identifier: 81, keyCode: kVK_RightArrow, eventModifiers: control, title: "switching Spaces"),
        SymbolicHotKey(identifier: 98, keyCode: kVK_ANSI_Slash, eventModifiers: shift | command, title: "the Help menu"),
        SymbolicHotKey(identifier: 184, keyCode: kVK_ANSI_5, eventModifiers: shift | command, title: "screenshots"),
    ]

    /// Shortcuts in the Apple menu and the application switcher, which every application shares.
    private static let menuShortcuts: [Entry] = [
        Entry(configuration: HotKeyConfiguration(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)), title: "switching applications"),
        Entry(configuration: HotKeyConfiguration(keyCode: UInt32(kVK_Tab), modifiers: UInt32(shiftKey | cmdKey)), title: "switching applications"),
        Entry(configuration: HotKeyConfiguration(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey | cmdKey)), title: "Force Quit"),
        Entry(configuration: HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(controlKey | cmdKey)), title: "Lock Screen"),
        Entry(configuration: HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(shiftKey | cmdKey)), title: "Log Out"),
    ]
}

@MainActor
final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        case unavailable(OSStatus)
        case handlerUnavailable(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unavailable(let status):
                "The shortcut is already in use or unavailable (\(status))."
            case .handlerUnavailable(let status):
                "Broccoli could not prepare the global shortcut handler (\(status))."
            }
        }
    }

    private var eventHandler: EventHandlerRef?
    private struct Binding {
        let reference: EventHotKeyRef
        let configuration: HotKeyConfiguration
        let deliveryTiming: GlobalHotKeyActionDelivery.Timing
        /// Acts again at the system key-repeat rate while the shortcut is held, like a step resize.
        let repeatsWhileHeld: Bool
        let action: @MainActor () -> Void
    }

    private var bindings: [String: Binding] = [:]
    private var bindingIDs: [UInt32: String] = [:]
    private var nextIdentifier: UInt32 = 1
    private let signature: OSType = 0x464C5348 // FLSH
    private var pressedIdentifierIDs: Set<UInt32> = []
    private var pressedAt: [UInt32: Date] = [:]
    private var repeatTasks: [UInt32: Task<Void, Never>] = [:]
    /// Ends a repeat whose release event was lost.
    private static let longestRepeat: TimeInterval = 10
    var configuration: HotKeyConfiguration? { bindings["launcher"]?.configuration }
    var onPressed: (() -> Void)?

    init() {
        _ = installHandler()
    }

    isolated deinit {
        for binding in bindings.values { UnregisterEventHotKey(binding.reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ configuration: HotKeyConfiguration) throws {
        try register(
            configuration,
            for: "launcher",
            deliveryTiming: .immediate
        ) { [weak self] in
            self?.onPressed?()
        }
    }

    func register(
        _ configuration: HotKeyConfiguration,
        for bindingID: String,
        repeatsWhileHeld: Bool = false,
        action: @escaping @MainActor () -> Void
    ) throws {
        try register(
            configuration,
            for: bindingID,
            deliveryTiming: .afterCallback,
            repeatsWhileHeld: repeatsWhileHeld,
            action: action
        )
    }

    private func register(
        _ configuration: HotKeyConfiguration,
        for bindingID: String,
        deliveryTiming: GlobalHotKeyActionDelivery.Timing,
        repeatsWhileHeld: Bool = false,
        action: @escaping @MainActor () -> Void
    ) throws {
        // A registered Carbon hot key is useful only when its application-level event handler
        // exists. Installation failure used to be ignored, leaving Settings to claim the
        // shortcut was ready even though no callback could ever be delivered. Retry once at the
        // point of registration and surface the real failure without creating a dead binding.
        if eventHandler == nil {
            let status = installHandler()
            guard status == noErr, eventHandler != nil else {
                throw RegistrationError.handlerUnavailable(status)
            }
        }
        if bindings[bindingID]?.configuration == configuration {
            let existing = bindings[bindingID]!
            bindings[bindingID] = Binding(
                reference: existing.reference,
                configuration: configuration,
                deliveryTiming: deliveryTiming,
                repeatsWhileHeld: repeatsWhileHeld,
                action: action
            )
            return
        }
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: nextIdentifier)
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw RegistrationError.unavailable(status)
        }
        // Keep the known-good shortcut alive until the replacement has registered. A conflict
        // must never leave the user without a way to reopen this accessory application.
        let previous = bindings[bindingID]
        bindings[bindingID] = Binding(
            reference: reference,
            configuration: configuration,
            deliveryTiming: deliveryTiming,
            repeatsWhileHeld: repeatsWhileHeld,
            action: action
        )
        bindingIDs[identifier.id] = bindingID
        nextIdentifier = nextIdentifier == UInt32.max ? 1 : nextIdentifier + 1
        if let previous {
            UnregisterEventHotKey(previous.reference)
            bindingIDs = bindingIDs.filter { $0.value != bindingID || $0.key == identifier.id }
        }
    }

    func unregister(_ bindingID: String) {
        guard let binding = bindings.removeValue(forKey: bindingID) else { return }
        UnregisterEventHotKey(binding.reference)
        bindingIDs = bindingIDs.filter { $0.value != bindingID }
        // Drop press tracking for identifiers that no longer resolve to a binding.
        pressedIdentifierIDs = pressedIdentifierIDs.filter { bindingIDs[$0] != nil }
        pressedAt = pressedAt.filter { bindingIDs[$0.key] != nil }
        for (identifier, task) in repeatTasks where bindingIDs[identifier] == nil {
            task.cancel()
            repeatTasks[identifier] = nil
        }
    }

    /// Carbon reports a held shortcut once, so a repeating binding repeats itself at the system
    /// key-repeat delay and rate until the shortcut is released.
    private func startRepeating(_ identifier: UInt32, action: @escaping @MainActor () -> Void) {
        repeatTasks[identifier]?.cancel()
        repeatTasks[identifier] = Task { @MainActor [weak self] in
            let started = Date()
            try? await Task.sleep(for: .seconds(NSEvent.keyRepeatDelay))
            while !Task.isCancelled,
                  let self,
                  self.pressedIdentifierIDs.contains(identifier),
                  Date().timeIntervalSince(started) < Self.longestRepeat {
                action()
                try? await Task.sleep(for: .seconds(NSEvent.keyRepeatInterval))
            }
        }
    }

    @discardableResult
    private func installHandler() -> OSStatus {
        guard eventHandler == nil else { return noErr }
        // Listening for the release as well lets a held key repeat be told apart from a
        // deliberate second press: repeats arrive without an intervening release.
        var types = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard parameterStatus == noErr else { return parameterStatus }
                let eventKind = GetEventKind(event)
                return MainActor.assumeIsolated {
                    guard identifier.signature == owner.signature,
                          let bindingID = owner.bindingIDs[identifier.id],
                          let binding = owner.bindings[bindingID] else {
                        return OSStatus(eventNotHandledErr)
                    }
                    if eventKind == UInt32(kEventHotKeyReleased) {
                        owner.pressedIdentifierIDs.remove(identifier.id)
                        owner.repeatTasks.removeValue(forKey: identifier.id)?.cancel()
                        return noErr
                    }
                    // Only the first press of a physical hold acts; toggling on repeated press
                    // events would open and close the launcher under the user's finger. Repeats
                    // arrive within the system key-repeat delay of the previous press; a press
                    // after a longer pause is a new one, so a lost release cannot wedge it.
                    let now = Date()
                    let isRepeat = owner.pressedIdentifierIDs.contains(identifier.id)
                        && owner.pressedAt[identifier.id].map {
                            now.timeIntervalSince($0) < NSEvent.keyRepeatDelay + 0.25
                        } ?? false
                    owner.pressedIdentifierIDs.insert(identifier.id)
                    owner.pressedAt[identifier.id] = now
                    if isRepeat { return noErr }
                    if binding.repeatsWhileHeld {
                        owner.startRepeating(identifier.id, action: binding.action)
                    }
                    // The launcher is a non-activating panel, so ordering it synchronously is
                    // safe and claims keyboard focus before the next key-down can reach the
                    // previously active application. Window-management bindings still defer:
                    // they can activate applications or present modal permission UI and must
                    // not re-enter AppKit from the Carbon callback.
                    GlobalHotKeyActionDelivery.perform(
                        binding.deliveryTiming,
                        action: binding.action
                    )
                    return noErr
                }
            },
            types.count,
            &types,
            pointer,
            &installedHandler
        )
        guard status == noErr, let installedHandler else {
            if let installedHandler { RemoveEventHandler(installedHandler) }
            return status == noErr ? OSStatus(paramErr) : status
        }
        eventHandler = installedHandler
        return noErr
    }
}
