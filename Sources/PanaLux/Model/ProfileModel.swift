import Foundation

public struct KnobBinding: Codable, Equatable, Hashable {
    public var param: String
    public var scale: Double

    public init(param: String, scale: Double = 0.0003) {
        self.param = param
        self.scale = scale
    }
}

public struct RingBinding: Codable, Equatable, Hashable {
    public var param: String
    public var scale: Double

    public init(param: String, scale: Double = 0.0003) {
        self.param = param
        self.scale = scale
    }
}

public protocol ParamBound { var param: String { get } }
extension KnobBinding: ParamBound {}
extension RingBinding: ParamBound {}

public struct BallBinding: Codable, Equatable, Hashable {
    public var hue: String
    public var sat: String
    public var radius: Double
    public var invert_x: Bool
    public var invert_y: Bool
    /// When set, rolling the ball drives this one slider (up/down; left/right is gentler)
    /// instead of a hue + saturation color wheel.
    public var param: String?

    public init(hue: String, sat: String, radius: Double = 3000.0, invert_x: Bool = true, invert_y: Bool = true) {
        self.hue = hue
        self.sat = sat
        self.radius = radius
        self.invert_x = invert_x
        self.invert_y = invert_y
    }

    public static func slider(_ param: String) -> BallBinding {
        var b = BallBinding(hue: param, sat: param)
        b.param = param
        return b
    }
}

/// A programmable analog overlay attached to a button.
/// Scope `focus` drives one Lightroom parameter from knobs, wheels, or both.
/// Scope `knobs` / `wheels` / `all` remaps that entire row while the program is active.
public struct AnalogProgram: Codable, Equatable, Hashable {
    public var scope: String              // "focus" | "knobs" | "wheels" | "all"
    public var focusParam: String?
    public var driveKnobs: Bool
    public var driveBalls: Bool
    public var knobs: [String: KnobBinding]?
    public var rings: [String: RingBinding]?
    public var balls: [String: BallBinding]?
    public var lightOnlyThisButton: Bool

    enum CodingKeys: String, CodingKey {
        case scope
        case focusParam = "focus_param"
        case driveKnobs = "drive_knobs"
        case driveBalls = "drive_balls"
        case knobs, rings, balls
        case lightOnlyThisButton = "light_only"
    }

    public init(
        scope: String = "focus",
        focusParam: String? = nil,
        driveKnobs: Bool = true,
        driveBalls: Bool = true,
        knobs: [String: KnobBinding]? = nil,
        rings: [String: RingBinding]? = nil,
        balls: [String: BallBinding]? = nil,
        lightOnlyThisButton: Bool = true
    ) {
        self.scope = scope
        self.focusParam = focusParam
        self.driveKnobs = driveKnobs
        self.driveBalls = driveBalls
        self.knobs = knobs
        self.rings = rings
        self.balls = balls
        self.lightOnlyThisButton = lightOnlyThisButton
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "focus"
        focusParam = try c.decodeIfPresent(String.self, forKey: .focusParam)
        driveKnobs = try c.decodeIfPresent(Bool.self, forKey: .driveKnobs) ?? true
        driveBalls = try c.decodeIfPresent(Bool.self, forKey: .driveBalls) ?? true
        knobs = try c.decodeIfPresent([String: KnobBinding].self, forKey: .knobs)
        rings = try c.decodeIfPresent([String: RingBinding].self, forKey: .rings)
        balls = try c.decodeIfPresent([String: BallBinding].self, forKey: .balls)
        lightOnlyThisButton = try c.decodeIfPresent(Bool.self, forKey: .lightOnlyThisButton) ?? true
    }

    public var appliesToKnobs: Bool {
        switch scope {
        case "focus": return driveKnobs
        case "knobs", "all": return true
        default: return false
        }
    }

    public var appliesToWheels: Bool {
        switch scope {
        case "focus": return driveBalls
        case "wheels", "all": return true
        default: return false
        }
    }

    public var summary: String {
        switch scope {
        case "focus":
            let param = CommandCatalog.shared.friendlyTitle(for: focusParam ?? "parameter")
            var via: [String] = []
            if driveKnobs { via.append("knobs") }
            if driveBalls { via.append("wheels") }
            let drive = via.isEmpty ? "knobs" : via.joined(separator: " + ")
            return "Focus \(param) via \(drive)"
        case "knobs":
            return "Custom knob row"
        case "wheels":
            return "Custom wheels"
        case "all":
            return "Custom knobs + wheels"
        default:
            return "Function set"
        }
    }

    public static func focused(_ param: String, knobs: Bool = true, balls: Bool = true) -> AnalogProgram {
        AnalogProgram(scope: "focus", focusParam: param, driveKnobs: knobs, driveBalls: balls)
    }

    public static func from(layer: LayerSpec, scope: String) -> AnalogProgram {
        AnalogProgram(
            scope: scope,
            driveKnobs: scope != "wheels",
            driveBalls: scope != "knobs",
            knobs: layer.knobs,
            rings: layer.rings,
            balls: layer.balls
        )
    }
}

public struct ButtonBinding: Codable, Equatable, Hashable {
    public var action: String?
    public var layer: String?
    public var hold_layer: String?
    public var modifier: String?
    public var enter_layer: String?
    public var set_variant: String?
    public var ps: String?
    public var tapProgram: AnalogProgram?
    public var holdProgram: AnalogProgram?
    /// Fired when a hold engages; `release_action` fires when it lets go (hold-to-compare).
    public var hold_action: String?
    public var release_action: String?
    /// Circular tool wheel while held (`mask_tools`). Ring and ball pick a wedge; release fires it.
    public var hold_picker: String?

    enum CodingKeys: String, CodingKey {
        case action, layer, hold_layer, modifier, enter_layer, set_variant, ps
        case tapProgram = "tap_program"
        case holdProgram = "hold_program"
        case hold_action, release_action, hold_picker
    }

    public init(
        action: String? = nil,
        layer: String? = nil,
        hold_layer: String? = nil,
        modifier: String? = nil,
        enter_layer: String? = nil,
        set_variant: String? = nil,
        ps: String? = nil,
        tapProgram: AnalogProgram? = nil,
        holdProgram: AnalogProgram? = nil,
        hold_action: String? = nil,
        release_action: String? = nil,
        hold_picker: String? = nil
    ) {
        self.action = action
        self.layer = layer
        self.hold_layer = hold_layer
        self.modifier = modifier
        self.enter_layer = enter_layer
        self.set_variant = set_variant
        self.ps = ps
        self.tapProgram = tapProgram
        self.holdProgram = holdProgram
        self.hold_action = hold_action
        self.release_action = release_action
        self.hold_picker = hold_picker
    }

    public var hasTapFunctionSet: Bool {
        tapProgram != nil || layer != nil || action != nil || ps != nil
    }
    public var hasTapAnything: Bool { hasTapFunctionSet || set_variant != nil }
    public var hasHoldFunctionSet: Bool {
        holdProgram != nil || hold_layer != nil || modifier != nil || hold_action != nil || hold_picker != nil
    }
    public var hasAnyAssignment: Bool {
        action != nil || layer != nil || hold_layer != nil || modifier != nil ||
        enter_layer != nil || set_variant != nil || ps != nil ||
        tapProgram != nil || holdProgram != nil || hold_action != nil || hold_picker != nil
    }

    public mutating func clearTap() {
        tapProgram = nil
        action = nil
        ps = nil
        layer = nil
        set_variant = nil
        enter_layer = nil
    }

    public mutating func clearHold() {
        holdProgram = nil
        hold_layer = nil
        modifier = nil
        hold_action = nil
        release_action = nil
        hold_picker = nil
    }
}

public struct VariantSpec: Codable, Equatable {
    public var knobs: [String: KnobBinding]?
    public var rings: [String: RingBinding]?
    public var balls: [String: BallBinding]?
}

public struct LayerSpec: Codable, Equatable {
    public var knobs: [String: KnobBinding]?
    public var rings: [String: RingBinding]?
    public var balls: [String: BallBinding]?
    public var buttons: [String: ButtonBinding]?
    public var default_variant: String?
    public var variants: [String: VariantSpec]?
    public var comment: String?
    /// Short name shown in the HUD and inspector ("Crop & Straighten").
    public var title: String?

    enum CodingKeys: String, CodingKey {
        case knobs, rings, balls, buttons, variants, default_variant, title
        case comment = "_comment"
    }
}

public struct Profile: Codable, Equatable {
    public var knobs: [String: KnobBinding]
    public var rings: [String: RingBinding]
    public var balls: [String: BallBinding]
    public var buttons: [String: ButtonBinding]
    public var modifiers: [String]
    public var layers: [String: LayerSpec]
    public var photoshop: [String: String]?

    enum CodingKeys: String, CodingKey {
        case knobs, rings, balls, buttons, modifiers, layers, photoshop
    }

    public static func loadDefault() -> Profile {
        if let data = AppResources.data("default_profile", "json"), let profile = try? JSONDecoder().decode(Profile.self, from: data) {
            return profile
        }

        return Profile.fallback()
    }

    /// Bump when the factory map gains something existing users should receive.
    public static let schemaVersion = 13

    public static func loadUserOrDefault() -> Profile {
        let factory = loadDefault()
        guard let data = try? Data(contentsOf: userProfileURL) else {
            return factory
        }
        do {
            var saved = try JSONDecoder().decode(Profile.self, from: data)
            for (key, binding) in factory.buttons {
                if saved.buttons[key] == nil || saved.buttons[key]?.hasAnyAssignment == false {
                    saved.buttons[key] = binding
                }
            }
            for (key, layer) in factory.layers where saved.layers[key] == nil {
                saved.layers[key] = layer
            }
            let migrated = migrate(saved, factory: factory, defaults: .standard) { ProfileStore.backup(reason: "before update") }
            if migrated != saved {
                // Persist now; the schema flag is already bumped, so this must not wait for the next edit.
                save(migrated)
            }
            return migrated
        } catch {
            // Never let a factory save overwrite a map we could not read. Keep a copy first.
            ProfileStore.quarantine(userProfileURL, reason: "unreadable")
            print("[Profile] Could not decode saved profile, using factory map: \(error)")
            return factory
        }
    }

    /// Command IDs that never existed in MIDI2LR, mapped to the real ones.
    public static let renamedCommands: [String: String] = [
        "ToggleOverlay": "ShoVwdevelop_before_after_horiz",
        "ToggleReference": "ShoVwRefHoriz",
        "Unflag": "RemoveFlag",
        "SetLabelRed": "ToggleRed",
        "SetLabelYellow": "ToggleYellow",
        "SetLabelGreen": "ToggleGreen",
        "ColorGradeBalance": "SplitToningBalance"
    ]

    static func migrate(_ input: Profile, factory: Profile, defaults: UserDefaults, backup: () -> Void) -> Profile {
        var p = input
        for (key, var spec) in p.buttons {
            if let a = spec.action, let fixed = renamedCommands[a] { spec.action = fixed }
            p.buttons[key] = spec
        }
        for (name, var layer) in p.layers {
            if var buttons = layer.buttons {
                for (key, var spec) in buttons {
                    if let a = spec.action, let fixed = renamedCommands[a] { spec.action = fixed }
                    buttons[key] = spec
                }
                layer.buttons = buttons
            }
            p.layers[name] = layer
        }

        let seen = defaults.integer(forKey: "profileSchemaVersion")
        if seen < 2 {
            // v2 adds hold modes to keys that only had a tap. Keys the user already
            // gave a hold keep it. Layer titles come from the factory map.
            backup()
            for key in ["VIEWER", "SELECT", "CURSOR"] {
                guard let factoryHold = factory.buttons[key], factoryHold.hasHoldFunctionSet else { continue }
                var spec = p.buttons[key] ?? ButtonBinding()
                if !spec.hasHoldFunctionSet {
                    spec.hold_layer = factoryHold.hold_layer
                    spec.holdProgram = factoryHold.holdProgram
                    p.buttons[key] = spec
                }
            }
            for (name, layer) in factory.layers {
                if p.layers[name]?.title == nil { p.layers[name]?.title = layer.title }
                if name == "MASK", let fb = layer.buttons, (p.layers[name]?.buttons ?? [:]).isEmpty {
                    p.layers[name]?.buttons = fb
                }
            }
        }
        if seen < 3 {
            // v3: wheel resets used Lightroom's "reset current wheel", which resets whichever
            // wheel was last active. Point each key at its own wheel.
            if seen >= 2 { backup() }
            for (key, which) in [("RESET_LIFT", "LIFT"), ("RESET_GAMMA", "GAMMA"), ("RESET_GAIN", "GAIN")]
            where p.buttons[key]?.action == "ColorGradeResetCurrent" {
                p.buttons[key]?.action = WheelReset.prefix + which
            }
        }
        if seen < 4 {
            // v4: free Bypass / Disable keys get Select All and Sync Settings.
            for (key, action) in [("BYPASS", "lr_menu:select_all"), ("DISABLE", "lr_menu:sync")]
            where !(p.buttons[key]?.hasAnyAssignment ?? false) {
                p.buttons[key] = ButtonBinding(action: action)
            }
        }
        if seen < 5 {
            // v5: every factory mode gets a key. Only fills a hold (or a tap) that is empty.
            if seen >= 2 { backup() }
            let holds = [("AUTO_COLOR", "TONE"), ("H/LITE", "DETAIL"), ("PLAY_STILL", "EFFECTS"),
                         ("GRAB_STILL", "LENS"), ("PLAY", "PRESETS")]
            for (key, layer) in holds where p.layers[layer] != nil {
                var spec = p.buttons[key] ?? ButtonBinding()
                guard spec.hold_layer == nil, spec.modifier == nil, spec.holdProgram == nil,
                      spec.hold_action == nil, spec.layer == nil else { continue }
                spec.hold_layer = layer
                p.buttons[key] = spec
            }
            for (key, action) in [("PLAY_REV", "Prev"), ("NEXT_CLIP", "Next")]
            where !(p.buttons[key]?.hasAnyAssignment ?? false) {
                p.buttons[key] = ButtonBinding(action: action)
            }
        }
        if seen < 6 {
            // v6: hold Add Node opens the mask tool wheel. Left ball in Masks moves the pointer.
            if seen >= 2 { backup() }
            if let picker = factory.buttons["ADD_NODE"]?.hold_picker {
                var spec = p.buttons["ADD_NODE"] ?? ButtonBinding()
                if spec.hold_picker == nil, spec.hold_layer == nil, spec.holdProgram == nil,
                   spec.modifier == nil, spec.hold_action == nil {
                    spec.hold_picker = picker
                    p.buttons["ADD_NODE"] = spec
                }
                if var mask = p.layers["MASK"], var buttons = mask.buttons {
                    var overlay = buttons["ADD_NODE"] ?? ButtonBinding()
                    if overlay.hold_picker == nil, overlay.hold_layer == nil,
                       overlay.holdProgram == nil, overlay.hold_action == nil {
                        overlay.hold_picker = picker
                        buttons["ADD_NODE"] = overlay
                        mask.buttons = buttons
                        p.layers["MASK"] = mask
                    }
                }
            }
            if var mask = p.layers["MASK"] {
                var balls = mask.balls ?? [:]
                if balls["TB_LIFT"] == nil, let fb = factory.layers["MASK"]?.balls?["TB_LIFT"] {
                    balls["TB_LIFT"] = fb
                    mask.balls = balls
                }
                var rings = mask.rings ?? [:]
                if rings["RING_GAIN"]?.param == "local_ToningLuminance",
                   let fb = factory.layers["MASK"]?.rings?["RING_GAIN"], PointerCommands.isSize(fb.param) {
                    rings["RING_GAIN"] = fb
                    mask.rings = rings
                }
                var buttons = mask.buttons ?? [:]
                if buttons["LOOP"] == nil, let fb = factory.layers["MASK"]?.buttons?["LOOP"] {
                    buttons["LOOP"] = fb
                    mask.buttons = buttons
                }
                p.layers["MASK"] = mask
            }
        }
        if seen < 7 {
            // v7: right ball places the mask (Add Node sits above it). Left ball keeps mask color.
            if seen >= 2 { backup() }
            if var mask = p.layers["MASK"] {
                var balls = mask.balls ?? [:]
                func isMove(_ b: BallBinding?) -> Bool {
                    guard let b else { return false }
                    return PointerCommands.isMove(b.param ?? "") || PointerCommands.isMove(b.hue)
                }
                if isMove(balls["TB_LIFT"]), !isMove(balls["TB_GAIN"]) {
                    let oldGain = balls["TB_GAIN"]
                    balls["TB_GAIN"] = balls["TB_LIFT"]
                    balls["TB_LIFT"] = oldGain ?? factory.layers["MASK"]?.balls?["TB_LIFT"]
                } else if !isMove(balls["TB_GAIN"]),
                          let fb = factory.layers["MASK"]?.balls?["TB_GAIN"], isMove(fb) {
                    balls["TB_GAIN"] = fb
                }
                mask.balls = balls
                p.layers["MASK"] = mask
            }
        }
        if seen < 8 {
            // v8: placing is a latch, not a ball map. Pointer balls go back to mask color
            // so rolling a wheel cannot ColorGrade the whole photo while Masks is on.
            if var mask = p.layers["MASK"] {
                var balls = mask.balls ?? [:]
                func isMove(_ b: BallBinding?) -> Bool {
                    guard let b else { return false }
                    return PointerCommands.isMove(b.param ?? "") || PointerCommands.isMove(b.hue)
                }
                let local = factory.layers["MASK"]?.balls?["TB_LIFT"]
                    ?? BallBinding(hue: "local_ToningHue", sat: "local_ToningSaturation")
                var changed = false
                for name in ["TB_LIFT", "TB_GAMMA", "TB_GAIN"] {
                    if balls[name] == nil || isMove(balls[name]) {
                        balls[name] = local
                        changed = true
                    }
                }
                if changed {
                    if seen >= 2 { backup() }
                    mask.balls = balls
                    p.layers["MASK"] = mask
                }
            }
        }
        if seen < 9 {
            // v9: mask placement is mouse-only for now. Strip factory pointer overlays
            // so Loop and the right ring do not steal clicks while the wheel still creates the mask.
            if var mask = p.layers["MASK"] {
                var changed = false
                if var buttons = mask.buttons {
                    if let action = buttons["LOOP"]?.action, PointerCommands.isPointer(action) {
                        buttons.removeValue(forKey: "LOOP")
                        mask.buttons = buttons
                        changed = true
                    }
                }
                if var rings = mask.rings, PointerCommands.isSize(rings["RING_GAIN"]?.param ?? "") {
                    rings["RING_GAIN"] = factory.layers["MASK"]?.rings?["RING_GAIN"]
                        ?? RingBinding(param: "local_ToningLuminance")
                    mask.rings = rings
                    changed = true
                }
                if changed {
                    if seen >= 2 { backup() }
                    p.layers["MASK"] = mask
                }
            }
        }
        if seen < 10 {
            // v10: Previous Still was the one key the factory map left empty. It now
            // gathers a photo into the bracket. Only fill it if it is still empty.
            let existing = p.buttons["PREV_STILL"]
            if existing == nil || (existing?.hasTapAnything == false && existing?.hasHoldFunctionSet == false) {
                if seen >= 2 { backup() }
                var spec = existing ?? ButtonBinding()
                spec.action = factory.buttons["PREV_STILL"]?.action ?? "AddOrRemoveFromTargetColl"
                p.buttons["PREV_STILL"] = spec
            }
        }
        if seen < 11 {
            // v11: holding Undo rewinds the whole editing session. Its tap is still Undo, and
            // a key the user already gave a hold keeps it.
            if p.layers["REWIND"] == nil, let rewind = factory.layers["REWIND"] {
                p.layers["REWIND"] = rewind
            }
            var spec = p.buttons["UNDO"] ?? ButtonBinding()
            if p.layers["REWIND"] != nil, !spec.hasHoldFunctionSet {
                if seen >= 2 { backup() }
                spec.hold_layer = "REWIND"
                p.buttons["UNDO"] = spec
            }
        }
        if seen < 12 {
            // v12: Rewind grew a transport. Play, Play Reverse and Stop run the session back, and
            // the outer rings became the speed dials that replace the old strength blend. Only a
            // layer still carrying that blend is replaced; one the user rearranged is theirs.
            if p.layers["REWIND"]?.rings?["RING_GAIN"]?.param == "rewind:strength",
               let rewind = factory.layers["REWIND"] {
                if seen >= 2 { backup() }
                p.layers["REWIND"] = rewind
            }
        }
        if seen < 13 {
            // v13: Prev/Next Node hop between takes while Rewind is held. Only keys the layer
            // has not already given a job are filled.
            if var rewind = p.layers["REWIND"], let shipped = factory.layers["REWIND"] {
                var buttons = rewind.buttons ?? [:]
                var changed = false
                for key in ["PREV_NODE", "NEXT_NODE"] where buttons[key] == nil {
                    if let spec = shipped.buttons?[key] { buttons[key] = spec; changed = true }
                }
                if changed {
                    if seen >= 2 { backup() }
                    rewind.buttons = buttons
                    p.layers["REWIND"] = rewind
                }
            }
        }
        if seen < schemaVersion {
            defaults.set(schemaVersion, forKey: "profileSchemaVersion")
        }
        return p
    }

    public static func save(_ profile: Profile) {
        do {
            let dir = userProfileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoded(profile).write(to: userProfileURL, options: .atomic)
        } catch {
            print("[Profile] Save failed: \(error)")
        }
    }

    public static func encoded(_ profile: Profile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    static var userProfileURL: URL { AppPaths.profileURL }

    public static func fallback() -> Profile {
        return Profile(
            knobs: [
                "Y_LIFT": KnobBinding(param: "Blacks"),
                "Y_GAMMA": KnobBinding(param: "Exposure"),
                "Y_GAIN": KnobBinding(param: "Whites"),
                "CONTRAST": KnobBinding(param: "Contrast"),
                "PIVOT": KnobBinding(param: "Clarity"),
                "MID_DETAIL": KnobBinding(param: "Texture"),
                "COL_BOOST": KnobBinding(param: "Vibrance"),
                "SHAD": KnobBinding(param: "Shadows"),
                "HI_LIGHT": KnobBinding(param: "Highlights"),
                "SAT": KnobBinding(param: "Saturation"),
                "HUE": KnobBinding(param: "Temperature"),
                "LUM_MIX": KnobBinding(param: "ColorGradeBlending")
            ],
            rings: [
                "RING_LIFT": RingBinding(param: "ColorGradeShadowLum"),
                "RING_GAMMA": RingBinding(param: "ColorGradeMidtoneLum"),
                "RING_GAIN": RingBinding(param: "ColorGradeHighlightLum")
            ],
            balls: [
                "TB_LIFT": BallBinding(hue: "SplitToningShadowHue", sat: "SplitToningShadowSaturation"),
                "TB_GAMMA": BallBinding(hue: "ColorGradeMidtoneHue", sat: "ColorGradeMidtoneSat"),
                "TB_GAIN": BallBinding(hue: "SplitToningHighlightHue", sat: "SplitToningHighlightSaturation")
            ],
            buttons: [
                "AUTO_COLOR": ButtonBinding(action: "AutoTone"),
                "OFFSET": ButtonBinding(layer: "OFFSET"),
                "USER": ButtonBinding(hold_layer: "TRANSFORM"),
                "SHIFT": ButtonBinding(hold_layer: "MIXER"),
                "LOOP": ButtonBinding(modifier: "FINE")
            ],
            modifiers: ["FINE"],
            layers: [:]
        )
    }
}
