import SwiftUI

/// One value on the rolling twelve-knob row.
public struct RewindKnobValue: Equatable, Identifiable {
    public var id: String { control }
    public let control: String
    public let label: String
    /// Normalised 0…1, for the little bar.
    public let value: Double
    /// Lightroom's own reading: "+0.35 EV".
    public let display: String
    /// Differs from the tip, so it is worth a brighter colour.
    public let isChanged: Bool

    public init(control: String, label: String, value: Double, display: String, isChanged: Bool) {
        self.control = control
        self.label = label
        self.value = value
        self.display = display
        self.isChanged = isChanged
    }
}

/// A landmark on the tape: an open, a mark, a structural edit, or a branch leaving the path.
public struct TrailMark: Identifiable, Equatable {
    public enum Kind: String, Equatable {
        case open, mark, branch, mask, crop, preset, paste, reset, action

        /// The landmarks the user put there by hand keep their names when space runs out.
        public var isNamedFirst: Bool {
            self == .mark || self == .branch || self == .open
        }

        public var symbol: String {
            switch self {
            case .open: return "photo"
            case .mark: return "bookmark.fill"
            case .branch: return "arrow.triangle.branch"
            case .mask: return "lasso"
            case .crop: return "crop"
            case .preset: return "square.stack.3d.up"
            case .paste: return "doc.on.clipboard"
            case .reset: return "arrow.counterclockwise"
            case .action: return "wand.and.stars"
            }
        }
    }

    public let id: String
    public let time: TimeInterval
    public let label: String
    public let kind: Kind
    /// Set when this mark is a branch that left the path here.
    public let branchName: String?

    public init(id: String, time: TimeInterval, label: String, kind: Kind, branchName: String? = nil) {
        self.id = id
        self.time = time
        self.label = label
        self.kind = kind
        self.branchName = branchName
    }
}

/// Everything the readout needs to draw one moment of rewinding. A value type, so every state
/// can be rendered offscreen and looked at.
public struct RewindState: Equatable {
    /// Trail time where the recording starts.
    public var origin: TimeInterval
    /// The newest point. Rolling back never moves it.
    public var tip: TimeInterval
    public var playhead: TimeInterval
    /// Seconds of tape across the whole track.
    public var window: TimeInterval
    public var marks: [TrailMark]
    public var knobs: [RewindKnobValue]
    /// nil on the original line; the branch's name once the editing has forked.
    public var branchName: String?
    public var isPeeking: Bool
    public var isAtTip: Bool
    public var caption: String
    /// 0…1 scrub speed, for how hard the playhead smears.
    public var speed: Double
    /// The speed dial. 1 is the pace the edits were made at.
    public var rate: Double
    public var isPlaying: Bool
    public var isReverse: Bool
    /// "212 of 640": where the playhead stands among the things that changed.
    public var stepNumber: Int
    public var stepCount: Int

    public init(origin: TimeInterval = 0, tip: TimeInterval = 0, playhead: TimeInterval = 0,
                window: TimeInterval = 60, marks: [TrailMark] = [],
                knobs: [RewindKnobValue] = [], branchName: String? = nil, isPeeking: Bool = false,
                isAtTip: Bool = true, caption: String = "Now", speed: Double = 0,
                rate: Double = 1, isPlaying: Bool = false, isReverse: Bool = false,
                stepNumber: Int = 0, stepCount: Int = 0) {
        self.origin = origin
        self.tip = tip
        self.playhead = playhead
        self.window = window
        self.marks = marks
        self.knobs = knobs
        self.branchName = branchName
        self.isPeeking = isPeeking
        self.isAtTip = isAtTip
        self.caption = caption
        self.speed = speed
        self.rate = rate
        self.isPlaying = isPlaying
        self.isReverse = isReverse
        self.stepNumber = stepNumber
        self.stepCount = stepCount
    }

    /// "1×", "0.25×", "12×": as short as the number allows.
    public static func rateText(_ rate: Double) -> String {
        let text: String
        if rate >= 10 { text = String(format: "%.0f", rate) }
        else if rate >= 1 { text = String(format: "%.1f", rate) }
        else { text = String(format: "%.2f", rate) }
        var trimmed = text
        if trimmed.contains(".") {
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
        }
        return trimmed + "×"
    }
    public var rateText: String { RewindState.rateText(rate) }

    public static let empty = RewindState()

    public static let accent = Color(red: 0.98, green: 0.68, blue: 0.22)
    /// A branch is a different line of editing, not a scratch on this one. It gets its own colour.
    public static let branchAccent = Color(red: 0.40, green: 0.80, blue: 1.00)

    /// Seconds between the ticks that slide under the playhead.
    public var tickSpacing: TimeInterval {
        for candidate in [1.0, 2.0, 5.0, 15.0, 30.0, 60.0, 300.0, 900.0] where window / candidate <= 26 {
            return candidate
        }
        return 1800
    }
}

/// The tape. The playhead stays put and time moves under it.
public struct TrailTrack: View {
    public let state: RewindState
    /// Where the playhead sits across the track: right of centre, so most of the width is the
    /// editing that happened, with room after it for the future a rollback has gone past.
    private let playheadFraction: CGFloat = 0.70

    public init(state: RewindState) {
        self.state = state
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let headX = width * playheadFraction
            let scale = width / CGFloat(max(1.0, state.window))
            let lineY = height * 0.46

            ZStack(alignment: .topLeading) {
                rail(width: width, y: lineY, headX: headX, scale: scale)
                ticks(width: width, y: lineY, headX: headX, scale: scale)
                marks(width: width, y: lineY, headX: headX, scale: scale, height: height)
                playhead(x: headX, height: height, y: lineY)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(SpringPhysics.bubble, value: state.playhead)
            .animation(SpringPhysics.micro, value: state.isPeeking)
        }
    }

    private func x(for time: TimeInterval, headX: CGFloat, scale: CGFloat) -> CGFloat {
        headX + CGFloat(time - state.playhead) * scale
    }

    /// Everything already recorded, in two weights: what is behind the playhead, and the future
    /// it has rolled past. The future is dimmed, never removed — nothing here is destroyed.
    @ViewBuilder
    private func rail(width: CGFloat, y: CGFloat, headX: CGFloat, scale: CGFloat) -> some View {
        let startX = x(for: state.origin, headX: headX, scale: scale)
        let tipX = x(for: state.tip, headX: headX, scale: scale)
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: 3)
                .offset(x: 0, y: y - 1.5)
            Capsule()
                .fill(RewindState.accent.opacity(0.75))
                .frame(width: max(0, min(headX, tipX) - max(0, startX)), height: 3)
                .offset(x: max(0, startX), y: y - 1.5)
            Capsule()
                .fill(RewindState.accent.opacity(0.22))
                .frame(width: max(0, min(width, tipX) - headX), height: 3)
                .offset(x: headX, y: y - 1.5)
            // The tip itself: the thing you can always come back to.
            Circle()
                .fill(state.isAtTip ? RewindState.accent : RewindState.accent.opacity(0.5))
                .frame(width: 6, height: 6)
                .offset(x: min(width - 3, max(-3, tipX - 3)), y: y - 3)
        }
    }

    /// Evenly spaced in time, so they slide under a still playhead as it scrubs.
    @ViewBuilder
    private func ticks(width: CGFloat, y: CGFloat, headX: CGFloat, scale: CGFloat) -> some View {
        let spacing = state.tickSpacing
        let leftEdge = state.playhead - Double(headX / scale)
        let firstTick = (leftEdge / spacing).rounded(.down) * spacing
        let count = min(64, Int(Double(width) / Double(scale) / spacing) + 2)
        ZStack(alignment: .topLeading) {
            ForEach(Array(0..<max(0, count)), id: \.self) { i in
                let t = firstTick + Double(i) * spacing
                let tx = x(for: t, headX: headX, scale: scale)
                if tx > -2 && tx < width + 2 {
                    Rectangle()
                        .fill(Color.white.opacity(t > state.playhead ? 0.10 : 0.18))
                        .frame(width: 1, height: 6)
                        .offset(x: tx, y: y - 3)
                }
            }
        }
    }

    @ViewBuilder
    private func marks(width: CGFloat, y: CGFloat, headX: CGFloat, scale: CGFloat, height: CGFloat) -> some View {
        let placed = TrailTrack.layout(marks: state.marks, playhead: state.playhead, headX: headX,
                                       scale: scale, width: width)
        ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.mark.id) { item in
                markGlyph(item: item, y: y, headX: headX)
            }
        }
    }

    @ViewBuilder
    private func markGlyph(item: PlacedMark, y: CGFloat, headX: CGFloat) -> some View {
        let isBranch = item.mark.kind == .branch
        let color = isBranch ? RewindState.branchAccent : RewindState.accent
        // Labels fade in as they come toward the playhead and out again as they pass.
        let nearness = TrailTrack.nearness(of: item.x, to: headX)
        ZStack(alignment: .topLeading) {
            if isBranch {
                // A branch is its own line leaving this one: a stub that goes somewhere,
                // in its own colour so it never reads as a scratch on this line.
                BranchStub()
                    .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 20, height: 11)
                    .offset(x: item.x, y: y)
            }
            Image(systemName: item.mark.kind.symbol)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(color)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Color(red: 0.05, green: 0.06, blue: 0.08)))
                .overlay(Circle().stroke(color.opacity(0.6), lineWidth: 1))
                .offset(x: item.x - 6.5, y: y - 6.5)
            if item.showsLabel {
                Text(item.mark.label)
                    .font(.system(size: 8, weight: isBranch ? .bold : .semibold, design: .rounded))
                    .foregroundColor(isBranch ? color : .white.opacity(0.9))
                    .lineLimit(1)
                    .frame(width: 104)
                    .opacity(nearness)
                    .offset(x: item.x - 52, y: y + 6 + CGFloat(item.row) * 9)
            }
        }
    }

    @ViewBuilder
    private func playhead(x headX: CGFloat, height: CGFloat, y: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // The smear: the faster the scrub, the more the head drags time behind it.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [RewindState.accent.opacity(0), RewindState.accent.opacity(0.35 * state.speed)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 26 + 40 * CGFloat(state.speed), height: 10)
                .offset(x: -(26 + 40 * CGFloat(state.speed)) / 2, y: y - 5)
            Capsule()
                .fill(state.isPeeking ? Color.white.opacity(0.85) : RewindState.accent)
                .frame(width: 2, height: height * 0.74)
                .offset(x: -1, y: height * 0.08)
            PlayheadArrow()
                .fill(state.isPeeking ? Color.white : RewindState.accent)
                .frame(width: 7, height: 5)
                .offset(x: -3.5, y: height * 0.08 - 5)
        }
        .offset(x: headX)
    }

    // MARK: - Label layout

    struct PlacedMark: Equatable {
        let mark: TrailMark
        let x: CGFloat
        let row: Int
        /// False when three events landed so close together that there is nowhere left to
        /// print this one's name. Its glyph still shows; only the label gives way.
        let showsLabel: Bool
    }

    /// Two events landing close together must not print on top of each other. Each label takes
    /// the first of three rows where nothing else is already sitting, and a label with nowhere
    /// to go is simply not drawn — overlapping type is worse than a nameless glyph.
    static func layout(marks: [TrailMark], playhead: TimeInterval, headX: CGFloat,
                       scale: CGFloat, width: CGFloat) -> [PlacedMark] {
        // Glyphs first, in time order: four edits inside a few seconds would otherwise draw as
        // one smudge. Each is nudged clear of the one before it, but never far enough to tell
        // a lie about when it happened, so a dense cluster still reads as a dense cluster.
        var positions: [(mark: TrailMark, x: CGFloat)] = []
        var lastX = -CGFloat.greatestFiniteMagnitude
        for mark in marks.sorted(by: { $0.time < $1.time }) {
            let honest = headX + CGFloat(mark.time - playhead) * scale
            guard honest > -40, honest < width + 40 else { continue }
            var x = honest
            if x - lastX < glyphSpacing {
                x = min(lastX + glyphSpacing, honest + maxGlyphNudge)
            }
            lastX = x
            positions.append((mark: mark, x: x))
        }

        var rows: [[ClosedRange<CGFloat>]] = [[], [], []]
        var placed: [PlacedMark] = []

        func consider(_ mark: TrailMark, _ x: CGFloat) {
            let halfWidth = labelWidth(mark.label) / 2
            let span = (x - halfWidth - 3)...(x + halfWidth + 3)
            var row: Int?
            for candidate in rows.indices where !rows[candidate].contains(where: { $0.overlaps(span) }) {
                row = candidate
                break
            }
            if let row { rows[row].append(span) }
            placed.append(PlacedMark(mark: mark, x: x, row: row ?? 0, showsLabel: row != nil))
        }

        // When the tape is crowded, the names worth keeping are the ones the user made.
        for item in positions where item.mark.kind.isNamedFirst { consider(item.mark, item.x) }
        for item in positions where !item.mark.kind.isNamedFirst { consider(item.mark, item.x) }
        return placed.sorted { $0.mark.time < $1.mark.time }
    }

    /// Close enough for laying out 8pt rounded text without measuring it.
    static func labelWidth(_ label: String) -> CGFloat {
        CGFloat(label.count) * 4.9 + 8
    }

    /// Two landmark glyphs closer than this read as one smudge.
    static let glyphSpacing: CGFloat = 11
    /// …and no glyph is moved further than this to clear its neighbour.
    static let maxGlyphNudge: CGFloat = 16

    /// 1 at the playhead, fading to nothing about a third of the track away. Labels come in as
    /// they approach and go out as they pass; the glyph on the rail stays either way, so the
    /// shape of the session is always readable even where its names are not.
    static func nearness(of x: CGFloat, to headX: CGFloat) -> Double {
        let distance = abs(Double(x - headX))
        return max(0.0, min(1.0, 1.0 - (distance - 26) / 130))
    }
}

/// The little diagonal that says "this line went somewhere else".
struct BranchStub: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.maxY)
        )
        return path
    }
}

struct PlayheadArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The twelve knobs, rolling. Values change digit by digit rather than jumping, so the numbers
/// read as the photo un-editing itself.
struct KnobRoll: View {
    let knobs: [RewindKnobValue]
    let accent: Color

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(knobs) { knob in
                VStack(alignment: .leading, spacing: 1) {
                    Text(knob.label)
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(knob.isChanged ? 0.75 : 0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(knob.display)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundColor(knob.isChanged ? accent : .white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(knob.isChanged ? accent.opacity(0.12) : Color.white.opacity(0.04))
                )
            }
        }
        .animation(.smooth(duration: 0.28), value: knobs)
    }
}

/// The whole Rewind readout: what you are holding, where the playhead is, how far back the
/// photo has been taken, and what the twelve knobs read there.
public struct RewindView: View {
    public let state: RewindState

    public init(state: RewindState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 5) {
            header
            TrailTrack(state: state)
                .frame(height: 62)
                .padding(.horizontal, 12)
            if !state.knobs.isEmpty {
                KnobRoll(knobs: state.knobs, accent: accent)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var accent: Color {
        state.branchName == nil ? RewindState.accent : RewindState.branchAccent
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                    .frame(width: 34, height: 34)
                Image(systemName: state.isPeeking ? "eye.fill" : "gobackward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("REWIND")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let branch = state.branchName {
                        Text(branch.uppercased())
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundColor(RewindState.branchAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(RewindState.branchAccent.opacity(0.18)))
                    }
                }
                Text(state.caption)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 6)

            transportMeter
        }
        .padding(.horizontal, 14)
        .animation(SpringPhysics.micro, value: state.caption)
    }

    /// What the transport is doing and how fast, with where you stand among the steps.
    private var transportMeter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: state.isPlaying ? (state.isReverse ? "backward.fill" : "play.fill") : "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(state.rateText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundColor(accent)
            if state.stepCount > 0 {
                Text("\(state.stepNumber) / \(state.stepCount)")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .animation(SpringPhysics.bubble, value: state.rate)
    }
}
