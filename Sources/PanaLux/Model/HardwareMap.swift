import Foundation

public class HardwareMap: ObservableObject {
    public static let shared = HardwareMap()
    
    @Published public var buttonBitToControl: [Int: String] = [:]
    @Published public var controlToButtonBit: [String: Int] = [:]
    
    private let customMapURL: URL = {
        let dir = AppPaths.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hardware_map.json")
    }()
    
    public init() {
        loadDefaultMap()
        loadCustomMap()
    }
    
    /// Button bits as reported by the Micro Color Panel (USB-C).
    private func loadDefaultMap() {
        let defaults: [Int: String] = [
            12: "AUTO_COLOR", 13: "OFFSET", 14: "COPY", 15: "PASTE",
            16: "UNDO", 17: "REDO", 18: "DELETE", 19: "RESET_ALL",
            20: "BYPASS", 21: "DISABLE",
            22: "USER", 23: "LOOP",
            24: "SHIFT",               // Physical Up-Shift (Upper-Left Triangle button)
            25: "CORNER_LOWER_RIGHT",  // Physical Down-Shift (Lower-Right Triangle button)
            26: "PLAY_STILL", 27: "WIPE_STILL", 28: "GRAB_STILL", 29: "H/LITE",
            30: "VIEWER", 31: "CURSOR", 32: "SELECT",
            33: "RESET_LIFT", 34: "RESET_GAMMA", 35: "RESET_GAIN",
            36: "ADD_NODE", 37: "ADD_WINDOW", 38: "ADD_KEYFRM",
            39: "PREV_STILL", 40: "NEXT_STILL",
            41: "PREV_FRAME", 42: "NEXT_FRAME",
            43: "PREV_NODE", 44: "NEXT_NODE",
            45: "PREV_CLIP", 46: "NEXT_CLIP",
            47: "PREV_KEYFRM", 48: "NEXT_KEYFRM",
            49: "PLAY_REV", 50: "PLAY", 51: "STOP"
        ]
        
        buttonBitToControl = defaults
        rebuildReverseMap()
    }
    
    private func rebuildReverseMap() {
        var rev: [String: Int] = [:]
        for (bit, name) in buttonBitToControl {
            rev[name] = bit
        }
        // Aliases for SVG mapping
        if let shiftBit = buttonBitToControl.first(where: { $0.value == "SHIFT" })?.key {
            rev["button_corner_upper_left"] = shiftBit
        }
        if let downShiftBit = buttonBitToControl.first(where: { $0.value == "CORNER_LOWER_RIGHT" })?.key {
            rev["button_corner_lower_right"] = downShiftBit
        }
        controlToButtonBit = rev
    }
    
    public func mapButton(bit: Int, to controlName: String) {
        buttonBitToControl[bit] = controlName
        rebuildReverseMap()
        saveCustomMap()
    }
    
    public func controlName(forButtonBit bit: Int) -> String? {
        return buttonBitToControl[bit]
    }
    
    public func buttonBit(forControl name: String) -> Int? {
        return controlToButtonBit[name]
    }
    
    private func loadCustomMap() {
        guard let data = try? Data(contentsOf: customMapURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (bitStr, name) in dict {
            if let bit = Int(bitStr) {
                buttonBitToControl[bit] = name
            }
        }
        rebuildReverseMap()
    }
    
    public func exportBits() -> [String: String] {
        var out: [String: String] = [:]
        for (bit, name) in buttonBitToControl {
            out[String(bit)] = name
        }
        return out
    }

    public func applyShared(_ bits: [String: String]) {
        for (key, name) in bits {
            guard let bit = Int(key) else { continue }
            buttonBitToControl[bit] = name
        }
        rebuildReverseMap()
        saveCustomMap()
    }

    private func saveCustomMap() {
        var stringDict: [String: String] = [:]
        for (bit, name) in buttonBitToControl {
            stringDict[String(bit)] = name
        }
        if let data = try? JSONEncoder().encode(stringDict) {
            try? data.write(to: customMapURL)
        }
    }
    
    public func resetToDefaults() {
        try? FileManager.default.removeItem(at: customMapURL)
        loadDefaultMap()
    }
}
