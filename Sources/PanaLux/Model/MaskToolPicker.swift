import Foundation
import Combine

/// New mask, or add / subtract / intersect with the one that’s already selected.
public enum MaskCombine: Int, CaseIterable, Equatable {
    case create = 0
    case add
    case subtract
    case intersect

    public var title: String {
        switch self {
        case .create: return "New"
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .intersect: return "Intersect"
        }
    }

    public var verb: String {
        switch self {
        case .create: return "New"
        case .add: return "Add"
        case .subtract: return "Sub"
        case .intersect: return "Int"
        }
    }

    public var symbol: String {
        switch self {
        case .create: return "plus.circle.fill"
        case .add: return "plus.square.fill"
        case .subtract: return "minus.square.fill"
        case .intersect: return "square.on.square.dashed"
        }
    }

    public var hint: String {
        switch self {
        case .create: return "A new mask"
        case .add: return "Add to the selected mask"
        case .subtract: return "Cut out of the selected mask"
        case .intersect: return "Keep the overlap"
        }
    }

    /// While the tool wheel is open, these keys pick New / Add / Subtract / Intersect.
    public static let buttonMap: [String: MaskCombine] = [
        "PREV_NODE": .create,
        "NEXT_NODE": .add,
        "PREV_FRAME": .subtract,
        "NEXT_FRAME": .intersect
    ]

    /// Left ring steps through combine modes while the wheel is open.
    public static let ringControl = "RING_LIFT"
}

/// One wedge on the mask tool wheel (hold Add Node).
public struct MaskTool: Equatable, Identifiable, Hashable {
    public var id: String { kind }
    public let kind: String
    public let title: String
    public let shortTitle: String
    public let symbol: String
    /// Radial, linear, brush, object, color, and luminance are placed with the pointer.
    public let placesWithPointer: Bool

    public var createCommand: String { "MaskNew\(kind)" }

    public func command(combine: MaskCombine) -> String? {
        let id = "Mask\(combine.verb)\(kind)"
        if CommandDatabase.shared.commands[id] != nil { return id }
        return nil
    }
}

/// Catalog and detent math for the GTA-style mask wheel.
public enum MaskToolPicker {
    public static let id = "mask_tools"

    /// Clockwise from 12 o’clock. Linear sits in the first slot so a hold with
    /// no spin still matches the Add Node tap (new linear mask).
    public static let tools: [MaskTool] = [
        MaskTool(kind: "Grad", title: "Linear", shortTitle: "Linear", symbol: "rectangle.split.2x1", placesWithPointer: true),
        MaskTool(kind: "Rad", title: "Radial", shortTitle: "Radial", symbol: "circle.dashed", placesWithPointer: true),
        MaskTool(kind: "Brush", title: "Brush", shortTitle: "Brush", symbol: "paintbrush.pointed.fill", placesWithPointer: true),
        MaskTool(kind: "Obj", title: "Object", shortTitle: "Object", symbol: "cube.transparent", placesWithPointer: true),
        MaskTool(kind: "Subject", title: "Subject", shortTitle: "Subject", symbol: "person.crop.rectangle", placesWithPointer: false),
        MaskTool(kind: "Sky", title: "Sky", shortTitle: "Sky", symbol: "cloud.sun.fill", placesWithPointer: false),
        MaskTool(kind: "People", title: "People", shortTitle: "People", symbol: "person.2.fill", placesWithPointer: false),
        MaskTool(kind: "Back", title: "Background", shortTitle: "Back", symbol: "rectangle.on.rectangle.angled", placesWithPointer: false),
        MaskTool(kind: "Color", title: "Color Range", shortTitle: "Color", symbol: "eyedropper.halffull", placesWithPointer: true),
        MaskTool(kind: "Lum", title: "Luminance", shortTitle: "Lum", symbol: "circle.lefthalf.filled", placesWithPointer: true),
        MaskTool(kind: "Depth", title: "Depth", shortTitle: "Depth", symbol: "square.3.layers.3d", placesWithPointer: false),
        MaskTool(kind: "Land", title: "Landscape", shortTitle: "Land", symbol: "mountain.2.fill", placesWithPointer: false)
    ]

    public static var count: Int { tools.count }

    /// HID units before the next wedge. A brisk ring turn is ~470 units.
    public static let detentUnits: Double = 150
    public static let combineDetentUnits: Double = 180
    public static let minStepInterval: TimeInterval = 0.09
    /// Trackball distance before aiming at a wedge, so a resting hand does not steal the ring.
    public static let aimDeadzone: Double = 220

    public static func supports(_ id: String) -> Bool { id == Self.id }

    /// Longest kind match, so `MaskNewColor` hits Color Range rather than a shorter substring.
    public static func tool(forCommand command: String) -> MaskTool? {
        tools
            .filter { command.contains($0.kind) }
            .max { $0.kind.count < $1.kind.count }
    }

    public static func placesWithPointer(command: String) -> Bool {
        tool(forCommand: command)?.placesWithPointer ?? false
    }

    public static func tool(at index: Int) -> MaskTool {
        tools[((index % count) + count) % count]
    }

    /// Angle of a wedge’s center, radians. 0 at 12 o’clock, clockwise.
    public static func centerAngle(index: Int) -> Double {
        Double(index) / Double(count) * 2 * .pi
    }

    /// SwiftUI point: y grows down, so 12 o’clock is minus cosine.
    public static func polarPoint(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(sin(angle)),
            y: center.y - radius * CGFloat(cos(angle))
        )
    }

    public static func wedgeStart(index: Int, gap: Double = 0.045) -> Double {
        centerAngle(index: index) - (.pi / Double(count)) + gap
    }

    public static func wedgeEnd(index: Int, gap: Double = 0.045) -> Double {
        centerAngle(index: index) + (.pi / Double(count)) - gap
    }

    public static func index(aiming dx: Double, dy: Double) -> Int? {
        let mag = hypot(dx, dy)
        guard mag >= aimDeadzone else { return nil }
        var a = atan2(dx, dy)
        if a < 0 { a += 2 * .pi }
        let slice = (2 * .pi) / Double(count)
        return Int((a + slice / 2) / slice) % count
    }

    public static func steppedIndex(from current: Int, clockwise: Bool) -> Int {
        let delta = clockwise ? 1 : -1
        return ((current + delta) % count + count) % count
    }

    public static func steppedCombine(from current: MaskCombine, clockwise: Bool) -> MaskCombine {
        let all = MaskCombine.allCases
        let i = current.rawValue + (clockwise ? 1 : -1)
        let wrapped = ((i % all.count) + all.count) % all.count
        return all[wrapped]
    }
}

/// Live state for the circular overlay. Kept off `StudioEngine` so aiming the ball
/// does not redraw the Map window.
public final class ToolWheelSession: ObservableObject {
    public static let shared = ToolWheelSession()

    @Published public var isPresented = false
    @Published public var ownerLabel = "Add Node"
    @Published public var selectedIndex = 0
    @Published public var combine: MaskCombine = .create
    @Published public var aimX: Double = 0
    @Published public var aimY: Double = 0
    @Published public var aimActive = false
    /// Bumps on every detent so the selected wedge can pulse.
    @Published public var tick: Int = 0

    private init() {}

    public var selected: MaskTool { MaskToolPicker.tool(at: selectedIndex) }
    public var selectedCommand: String? { selected.command(combine: combine) }

    public func present(ownerLabel: String, index: Int, combine: MaskCombine = .create) {
        self.ownerLabel = ownerLabel
        selectedIndex = index
        self.combine = combine
        aimX = 0
        aimY = 0
        aimActive = false
        isPresented = true
    }

    public func hide() {
        isPresented = false
        aimActive = false
    }
}
