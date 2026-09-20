import Foundation

/// Builds hover-arrow links from a button to the analog controls it drives.
public enum MappingConnections {
    public static func all(from profile: Profile) -> [String: [[String: String]]] {
        var map: [String: [[String: String]]] = [:]
        for (button, spec) in profile.buttons {
            var links: [[String: String]] = []
            if let program = spec.tapProgram {
                links.append(contentsOf: analogLinks(program, profile: profile))
            }
            if let program = spec.holdProgram {
                links.append(contentsOf: analogLinks(program, profile: profile))
            }
            if spec.hold_picker != nil {
                links.append(contentsOf: pickerLinks())
            }
            if let layer = spec.hold_layer ?? spec.layer, let specLayer = profile.layers[layer] {
                links.append(contentsOf: layerLinks(specLayer, title: LayerNames.defaultTitle(layer)))
            }
            if !links.isEmpty, let svg = PanelControlMapping.profileToSvg[button] {
                map[svg] = links
            }
        }
        return map
    }

    public static func live(engine: StudioEngine) -> [String: [[String: String]]] {
        var map = all(from: engine.profile)
        var owners = Set(engine.physicallyHeldControlNames)
        if let held = engine.heldProgramButton { owners.insert(held) }
        if let edit = engine.inspectorHoldEdit { owners.insert(edit) }
        for name in owners {
            guard let svg = PanelControlMapping.profileToSvg[name] else { continue }
            let spec = engine.profile.buttons[name]
            if let program = spec?.holdProgram {
                let links = analogLinks(program, profile: engine.profile)
                map[svg] = links.isEmpty ? potentialAnalogTargets() : links
            } else if spec?.hold_picker != nil {
                map[svg] = pickerLinks()
            } else if spec?.hold_layer == nil && spec?.modifier == nil {
                if map[svg] == nil || map[svg]?.isEmpty == true {
                    map[svg] = potentialAnalogTargets()
                }
            }
        }
        return map
    }

    /// Every knob, ring, and ball a hold can drive.
    public static func potentialAnalogTargets() -> [[String: String]] {
        (PanelLayout.knobs + PanelLayout.rings + PanelLayout.balls).compactMap { id in
            guard let svg = PanelControlMapping.profileToSvg[id] else { return nil }
            return ["to": svg, "label": "Drop"]
        }
    }

    public static func overlayBindingLabels(profile: Profile, layer: String?, variant: String? = nil) -> [String: String] {
        var dict: [String: String] = [:]
        guard let layer, var spec = profile.layers[layer] else { return dict }
        if layer == "MASK", AppSettings.shared.mirrorMaskToBase {
            spec.knobs = LocalAdjustments.mirroredKnobs(from: profile)
        } else if let variant, let knobs = spec.variants?[variant]?.knobs {
            spec.knobs = (spec.knobs ?? [:]).merging(knobs) { _, v in v }
        }
        for (svgId, profId) in PanelControlMapping.svgToProfile {
            dict[svgId] = label(for: profId, layer: spec, fallback: profile)
        }
        return dict
    }

    public static func heldSvgIds(engine: StudioEngine) -> [String] {
        var names = Set(engine.physicallyHeldControlNames)
        if engine.combinationEditorActive {
            names.formUnion(engine.combinationHeld)
            names.insert(engine.combinationTrigger)
        }
        if let overlay = engine.overlayLayerName {
            for (name, spec) in engine.profile.buttons {
                if spec.hold_layer == overlay || spec.layer == overlay {
                    names.insert(name)
                }
            }
        }
        if let held = engine.heldProgramButton { names.insert(held) }
        return names.compactMap { PanelControlMapping.profileToSvg[$0] }
    }

    private static func analogLinks(_ program: AnalogProgram, profile: Profile) -> [[String: String]] {
        var links: [[String: String]] = []
        if program.scope == "focus", let param = program.focusParam {
            let title = CommandDatabase.shared.shortLabel(for: param)
            if program.appliesToKnobs {
                let knobs = profile.knobs.filter { $0.value.param == param }.map(\.key)
                let targets = knobs.isEmpty ? PanelLayout.knobs : knobs
                for id in targets {
                    if let svg = PanelControlMapping.profileToSvg[id] {
                        links.append(["to": svg, "label": title])
                    }
                }
            }
            if program.appliesToWheels {
                for id in PanelLayout.balls + PanelLayout.rings {
                    if let svg = PanelControlMapping.profileToSvg[id] {
                        links.append(["to": svg, "label": title])
                    }
                }
            }
        } else {
            // Per-control map: an arrow for each control that is set, labeled with its slider.
            let db = CommandDatabase.shared
            var labels: [String: String] = [:]
            for (id, k) in program.knobs ?? [:] { labels[id] = db.shortLabel(for: k.param) }
            for (id, r) in program.rings ?? [:] { labels[id] = db.shortLabel(for: r.param) }
            for (id, b) in program.balls ?? [:] { labels[id] = db.shortLabel(for: b.param ?? b.hue) }
            for id in PanelLayout.knobs + PanelLayout.rings + PanelLayout.balls {
                if let label = labels[id], let svg = PanelControlMapping.profileToSvg[id] {
                    links.append(["to": svg, "label": label])
                }
            }
        }
        return links
    }

    /// Rings and balls pick a wedge on the tool wheel.
    private static func pickerLinks() -> [[String: String]] {
        var links: [[String: String]] = []
        if let svg = PanelControlMapping.profileToSvg["RING_LIFT"] {
            links.append(["to": svg, "label": "New / Add / Sub / Int"])
        }
        for id in ["RING_GAMMA", "RING_GAIN"] {
            if let svg = PanelControlMapping.profileToSvg[id] {
                links.append(["to": svg, "label": "Pick tool"])
            }
        }
        for id in PanelLayout.balls {
            if let svg = PanelControlMapping.profileToSvg[id] {
                links.append(["to": svg, "label": "Aim"])
            }
        }
        for (id, mode) in MaskCombine.buttonMap {
            if let svg = PanelControlMapping.profileToSvg[id] {
                links.append(["to": svg, "label": mode.title])
            }
        }
        return links
    }

    /// Each control the mode changes, labeled with what it becomes.
    private static func layerLinks(_ layer: LayerSpec, title: String) -> [[String: String]] {
        let db = CommandDatabase.shared
        var labels: [String: String] = [:]
        let variant = layer.default_variant.flatMap { layer.variants?[$0] } ?? layer.variants?.values.first
        for (id, k) in variant?.knobs ?? [:] { labels[id] = db.shortLabel(for: k.param) }
        for (id, k) in layer.knobs ?? [:] { labels[id] = db.shortLabel(for: k.param) }
        for (id, r) in layer.rings ?? [:] { labels[id] = db.shortLabel(for: r.param) }
        for (id, b) in layer.balls ?? [:] { labels[id] = db.shortLabel(for: b.param ?? b.hue) }
        return labels.keys.sorted().compactMap { id -> [String: String]? in
            guard let svg = PanelControlMapping.profileToSvg[id] else { return nil }
            return ["to": svg, "label": labels[id] ?? ""]
        }
    }

    private static func label(for control: String, layer: LayerSpec, fallback: Profile) -> String {
        if let knob = layer.knobs?[control] { return CommandDatabase.shared.label(for: knob.param) }
        if let ring = layer.rings?[control] { return CommandDatabase.shared.label(for: ring.param) }
        if let ball = layer.balls?[control] { return CommandDatabase.shared.label(for: ball.param ?? ball.hue) }
        if let btn = layer.buttons?[control] {
            if let a = btn.action {
                var text = CommandDatabase.shared.label(for: a)
                if fallback.buttons[control]?.hold_picker != nil, btn.hold_picker == nil {
                    text += " · Hold: Mask tools"
                }
                return text
            }
            if let h = btn.hold_layer { return "Hold: \(LayerNames.defaultTitle(h))" }
            if let l = btn.layer { return "Toggle \(LayerNames.defaultTitle(l))" }
            if let v = btn.set_variant { return "Bank \(v)" }
            if btn.hold_picker != nil { return "Hold: Mask tools" }
        }
        if let knob = fallback.knobs[control] { return CommandDatabase.shared.label(for: knob.param) }
        if let ring = fallback.rings[control] { return CommandDatabase.shared.label(for: ring.param) }
        if let ball = fallback.balls[control] { return CommandDatabase.shared.label(for: ball.param ?? ball.hue) }
        if let btn = fallback.buttons[control] {
            if let h = btn.hold_layer { return "Hold: \(LayerNames.defaultTitle(h))" }
            if let p = btn.hold_picker, MaskToolPicker.supports(p) { return "Hold: Mask tools" }
            if let l = btn.layer { return "Toggle \(LayerNames.defaultTitle(l))" }
            if let a = btn.action { return "(Base) " + CommandDatabase.shared.label(for: a) }
            if btn.ps != nil { return "(Base) Photoshop" }
        }
        return "-"
    }
}
