import Foundation

/// Hold these controls, then press the trigger. Global combinations precede mode assignments.
public struct ButtonCombination: Codable, Equatable, Identifiable {
    public var held: [String]
    public var trigger: String
    public var binding: ButtonBinding
    public var id: String { Set(held).sorted().joined(separator: "+") + ">" + trigger }
    public var title: String {
        held.map { PanelLayout.label(forControl: $0) }.joined(separator: " + ")
            + " → " + PanelLayout.label(forControl: trigger)
    }
    public static var defaults: [ButtonCombination] {
        ["LIFT", "GAMMA", "GAIN"].flatMap { wheel in
            [ButtonCombination(held: ["SHIFT"], trigger: "RESET_" + wheel,
                               binding: ButtonBinding(action: WheelReset.prefix + wheel + ":ball")),
             ButtonCombination(held: ["CORNER_LOWER_RIGHT"], trigger: "RESET_" + wheel,
                               binding: ButtonBinding(action: WheelReset.prefix + wheel + ":ring"))]
        }
    }
}

/// Pure input arbitration: no timers, hardware, UI, or Lightroom side effects.
struct CombinationInput {
    enum Decision {
        case normal, deferTap, tap, suppress
        case fire(ButtonCombination)
    }
    private(set) var pressed: Set<String> = []
    private var consumed: Set<String> = []
    private var deferred: Set<String> = []

    mutating func reset() { pressed = []; consumed = []; deferred = [] }

    mutating func receive(_ name: String, down: Bool, combinations: [ButtonCombination]) -> Decision {
        if down {
            guard !pressed.contains(name) else { return .suppress }
            let candidates = combinations.filter {
                $0.trigger == name && !$0.held.isEmpty && !$0.held.contains(name)
                    && Set($0.held).isSubset(of: pressed)
            }.sorted {
                if Set($0.held).count != Set($1.held).count { return Set($0.held).count > Set($1.held).count }
                return $0.id < $1.id
            }
            pressed.insert(name)
            if let match = candidates.first {
                consumed.formUnion(match.held + [name])
                deferred.subtract(match.held + [name])
                return .fire(match)
            }
            if combinations.contains(where: { $0.held.contains(name) }) {
                deferred.insert(name)
                return .deferTap
            }
            return .normal
        }
        pressed.remove(name)
        if consumed.remove(name) != nil { deferred.remove(name); return .suppress }
        if deferred.remove(name) != nil { return .tap }
        return .normal
    }
}
