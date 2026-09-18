import SwiftUI

/// One thing that happened on the trail.
public struct TrailMark: Equatable, Hashable, Identifiable {
    public enum Kind: Equatable, Hashable {
        /// A knob turn. Hundreds of these; they rewind smoothly.
        case edit
        /// Auto Tone, a preset, a paste. These are steps, so the scrub clicks onto them.
        case landmark(String)
        /// A full develop state, masks and crop included. Crossing one restores it exactly.
        case keyframe(String)
        /// "I liked it here."
        case mark
        /// Where another take grows from this one.
        case fork(takes: Int)
    }

    public let id = UUID()
    /// Seconds before the tip. 0 is now.
    public let ago: TimeInterval
    public let kind: Kind

    public init(ago: TimeInterval, kind: Kind) {
        self.ago = ago
        self.kind = kind
    }
}

public struct RewindState: Equatable {
    /// Where the playhead sits, in seconds before the tip.
    public let ago: TimeInterval
    /// How far back this take goes.
    public let span: TimeInterval
    public let marks: [TrailMark]
    public let takeName: String
    public let otherTakes: Int
    public let editsBack: Int
    /// The twelve knobs as they were at the playhead.
    public let knobs: [KnobCell]

    public init(ago: TimeInterval, span: TimeInterval, marks: [TrailMark],
                takeName: String, otherTakes: Int, editsBack: Int, knobs: [KnobCell]) {
        self.ago = ago
        self.span = span
        self.marks = marks
        self.takeName = takeName
        self.otherTakes = otherTakes
        self.editsBack = editsBack
        self.knobs = knobs
    }
}

/// The notch while you are scrubbing your own session.
public struct RewindView: View {
    public let state: RewindState
    private let accent = Color(red: 0.42, green: 0.78, blue: 1.0)

    public init(state: RewindState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            TrailTrack(state: state, accent: accent)
                .frame(height: 30)
            if !state.knobs.isEmpty {
                KnobRowGrid(cells: state.knobs, accent: accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent)
            Text("REWIND")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .tracking(0.6)
            Text(state.takeName)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
            Spacer(minLength: 4)
            if state.otherTakes > 0 {
                Label("\(state.otherTakes)", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(Self.caption(ago: state.ago, edits: state.editsBack))
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(state.ago == 0 ? .white.opacity(0.5) : accent)
        }
    }

    static func caption(ago: TimeInterval, edits: Int) -> String {
        if ago <= 0.5 { return "now" }
        let mins = Int(ago) / 60
        let secs = Int(ago) % 60
        let time = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        return "\(time) back · \(edits) edits"
    }
}

/// The trail itself: the take you are on, what happened along it, and where other takes grow.
struct TrailTrack: View {
    let state: RewindState
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let mid = geo.size.height * 0.62
            // Oldest on the left, now on the right.
            let x: (TimeInterval) -> CGFloat = { ago in
                guard state.span > 0 else { return w }
                return w * CGFloat(1.0 - min(max(ago / state.span, 0), 1))
            }
            let head = x(state.ago)

            ZStack(alignment: .topLeading) {
                // The whole take, including the part you have rolled back past. It stays:
                // rolling forward puts you exactly where you were.
                Capsule()
                    .fill(Color.white.opacity(0.13))
                    .frame(width: w, height: 3)
                    .position(x: w / 2, y: mid)

                // Where you are now.
                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: max(head, 2), height: 3)
                    .position(x: max(head, 2) / 2, y: mid)

                ForEach(state.marks) { mark in
                    markView(mark, at: x(mark.ago), mid: mid)
                }

                // Playhead
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 20)
                    .position(x: head, y: mid - 1)
                    .shadow(color: accent.opacity(0.9), radius: 5)

                // The tip: where you were before you started rolling back.
                Circle()
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
                    .position(x: w - 3, y: mid)
            }
        }
    }

    @ViewBuilder
    private func markView(_ mark: TrailMark, at x: CGFloat, mid: CGFloat) -> some View {
        switch mark.kind {
        case .edit:
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 6)
                .position(x: x, y: mid)

        case .landmark(let name):
            VStack(spacing: 2) {
                Text(name)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize()
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1.5, height: 11)
            }
            .position(x: x, y: mid - 6)

        case .keyframe(let name):
            // A full state, masks and crop included.
            VStack(spacing: 2) {
                Text(name)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.76, blue: 0.4))
                    .fixedSize()
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 1.0, green: 0.76, blue: 0.4))
                    .frame(width: 2.5, height: 14)
            }
            .position(x: x, y: mid - 7)

        case .mark:
            Image(systemName: "bookmark.fill")
                .font(.system(size: 7))
                .foregroundColor(Color(red: 0.55, green: 0.9, blue: 0.6))
                .position(x: x, y: mid - 12)

        case .fork(let takes):
            // Another take grows from here. Roll back to it and edit, and this is where
            // the new one starts.
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: x, y: mid))
                    p.addQuadCurve(to: CGPoint(x: x + 22, y: mid + 11),
                                   control: CGPoint(x: x + 12, y: mid))
                }
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if takes > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: x, y: mid))
                        p.addQuadCurve(to: CGPoint(x: x + 18, y: mid - 12),
                                       control: CGPoint(x: x + 10, y: mid))
                    }
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 4, height: 4)
                    .position(x: x, y: mid)
            }
        }
    }
}
