import SwiftUI

/// Circular weapon-wheel overlay: twelve mask tools around a center readout.
public struct ToolWheelView: View {
    @ObservedObject var session = ToolWheelSession.shared

    public init() {}

    public var body: some View {
        ToolWheelCanvas(
            selectedIndex: session.selectedIndex,
            combine: session.combine,
            ownerLabel: session.ownerLabel,
            aimActive: session.aimActive,
            aimX: session.aimX,
            aimY: session.aimY,
            tick: session.tick
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: session.selectedIndex)
        .animation(.easeOut(duration: 0.16), value: session.combine)
        .animation(.easeOut(duration: 0.12), value: session.tick)
    }
}

/// Shared drawing for the live overlay and the intro.
public struct ToolWheelCanvas: View {
    public var selectedIndex: Int
    public var combine: MaskCombine
    public var ownerLabel: String
    public var aimActive: Bool = false
    public var aimX: Double = 0
    public var aimY: Double = 0
    public var tick: Int = 0
    public var size: CGFloat = 400

    public init(selectedIndex: Int, combine: MaskCombine, ownerLabel: String,
                aimActive: Bool = false, aimX: Double = 0, aimY: Double = 0, tick: Int = 0, size: CGFloat = 400) {
        self.selectedIndex = selectedIndex
        self.combine = combine
        self.ownerLabel = ownerLabel
        self.aimActive = aimActive
        self.aimX = aimX
        self.aimY = aimY
        self.tick = tick
        self.size = size
    }

    private var tools: [MaskTool] { MaskToolPicker.tools }
    private var count: Int { tools.count }
    private var selected: MaskTool { MaskToolPicker.tool(at: selectedIndex) }
    private var accent: Color { LayerNames.color("MASK") }
    private var combineColor: Color {
        switch combine {
        case .create: return accent
        case .add: return Color(red: 0.40, green: 0.82, blue: 0.50)
        case .subtract: return Color(red: 1.00, green: 0.42, blue: 0.38)
        case .intersect: return Color(red: 0.45, green: 0.68, blue: 1.00)
        }
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.07).opacity(0.94))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            wedges
            aimPip
            centerHub
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, .dark)
    }

    private var wedges: some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        let inner = size * 0.175
        let outer = size * 0.46
        return ZStack {
            ForEach(Array(tools.enumerated()), id: \.offset) { i, tool in
                let on = i == selectedIndex
                MaskToolPicker.wedgePath(index: i, inner: inner, outer: on ? outer + 6 : outer, center: center)
                    .fill(on ? combineColor.opacity(0.42) : Color.white.opacity(0.06))
                    .overlay(
                        MaskToolPicker.wedgePath(index: i, inner: inner, outer: on ? outer + 6 : outer, center: center)
                            .stroke(on ? combineColor : Color.white.opacity(0.10), lineWidth: on ? 2.4 : 1)
                    )
                    .shadow(color: on ? combineColor.opacity(0.5) : .clear, radius: on ? 10 : 0)
                wedgeLabel(tool: tool, index: i, on: on, center: center, radius: size * 0.325)
            }
        }
    }

    private func wedgeLabel(tool: MaskTool, index: Int, on: Bool, center: CGPoint, radius: CGFloat) -> some View {
        let pt = MaskToolPicker.polarPoint(angle: MaskToolPicker.centerAngle(index: index), radius: radius, center: center)
        return VStack(spacing: 3) {
            Image(systemName: tool.symbol)
                .font(.system(size: on ? 17 : 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(tool.shortTitle)
                .font(.system(size: on ? 11 : 9, weight: on ? .bold : .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(on ? Color.white : Color.white.opacity(0.7))
        .scaleEffect(on ? (tick % 2 == 0 ? 1.06 : 1.0) : 1)
        .frame(width: 72, height: 44)
        .position(x: pt.x, y: pt.y)
    }

    @ViewBuilder
    private var aimPip: some View {
        if aimActive {
            let center = CGPoint(x: size / 2, y: size / 2)
            let a = atan2(aimX, aimY)
            let pt = MaskToolPicker.polarPoint(angle: a, radius: size * 0.42, center: center)
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .shadow(color: .white.opacity(0.8), radius: 4)
                .position(x: pt.x, y: pt.y)
        }
    }

    private var centerHub: some View {
        VStack(spacing: 5) {
            Image(systemName: selected.symbol)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(combineColor)
            Text("\(combine.title) \(selected.title)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                ForEach(MaskCombine.allCases, id: \.rawValue) { mode in
                    Text(mode.title)
                        .font(.system(size: 8, weight: mode == combine ? .bold : .medium, design: .rounded))
                        .foregroundStyle(mode == combine ? Color.white : Color.white.opacity(0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(mode == combine ? combineColor.opacity(0.85) : Color.white.opacity(0.08)))
                }
            }
            Text("Release \(ownerLabel)")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(width: 132, height: 132)
        .background(
            Circle()
                .fill(Color.black.opacity(0.55))
                .overlay(Circle().strokeBorder(combineColor.opacity(0.4), lineWidth: 1.2))
        )
    }
}

extension MaskToolPicker {
    static func wedgePath(index: Int, inner: CGFloat, outer: CGFloat, center: CGPoint) -> Path {
        let start = wedgeStart(index: index)
        let end = wedgeEnd(index: index)
        let steps = 10
        var p = Path()
        p.move(to: polarPoint(angle: start, radius: inner, center: center))
        p.addLine(to: polarPoint(angle: start, radius: outer, center: center))
        for s in 1...steps {
            let a = start + (end - start) * Double(s) / Double(steps)
            p.addLine(to: polarPoint(angle: a, radius: outer, center: center))
        }
        p.addLine(to: polarPoint(angle: end, radius: inner, center: center))
        for s in 1...steps {
            let a = end - (end - start) * Double(s) / Double(steps)
            p.addLine(to: polarPoint(angle: a, radius: inner, center: center))
        }
        p.closeSubpath()
        return p
    }
}
