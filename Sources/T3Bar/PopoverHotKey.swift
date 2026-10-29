import T3BarCore
import Carbon.HIToolbox
import Observation

/// Keeps the "open T3 Bar" shortcut from settings registered system-wide, and says why when the system refuses it.
///
/// Carbon's hot key API is used because it needs no Accessibility permission, unlike an event tap or a global
/// `NSEvent` monitor, and it consumes the keystroke so the frontmost app does not also act on it.
@MainActor @Observable
final class PopoverHotKey {
    /// Why the chosen shortcut does not work, for the Settings window; nil when it works or none is set.
    private(set) var failure: String?
    @ObservationIgnored var onPress: () -> Void = {}

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private var registration: EventHotKeyRef?
    /// While the Settings window records a new shortcut, the old one must not fire, or pressing it again to keep it
    /// would toggle the popover instead of being recorded.
    @ObservationIgnored private var isPaused = false

    /// Shared by every hot key this app registers; there is only one, so any press is ours.
    private static let hotKeyID = EventHotKeyID(signature: fourCharCode("AIBr"), id: 1)

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        installPressHandler()
        settingsDidChange()
    }

    func settingsDidChange() {
        unregister()
        guard !isPaused, let shortcut = settingsStore.settings.openPopoverShortcut else {
            failure = nil
            return
        }
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbonFlags, Self.hotKeyID,
                                         GetApplicationEventTarget(), 0, &registration)
        failure = status == noErr ? nil : "macOS didn't accept this shortcut (error \(status)). Try another."
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        settingsDidChange()
    }

    private func unregister() {
        guard let registration else { return }
        UnregisterEventHotKey(registration)
        self.registration = nil
    }

    /// Installed once for the app's lifetime, which is this object's lifetime, so `self` is never released under it.
    private func installPressHandler() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<PopoverHotKey>.fromOpaque(userData!).takeUnretainedValue().onPress()
            }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}

extension GlobalShortcut.Modifiers {
    fileprivate var carbonFlags: UInt32 {
        var flags = 0
        if contains(.control) { flags |= controlKey }
        if contains(.option) { flags |= optionKey }
        if contains(.shift) { flags |= shiftKey }
        if contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}

private func fourCharCode(_ code: String) -> OSType {
    code.utf8.reduce(0) { $0 << 8 | OSType($1) }
}
