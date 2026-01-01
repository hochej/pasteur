import AppKit
import Carbon

enum HotkeyParser {
    struct Result {
        let modifiers: NSEvent.ModifierFlags
        let keyCode: UInt32
    }

    static func parse(_ shortcut: String) -> Result {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        var modifiers: NSEvent.ModifierFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: keyPart = part
            }
        }

        let keyCode = keyCodeForKey(keyPart) ?? UInt32(kVK_ANSI_M)
        return Result(modifiers: modifiers, keyCode: keyCode)
    }

    private static func keyCodeForKey(_ key: String?) -> UInt32? {
        guard let key, !key.isEmpty else { return nil }
        let map: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A),
            "b": UInt32(kVK_ANSI_B),
            "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E),
            "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G),
            "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J),
            "k": UInt32(kVK_ANSI_K),
            "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M),
            "n": UInt32(kVK_ANSI_N),
            "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q),
            "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S),
            "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V),
            "w": UInt32(kVK_ANSI_W),
            "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y),
            "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0),
            "1": UInt32(kVK_ANSI_1),
            "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4),
            "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6),
            "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9)
        ]
        return map[key]
    }
}
