import AppKit
import Carbon

final class HotkeyController {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private let modifiers: NSEvent.ModifierFlags
    private let keyCode: UInt32
    private let hotKeyId: UInt32
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?

    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt32, handler: @escaping () -> Void) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.handler = handler
        self.hotKeyId = UInt32.random(in: 1...UInt32.max)
    }

    func register() {
        if !HotkeyController.handlerInstalled {
            HotkeyController.installGlobalHandler()
        }

        HotkeyController.handlers[hotKeyId] = handler

        var hotKeyID = EventHotKeyID(signature: fourCharCode("PSTR"), id: hotKeyId)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers(from: modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            HotkeyController.handlers.removeValue(forKey: hotKeyId)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        HotkeyController.handlers.removeValue(forKey: hotKeyId)
    }

    deinit {
        unregister()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private func fourCharCode(_ string: String) -> OSType {
        let scalars = Array(string.utf8)
        var result: UInt32 = 0
        for scalar in scalars.prefix(4) {
            result = (result << 8) + UInt32(scalar)
        }
        return result
    }

    private static func installGlobalHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if status == noErr, let handler = HotkeyController.handlers[hotKeyID.id] {
                    handler()
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            nil
        )
        handlerInstalled = true
    }
}
