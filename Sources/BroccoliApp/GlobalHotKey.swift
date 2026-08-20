import Carbon
import Foundation

@MainActor
enum GlobalHotKeyActionDelivery {
    static func enqueue(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in action() }
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let commandSpace = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey)
    )

    static let controlSpace = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey)
    )

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
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
        let action: @MainActor () -> Void
    }

    private var bindings: [String: Binding] = [:]
    private var bindingIDs: [UInt32: String] = [:]
    private var nextIdentifier: UInt32 = 1
    private let signature: OSType = 0x464C5348 // FLSH
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
        try register(configuration, for: "launcher") { [weak self] in
            self?.onPressed?()
        }
    }

    func register(
        _ configuration: HotKeyConfiguration,
        for bindingID: String,
        action: @escaping @MainActor () -> Void
    ) throws {
        // A registered Carbon hot key is useful only when its application-level event handler
        // exists. Installation failure used to be ignored, allowing the menu bar to claim the
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
            action: action
        )
        bindingIDs[identifier.id] = bindingID
        nextIdentifier = nextIdentifier == UInt32.max ? 1 : nextIdentifier + 1
        if let previous {
            UnregisterEventHotKey(previous.reference)
            bindingIDs = bindingIDs.filter { $0.value != bindingID || $0.key == identifier.id }
        }
    }

    func unregister() {
        unregister("launcher")
    }

    func unregister(_ bindingID: String) {
        guard let binding = bindings.removeValue(forKey: bindingID) else { return }
        UnregisterEventHotKey(binding.reference)
        bindingIDs = bindingIDs.filter { $0.value != bindingID }
    }

    @discardableResult
    private func installHandler() -> OSStatus {
        guard eventHandler == nil else { return noErr }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
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
                return MainActor.assumeIsolated {
                    guard identifier.signature == owner.signature,
                          let bindingID = owner.bindingIDs[identifier.id],
                          let binding = owner.bindings[bindingID] else {
                        return OSStatus(eventNotHandledErr)
                    }
                    // Finish consuming the Carbon event before activating Broccoli or
                    // ordering windows. Re-entering AppKit synchronously from this callback
                    // can make the previous app resign and reactivate in the same event turn,
                    // which looks like Command-Space merely switched windows.
                    GlobalHotKeyActionDelivery.enqueue(binding.action)
                    return noErr
                }
            },
            1,
            &type,
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
