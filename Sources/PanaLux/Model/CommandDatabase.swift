import Foundation

public struct LightroomCommand: Identifiable, Hashable {
    public let id: String
    public let label: String
    public let group: String
    public let type: String // "parameter" or "button"
    public let explanation: String
    
    public var isParameter: Bool {
        return type == "parameter"
    }
}

public class CommandDatabase: ObservableObject {
    public static let shared = CommandDatabase()
    
    @Published public var commands: [String: LightroomCommand] = [:]
    @Published public var categories: [String] = []
    
    public init() {
        loadCommands()
    }
    
    private func loadCommands() {
        guard let data = AppResources.data("commands", "json") else {
            print("[CommandDatabase] Could not locate commands.json, using fallback dictionary.")
            populateFallbacks()
            return
        }
        
        struct RawEntry: Decodable {
            let label: String
            let group: String
            let type: String
            let explanation: String?
        }
        
        do {
            let rawDict = try JSONDecoder().decode([String: RawEntry].self, from: data)
            var parsed: [String: LightroomCommand] = [:]
            var groupSet = Set<String>()
            
            for (key, item) in rawDict {
                let cmd = LightroomCommand(
                    id: key,
                    label: item.label.isEmpty ? key : item.label,
                    group: item.group,
                    type: item.type,
                    explanation: Self.cleanExplanation(item.explanation ?? "")
                )
                parsed[key] = cmd
                if !item.group.isEmpty {
                    groupSet.insert(item.group)
                }
            }
            
            self.commands = parsed
            self.categories = ["All"] + Array(groupSet).sorted()
        } catch {
            print("[CommandDatabase] Error parsing commands.json: \(error)")
            populateFallbacks()
        }
    }
    
    /// The MIDI2LR wiki text has Markdown and mis-decoded UTF-8 ("\\226\\128\\153"). Make it plain.
    static func cleanExplanation(_ raw: String) -> String {
        var t = raw
        t = t.replacingOccurrences(of: "\\226\\128\\153", with: "’")
        t = t.replacingOccurrences(of: "\\226\\128\\148", with: "—")
        t = t.replacingOccurrences(of: "\\226\\128\\147", with: "–")
        t = t.replacingOccurrences(of: #"\\\d{3}"#, with: "", options: .regularExpression)
        for token in ["**", "<kbd>", "</kbd>", "`"] {
            t = t.replacingOccurrences(of: token, with: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func populateFallbacks() {
        let basics = [
            ("Exposure", "Exposure", "parameter", "basic"),
            ("Contrast", "Contrast", "parameter", "basic"),
            ("Highlights", "Highlights", "parameter", "basic"),
            ("Shadows", "Shadows", "parameter", "basic"),
            ("Whites", "Whites", "parameter", "basic"),
            ("Blacks", "Blacks", "parameter", "basic"),
            ("Texture", "Texture", "parameter", "basic"),
            ("Clarity", "Clarity", "parameter", "basic"),
            ("Dehaze", "Dehaze", "parameter", "basic"),
            ("Vibrance", "Vibrance", "parameter", "basic"),
            ("Saturation", "Saturation", "parameter", "basic"),
            ("Temperature", "Temperature", "parameter", "basic"),
            ("Tint", "Tint", "parameter", "basic"),
            ("AutoTone", "Auto Tone", "button", "basic"),
            ("ResetAll", "Reset All", "button", "basic")
        ]
        var parsed: [String: LightroomCommand] = [:]
        for (id, label, type, group) in basics {
            parsed[id] = LightroomCommand(id: id, label: label, group: group, type: type, explanation: "")
        }
        self.commands = parsed
        self.categories = ["All", "basic"]
    }
    
    public func label(for id: String) -> String {
        if let override = Self.titleOverrides[id] { return override }
        if let mask = Self.maskTitle(id) { return mask }
        if id.hasPrefix("local_"), let cmd = commands[id] {
            return "Mask " + cmd.label.prefix(1).uppercased() + cmd.label.dropFirst()
        }
        if id.hasPrefix("Crop"), ["CropLeft", "CropRight", "CropTop", "CropBottom"].contains(id), let cmd = commands[id] {
            return "Crop \(cmd.label)"
        }
        if let cmd = commands[id] {
            if cmd.label.count < 4 || cmd.label.lowercased() == "auto" {
                return "\(humanizeGroup(cmd.group)): \(cmd.label)"
            }
            // "ResetSharpness" is labeled "Sharpness" in the plugin, same as the slider.
            if id.hasPrefix("Reset"), !cmd.isParameter, !cmd.label.lowercased().hasPrefix("reset") {
                return "Reset \(cmd.label)"
            }
            return cmd.label
        }
        if let special = CommandCatalog.shared.command(for: id) { return special.title }
        return id
    }
    
    /// A few characters for the HUD's twelve-knob row.
    public func shortLabel(for id: String) -> String {
        if let short = Self.shortOverrides[id] { return short }
        var t = label(for: id)
        for (long, short) in Self.shortening {
            t = t.replacingOccurrences(of: long, with: short)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
    
    /// Knobs and rings accept sliders and turn-to-step commands.
    public func isDialable(_ id: String) -> Bool {
        (commands[id]?.isParameter ?? false) || RepeatCommands.isRepeat(id)
    }
    
    private static let maskKinds: [String: String] = [
        "Rad": "Radial", "Grad": "Linear", "Brush": "Brush", "Color": "Color Range", "Lum": "Luminance Range",
        "Depth": "Depth Range", "Sky": "Sky", "Subject": "Subject", "People": "People", "Obj": "Object",
        "Back": "Background", "Land": "Landscape"
    ]
    
    private static func maskTitle(_ id: String) -> String? {
        let verbs: [(String, String)] = [("MaskNew", "New %@ Mask"), ("MaskAdd", "Add %@ to Mask"),
                                         ("MaskSub", "Subtract %@"), ("MaskInt", "Intersect %@")]
        for (prefix, format) in verbs where id.hasPrefix(prefix) {
            guard let kind = maskKinds[String(id.dropFirst(prefix.count))] else { continue }
            return String(format: format, kind)
        }
        return nil
    }
    
    public func explanation(for id: String) -> String {
        commands[id]?.explanation ?? ""
    }
    
    public func catalogCommand(for id: String) -> CatalogCommand {
        if let special = CommandCatalog.shared.command(for: id) {
            return special
        }
        let cmd = commands[id]
        let title = label(for: id)
        let kind = RepeatCommands.isRepeat(id) ? "Turn to step" : ((cmd?.isParameter ?? true) ? "Slider" : "Command")
        let group = cmd.map { humanizeGroup($0.group) } ?? ""
        let subtitle = [kind, group, id].filter { !$0.isEmpty }.joined(separator: " · ")
        return CatalogCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            isParameter: cmd == nil ? true : isDialable(id),
            icon: RepeatCommands.isRepeat(id) ? "dial.medium" : ((cmd?.isParameter ?? true) ? "slider.horizontal.3" : "button.programmable")
        )
    }
    
    public func search(_ rawQuery: String, preferButtons: Bool) -> [CatalogCommand] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results: [CatalogCommand] = []
        var seen = Set<String>()
        
        func append(_ item: CatalogCommand) {
            guard !seen.contains(item.id) else { return }
            seen.insert(item.id)
            results.append(item)
        }
        
        if q.isEmpty {
            return allItems()
        }
        
        if let aliased = Self.searchAliases[q] {
            append(catalogCommand(for: aliased))
        }
        for (alias, id) in Self.searchAliases where alias.contains(q) || q.contains(alias) {
            append(catalogCommand(for: id))
        }
        
        for cat in CommandCatalog.shared.categories {
            for item in cat.items {
                if matches(item.title, item.subtitle, item.id, q) { append(item) }
            }
        }
        
        let ranked = commands.values.compactMap { cmd -> (Int, CatalogCommand)? in
            let item = catalogCommand(for: cmd.id)
            guard matches(item.title, item.subtitle, cmd.id, q) || cmd.group.lowercased().contains(q) else { return nil }
            var score = 0
            let t = item.title.lowercased()
            let i = cmd.id.lowercased()
            if t == q || i == q { score += 100 }
            if t.hasPrefix(q) || i.hasPrefix(q) { score += 40 }
            if t.contains(q) { score += 20 }
            if i.contains(q) { score += 10 }
            if preferButtons && !cmd.isParameter { score += 5 }
            return (score, item)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
        
        for item in ranked { append(item) }
        return results
    }
    
    /// Every MIDI2LR command plus panel extras (hold layers, Photoshop round-trip).
    public func allItems() -> [CatalogCommand] {
        var seen = Set<String>()
        var items: [CatalogCommand] = []
        for cmd in commands.values.sorted(by: { label(for: $0.id) < label(for: $1.id) }) {
            seen.insert(cmd.id)
            items.append(catalogCommand(for: cmd.id))
        }
        for extra in CommandCatalog.shared.categories.flatMap(\.items) where !seen.contains(extra.id) {
            seen.insert(extra.id)
            items.append(extra)
        }
        return items
    }
    
    public func items(inGroup group: String) -> [CatalogCommand] {
        if group == "All" { return allItems() }
        return commands.values
            .filter { $0.group == group }
            .sorted { label(for: $0.id) < label(for: $1.id) }
            .map { catalogCommand(for: $0.id) }
    }
    
    /// Groups from commands.json, Mask near the front, plus a Panel extras bucket.
    public func browseGroups() -> [String] {
        var groups = categories.filter { $0 != "All" }
        if let i = groups.firstIndex(of: "mask") {
            groups.remove(at: i)
            groups.insert("mask", at: min(1, groups.count))
        }
        return groups
    }
    
    private func matches(_ title: String, _ subtitle: String, _ id: String, _ q: String) -> Bool {
        title.lowercased().contains(q) || subtitle.lowercased().contains(q) || id.lowercased().contains(q)
    }
    
    private func humanizeGroup(_ group: String) -> String {
        let spaced = group.replacingOccurrences(of: "_", with: " ")
        if spaced == spaced.lowercased() {
            return spaced.capitalized
        }
        return spaced
    }
    
    private static let titleOverrides: [String: String] = [
        "WhiteBalanceAuto": "Auto White Balance",
        "WhiteBalanceAs_Shot": "White Balance: As Shot",
        "WhiteBalanceDaylight": "White Balance: Daylight",
        "WhiteBalanceCloudy": "White Balance: Cloudy",
        "WhiteBalanceShade": "White Balance: Shade",
        "WhiteBalanceTungsten": "White Balance: Tungsten",
        "WhiteBalanceFluorescent": "White Balance: Fluorescent",
        "WhiteBalanceFlash": "White Balance: Flash",
        "AutoTone": "Auto Tone",
        "NextPrev": "Previous / Next Photo",
        "SelectRightLeft": "Extend Selection",
        "RotateRightLeft": "Rotate Photo",
        "ZoomInOut": "Zoom",
        "ZoomOutIn": "Zoom (Reversed)",
        "PresetPreviousNext": "Step Through Presets",
        "RedoUndo": "Undo / Redo",
        "ChangeBrushSize": "Brush Size",
        "ChangeFeatherSize": "Brush Feather",
        "ChangeCurrentSlider": "Selected Slider",
        "ChangeLastDevelopParameter": "Last Adjusted Slider",
        "IncreaseDecreaseRating": "Star Rating",
        "MaskNext": "Next Mask",
        "MaskPrevious": "Previous Mask",
        "MaskNextTool": "Next Mask Tool",
        "MaskPreviousTool": "Previous Mask Tool",
        "MaskInvert": "Invert Mask",
        "MaskHide": "Show / Hide Mask Overlay",
        "MaskEnable": "Mask On / Off",
        "MaskDelete": "Delete Mask",
        "MaskReset": "Reset Mask",
        "CycleMaskOverlayColor": "Cycle Overlay Color",
        "ShoVwdevelop_before": "Before View",
        "ShoVwdevelop_loupe": "Develop Loupe",
        "ShoVwdevelop_before_after_horiz": "Before / After",
        "ShoVwdevelop_before_after_vert": "Before / After (Stacked)",
        "ShoVwcompare": "Compare View",
        "ShoVwsurvey": "Survey View",
        "ShoVwgrid": "Grid View",
        "ShoVwloupe": "Loupe View",
        "straightenAngle": "Straighten",
        "ResetstraightenAngle": "Reset Straighten",
        "CropOverlay": "Crop Tool",
        "ResetCrop": "Reset Crop",
        "PresetAmount": "Preset Amount",
        "local_Amount": "Mask Amount",
        "pointer:move": "Pointer",
        "pointer:click": "Click",
        "pointer:down": "Click and hold",
        "pointer:up": "Release click",
        "pointer:size": "Mask Size",
        "openExportWithPreviousDialog": "Export with Previous",
        "openExportDialog": "Export…",
        "LRCopy": "Copy Settings",
        "LRPaste": "Paste Settings",
        "FullRefresh": "Refresh Values from Lightroom",
        "smart_roundtrip": "Open as Layers in Photoshop"
    ]
    
    private static let shortOverrides: [String: String] = [
        "Exposure": "Exposure", "local_Exposure": "Exposure", "Temperature": "Temp", "local_Temperature": "Temp",
        "ColorGradeBlending": "Blending", "SplitToningBalance": "Balance", "straightenAngle": "Straighten",
        "PresetPreviousNext": "Presets", "NextPrev": "Photos", "ZoomInOut": "Zoom",
        "ChangeBrushSize": "Brush", "ChangeFeatherSize": "Feather", "IncreaseDecreaseRating": "Rating",
        "pointer:move": "Pointer", "pointer:click": "Click", "pointer:size": "Size",
        "LensProfileDistortionScale": "Distortion", "LensProfileVignettingScale": "Lens Vig",
        "LensManualDistortionAmount": "Manual Dist", "VignetteAmount": "Lens Vig Amt",
        "LensBlurAmount": "Blur", "LensBlurHighlightsBoost": "Bokeh Boost",
        "SharpenEdgeMasking": "Masking", "Sharpness": "Sharpen", "SharpenRadius": "Radius", "SharpenDetail": "Detail",
        "LuminanceSmoothing": "Lum NR", "ColorNoiseReduction": "Color NR", "GrainFrequency": "Roughness",
        "CurveRefineSaturation": "Refine Sat", "local_Amount": "Amount", "PresetAmount": "Amount"
    ]
    
    private static let shortening: [(String, String)] = [
        ("Saturation Adjustment ", "Sat "), ("Hue Adjustment ", "Hue "), ("Luminance Adjustment ", "Lum "),
        ("Post Crop Vignette ", "Vig "), ("Perspective ", ""), ("Mask ", ""), ("Crop ", ""),
        ("Color Noise Reduction ", "Color NR "), ("Luminance Noise Reduction ", "Lum NR "),
        ("Luminance ", "Lum "), ("Saturation", "Sat"), ("Defringe ", "Fringe "), ("Parametric ", ""),
        (" Amount", ""), ("Highlights", "Highs"), ("Temperature", "Temp")
    ]
    
    private static let searchAliases: [String: String] = [
        "auto temperature": "WhiteBalanceAuto",
        "auto temp": "WhiteBalanceAuto",
        "auto wb": "WhiteBalanceAuto",
        "awb": "WhiteBalanceAuto",
        "auto white balance": "WhiteBalanceAuto",
        "auto white": "WhiteBalanceAuto",
        "kelvin auto": "WhiteBalanceAuto",
        "auto tone": "AutoTone",
        "auto expose": "AutoTone",
        "auto color": "AutoTone",
        "compare": "ShoVwdevelop_before_after_horiz",
        "before after": "ShoVwdevelop_before_after_horiz",
        "brush size": "ChangeBrushSize",
        "straighten": "straightenAngle",
        "rotate crop": "straightenAngle",
        "export": "openExportWithPreviousDialog",
        "photoshop": "smart_roundtrip",
        "auto colour": "AutoTone",
        "autocolor": "AutoTone",
        "upright auto": "UprightAuto"
    ]
}
