import Carbon.HIToolbox

/// System-wide hotkey via Carbon (works without Accessibility permission).
@MainActor
final class HotKey {
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            }
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: OSType(0x4643_4D53), id: id),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }
}
