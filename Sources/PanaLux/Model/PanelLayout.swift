import Foundation

/// Physical layout of the Micro Color Panel — used by the Map, the tour, and the reference card.
public enum PanelLayout {
    public static let knobs: [String] = [
        "Y_LIFT", "Y_GAMMA", "Y_GAIN", "CONTRAST",
        "PIVOT", "MID_DETAIL", "COL_BOOST", "SHAD",
        "HI_LIGHT", "SAT", "HUE", "LUM_MIX"
    ]
    
    public static let balls: [String] = ["TB_LIFT", "TB_GAMMA", "TB_GAIN"]
    public static let rings: [String] = ["RING_LIFT", "RING_GAMMA", "RING_GAIN"]
    
    public static let knobLabels: [String: String] = [
        "Y_LIFT": "Knob 1 · Y Lift",
        "Y_GAMMA": "Knob 2 · Y Gamma",
        "Y_GAIN": "Knob 3 · Y Gain",
        "CONTRAST": "Knob 4 · Contrast",
        "PIVOT": "Knob 5 · Pivot",
        "MID_DETAIL": "Knob 6 · Mid Detail",
        "COL_BOOST": "Knob 7 · Color Boost",
        "SHAD": "Knob 8 · Shadows",
        "HI_LIGHT": "Knob 9 · Highlights",
        "SAT": "Knob 10 · Saturation",
        "HUE": "Knob 11 · Hue / Temp",
        "LUM_MIX": "Knob 12 · Lum Mix"
    ]
    
    public static let ballLabels: [String: String] = [
        "TB_LIFT": "Left ball · Shadows",
        "TB_GAMMA": "Center ball · Midtones",
        "TB_GAIN": "Right ball · Highlights"
    ]
    
    public static let ringLabels: [String: String] = [
        "RING_LIFT": "Left ring · Shadow lum",
        "RING_GAMMA": "Center ring · Midtone lum",
        "RING_GAIN": "Right ring · Highlight lum"
    ]
    
    public static let focusFavorites: [String] = [
        "Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks",
        "Texture", "Clarity", "Dehaze", "Vibrance", "Saturation",
        "Temperature", "Tint", "ColorGradeBlending"
    ]
    
    public struct ButtonGroup: Identifiable {
        public let id: String
        public let title: String
        public let buttons: [(id: String, label: String)]
    }
    
    public static let buttonGroups: [ButtonGroup] = [
        ButtonGroup(id: "grade", title: "Grade & Edit", buttons: [
            ("AUTO_COLOR", "Auto Color"),
            ("OFFSET", "Offset"),
            ("COPY", "Copy"),
            ("PASTE", "Paste"),
            ("UNDO", "Undo"),
            ("REDO", "Redo"),
            ("DELETE", "Delete"),
            ("RESET_ALL", "Reset All"),
            ("BYPASS", "Bypass"),
            ("DISABLE", "Disable")
        ]),
        ButtonGroup(id: "modifiers", title: "Modifiers", buttons: [
            ("USER", "User"),
            ("LOOP", "Loop"),
            ("SHIFT", "Up Shift"),
            ("CORNER_LOWER_RIGHT", "Down Shift")
        ]),
        ButtonGroup(id: "viewer", title: "Viewer & Select", buttons: [
            ("PLAY_STILL", "Play Still"),
            ("WIPE_STILL", "Wipe Still"),
            ("GRAB_STILL", "Grab Still"),
            ("H/LITE", "H / Lite"),
            ("VIEWER", "Viewer"),
            ("CURSOR", "Cursor"),
            ("SELECT", "Select")
        ]),
        ButtonGroup(id: "wheels", title: "Wheel Resets & Nodes", buttons: [
            ("RESET_LIFT", "Reset Lift"),
            ("RESET_GAMMA", "Reset Gamma"),
            ("RESET_GAIN", "Reset Gain"),
            ("ADD_NODE", "Add Node"),
            ("ADD_WINDOW", "Add Window"),
            ("ADD_KEYFRM", "Add Keyframe")
        ]),
        ButtonGroup(id: "nav", title: "Navigation", buttons: [
            ("PREV_STILL", "Prev Still"),
            ("NEXT_STILL", "Next Still"),
            ("PREV_KEYFRM", "Prev Keyframe"),
            ("NEXT_KEYFRM", "Next Keyframe"),
            ("PREV_NODE", "Prev Node"),
            ("NEXT_NODE", "Next Node"),
            ("PREV_FRAME", "Prev Frame"),
            ("NEXT_FRAME", "Next Frame"),
            ("PREV_CLIP", "Prev Clip"),
            ("NEXT_CLIP", "Next Clip")
        ]),
        ButtonGroup(id: "transport", title: "Transport", buttons: [
            ("PLAY_REV", "Reverse"),
            ("PLAY", "Play"),
            ("STOP", "Stop")
        ])
    ]
    
    public static func label(forControl id: String) -> String {
        if id.hasPrefix("PRESS_") { return "Press " + label(forControl: String(id.dropFirst(6))) }
        if let label = knobLabels[id] { return label }
        if let label = ballLabels[id] { return label }
        if let label = ringLabels[id] { return label }
        for group in buttonGroups {
            if let match = group.buttons.first(where: { $0.id == id }) {
                return match.label
            }
        }
        return id.replacingOccurrences(of: "_", with: " ")
    }
    
    /// "Knob 3", "Left ring" — for chips and tight spaces.
    public static func shortLabel(forControl id: String) -> String {
        if let i = knobs.firstIndex(of: id) { return "Knob \(i + 1)" }
        switch id {
        case "RING_LIFT": return "Left ring"
        case "RING_GAMMA": return "Center ring"
        case "RING_GAIN": return "Right ring"
        case "TB_LIFT": return "Left ball"
        case "TB_GAMMA": return "Center ball"
        case "TB_GAIN": return "Right ball"
        default: return label(forControl: id)
        }
    }
    
    public static var allButtons: [String] { buttonGroups.flatMap { $0.buttons.map(\.id) } }
    
    public static func isAnalog(_ id: String) -> Bool {
        knobs.contains(id) || balls.contains(id) || rings.contains(id)
            || id.hasPrefix("TB_") || id.hasPrefix("RING_") || id.hasPrefix("Y_")
    }
    
    public static func isKnob(_ id: String) -> Bool {
        knobs.contains(id) || id.hasPrefix("Y_")
    }
    
    public static func isRing(_ id: String) -> Bool {
        rings.contains(id) || id.hasPrefix("RING_")
    }
    
    public static func isBall(_ id: String) -> Bool {
        balls.contains(id) || id.hasPrefix("TB_")
    }
    
    public static func isButton(_ id: String) -> Bool {
        !isAnalog(id)
    }
}
