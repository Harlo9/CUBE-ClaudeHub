import Carbon.HIToolbox

/// The keyboard shortcut that shows or hides the widget (⌃⌥W), from any app.
///
/// A "global hot key": the app asks macOS to watch for this key combination, and macOS
/// tells the app each time it is pressed, whatever app is in front. No permission is
/// needed (unlike watching every key), and the other apps no longer receive it.
@MainActor
final class WidgetHotKey {
    private let onPress: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Lives as long as the app (owned by the widget's window controller).
    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<WidgetHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.onPress() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let id = EventHotKeyID(signature: OSType(0x4355_4245), id: 1)   // "CUBE"
        let status = RegisterEventHotKey(Constants.Window.toggleHotKeyCode, Constants.Window.toggleHotKeyModifiers,
                                         id, GetApplicationEventTarget(), 0, &hotKey)
        // Already taken by another app: the shortcut does nothing, the rest works.
        if status != noErr { NSLog("Cube Hub: shortcut \(Constants.Window.toggleHotKeyLabel) unavailable (\(status))") }
    }
}
