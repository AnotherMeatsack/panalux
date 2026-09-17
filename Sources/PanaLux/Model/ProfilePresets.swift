import Foundation

public struct MappingPreset: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let blurb: String
    public let isHome: Bool

    public init(id: String, title: String, blurb: String, isHome: Bool = false) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.isHome = isHome
    }
}

public enum ProfilePresets {
    public static let home = MappingPreset(
        id: "home",
        title: "My Home",
        blurb: "The map you saved as home.",
        isHome: true
    )

    public static let factory: [MappingPreset] = [
        MappingPreset(id: "resolve", title: "Factory", blurb: "Lift/gamma/gain wheels, Shift mixer, User upright, Cursor masks, Viewer crop, Select cull."),
        MappingPreset(id: "cull", title: "Library Cull", blurb: "Pick, reject, rate, and move. Rings scroll photos and zoom."),
        MappingPreset(id: "portrait", title: "Portrait", blurb: "Skin first: texture, clarity, temp and tint. Masks on Cursor."),
        MappingPreset(id: "architecture", title: "Architecture", blurb: "Upright on Auto Color. Transform while holding User."),
        MappingPreset(id: "flash", title: "Flash Blend", blurb: "Grab Still opens frames as Photoshop layers. Play exports."),
        MappingPreset(id: "presets", title: "Preset Browser", blurb: "Knob 1 steps presets, ring sets the amount, the grade row fires presets 1–10.")
    ]

    public static var all: [MappingPreset] { [home] + factory }

    private static var homeURL: URL { AppPaths.homeURL }

    public static func snapshotHomeIfNeeded(_ profile: Profile) {
        if !FileManager.default.fileExists(atPath: homeURL.path) {
            snapshotHome(profile)
        }
    }

    public static func snapshotHome(_ profile: Profile) {
        Profile.save(profile)
        do {
            try FileManager.default.createDirectory(at: homeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Profile.encoded(profile).write(to: homeURL, options: .atomic)
        } catch {
            print("[Presets] Home snapshot failed: \(error)")
        }
    }

    public static func loadHome() -> Profile {
        if let data = try? Data(contentsOf: homeURL),
           let saved = try? JSONDecoder().decode(Profile.self, from: data) {
            return saved
        }
        return Profile.loadUserOrDefault()
    }

    public static func profile(for preset: MappingPreset) -> Profile {
        switch preset.id {
        case "home": return loadHome()
        case "cull": return culling(from: Profile.loadDefault())
        case "portrait": return portrait(from: Profile.loadDefault())
        case "architecture": return architecture(from: Profile.loadDefault())
        case "flash": return flashBlend(from: Profile.loadDefault())
        case "presets": return presetBrowser(from: Profile.loadDefault())
        default: return Profile.loadDefault()
        }
    }

    public static func apply(_ preset: MappingPreset, to engine: StudioEngine) {
        if !preset.isHome && !FileManager.default.fileExists(atPath: homeURL.path) {
            snapshotHome(engine.profile)
        }
        engine.replaceProfile(profile(for: preset), reason: "before \(preset.title)")
    }

    private static func culling(from base: Profile) -> Profile {
        var p = base
        p.buttons["SELECT"] = ButtonBinding(action: "Pick")
        p.buttons["DELETE"] = ButtonBinding(action: "Reject")
        p.buttons["UNDO"] = ButtonBinding(action: "Undo")
        p.buttons["REDO"] = ButtonBinding(action: "Redo")
        p.buttons["PREV_FRAME"] = ButtonBinding(action: "Prev")
        p.buttons["NEXT_FRAME"] = ButtonBinding(action: "Next")
        p.buttons["PREV_CLIP"] = ButtonBinding(action: "Prev")
        p.buttons["NEXT_CLIP"] = ButtonBinding(action: "Next")
        p.buttons["VIEWER"] = ButtonBinding(action: "SwToMlibrary", hold_layer: "CULL")
        p.buttons["PLAY"] = ButtonBinding(action: "SwToMdevelop")
        p.buttons["WIPE_STILL"] = ButtonBinding(action: "ShoVwcompare")
        p.buttons["H/LITE"] = ButtonBinding(action: "ShoVwsurvey")
        p.buttons["AUTO_COLOR"] = ButtonBinding(action: "SetRating1")
        p.buttons["OFFSET"] = ButtonBinding(action: "SetRating2")
        p.buttons["COPY"] = ButtonBinding(action: "SetRating3")
        p.buttons["PASTE"] = ButtonBinding(action: "SetRating4")
        p.buttons["RESET_ALL"] = ButtonBinding(action: "SetRating5")
        p.buttons["PLAY_STILL"] = ButtonBinding(action: "VirtualCopy")
        p.rings["RING_GAMMA"] = RingBinding(param: "NextPrev")
        p.rings["RING_GAIN"] = RingBinding(param: "ZoomInOut")
        return p
    }

    private static func portrait(from base: Profile) -> Profile {
        var p = base
        p.knobs["PIVOT"] = KnobBinding(param: "Clarity")
        p.knobs["MID_DETAIL"] = KnobBinding(param: "Texture")
        p.knobs["COL_BOOST"] = KnobBinding(param: "Vibrance")
        p.knobs["HUE"] = KnobBinding(param: "Temperature")
        p.knobs["SAT"] = KnobBinding(param: "Saturation")
        p.buttons["AUTO_COLOR"] = ButtonBinding(action: "WhiteBalanceAuto")
        p.buttons["ADD_KEYFRM"] = ButtonBinding(action: "MaskNewPeople", enter_layer: "MASK")
        return p
    }

    private static func architecture(from base: Profile) -> Profile {
        var p = base
        p.buttons["USER"] = ButtonBinding(hold_layer: "TRANSFORM")
        p.buttons["AUTO_COLOR"] = ButtonBinding(action: "UprightAuto")
        p.buttons["VIEWER"] = ButtonBinding(action: "UprightFull", hold_layer: "CROP")
        p.buttons["RESET_ALL"] = ButtonBinding(action: "ResetPerspectiveUpright")
        p.buttons["LOOP"] = ButtonBinding(action: "EnableLensCorrections", hold_layer: "LENS")
        return p
    }

    private static func flashBlend(from base: Profile) -> Profile {
        var p = base
        p.buttons["GRAB_STILL"] = ButtonBinding(ps: "smart_roundtrip")
        p.buttons["PLAY"] = ButtonBinding(action: "openExportWithPreviousDialog")
        p.buttons["PLAY_STILL"] = ButtonBinding(action: "VirtualCopy")
        p.buttons["CORNER_LOWER_RIGHT"] = ButtonBinding(hold_layer: "MULTISELECT")
        p.buttons["PREV_KEYFRM"] = ButtonBinding(action: "Prev")
        p.buttons["NEXT_KEYFRM"] = ButtonBinding(action: "Next")
        return p
    }

    private static func presetBrowser(from base: Profile) -> Profile {
        var p = base
        p.buttons["USER"] = ButtonBinding(hold_layer: "PRESETS")
        p.buttons["LOOP"] = ButtonBinding(action: "PresetNext", hold_layer: "PRESETS")
        return p
    }
}
