@preconcurrency import AppKit
import Carbon

/// What a finished launch should present. Opening Broccoli by hand shows Settings.
/// A login-item launch stays silent.
enum ApplicationLaunchPresentation: Equatable {
    case none
    case launcher
    case settings
}

enum ApplicationLaunchRouter {
    static func presentation(
        arguments: [String],
        launchedAsLoginItem: Bool
    ) -> ApplicationLaunchPresentation {
        if arguments.contains("--show-launcher") { return .launcher }
        if arguments.contains("--show-settings") { return .settings }
        return launchedAsLoginItem ? .none : .settings
    }

    /// macOS marks a login-item launch on the open event. Login launches carry the marker as
    /// the value of `keyAEPropData`; the SDK header also describes it as its own parameter.
    static func launchedAsLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            || event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }
}

/// Command-Q while Settings is key closes that window. The launcher holds focus without
/// Broccoli being the frontmost app, so the same shortcut there is handled by the panel
/// and must not be taken here.
enum SettingsCommandQ {
    static func closesSettings(event: NSEvent, settingsWindowIsKey: Bool) -> Bool {
        guard settingsWindowIsKey, event.type == .keyDown else { return false }
        return event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "q"
    }
}
