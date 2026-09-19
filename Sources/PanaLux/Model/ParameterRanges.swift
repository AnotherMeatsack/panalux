import Foundation

/// What a Lightroom slider's 0…1 value means in the numbers Lightroom itself shows.
///
/// MIDI2LR normalises every parameter to 0…1, which throws away whether a slider runs
/// −100…100 or 0…150. Without that, a unipolar slider reads as a large negative number:
/// Sharpness 52 of 150 is 0.35 normalised, and printing it as bipolar gives "−31".
public struct ParameterRange: Equatable {
    public let low: Double
    public let high: Double
    public let decimals: Int
    public let suffix: String

    /// Sliders that rest at zero in the middle print a sign. Sliders that start at zero don't.
    public var isBipolar: Bool { low < 0 }

    public init(_ low: Double, _ high: Double, decimals: Int = 0, suffix: String = "") {
        self.low = low
        self.high = high
        self.decimals = decimals
        self.suffix = suffix
    }

    public func display(_ normalized: Double) -> String {
        let real = low + normalized * (high - low)
        if isBipolar {
            return ValueFormatter.signed(real, decimals: decimals, suffix: suffix)
        }
        return String(format: "%.\(decimals)f", real) + suffix
    }
}

/// How far a turn should move a slider, relative to the map's `scale`. Every map's scale was tuned
/// against a slider that spans 0…1 of *something reasonable*; a slider whose real span is far
/// wider needs its turns shrunk in proportion, or one click would cross a lot of it.
public enum ParameterFeel {
    /// Kelvin. The plugin used to squeeze Temperature into 3000–9000 K, which made the knob stop at
    /// 3000 K. It now spans Lightroom's whole 2000–50000 K, eight times wider, so a turn is
    /// eight times smaller: the knob feels exactly as it always did, and no longer has an end.
    static let temperatureSpan = 48_000.0
    static let temperatureFeltSpan = 6_000.0

    public static func travel(for param: String, range: ParameterRange? = nil) -> Double {
        guard param == "Temperature" else { return 1 }
        if let range {
            return range.high >= 1000 ? min(1, temperatureFeltSpan / (range.high - range.low)) : 1
        }
        return temperatureFeltSpan / temperatureSpan
    }
}

public enum ParameterRanges {
    /// Ranges as Lightroom's own panels show them. Anything absent falls back to the
    /// bipolar −100…100 default, which is right for most Develop sliders.
    static let table: [String: ParameterRange] = {
        var t: [String: ParameterRange] = [:]

        func bipolar(_ names: [String]) { for n in names { t[n] = ParameterRange(-100, 100) } }
        func unit(_ names: [String]) { for n in names { t[n] = ParameterRange(0, 100) } }

        // Basic
        bipolar(["Contrast", "Highlights", "Shadows", "Whites", "Blacks",
                 "Texture", "Clarity", "Dehaze", "Vibrance", "Saturation"])

        // Tone curve. The region sliders are bipolar; the splits between them are not.
        bipolar(["ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights"])
        unit(["ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit"])

        // Detail. These are the ones the bipolar default got most wrong.
        t["Sharpness"] = ParameterRange(0, 150)
        t["SharpenRadius"] = ParameterRange(0.5, 3.0, decimals: 1)
        unit(["SharpenDetail", "SharpenEdgeMasking",
              "LuminanceSmoothing", "LuminanceNoiseReductionDetail", "LuminanceNoiseReductionContrast",
              "ColorNoiseReduction", "ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness"])

        // Effects
        bipolar(["PostCropVignetteAmount", "PostCropVignetteRoundness", "VignetteAmount"])
        unit(["PostCropVignetteMidpoint", "PostCropVignetteFeather", "PostCropVignetteHighlightContrast",
              "VignetteMidpoint", "GrainAmount", "GrainSize", "GrainFrequency"])

        // Colour grading
        bipolar(["ColorGradeShadowLum", "ColorGradeMidtoneLum", "ColorGradeHighlightLum",
                 "ColorGradeGlobalLum", "SplitToningBalance"])
        unit(["ColorGradeBlending"])

        // Lens and transform
        unit(["DefringePurpleHueLo", "DefringePurpleHueHi", "DefringeGreenHueLo", "DefringeGreenHueHi"])
        t["DefringePurpleAmount"] = ParameterRange(0, 20)
        t["DefringeGreenAmount"] = ParameterRange(0, 20)
        t["LensProfileDistortionScale"] = ParameterRange(0, 200)
        t["LensProfileVignettingScale"] = ParameterRange(0, 200)
        t["LensProfileChromaticAberrationScale"] = ParameterRange(0, 200)
        bipolar(["LensManualDistortionAmount", "PerspectiveVertical", "PerspectiveHorizontal",
                 "PerspectiveAspect", "PerspectiveX", "PerspectiveY"])
        t["PerspectiveRotate"] = ParameterRange(-10, 10, decimals: 1, suffix: "°")
        t["PerspectiveScale"] = ParameterRange(50, 150)

        // Calibration
        bipolar(["ShadowTintCalibration",
                 "RedHueCalibration", "RedSaturationCalibration",
                 "GreenHueCalibration", "GreenSaturationCalibration",
                 "BlueHueCalibration", "BlueSaturationCalibration"])

        // Masks
        t["local_Exposure"] = ParameterRange(-4, 4, decimals: 2, suffix: " EV")
        unit(["local_LuminanceNoise", "local_Moire", "local_Defringe"])

        return t
    }()

    public static func range(for param: String) -> ParameterRange? {
        if let exact = table[param] { return exact }

        // Colour Mixer bands: Hue_Red, Saturation_Aqua, Luminance_Magenta…
        for prefix in ["Hue_", "Saturation_", "Luminance_"] where param.hasPrefix(prefix) {
            return ParameterRange(-100, 100)
        }
        // Colour grading wheels report an angle, not an amount.
        if param.hasPrefix("ColorGrade"), param.hasSuffix("Hue") {
            return ParameterRange(0, 360, suffix: "°")
        }
        if param.hasPrefix("ColorGrade"), param.hasSuffix("Sat") {
            return ParameterRange(0, 100)
        }
        // A mask slider usually matches its global namesake.
        if param.hasPrefix("local_") {
            let base = String(param.dropFirst("local_".count))
            if let inherited = table[base] { return inherited }
        }
        return nil
    }
}


/// Ranges describe the actual normalization window used by the plugin, scoped to
/// the photo so a delayed RAW reply cannot change a TIFF's control feel.
struct PhotoParameterRanges {
    private(set) var photoID: String?
    private(set) var values: [String: ParameterRange] = [:]
    mutating func reset(photoID: String?) { self.photoID = photoID; values.removeAll() }
    @discardableResult
    mutating func accept(_ payload: String) -> Bool {
        let fields = payload.split(separator: " ").map(String.init)
        guard fields.count == 4, fields[0] == photoID,
              let low = Double(fields[2]), let high = Double(fields[3]),
              low.isFinite, high.isFinite, high > low, (high - low).isFinite else { return false }
        let param = fields[1]
        let fallback = ParameterRanges.range(for: param)
        let suffix = param == "Temperature" ? (high >= 1000 ? " K" : "") : (fallback?.suffix ?? (param == "Exposure" ? " EV" : (param == "straightenAngle" ? "°" : "")))
        let decimals = (param == "Exposure" || param == "local_Exposure") ? 2 : (fallback?.decimals ?? (param == "straightenAngle" ? 1 : 0))
        values[param] = ParameterRange(low, high, decimals: decimals, suffix: suffix)
        return true
    }
}
