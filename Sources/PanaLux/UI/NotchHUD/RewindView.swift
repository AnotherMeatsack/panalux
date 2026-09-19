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

/// One tangent, drawn as a lane: where its own line runs, how busy it was, and where it came from.
public struct TangentLane: Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Position in the order tangents were made, which is also which colour it wears.
    public let colorIndex: Int
    /// Where this tangent's own line begins (the moment it left its parent) and where it ends.
    public let start: TimeInterval
    public let tip: TimeInterval
    public let parentID: String?
    /// The tangent being edited and looked at right now.
    public let isActive: Bool
    /// Part of the line that leads to the active tangent, so it is drawn as history, not as a stranger.
    public let isOnPath: Bool
    /// How much happened in each slice of the whole session, 0…1.
    public let activity: [Float]

    public init(id: String, name: String, colorIndex: Int, start: TimeInterval, tip: TimeInterval,
                parentID: String?, isActive: Bool, isOnPath: Bool, activity: [Float]) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.start = start
        self.tip = tip
        self.parentID = parentID
        self.isActive = isActive
        self.isOnPath = isOnPath
        self.activity = activity
    }
}

/// Which tangent the editing is on, for the badge that rides beside every readout.
public struct TangentInfo: Equatable {
    public let name: String
    public let colorIndex: Int
    /// 1-based, in the order tangents were made.
    public let number: Int
    public let total: Int

    public init(name: String, colorIndex: Int, number: Int, total: Int) {
        self.name = name
        self.colorIndex = colorIndex
        self.number = number
        self.total = total
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
    /// Every tangent, for the lanes.
    public var tangents: [TangentLane]
    /// 1-based position of the active tangent, and how many there are.
    public var tangentNumber: Int
    public var tangentCount: Int
    public var tangentColorIndex: Int
    /// The steps around the playhead, for the tape's ticks.
    public var steps: [TimeInterval]
    /// The stretch of time the lanes cover.
    public var spanStart: TimeInterval
    public var spanEnd: TimeInterval

    public init(origin: TimeInterval = 0, tip: TimeInterval = 0, playhead: TimeInterval = 0,
                window: TimeInterval = 60, marks: [TrailMark] = [],
                knobs: [RewindKnobValue] = [], branchName: String? = nil, isPeeking: Bool = false,
                isAtTip: Bool = true, caption: String = "Now", speed: Double = 0,
                rate: Double = 1, isPlaying: Bool = false, isReverse: Bool = false,
                stepNumber: Int = 0, stepCount: Int = 0,
                tangents: [TangentLane] = [], tangentNumber: Int = 1, tangentCount: Int = 1, tangentColorIndex: Int = 0,
                steps: [TimeInterval] = [], spanStart: TimeInterval = 0, spanEnd: TimeInterval = 0) {
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
        self.tangents = tangents
        self.tangentNumber = tangentNumber
        self.tangentCount = tangentCount
        self.tangentColorIndex = tangentColorIndex
        self.steps = steps
        self.spanStart = spanStart
        self.spanEnd = spanEnd
    }

    /// One colour per tangent, in the order they were made. The original wears the amber Rewind
    /// has always had; the rest are picked to stay apart from it and from each other.
    public static let tangentPalette: [Color] = [
        Color(red: 1.00, green: 0.70, blue: 0.25),   // original: amber
        Color(red: 0.36, green: 0.80, blue: 1.00),   // cyan
        Color(red: 0.75, green: 0.52, blue: 1.00),   // violet
        Color(red: 0.32, green: 0.86, blue: 0.55),   // green
        Color(red: 1.00, green: 0.42, blue: 0.55),   // rose
        Color(red: 0.98, green: 0.90, blue: 0.40)    // lemon
    ]
    public static func tangentColor(_ index: Int) -> Color {
        tangentPalette[((index % tangentPalette.count) + tangentPalette.count) % tangentPalette.count]
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

// MARK: - Motion

/// The springs behind the readout. A class rather than state: the display-rate timeline
/// advances it once a frame, and it must not ask SwiftUI to redraw on its own.
///
/// Everything here is critically damped, so things arrive quickly and never overshoot. That is
/// the whole of the "Apple" feel: motion that starts at once, has weight, and comes to rest.
final class RewindMotion {
    /// Where the playhead is drawn, in trail time. It chases the real one.
    var position: Double = .nan
    /// The tape's visible span in seconds. It re-zooms smoothly as the editing gets denser.
    var window: Double = 8
    /// 0…1 blip that fires each time the playhead lands on a new step, then decays.
    private(set) var pulse: Double = 0
    /// 0…1 how fast the tape is moving, so the tape can lean into its own speed.
    private(set) var speed: Double = 0
    /// Per tangent, how "lit" its lane is: eases toward 1 for the active one.
    private(set) var glow: [String: Double] = [:]

    private var velocity: Double = 0
    private var logWindowVelocity: Double = 0
    private var lastStep: Int = -1
    private var lastTime: TimeInterval = 0

    /// One step of a critically damped spring, solved exactly rather than integrated. It gives the
    /// same answer at 60, 120 or 240 Hz and cannot blow up if a frame is late, so a faster screen
    /// is smoother without being any different.
    static func spring(_ offset: inout Double, _ velocity: inout Double, omega: Double, dt: Double) {
        let decay = exp(-omega * dt)
        let c = velocity + omega * offset
        let newOffset = (offset + c * dt) * decay
        let newVelocity = (velocity - omega * c * dt) * decay
        offset = newOffset
        velocity = newVelocity
    }

    func advance(_ state: RewindState, now: TimeInterval) {
        let target = state.isPeeking ? state.tip : state.playhead
        if position.isNaN {
            position = target
            window = max(1, state.window)
            lastStep = state.stepNumber
            for lane in state.tangents { glow[lane.id] = lane.isActive ? 1 : 0 }
        }
        let dt = lastTime == 0 ? 1.0 / 120.0 : min(1.0 / 30.0, max(0, now - lastTime))
        lastTime = now
        guard dt > 0 else { return }

        // A jump bigger than the tape would glide across nothing. Start the glide from the edge
        // of what is on screen instead, so the last stretch is always something you can see.
        let reach = window * 0.55
        if abs(position - target) > reach {
            position = target - max(-reach, min(reach, position - target))
        }
        var offset = position - target
        RewindMotion.spring(&offset, &velocity, omega: 30, dt: dt)
        position = target + offset
        if abs(offset) < 1e-4, abs(velocity) < 1e-3 { position = target; velocity = 0 }

        // The zoom moves in log space and much more slowly: it should feel like focus, not motion.
        let logTarget = log(max(0.5, state.window))
        var logOffset = log(max(0.5, window)) - logTarget
        RewindMotion.spring(&logOffset, &logWindowVelocity, omega: 7, dt: dt)
        window = exp(logTarget + logOffset)

        if state.stepNumber != lastStep {
            if lastStep != -1 { pulse = min(1, pulse + 0.9) }
            lastStep = state.stepNumber
        }
        pulse *= exp(-dt * 6.5)
        if pulse < 0.001 { pulse = 0 }

        let rel = abs(velocity) / max(0.5, window)
        speed += (min(1, rel * 1.6) - speed) * (1 - exp(-dt * 9))

        for lane in state.tangents {
            let now = glow[lane.id] ?? 0
            glow[lane.id] = now + ((lane.isActive ? 1 : 0) - now) * (1 - exp(-dt * 10))
        }
    }
}

// MARK: - The badge

/// Which tangent you are on. It rides beside every readout, so you cannot forget you are on a
/// tangent, and it is the same colour as that tangent's lane and playhead everywhere else.
public struct TangentBadge: View {
    public let name: String
    public let colorIndex: Int
    public var detail: String?

    public init(name: String, colorIndex: Int, detail: String? = nil) {
        self.name = name
        self.colorIndex = colorIndex
        self.detail = detail
    }

    public init(_ info: TangentInfo) {
        self.init(name: info.name, colorIndex: info.colorIndex, detail: "\(info.number) of \(info.total)")
    }

    public var body: some View {
        let color = RewindState.tangentColor(colorIndex)
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.9), radius: 3)
            Text(name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .opacity(0.62)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(color.opacity(0.38), lineWidth: 0.75))
    }
}

// MARK: - The tape

/// The tape. The playhead stays put in the middle and time moves under it. Every tick is one
/// thing you changed; the ticks under the playhead swell like a magnifying glass, and each new
/// step gives them a small blip, so turning the ring feels like it is touching the tape.
public struct TrailTrack: View {
    public let state: RewindState
    let motion: RewindMotion
    /// The frame's time. Passing it in is what makes the canvas redraw every frame.
    let now: TimeInterval

    init(state: RewindState, motion: RewindMotion, now: TimeInterval) {
        self.state = state
        self.motion = motion
        self.now = now
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            _ = now
            TrailTrack.draw(&ctx, size: size, state: state, motion: motion)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.09),
                .init(color: .black, location: 0.91),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        )
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, state: RewindState, motion: RewindMotion) {
        let position = motion.position.isNaN ? state.playhead : motion.position
        let window = max(0.5, motion.window)
        let headX = size.width * 0.5
        let scale = size.width / CGFloat(window)
        let base = size.height * 0.60
        let color = RewindState.tangentColor(state.tangentColorIndex)
        let pulse = CGFloat(motion.pulse)

        // The line the ticks stand on.
        ctx.fill(Path(CGRect(x: 0, y: base - 0.5, width: size.width, height: 1)),
                 with: .color(.white.opacity(0.09)))

        // Ticks: one per step. Near the playhead they grow, and a fresh step makes them jump.
        let sigma: CGFloat = 60 + 26 * CGFloat(motion.speed)
        for t in state.steps {
            let x = headX + CGFloat(t - position) * scale
            if x < -4 || x > size.width + 4 { continue }
            let d = abs(x - headX)
            let magnify = exp(-pow(d / sigma, 2))
            let blip = pulse * exp(-pow(d / 36, 2))
            let height = 10 + 34 * magnify + 20 * blip
            let width = 1.3 + 1.1 * magnify
            let passed = t <= position + 1e-6
            let alpha = (passed ? 0.50 : 0.22) + 0.46 * Double(magnify)
            let rect = CGRect(x: x - width / 2, y: base - height / 2, width: width, height: height)
            ctx.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(.white.opacity(alpha)))
        }

        // The playhead: a soft glow under a crisp line, and a timecode on top.
        let lineWidth = 2.4 + 1.2 * pulse
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.fill(
                Path(roundedRect: CGRect(x: headX - 3, y: 12, width: 6, height: size.height - 14), cornerRadius: 3),
                with: .color(color.opacity(0.50 + 0.30 * Double(pulse)))
            )
        }
        ctx.fill(
            Path(roundedRect: CGRect(x: headX - lineWidth / 2, y: 12, width: lineWidth, height: size.height - 14),
                 cornerRadius: lineWidth / 2),
            with: .color(color)
        )
        // Landmarks: a glyph above the tape, a stem to it, a name below. The ones the playhead is
        // passing swell, the same way the ticks do.
        let placed = layout(marks: state.marks, playhead: position, headX: headX, scale: scale, width: size.width)
        for item in placed {
            let d = abs(item.x - headX)
            let near = CGFloat(exp(-pow(d / 34, 2)))
            let isBranch = item.mark.kind == .branch
            let tint = isBranch
                ? RewindState.tangentColor(state.tangents.first { $0.name == item.mark.label }?.colorIndex ?? 1)
                : Color.white
            let radius: CGFloat = 8 * (1 + 0.32 * near + 0.22 * pulse * near)
            let center = CGPoint(x: item.x, y: base - 33)

            var stem = Path()
            stem.move(to: CGPoint(x: item.x, y: center.y + radius))
            stem.addLine(to: CGPoint(x: item.x, y: base - 6))
            ctx.stroke(stem, with: .color(tint.opacity(0.28 + 0.4 * Double(near))), lineWidth: 1)

            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2))
            ctx.fill(disc, with: .color(Color(red: 0.06, green: 0.07, blue: 0.09)))
            ctx.stroke(disc, with: .color(tint.opacity(0.55 + 0.4 * Double(near))), lineWidth: 1)
            var symbol = ctx.resolve(Image(systemName: item.mark.kind.symbol))
            symbol.shading = .color(tint.opacity(0.95))
            let glyph = radius * 1.05
            ctx.draw(symbol, in: CGRect(x: center.x - glyph / 2, y: center.y - glyph / 2, width: glyph, height: glyph))

            if item.showsLabel {
                let labelCenter = CGPoint(x: item.x, y: base + 15 + CGFloat(item.row) * 12)
                let backing = CGRect(x: labelCenter.x - labelWidth(item.mark.label) / 2, y: labelCenter.y - 7,
                                     width: labelWidth(item.mark.label), height: 14)
                ctx.fill(Path(roundedRect: backing, cornerRadius: 7),
                         with: .color(Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.78)))
                ctx.draw(
                    Text(item.mark.label)
                        .font(.system(size: 8.5, weight: isBranch ? .bold : .semibold, design: .rounded))
                        .foregroundColor(isBranch ? tint : .white.opacity(0.92)),
                    at: labelCenter,
                    anchor: .center
                )
            }
        }

        let stamp = CGRect(x: headX - 25, y: 0, width: 50, height: 15)
        ctx.fill(Path(roundedRect: stamp, cornerRadius: 7.5), with: .color(Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.85)))
        ctx.stroke(Path(roundedRect: stamp, cornerRadius: 7.5), with: .color(color.opacity(0.55)), lineWidth: 0.75)
        ctx.draw(
            Text(RewindEngine.clock(position - state.spanStart))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color),
            at: CGPoint(x: stamp.midX, y: stamp.midY),
            anchor: .center
        )
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

// MARK: - The tangents

/// Every tangent as a lane over the whole session, with the playhead running down through all of
/// them. Forks curve off the line they left; the tangent being edited is lit and the rest sit back.
struct TangentsMap: View {
    let state: RewindState
    let motion: RewindMotion
    let now: TimeInterval

    static let rowHeight: CGFloat = 21
    static let labelWidth: CGFloat = 64
    static let maxRows = 5

    static func height(for tangentCount: Int) -> CGFloat {
        CGFloat(min(max(1, tangentCount), maxRows)) * rowHeight + 8
    }

    /// At most five lanes; when there are more, the window follows the active tangent.
    static func visible(_ tangents: [TangentLane]) -> [TangentLane] {
        guard tangents.count > maxRows else { return tangents }
        let active = tangents.firstIndex { $0.isActive } ?? 0
        let first = min(max(0, active - maxRows / 2), tangents.count - maxRows)
        return Array(tangents[first..<(first + maxRows)])
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            _ = now
            TangentsMap.draw(&ctx, size: size, state: state, motion: motion)
        }
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, state: RewindState, motion: RewindMotion) {
        let lanes = visible(state.tangents)
        guard !lanes.isEmpty else { return }
        let x0 = labelWidth
        let plotWidth = max(1, size.width - x0 - 6)
        let span = max(1, state.spanEnd - state.spanStart)
        func x(_ t: TimeInterval) -> CGFloat {
            x0 + CGFloat(min(1, max(0, (t - state.spanStart) / span))) * plotWidth
        }
        func y(_ row: Int) -> CGFloat { 4 + rowHeight * CGFloat(row) + rowHeight / 2 }
        let rowOf = Dictionary(uniqueKeysWithValues: lanes.enumerated().map { ($1.id, $0) })
        let position = motion.position.isNaN ? state.playhead : motion.position
        let pulse = CGFloat(motion.pulse)

        for (row, lane) in lanes.enumerated() {
            let color = RewindState.tangentColor(lane.colorIndex)
            let glow = CGFloat(motion.glow[lane.id] ?? (lane.isActive ? 1 : 0))
            let cy = y(row)
            let dim = 0.40 + 0.60 * Double(glow)

            // The lit lane: a quiet wash behind the tangent being edited.
            if glow > 0.01 {
                ctx.fill(
                    Path(roundedRect: CGRect(x: 2, y: cy - rowHeight / 2 + 1, width: size.width - 4, height: rowHeight - 2), cornerRadius: 7),
                    with: .color(color.opacity(0.10 * Double(glow)))
                )
            }

            // Name.
            ctx.draw(
                Text(lane.name)
                    .font(.system(size: 9, weight: lane.isActive ? .bold : .semibold, design: .rounded))
                    .foregroundColor(color.opacity(0.55 + 0.45 * Double(glow))),
                at: CGPoint(x: 12 + 4, y: cy), anchor: .leading
            )
            ctx.fill(Path(ellipseIn: CGRect(x: 6, y: cy - 2.5, width: 5, height: 5)),
                     with: .color(color.opacity(0.35 + 0.65 * Double(glow))))

            // Its line, from where it left its parent to its own last moment.
            let left = x(lane.start)
            let right = max(left + 2, x(lane.tip))
            ctx.fill(Path(roundedRect: CGRect(x: left, y: cy - 1, width: right - left, height: 2), cornerRadius: 1),
                     with: .color(color.opacity(0.30 * dim + 0.10)))

            // Activity: what you did, when. Dense bursts stand tall; quiet stretches are flat.
            let n = max(1, lane.activity.count)
            let slot = plotWidth / CGFloat(n)
            for (i, value) in lane.activity.enumerated() where value > 0.02 {
                let t0 = state.spanStart + Double(i) / Double(n) * span
                guard t0 >= lane.start - span / Double(n), t0 <= lane.tip + span / Double(n) else { continue }
                let barHeight = 2 + 11 * CGFloat(value)
                let rect = CGRect(x: x0 + CGFloat(i) * slot + 0.3, y: cy - barHeight / 2,
                                  width: max(1, slot - 0.8), height: barHeight)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 0.8),
                         with: .color(color.opacity((0.22 + 0.55 * Double(value)) * dim)))
            }

            // Where it left its parent: a curve off the parent's line into this one.
            if let parentID = lane.parentID, let parentRow = rowOf[parentID] {
                let from = CGPoint(x: left, y: y(parentRow))
                let to = CGPoint(x: left + 12, y: cy)
                var curve = Path()
                curve.move(to: from)
                curve.addCurve(to: to, control1: CGPoint(x: from.x + 9, y: from.y),
                               control2: CGPoint(x: to.x - 9, y: to.y))
                ctx.stroke(curve, with: .color(color.opacity(0.35 + 0.55 * Double(glow))),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: from.x - 2.25, y: from.y - 2.25, width: 4.5, height: 4.5)),
                         with: .color(color.opacity(0.9)))
            }
        }

        // The playhead, down through every tangent.
        let px = x(position)
        let lineColor = RewindState.tangentColor(state.tangentColorIndex)
        ctx.fill(Path(CGRect(x: px - 0.6, y: 2, width: 1.2, height: size.height - 4)),
                 with: .color(lineColor.opacity(0.65)))
        if let activeRow = lanes.firstIndex(where: { $0.isActive }) {
            let radius: CGFloat = 3.6 + 2.4 * pulse
            let center = CGPoint(x: px, y: y(activeRow))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(Path(ellipseIn: CGRect(x: center.x - radius - 2, y: center.y - radius - 2,
                                                  width: (radius + 2) * 2, height: (radius + 2) * 2)),
                           with: .color(lineColor.opacity(0.7)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(lineColor))
        }
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

/// The whole Rewind readout: which tangent you are on, the tape under the playhead, every tangent as
/// a lane, and what the twelve knobs read right here.
public struct RewindView: View {
    public let state: RewindState
    @State private var motion = RewindMotion()

    public init(state: RewindState) {
        self.state = state
    }

    /// The window is sized to this: header, tape, lanes, knobs, and the padding between.
    public static func height(tangentCount: Int, hasKnobs: Bool) -> CGFloat {
        let lanes = TangentsMap.height(for: tangentCount)
        return 54 + 112 + 8 + lanes + (hasKnobs ? 8 + 70 : 0) + 14
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let _ = motion.advance(state, now: now)
                VStack(spacing: 8) {
                    TrailTrack(state: state, motion: motion, now: now)
                        .frame(height: 112)
                    TangentsMap(state: state, motion: motion, now: now)
                        .frame(height: TangentsMap.height(for: state.tangents.count))
                }
            }
            .padding(.horizontal, 14)
            if !state.knobs.isEmpty {
                KnobRoll(knobs: state.knobs, accent: accent)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var accent: Color { RewindState.tangentColor(state.tangentColorIndex) }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isPeeking ? "eye.fill" : "gobackward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("REWIND")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    TangentBadge(name: state.tangentCount > 1 || state.branchName != nil ? (state.branchName ?? "Original") : "Original",
                              colorIndex: state.tangentColorIndex,
                              detail: state.tangentCount > 1 ? "\(state.tangentNumber) of \(state.tangentCount)" : nil)
                        .id(state.tangentNumber)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Text(state.caption)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 6)
            transportMeter
        }
        .padding(.horizontal, 14)
        .animation(.smooth(duration: 0.3), value: state.tangentNumber)
    }

    /// What the transport is doing and how fast, with where you stand among the steps.
    private var transportMeter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: state.isPlaying ? (state.isReverse ? "backward.fill" : "play.fill") : "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(state.rateText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundColor(accent)
            if state.stepCount > 0 {
                Text("\(state.stepNumber) / \(state.stepCount)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .animation(.smooth(duration: 0.25), value: state.rate)
    }
}
