import Foundation

/// Maps a Base (global) develop slider onto the matching local/mask slider
/// so Masks keep every knob in the same seat.
public enum LocalAdjustments {
    /// Global MIDI2LR id → local id. Params with no local twin are omitted.
    public static let globalToLocal: [String: String] = [
        "Blacks": "local_Blacks",
        "Exposure": "local_Exposure",
        "Whites": "local_Whites",
        "Contrast": "local_Contrast",
        "Clarity": "local_Clarity",
        "Texture": "local_Texture",
        "Vibrance": "local_Dehaze",
        "Shadows": "local_Shadows",
        "Highlights": "local_Highlights",
        "Saturation": "local_Saturation",
        "Temperature": "local_Temperature",
        "Tint": "local_Tint",
        "ColorGradeBlending": "local_Amount",
        "Dehaze": "local_Dehaze",
        "Sharpness": "local_Sharpness",
        "LuminanceNoise": "local_LuminanceNoise"
    ]

    public static func localParam(forGlobal id: String) -> String? {
        if id.hasPrefix("local_") { return id }
        return globalToLocal[id]
    }

    /// One knob binding per Base knob, pointed at the local slider.
    public static func mirroredKnobs(from profile: Profile) -> [String: KnobBinding] {
        var out: [String: KnobBinding] = [:]
        for (id, knob) in profile.knobs {
            guard let local = localParam(forGlobal: knob.param) else { continue }
            out[id] = KnobBinding(param: local, scale: knob.scale)
        }
        return out
    }
}
