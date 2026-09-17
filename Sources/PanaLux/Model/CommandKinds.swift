import Foundation

/// MIDI2LR "repeat" commands are knob gestures. The MIDI2LR desktop app normally turns them
/// into repeated button presses; PanaLux talks to the plugin directly, so it does that here.
public enum RepeatCommands {
    public struct Pair {
        public let clockwise: String
        public let counterClockwise: String
    }

    private static let pairs: [String: Pair] = {
        var table: [String: Pair] = [
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
        [ball?.hue, ball?.sat, ringParam]
            .compactMap { $0 }
            .map { "Reset" + $0 }
            .filter { known.contains($0) }
    }
}
