import Carbon
import Cocoa

/// Global hotkey using Carbon RegisterEventHotKey — no accessibility permission needed.
class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    deinit {
        unregister()
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(0x564D4943), id: 1) // "VMIC"

        // Install handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let myself = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                myself.callback()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handlerCallback, 1, &eventType, selfPtr, &eventHandler)

        // Convert NSEvent modifier flags to Carbon modifiers
        var carbonMods: UInt32 = 0
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { carbonMods |= UInt32(controlKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { carbonMods |= UInt32(optionKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { carbonMods |= UInt32(shiftKey) }
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { carbonMods |= UInt32(cmdKey) }

        let status = RegisterEventHotKey(keyCode, carbonMods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            Log.d("GlobalHotkey registered: keyCode=\(keyCode), mods=\(carbonMods)")
        } else {
            Log.d("GlobalHotkey registration FAILED: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
