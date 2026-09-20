import Foundation

/// A staged transfer never mutates the live map. Tap and hold are independent slices.
enum MapSlice: String, CaseIterable, Identifiable {
    case all = "Whole control", tap = "Tap only", hold = "Hold only"
    var id: String { rawValue }
}

struct MapTransferSelection: Equatable {
    var controls: Set<String> = []
    var slice: MapSlice = .all
    var combinations: Set<String> = []
}

struct MapTransferResult {
    var profile: Profile
    var changes: [String]
}

enum MapTransfer {
    static let controls = PanelLayout.knobs + PanelLayout.rings + PanelLayout.balls
        + PanelLayout.knobs.map { "PRESS_" + $0 } + PanelLayout.allButtons

    static func button(_ profile: Profile, _ id: String) -> ButtonBinding {
        profile.buttons[id] ?? (id.hasPrefix("PRESS_")
            ? ButtonBinding(action: "reset_knob:" + String(id.dropFirst(6))) : ButtonBinding())
    }

    /// Referenced layers are cloned under fresh IDs. Copying one held mode must not
    /// silently replace a destination mode shared by unrelated controls.
    static func merge(source: Profile, into destination: Profile, selection: MapTransferSelection) -> MapTransferResult {
        var result = destination
        var changes: [String] = []
        var cloned: [String: String] = [:]
        func cloneLayer(_ id: String?) -> String? {
            guard let id else { return nil }
            guard let layer = source.layers[id] else { return id }
            if let existing = cloned[id] { return existing }
            if destination.layers[id] == layer { cloned[id] = id; return id }
            var newID = id + "_SHARED"
            var suffix = 2
            while result.layers[newID] != nil {
                newID = id + "_SHARED_" + String(suffix); suffix += 1
            }
            cloned[id] = newID // register before walking cyclic mode references
            result.layers[newID] = layer
            var copy = layer
            copy.title = layer.title ?? LayerNames.defaultTitle(id)
            copy.buttons = layer.buttons?.mapValues { remap($0) }
            result.layers[newID] = copy
            changes.append("Includes mode: " + (copy.title ?? id))
            return newID
        }
        func remap(_ original: ButtonBinding) -> ButtonBinding {
            var b = original
            b.layer = cloneLayer(b.layer)
            b.hold_layer = cloneLayer(b.hold_layer)
            b.enter_layer = cloneLayer(b.enter_layer)
            if let modifier = b.modifier, !result.modifiers.contains(modifier) { result.modifiers.append(modifier) }
            return b
        }
        for id in selection.controls.sorted() where controls.contains(id) {
            if PanelLayout.isAnalog(id) {
                guard selection.slice == .all else { continue }
                if PanelLayout.knobs.contains(id) { result.knobs[id] = source.knobs[id] }
                if PanelLayout.rings.contains(id) { result.rings[id] = source.rings[id] }
                if PanelLayout.balls.contains(id) { result.balls[id] = source.balls[id] }
            } else {
                let incoming = button(source, id)
                var binding = button(destination, id)
                switch selection.slice {
                case .all: binding = incoming
                case .tap:
                    binding.clearTap()
                    binding.action = incoming.action; binding.layer = incoming.layer
                    binding.enter_layer = incoming.enter_layer; binding.set_variant = incoming.set_variant
                    binding.ps = incoming.ps; binding.tapProgram = incoming.tapProgram
                case .hold:
                    binding.clearHold()
                    binding.hold_layer = incoming.hold_layer; binding.modifier = incoming.modifier
                    binding.holdProgram = incoming.holdProgram; binding.hold_action = incoming.hold_action
                    binding.release_action = incoming.release_action; binding.hold_picker = incoming.hold_picker
                }
                // Remap only incoming half; preserve destination references on the other half.
                var copied = incoming
                if selection.slice == .tap { copied.clearHold() }
                if selection.slice == .hold { copied.clearTap() }
                copied = remap(copied)
                if selection.slice != .hold { binding.layer = copied.layer; binding.enter_layer = copied.enter_layer }
                if selection.slice != .tap { binding.hold_layer = copied.hold_layer }
                result.buttons[id] = binding
            }
            changes.append(PanelLayout.label(forControl: id) + " · " + selection.slice.rawValue)
        }
        var combos = destination.combinations ?? ButtonCombination.defaults
        for entry in source.combinations ?? ButtonCombination.defaults where selection.combinations.contains(entry.id) {
            var copy = entry; copy.binding = remap(entry.binding)
            combos.removeAll { $0.id == copy.id }; combos.append(copy)
            changes.append("Combination: " + entry.title)
        }
        if !selection.combinations.isEmpty { result.combinations = combos }
        return MapTransferResult(profile: result, changes: changes)
    }

    static func label(_ profile: Profile, _ id: String, slice: MapSlice) -> String {
        let db = CommandDatabase.shared
        if let b = profile.knobs[id] { return db.label(for: b.param) }
        if let b = profile.rings[id] { return db.label(for: b.param) }
        if let b = profile.balls[id] { return db.label(for: b.param ?? b.hue) }
        let b = button(profile, id)
        let tap = MapReadme.tapLine(b), hold = MapReadme.holdLine(b)
        switch slice {
        case .tap: return tap.isEmpty ? "Unassigned tap" : tap
        case .hold: return hold.isEmpty ? "Unassigned hold" : hold
        case .all: return [tap, hold.isEmpty ? "" : "Hold: " + hold].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
}
