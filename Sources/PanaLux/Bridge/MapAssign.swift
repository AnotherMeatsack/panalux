import Foundation

/// A copied control assignment.
public enum ControlClipboard: Equatable {
    case dial(param: String, scale: Double)
    case ball(BallBinding)
    case button(ButtonBinding)

    var summary: String {
        switch self {
        case .dial(let p, _): return CommandDatabase.shared.label(for: p)
        case .ball(let b): return CommandDatabase.shared.label(for: b.hue)
        case .button: return "key assignment"
        }
    }
}

extension StudioEngine {
    /// Held mode wins, so holding a key on the panel edits what you are holding.
    public var effectiveEditLayer: String? {
        overlayLayerName ?? mapEditLayer
    }

    /// Drop a catalog command onto an SVG control. Hold overlays win while a key is down.
    public func applyDroppedCommand(commandId: String, ontoSvg svgId: String) {
        let control = PanelControlMapping.toProfileId(svgId)
        applyDroppedCommand(commandId: commandId, ontoControl: control)
        highlightHardwareControl(control)
        lastButtonName = PanelLayout.isButton(control) ? control : lastButtonName
        lastAnalogName = PanelLayout.isAnalog(control) ? control : lastAnalogName
    }

    public func applyDroppedCommand(commandId: String, ontoControl control: String, preferHold: Bool? = nil) {
        let item = CommandDatabase.shared.catalogCommand(for: commandId)

        if PanelLayout.isBall(control) {
            guard item.isParameter else {
                mapStatusMessage = "Trackballs take sliders or color wheels."
                return
            }
            setBallSlider(control, param: item.id)
            return
        }

        let holdOwner = engagedHoldActivator ?? inspectorHoldEdit
        if overlayLayerName == nil, mapEditLayer == nil, let owner = holdOwner, PanelLayout.isAnalog(control) {
            if item.isParameter {
                assignHoldAnalog(button: owner, control: control, param: item.id)
                mapStatusMessage = "Hold \(PanelLayout.label(forControl: owner)): \(shortName(item)) on \(PanelLayout.shortLabel(forControl: control))"
            } else {
                mapStatusMessage = "That’s a key command. Drop it on a key."
            }
            return
        }

        if let layer = effectiveEditLayer {
            assignInLayer(layer, control: control, item: item)
            return
        }

        if PanelLayout.isAnalog(control) {
            guard item.isParameter else {
                mapStatusMessage = "\(PanelLayout.isRing(control) ? "Rings" : "Knobs") take sliders or turn-to-step commands."
                return
            }
            if PanelLayout.isRing(control) {
                profile.rings[control] = RingBinding(param: item.id, scale: profile.rings[control]?.scale ?? 0.0003)
            } else {
                profile.knobs[control] = KnobBinding(param: item.id, scale: profile.knobs[control]?.scale ?? 0.0003)
            }
            mapStatusMessage = "\(shortName(item)) → \(PanelLayout.shortLabel(forControl: control))"
            return
        }

        assignButtonCommand(control, item: item, preferHold: preferHold ?? (inspectorHoldEdit == control))
    }

    public var engagedHoldActivator: String? {
        physicallyHeldControlNames.first { name in
            let spec = profile.buttons[name]
            return spec?.holdProgram != nil || (spec?.hasHoldFunctionSet == true && spec?.hold_layer == nil)
        } ?? heldProgramButton
    }

    private func assignInLayer(_ layerName: String, control: String, item: CatalogCommand) {
        var layer = profile.layers[layerName] ?? LayerSpec()
        let title = layerTitle(layerName)
        if PanelLayout.isBall(control) {
            guard item.isParameter else { mapStatusMessage = "Trackballs take sliders."; return }
            var balls = layer.balls ?? [:]
            balls[control] = .slider(item.id)
            layer.balls = balls
        } else if PanelLayout.isRing(control) {
            guard item.isParameter else { mapStatusMessage = "Rings take sliders."; return }
            var rings = layer.rings ?? [:]
            rings[control] = RingBinding(param: item.id)
            layer.rings = rings
        } else if PanelLayout.isKnob(control) {
            guard item.isParameter else { mapStatusMessage = "Knobs take sliders."; return }
            if let variant = activeVariants[layerName], layer.variants?[variant] != nil {
                var knobs = layer.variants?[variant]?.knobs ?? [:]
                knobs[control] = KnobBinding(param: item.id)
                layer.variants?[variant]?.knobs = knobs
            } else {
                var knobs = layer.knobs ?? [:]
                knobs[control] = KnobBinding(param: item.id)
                layer.knobs = knobs
            }
        } else {
            guard !item.isParameter || item.id.contains(":") else {
                mapStatusMessage = "Inside a mode, keys fire commands. Put sliders on knobs."
                return
            }
            var buttons = layer.buttons ?? [:]
            var spec = ButtonBinding()
            applyTapItem(&spec, item)
            buttons[control] = spec
            layer.buttons = buttons
        }
        profile.layers[layerName] = layer
        mapStatusMessage = "\(title): \(shortName(item)) → \(PanelLayout.shortLabel(forControl: control))"
    }

    private func assignHoldAnalog(button: String, control: String, param: String) {
        var spec = profile.buttons[button] ?? ButtonBinding()
        var program = spec.holdProgram ?? AnalogProgram(scope: "knobs", driveKnobs: true, driveBalls: false)

        // A focus program ("every knob drives Vignette") becomes a per-control map that
        // starts empty: only the control you set changes, the rest keep their Base job.
        if program.scope == "focus" {
            program = AnalogProgram(scope: "knobs", driveKnobs: true, driveBalls: false)
        }
        // Older builds copied the focus slider onto the whole row. Undo that the first time
        // one control is set, so the row is no longer locked to one adjustment.
        Self.dropUniformFill(&program.knobs, count: PanelLayout.knobs.count, keeping: control)
        Self.dropUniformFill(&program.rings, count: PanelLayout.rings.count, keeping: control)

        if PanelLayout.isKnob(control) {
            var knobs = program.knobs ?? [:]
            knobs[control] = KnobBinding(param: param)
            program.knobs = knobs
            program.driveKnobs = true
            if program.scope == "wheels" { program.scope = "all" }
            if program.scope != "all" { program.scope = "knobs" }
        } else if PanelLayout.isRing(control) {
            var rings = program.rings ?? [:]
            rings[control] = RingBinding(param: param)
            program.rings = rings
            program.driveBalls = true
            if program.scope == "knobs" { program.scope = "all" }
            if program.scope != "all" { program.scope = "wheels" }
        }

        spec.clearHold()
        spec.holdProgram = program
        profile.buttons[button] = spec
    }

    static func dropUniformFill<B>(_ map: inout [String: B]?, count: Int, keeping control: String) where B: ParamBound {
        guard let m = map, m.count == count, Set(m.values.map(\.param)).count == 1 else { return }
        map = m.filter { $0.key == control }
    }

    /// The slider a hold key's program puts on a control, if any.
    public func holdProgramParam(owner: String, control: String) -> String? {
        guard let p = profile.buttons[owner]?.holdProgram else { return nil }
        if p.scope == "focus" {
            let applies = PanelLayout.isKnob(control) ? p.appliesToKnobs : p.appliesToWheels
            return applies ? p.focusParam : nil
        }
        return p.knobs?[control]?.param ?? p.rings?[control]?.param ?? p.balls?[control]?.param
    }

    func assignButtonCommand(_ control: String, item: CatalogCommand, preferHold: Bool) {
        if let layer = effectiveEditLayer {
            assignInLayer(layer, control: control, item: item)
            return
        }
        var spec = profile.buttons[control] ?? ButtonBinding()
        let holdOnly = item.id.starts(with: "hold_layer:") || item.id.starts(with: "modifier:")
            || item.id.starts(with: "hold_picker:") || item.id == Self.holdCompareID
        if preferHold || holdOnly {
            applyHoldItem(&spec, item)
            mapStatusMessage = "Hold \(PanelLayout.label(forControl: control)): \(shortName(item))"
        } else {
            applyTapItem(&spec, item)
            mapStatusMessage = "Tap \(PanelLayout.label(forControl: control)): \(shortName(item))"
        }
        profile.buttons[control] = spec
    }

    public static let holdCompareID = "hold_compare"

    /// Ids that belong on `ButtonBinding.ps`, not on `action`.
    static let photoshopActionIDs: Set<String> = ["smart_roundtrip", "bracket_roundtrip", "align_layers"]

    func applyTapItem(_ spec: inout ButtonBinding, _ item: CatalogCommand) {
        spec.clearTap()
        if item.id.starts(with: "layer:") {
            spec.layer = String(item.id.dropFirst("layer:".count))
        } else if item.id.starts(with: "set_variant:") {
            spec.set_variant = String(item.id.dropFirst("set_variant:".count))
        } else if Self.photoshopActionIDs.contains(item.id) {
            spec.ps = item.id
        } else if item.isParameter {
            spec.tapProgram = AnalogProgram.focused(item.id)
        } else if item.id.starts(with: "hold_layer:") || item.id.starts(with: "modifier:")
                    || item.id.starts(with: "hold_picker:") || item.id == Self.holdCompareID {
            applyHoldItem(&spec, item)
        } else {
            spec.action = item.id
        }
    }

    func applyHoldItem(_ spec: inout ButtonBinding, _ item: CatalogCommand) {
        spec.clearHold()
        if item.id.starts(with: "hold_layer:") {
            spec.hold_layer = String(item.id.dropFirst("hold_layer:".count))
        } else if item.id.starts(with: "layer:") {
            spec.hold_layer = String(item.id.dropFirst("layer:".count))
        } else if item.id.starts(with: "modifier:") {
            spec.modifier = String(item.id.dropFirst("modifier:".count))
        } else if item.id == Self.holdCompareID {
            spec.hold_action = MomentaryCommands.compareBefore
            spec.release_action = MomentaryCommands.compareRestore
        } else if item.id.starts(with: "hold_picker:") {
            spec.hold_picker = String(item.id.dropFirst("hold_picker:".count))
        } else if item.id == PointerCommands.click {
            spec.hold_action = PointerCommands.down
            spec.release_action = PointerCommands.up
        } else if PointerCommands.isPointer(item.id) && item.id != PointerCommands.move {
            spec.hold_action = item.id
        } else if item.isParameter {
            spec.holdProgram = AnalogProgram.focused(item.id)
        } else if !item.id.contains(":") {
            spec.hold_action = item.id
        }
    }

    // MARK: - Copy, paste, swap, clear

    public func copyControl(_ control: String) {
        if let layer = effectiveEditLayer, let spec = profile.layers[layer] {
            if let k = spec.knobs?[control] { clipboard = .dial(param: k.param, scale: k.scale) }
            else if let r = spec.rings?[control] { clipboard = .dial(param: r.param, scale: r.scale) }
            else if let b = spec.balls?[control] { clipboard = .ball(b) }
            else if let s = spec.buttons?[control] { clipboard = .button(s) }
        } else if let k = profile.knobs[control] { clipboard = .dial(param: k.param, scale: k.scale) }
        else if let r = profile.rings[control] { clipboard = .dial(param: r.param, scale: r.scale) }
        else if let b = profile.balls[control] { clipboard = .ball(b) }
        else if let s = profile.buttons[control] { clipboard = .button(s) }
        mapStatusMessage = clipboard.map { "Copied \($0.summary)" } ?? "Nothing to copy"
    }

    public func canPaste(onto control: String) -> Bool {
        switch clipboard {
        case .dial: return PanelLayout.isKnob(control) || PanelLayout.isRing(control)
        case .ball: return PanelLayout.isBall(control)
        case .button: return PanelLayout.isButton(control)
        case nil: return false
        }
    }

    public func pasteControl(onto control: String) {
        guard let clip = clipboard, canPaste(onto: control) else { return }
        write(clip, to: control)
        mapStatusMessage = "Pasted onto \(PanelLayout.shortLabel(forControl: control))"
    }

    public func canSwap(_ a: String, _ b: String) -> Bool {
        guard a != b else { return false }
        let dial = { (c: String) in PanelLayout.isKnob(c) || PanelLayout.isRing(c) }
        return (dial(a) && dial(b)) || (PanelLayout.isBall(a) && PanelLayout.isBall(b))
            || (PanelLayout.isButton(a) && PanelLayout.isButton(b))
    }

    public func swapControls(_ a: String, _ b: String) {
        guard canSwap(a, b) else {
            mapStatusMessage = "Swap needs two controls of the same kind."
            return
        }
        let ca = read(a)
        let cb = read(b)
        write(cb, to: a)
        write(ca, to: b)
        mapStatusMessage = "Swapped \(PanelLayout.shortLabel(forControl: a)) and \(PanelLayout.shortLabel(forControl: b))"
    }

    public func clearControl(_ control: String, slot: ButtonSlot = .both) {
        if effectiveEditLayer == nil, PanelLayout.isAnalog(control) || PanelLayout.isBall(control),
           let owner = engagedHoldActivator ?? inspectorHoldEdit,
           var spec = profile.buttons[owner], var program = spec.holdProgram {
            if program.scope == "focus" {
                program = AnalogProgram(scope: "knobs", driveKnobs: true, driveBalls: false)
            }
            program.knobs?[control] = nil
            program.rings?[control] = nil
            program.balls?[control] = nil
            spec.holdProgram = program
            profile.buttons[owner] = spec
            mapStatusMessage = "\(PanelLayout.shortLabel(forControl: control)) keeps its Base job while holding \(PanelLayout.label(forControl: owner))"
            return
        }
        if let layer = effectiveEditLayer {
            var spec = profile.layers[layer] ?? LayerSpec()
            spec.knobs?[control] = nil
            spec.rings?[control] = nil
            spec.balls?[control] = nil
            spec.buttons?[control] = nil
            if let v = activeVariants[layer] { spec.variants?[v]?.knobs?[control] = nil }
            profile.layers[layer] = spec
            mapStatusMessage = "\(PanelLayout.shortLabel(forControl: control)) passes through to Base in \(layerTitle(layer))"
            return
        }
        if PanelLayout.isRing(control) {
            profile.rings.removeValue(forKey: control)
        } else if PanelLayout.isBall(control) {
            profile.balls.removeValue(forKey: control)
        } else if PanelLayout.isKnob(control) {
            profile.knobs.removeValue(forKey: control)
        } else {
            var spec = profile.buttons[control] ?? ButtonBinding()
            switch slot {
            case .tap: spec.clearTap()
            case .hold: spec.clearHold()
            case .both: spec = ButtonBinding()
            }
            profile.buttons[control] = spec
        }
        mapStatusMessage = "Cleared \(PanelLayout.shortLabel(forControl: control))"
    }

    public enum ButtonSlot { case tap, hold, both }

    /// Knob and ring speed. 1.0 is the factory feel.
    public func dialScale(_ control: String) -> Double? {
        if let layer = effectiveEditLayer, let spec = profile.layers[layer] {
            if let k = spec.knobs?[control] { return k.scale }
            if let r = spec.rings?[control] { return r.scale }
            return nil
        }
        return profile.knobs[control]?.scale ?? profile.rings[control]?.scale
    }

    public func setDialScale(_ control: String, _ scale: Double) {
        if let layer = effectiveEditLayer {
            if profile.layers[layer]?.knobs?[control] != nil { profile.layers[layer]?.knobs?[control]?.scale = scale }
            if profile.layers[layer]?.rings?[control] != nil { profile.layers[layer]?.rings?[control]?.scale = scale }
            return
        }
        if profile.knobs[control] != nil { profile.knobs[control]?.scale = scale }
        if profile.rings[control] != nil { profile.rings[control]?.scale = scale }
    }

    private func read(_ control: String) -> ControlClipboard? {
        let saved = clipboard
        let savedMessage = mapStatusMessage
        clipboard = nil
        copyControl(control)
        let value = clipboard
        clipboard = saved
        mapStatusMessage = savedMessage
        return value
    }

    private func write(_ clip: ControlClipboard?, to control: String) {
        if let layer = effectiveEditLayer {
            var spec = profile.layers[layer] ?? LayerSpec()
            switch clip {
            case .dial(let p, let s):
                if PanelLayout.isRing(control) {
                    var rings = spec.rings ?? [:]; rings[control] = RingBinding(param: p, scale: s); spec.rings = rings
                } else {
                    var knobs = spec.knobs ?? [:]; knobs[control] = KnobBinding(param: p, scale: s); spec.knobs = knobs
                }
            case .ball(let b):
                var balls = spec.balls ?? [:]; balls[control] = b; spec.balls = balls
            case .button(let b):
                var buttons = spec.buttons ?? [:]; buttons[control] = b; spec.buttons = buttons
            case nil:
                spec.knobs?[control] = nil; spec.rings?[control] = nil; spec.balls?[control] = nil; spec.buttons?[control] = nil
            }
            profile.layers[layer] = spec
            return
        }
        switch clip {
        case .dial(let p, let s):
            if PanelLayout.isRing(control) { profile.rings[control] = RingBinding(param: p, scale: s) }
            else { profile.knobs[control] = KnobBinding(param: p, scale: s) }
        case .ball(let b):
            profile.balls[control] = b
            profileStructureChanged()
        case .button(let b):
            profile.buttons[control] = b
        case nil:
            profile.knobs[control] = nil
            profile.rings[control] = nil
            profile.balls[control] = nil
            profile.buttons[control] = nil
        }
    }

    private func shortName(_ item: CatalogCommand) -> String {
        CommandTileView.shortTitle(item.title)
    }
}

extension StudioEngine {
    /// Roll a trackball to drive one slider — in the mode being edited or held, a hold program, or Base.
    public func setBallSlider(_ control: String, param: String) {
        let name = CommandDatabase.shared.label(for: param)
        if let layer = effectiveEditLayer {
            var spec = profile.layers[layer] ?? LayerSpec()
            var balls = spec.balls ?? [:]
            balls[control] = .slider(param)
            spec.balls = balls
            profile.layers[layer] = spec
            mapStatusMessage = "\(layerTitle(layer)): \(name) → \(PanelLayout.shortLabel(forControl: control))"
        } else if let owner = engagedHoldActivator ?? inspectorHoldEdit {
            var spec = profile.buttons[owner] ?? ButtonBinding()
            var program = spec.holdProgram ?? AnalogProgram(scope: "wheels", driveKnobs: false, driveBalls: true)
            if program.scope == "focus" {
                program = AnalogProgram(scope: "wheels", driveKnobs: false, driveBalls: true)
            } else if program.scope == "knobs" {
                program.scope = "all"
                program.driveBalls = true
            }
            var balls = program.balls ?? [:]
            balls[control] = .slider(param)
            program.balls = balls
            spec.holdProgram = program
            profile.buttons[owner] = spec
            mapStatusMessage = "Hold \(PanelLayout.label(forControl: owner)): \(name) on \(PanelLayout.shortLabel(forControl: control))"
        } else {
            var b = BallBinding.slider(param)
            if let old = profile.balls[control] {
                b.radius = old.radius; b.invert_x = old.invert_x; b.invert_y = old.invert_y
            }
            profile.balls[control] = b
            profileStructureChanged()
            mapStatusMessage = "\(name) → \(PanelLayout.shortLabel(forControl: control))"
        }
    }
}
