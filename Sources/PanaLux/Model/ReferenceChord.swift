import Foundation

/// Delay only the two candidate down events briefly, so peeking never fires their taps.
/// A lone press retains its normal tap/hold after the grace period. Other combinations
/// flush the pending event first, preserving their existing order and priority.
struct ReferenceChord {
    static let members: Set<String> = ["PREV_STILL", "NEXT_STILL"]
    static let grace: TimeInterval = 0.3
    struct Event: Equatable { let name: String; let down: Bool }
    private(set) var pressed: Set<String> = []
    private(set) var pending: String?
    private(set) var visible = false
    private var consumed = false
    private var bypass = false

    mutating func receive(_ name: String, down: Bool) -> [Event] {
        guard Self.members.contains(name) else {
            return (down ? flush() : []) + [Event(name: name, down: down)]
        }
        if down {
            guard pressed.insert(name).inserted else { return [] }
        } else {
            guard pressed.remove(name) != nil else { return [Event(name: name, down: false)] }
        }
        if consumed {
            if !down { visible = false }
            if pressed.isEmpty { consumed = false; bypass = false }
            return []
        }
        if bypass {
            if pressed.isEmpty { bypass = false }
            return [Event(name: name, down: down)]
        }
        if down {
            if pending != nil {
                pending = nil
                consumed = true
                visible = true
            } else { pending = name }
            return []
        }
        if pending == name {
            pending = nil
            return [Event(name: name, down: true), Event(name: name, down: false)]
        }
        return []
    }

    mutating func flush() -> [Event] {
        guard let name = pending else { return [] }
        pending = nil
        bypass = true
        return [Event(name: name, down: true)]
    }

    mutating func reset() { self = ReferenceChord() }
}
