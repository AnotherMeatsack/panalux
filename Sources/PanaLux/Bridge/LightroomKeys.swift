import AppKit
import ApplicationServices

/// Types a keyboard shortcut into Lightroom. The plugin asks for these ("SendKey 12 c")
/// for Copy/Paste Settings and user keys; the stock MIDI2LR app used to do the typing.
enum LightroomKeys {
    static let bundleIDs = ["com.adobe.LightroomClassicCC7", "com.adobe.Lightroom"]

    static var lightroomPID: pid_t? {
        NSWorkspace.shared.runningApplications
            .first { bundleIDs.contains($0.bundleIdentifier ?? "") }?.processIdentifier
    }

    /// Plugin format: "<modifier bits> <key>". 1 Option, 2 Control, 4 Shift, 8 Command.
    static func send(_ payload: String) {
        let parts = payload.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let bits = Int(parts[0]) else { return }
        var flags: CGEventFlags = []
        if bits & 1 != 0 { flags.insert(.maskAlternate) }
        if bits & 2 != 0 { flags.insert(.maskControl) }
        if bits & 4 != 0 { flags.insert(.maskShift) }
        if bits & 8 != 0 { flags.insert(.maskCommand) }
        let key = String(parts[1]).trimmingCharacters(in: .whitespaces).lowercased()
        press(key, flags: flags)
    }

    @discardableResult
    static func press(_ key: String, flags: CGEventFlags) -> Bool {
        guard let code = keyCodes[key], let pid = lightroomPID,
              LightroomAccessibility.isTrusted(prompt: true) else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return false }
            e.flags = flags
            e.postToPid(pid)
        }
        return true
    }

    /// US ANSI virtual key codes.
    static let keyCodes: [String: CGKeyCode] = {
        let letters = "asdfhgzxcv_bqweryt123465=97-80]ou[ip_lj'k;\\,/nm."
        var map: [String: CGKeyCode] = [:]
        for (i, ch) in letters.enumerated() where ch != "_" {
            map[String(ch)] = CGKeyCode(i)
        }
        map["return"] = 36; map["tab"] = 48; map["space"] = 49; map[" "] = 49
        map["delete"] = 51; map["escape"] = 53; map["`"] = 50
        map["left"] = 123; map["right"] = 124; map["down"] = 125; map["up"] = 126
        return map
    }()
}
