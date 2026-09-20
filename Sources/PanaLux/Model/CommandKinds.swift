import Foundation
import CoreGraphics

/// MIDI2LR "repeat" commands are knob gestures. The MIDI2LR desktop app normally turns them
/// into repeated button presses; PanaLux talks to the plugin directly, so it does that here.
public enum RepeatCommands {
    public struct Pair {
        public let clockwise: String
        public let counterClockwise: String
    }

    private static let pairs: [String: Pair] = {
        var table: [String: Pair] = [
            "PointCurveBlacksUpDown": Pair(clockwise: "PanaLuxPointCurveBlacksUp", counterClockwise: "PanaLuxPointCurveBlacksDown"),
            "PointCurveHighlightsUpDown": Pair(clockwise: "PanaLuxPointCurveHighlightsUp", counterClockwise: "PanaLuxPointCurveHighlightsDown"),
            "NextPrev": Pair(clockwise: "Next", counterClockwise: "Prev"),
            "SelectRightLeft": Pair(clockwise: "Select1Right", counterClockwise: "Select1Left"),
            "RotateRightLeft": Pair(clockwise: "RotateRight", counterClockwise: "RotateLeft"),
            "ZoomInOut": Pair(clockwise: "ZoomInSmallStep", counterClockwise: "ZoomOutSmallStep"),
            "ZoomOutIn": Pair(clockwise: "ZoomOutSmallStep", counterClockwise: "ZoomInSmallStep"),
            "PresetPreviousNext": Pair(clockwise: "PresetNext", counterClockwise: "PresetPrevious"),
            "RedoUndo": Pair(clockwise: "Redo", counterClockwise: "Undo"),
            "ChangeBrushSize": Pair(clockwise: "BrushSizeLarger", counterClockwise: "BrushSizeSmaller"),
            "ChangeFeatherSize": Pair(clockwise: "BrushFeatherLarger", counterClockwise: "BrushFeatherSmaller"),
            "ChangeCurrentSlider": Pair(clockwise: "SliderIncrease", counterClockwise: "SliderDecrease"),
            "ChangeLastDevelopParameter": Pair(clockwise: "IncrementLastDevelopParameter", counterClockwise: "DecrementLastDevelopParameter"),
            "IncreaseDecreaseRating": Pair(clockwise: "IncreaseRating", counterClockwise: "DecreaseRating")
        ]
        for n in stride(from: 1, through: 39, by: 2) {
            table["Key\(n + 1)Key\(n)"] = Pair(clockwise: "Key\(n + 1)", counterClockwise: "Key\(n)")
        }
        for name in ["Blacks", "Clarity", "Contrast", "Exp", "Highlights", "Sat", "Shadows", "Temp", "Tint", "Vibrance", "Whites"] {
            table["QuickDev\(name)Adj"] = Pair(clockwise: "QuickDev\(name)Small", counterClockwise: "QuickDev\(name)SmallDec")
        }
        // The bundled bridge's public ID uses "Smal"; preserve that wire spelling.
        table["QuickDevTempAdj"] = Pair(clockwise: "QuickDevTempSmall", counterClockwise: "QuickDevTempSmalDec")
        return table
    }()

    public static func pair(for id: String) -> Pair? {
        guard let pair = pairs[id] else { return nil }
        // Only offer pairs whose halves exist in this MIDI2LR catalog.
        let db = CommandDatabase.shared
        guard db.commands[pair.clockwise] != nil, db.commands[pair.counterClockwise] != nil else { return nil }
        return pair
    }

    public static func isRepeat(_ id: String) -> Bool { pair(for: id) != nil }
}

/// Commands whose result takes Lightroom a moment (AI masks, detection). The HUD shows a working state.
public enum SlowCommands {
    private static let aiMaskKinds = ["Subject", "Sky", "People", "Obj", "Back", "Depth", "Land"]

    public static func isSlow(_ id: String) -> Bool {
        guard id.hasPrefix("Mask") else { return false }
        return aiMaskKinds.contains { id.hasSuffix($0) }
    }
}

/// A button that fires one command on press and another on release (hold-to-compare).
public enum MomentaryCommands {
    public static let compareBefore = "ShoVwdevelop_before"
    public static let compareRestore = "ShoVwdevelop_loupe"
}

/// Trackball-as-mouse while Masks is on. Not MIDI2LR IDs.
/// A button that types a key into Lightroom, for the things Lightroom only offers as a shortcut.
/// The id says which: `key:\` is the backslash that flips Before and After, `key:shift+e` is
/// Shift-E, `key:cmd+opt+z` is Command-Option-Z. Modifiers are shift, cmd, opt and ctrl.
public enum KeyCommands {
    public static let prefix = "key:"
    /// Lightroom's own Before/After toggle: press for Before, press again to come back.
    public static let beforeAfter = "key:\\"

    public static func isKey(_ id: String) -> Bool { id.hasPrefix(prefix) && id.count > prefix.count }

    /// The key and modifiers an id asks for, or nil when it does not make sense.
    public static func parse(_ id: String) -> (key: String, flags: CGEventFlags)? {
        guard isKey(id) else { return nil }
        var parts = String(id.dropFirst(prefix.count)).components(separatedBy: "+")
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var flags: CGEventFlags = []
        for modifier in parts {
            switch modifier.lowercased() {
            case "shift": flags.insert(.maskShift)
            case "cmd", "command": flags.insert(.maskCommand)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: return nil
            }
        }
        let key = last.lowercased()
        guard LightroomKeys.keyCodes[key] != nil else { return nil }
        return (key, flags)
    }

    public static func title(_ id: String) -> String {
        if id == beforeAfter { return "Before / After (Toggle)" }
        guard let parsed = parse(id) else { return "Press a key" }
        var symbols = ""
        if parsed.flags.contains(.maskControl) { symbols += "⌃" }
        if parsed.flags.contains(.maskAlternate) { symbols += "⌥" }
        if parsed.flags.contains(.maskShift) { symbols += "⇧" }
        if parsed.flags.contains(.maskCommand) { symbols += "⌘" }
        return "Press \(symbols)\(parsed.key.uppercased()) in Lightroom"
    }
}

public enum PointerCommands {
    public static let prefix = "pointer:"
    public static let move = "pointer:move"
    public static let click = "pointer:click"
    public static let down = "pointer:down"
    public static let up = "pointer:up"
    public static let size = "pointer:size"

    public static func isPointer(_ id: String) -> Bool { id.hasPrefix(prefix) }
    public static func isMove(_ id: String) -> Bool { id == move }
    public static func isSize(_ id: String) -> Bool { id == size }
}

/// Rewind is PanaLux's own recorder, not a Lightroom command. These IDs are mapped like any
/// other command, so the whole gesture stays remappable.
public enum RewindCommands {
    public static let prefix = "rewind:"
    /// Analog: turn to move the playhead through the recording.
    public static let scrub = "rewind:scrub"
    /// Analog: the playback speed dial. The fine one is for slow motion, the coarse one for
    /// getting anywhere quickly. Clockwise is faster on both.
    public static let speedFine = "rewind:speed_fine"
    public static let landmarks = "rewind:landmarks"
    public static let tangents = "rewind:tangents"
    public static let speed = "rewind:speed"
    /// Keys: play forward, play backward, and stop where it is.
    public static let play = "rewind:play"
    public static let playReverse = "rewind:play_rev"
    public static let pause = "rewind:pause"
    /// Keys: hop to the previous or next tangent, keeping your place in time.
    public static let tangentPrevious = "rewind:take_prev"
    public static let tangentNext = "rewind:take_next"
    public static let tip = "rewind:tip"
    public static let mark = "rewind:mark"
    public static let branch = "rewind:branch"
    public static let previous = "rewind:prev"
    public static let next = "rewind:next"
    /// Hold to see the tip without moving the playhead; release goes back to the past.
    public static let peek = "rewind:peek"
    public static let unpeek = "rewind:unpeek"

    public static func isRewind(_ id: String) -> Bool { id.hasPrefix(prefix) }
    /// Knobs and rings drive these; everything else is a key.
    public static func isAnalog(_ id: String) -> Bool { id == scrub || id == speed || id == speedFine || id == landmarks || id == tangents }

    public static func title(_ id: String) -> String {
        switch id {
        case landmarks: return "Previous / next landmark"
        case tangents: return "Previous / next tangent"
        case scrub: return "Scrub the trail"
        case speed: return "Playback speed"
        case speedFine: return "Playback speed, fine"
        case play: return "Play"
        case playReverse: return "Play backward"
        case pause: return "Pause"
        case tangentPrevious: return "Previous tangent"
        case tangentNext: return "Next tangent"
        case tip: return "Back to now"
        case mark: return "Mark this"
        case branch: return "Branch here"
        case previous: return "Previous landmark"
        case next: return "Next landmark"
        case peek: return "Peek at now"
        case unpeek: return "Back to the past"
        default: return "Rewind"
        }
    }
}

/// "Reset Lift/Gamma/Gain" resets exactly that wheel: the ball's hue and saturation and the ring.
public enum WheelReset {
    public static let prefix = "reset_wheel:"

    public static func title(_ which: String) -> String {
        switch which {
        case "LIFT": return "Shadows wheel reset"
        case "GAMMA": return "Midtones wheel reset"
        case "GAIN": return "Highlights wheel reset"
        default: return "Wheel reset"
        }
    }

    /// MIDI2LR resets any slider with "Reset" + its name.
    public static func commands(ball: BallBinding?, ringParam: String?, known: Set<String>) -> [String] {
        [ball?.param ?? ball?.hue, ball?.param == nil ? ball?.sat : nil, ringParam]
            .compactMap { $0 }
            .map { "Reset" + $0 }
            .filter { known.contains($0) }
    }
}
