import Carbon.HIToolbox
import NotchDeckCore

/// A system-wide keyboard shortcut registered with Carbon's
/// `RegisterEventHotKey`. Unlike a global `NSEvent` key monitor it needs no
/// Accessibility permission, and the shortcut is consumed so it never reaches
/// the frontmost app.
@MainActor
final class GlobalHotkey {
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Distinguishes our events from any other Carbon hotkeys in the process.
    private static let signature: OSType = 0x4E_44_43_4B // 'NDCK'
    private static let identifier: UInt32 = 1

    init(action: @escaping () -> Void) {
        self.action = action
        installHandler()
    }

    /// Replaces the current shortcut. Returns false when the shortcut is invalid
    /// or already taken by another app, leaving no shortcut registered.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        guard hotkey.isValid else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            Self.carbonModifiers(hotkey.modifiers),
            EventHotKeyID(signature: Self.signature, id: Self.identifier),
            GetApplicationEventTarget(),
            // Exclusive, so a shortcut another app already claimed fails loudly
            // here instead of silently firing in both apps.
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr, id.signature == GlobalHotkey.signature, id.id == GlobalHotkey.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers application-target events on the main thread.
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.action() }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }

    private static func carbonModifiers(_ modifiers: Hotkey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}
