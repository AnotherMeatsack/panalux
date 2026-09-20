import SwiftUI

/// A scripted editing session for the intro's Rewind+ slide.
///
/// The slide shows the real readout, `RewindView`, driven by a made-up session, so what plays is
/// what the panel does: the same tape, the same lanes, the same springs. Nothing here touches
/// Lightroom or the trail; it is a function from "seconds into the slide" to "what the readout
/// would be showing, and which keys and rings are down".
enum IntroRewindDemo {
    struct Frame {
        var state: RewindState
        /// Panel key ids that are held or pressed right now.
        var keys: [String]
        /// A key press, not a hold: drawn brighter and pushed in.
        var flashing: Bool
        /// Which rings are being turned: 0 left, 1 centre, 2 right.
        var rings: Set<Int>
        var changedKnobs: Set<Int>
        var step: String
        /// The readout only exists while Undo is held.
        var readoutOpacity: Double
    }

    static let length: TimeInterval = 46
    /// Ends just after a burst of edits, so "now" has ticks around it and the tape is never empty.
    static let tip: TimeInterval = 226
    static let spanEnd: TimeInterval = 240
    static let window: TimeInterval = 17

    /// Bursts of turning with quiet between them, the way a real session looks.
    static let bursts: [Double] = [6, 14, 26, 41, 58, 66, 92, 104, 121, 141, 158, 176, 196, 214]

    /// Every change in the original line: sixteen steps a burst, and the two ends.
    static let steps: [TimeInterval] = {
        var out: [TimeInterval] = [0]
        for centre in bursts {
            for i in 0..<16 { out.append(centre + Double(i) * 0.55 + Double((i * 7) % 3) * 0.08) }
        }
        out.append(tip)
        return out.sorted()
    }()

    static let marks: [TrailMark] = [
        TrailMark(id: "open", time: 0, label: "Opened", kind: .open),
        TrailMark(id: "wb", time: 26, label: "Auto White Balance", kind: .action),
        TrailMark(id: "mask", time: 58, label: "New Radial Mask", kind: .mask),
        TrailMark(id: "mark", time: 92, label: "Mark", kind: .mark),
        TrailMark(id: "crop", time: 140, label: "Crop", kind: .crop)
    ]

    /// What each step changed, cycled: this is what the caption reads as you click through.
    static let changes = [
        "Exposure +0.35 EV", "Contrast +11", "Temp 5650 K", "Shadows -4", "Vibrance +9",
        "Highlights -7", "Whites +2", "Texture +3", "Exposure +0.30 EV", "Contrast +8"
    ]

    // MARK: - The script

    static func frame(at t: TimeInterval) -> Frame {
        let last = steps.count - 1
        let held = t >= 1.4
        var keys: [String] = held ? ["button_undo"] : []
        var flashing = false
        var rings: Set<Int> = []
        var changed: Set<Int> = []
        var playhead = tip
        var caption = "Now"
        var step = "Hold Undo"
        var isPlaying = false
        var rate = 1.0
        var jogSpeed = 0.0
        var lines = 1                       // 1 = just the original, 2 = a tangent exists
        var activeLine = 0
        var forkTime = 0.0
        var tangentTip = 0.0
        var rolledBack = 0.0

        // 1. The right ring: one click, one change. Then faster, to travel.
        let phase1 = 1.4..<7.5
        if phase1.contains(t) {
            step = "1  Turn the right ring: one click, one change"
            let n = backCount(t)
            playhead = steps[max(0, last - n)]
            caption = changes[(last - n) % changes.count]
            rings = t >= 2.0 ? [2] : []
            jogSpeed = t >= 5.0 ? 0.7 : 0.05
            rolledBack = min(0.85, Double(n) / 44)
        }

        // 2. Play it back at normal speed.
        let playStart = 7.5, stopAt = 12.5
        let restingAfterJog = steps[max(0, last - backCount(playStart))]
        if t >= playStart && t < 13.2 {
            step = t < stopAt ? "2  Press Play to replay your edit" : "2  Stop pauses it, right where you are"
            let until = min(t, stopAt)
            playhead = restingAfterJog + advance(from: playStart, to: until)
            let dial = dialRate(at: until - playStart)
            rate = dial
            isPlaying = t < stopAt
            caption = isPlaying ? "Playing" : "Paused · " + changes[stepIndex(at: playhead) % changes.count]
            rolledBack = max(0.2, 0.85 - (playhead - restingAfterJog) / 14)
            if t < playStart + 0.45 { keys.append("button_transport_forward"); flashing = true }
            if t >= stopAt && t < stopAt + 0.45 { keys.append("button_transport_stop"); flashing = true }
        }
        let paused = restingAfterJog + advance(from: playStart, to: stopAt)

        // 3. Add Node: a tangent starts here, and the original is kept.
        let tangentAt = 13.2
        if t >= tangentAt && t < 18.8 {
            step = "3  Add Node: a tangent starts here. The original is kept"
            lines = 2
            activeLine = 1
            forkTime = paused
            let grown = max(0, t - (tangentAt + 0.4))
            tangentTip = min(spanEnd - 3, paused + min(44, grown * 10))
            playhead = tangentTip
            caption = t < tangentAt + 2.4
                ? "Tangent 2 started at \(RewindEngine.clock(paused)) · Original is kept"
                : changes[(Int(grown / 0.6) + 1) % changes.count]
            if t < tangentAt + 0.45 { keys.append("button_add_node"); flashing = true }
            if t >= tangentAt + 1.2 {
                changed = [Int(grown / 0.9) % 2 == 0 ? 1 : 3]
                rings = []
            }
            rolledBack = 0.1
        }

        // 4. The center ring compares tangents.
        let hopStart = 18.8
        if t >= hopStart {
            step = "4  Turn the center ring to compare tangents. Both versions stay saved."
            lines = 2
            forkTime = paused
            tangentTip = min(spanEnd - 3, paused + 44)
            // Still on the tangent, then Original, tangent, Original: three hops.
            let hops = t < 19.4 ? 0 : min(3, 1 + Int((t - 19.4) / 1.9))
            activeLine = hops % 2 == 0 ? 1 : 0
            playhead = activeLine == 0 ? tip : tangentTip
            let since = t - (19.4 + Double(max(0, hops - 1)) * 1.9)
            if hops > 0, since >= 0, since < 0.8 { rings = [1] }
            caption = (activeLine == 0 ? "Original" : "Tangent 2") + " · " + (activeLine == 0 ? "Exposure +0.90 EV" : "Contrast +11")
            rolledBack = activeLine == 0 ? 0 : 0.5
            changed = []
        }

        if t >= 24 {
            step = "5  Turn the left ring to jump between recorded landmarks"
            activeLine = 0
            playhead = t < 26 ? 140 : 92
            caption = t < 26 ? "Crop landmark" : "Marked moment"
            rings = [0]
        }

        // Assemble what the readout would show.
        let onTangent = activeLine == 1 && lines == 2
        let activeTip = onTangent ? tangentTip : tip
        let nearby = stepsForTape(around: playhead, onTangent: onTangent, forkTime: forkTime, tangentTip: tangentTip)
        // True totals, not the handful drawn: steps in the original up to the fork, then the tangent's own.
        let beforeFork = stepIndex(at: forkTime) + 1
        let tangentSteps = { (to: TimeInterval) in max(0, Int((to - forkTime) / 0.6)) }
        let number = onTangent ? beforeFork + tangentSteps(playhead) : stepIndex(at: playhead) + 1
        let total = onTangent ? beforeFork + tangentSteps(tangentTip) : steps.count
        var tapeMarks = marks
        if lines == 2 {
            tapeMarks.append(TrailMark(id: "fork", time: forkTime, label: "Tangent 2", kind: .branch, branchName: "Tangent 2"))
        }
        var state = RewindState(
            origin: 0, tip: activeTip, playhead: playhead, window: window,
            marks: tapeMarks, knobs: knobs(rolledBack: rolledBack, onTangent: onTangent),
            branchName: onTangent ? "Tangent 2" : nil,
            isPeeking: false, isAtTip: activeTip - playhead < 0.4, caption: caption, speed: jogSpeed,
            rate: rate, isPlaying: isPlaying, isReverse: false,
            stepNumber: number, stepCount: max(number, total),
            tangents: lanes(lines: lines, active: activeLine, forkTime: forkTime, tangentTip: tangentTip),
            tangentNumber: onTangent ? 2 : 1, tangentCount: lines, tangentColorIndex: onTangent ? 1 : 0,
            steps: nearby, spanStart: 0, spanEnd: spanEnd
        )
        // Before Undo goes down there is nothing to show.
        if !held { state.caption = "Now" }
        return Frame(
            state: state, keys: keys, flashing: flashing, rings: rings, changedKnobs: changed, step: step,
            readoutOpacity: held ? min(1, (t - 1.4) / 0.5) : 0
        )
    }

    // MARK: - Pieces of the script

    /// How many steps back the ring has been turned by `t`: slow and exact, then quicker.
    static func backCount(_ t: TimeInterval) -> Int {
        if t < 2.0 { return 0 }
        if t < 5.0 { return Int((t - 2.0) / 0.4) }                    // 0…7, one click at a time
        return 7 + Int((min(t, 7.5) - 5.0) / 0.25) * 12               // then travelling: most of the session
    }

    /// Playback has no duplicate speed dials in the factory layout.
    static func dialRate(at u: TimeInterval) -> Double { 1 }

    /// Trail time covered by playback between two moments of the slide.
    static func advance(from a: TimeInterval, to b: TimeInterval) -> Double {
        guard b > a else { return 0 }
        var total = 0.0
        var u = 0.0
        let dt = 0.02
        while a + u < b {
            total += dialRate(at: u) * min(dt, b - a - u)
            u += dt
        }
        return total
    }

    static func stepIndex(at t: TimeInterval) -> Int {
        var found = 0
        for (i, s) in steps.enumerated() where s <= t + 1e-6 { found = i }
        return found
    }

    /// The steps the tape draws around the playhead. On a tangent that is the original's steps up to
    /// where it left, then the tangent's own; on the original it is just the original's.
    static func stepsForTape(around playhead: TimeInterval, onTangent: Bool, forkTime: TimeInterval,
                             tangentTip: TimeInterval) -> [TimeInterval] {
        let half = window * 1.4
        var out = steps.filter { abs($0 - playhead) <= half }
        if onTangent {
            out = out.filter { $0 <= forkTime + 1e-6 }
            var t = forkTime + 0.6
            while t <= tangentTip + 1e-6 {
                if abs(t - playhead) <= half { out.append(t) }
                t += 0.6
            }
        }
        return out.sorted()
    }

    static func lanes(lines: Int, active: Int, forkTime: TimeInterval, tangentTip: TimeInterval) -> [TangentLane] {
        let original = TangentLane(
            id: "t0", name: "Original", colorIndex: 0, start: 0, tip: tip, parentID: nil,
            isActive: active == 0, isOnPath: true,
            activity: activity(from: 0, to: tip, salt: 0)
        )
        guard lines == 2 else { return [original] }
        let tangent = TangentLane(
            id: "t1", name: "Tangent 2", colorIndex: 1, start: forkTime, tip: max(forkTime + 0.5, tangentTip),
            parentID: "t0", isActive: active == 1, isOnPath: active == 1,
            activity: activity(from: forkTime, to: tangentTip, salt: 5, dense: true)
        )
        return [original, tangent]
    }

    static func activity(from: TimeInterval, to: TimeInterval, salt: Int, dense: Bool = false) -> [Float] {
        let n = RewindEngine.laneBuckets
        var counts = [Float](repeating: 0, count: n)
        if dense {
            let a = Int(from / spanEnd * Double(n)), b = min(n - 1, Int(to / spanEnd * Double(n)))
            if b >= a {
                for i in a...b { counts[i] = Float(8 + ((i * 5 + salt) % 7)) }
            }
        } else {
            for centre in bursts where centre >= from - 1 && centre <= to {
                counts[min(n - 1, Int(centre / spanEnd * Double(n)))] += Float(9 + (Int(centre) + salt) % 5)
            }
        }
        let peak = counts.max() ?? 1
        return peak > 0 ? counts.map { ($0 / peak).squareRoot() } : counts
    }

    /// The twelve knobs at the playhead. Rolled back, more of them read differently from now.
    static func knobs(rolledBack: Double, onTangent: Bool) -> [RewindKnobValue] {
        let row: [(String, String, Double, String, String, String)] = [
            ("Y_LIFT", "Blacks", 0.46, "-8", "0", "-3"),
            ("Y_GAMMA", "Exposure", 0.62, "+0.90 EV", "+0.35 EV", "+0.55 EV"),
            ("Y_GAIN", "Whites", 0.55, "+10", "+2", "+6"),
            ("CONTRAST", "Contrast", 0.68, "+36", "+11", "+24"),
            ("PIVOT", "Clarity", 0.52, "+4", "0", "+8"),
            ("MID_DETAIL", "Texture", 0.58, "+16", "+3", "+10"),
            ("COL_BOOST", "Vibrance", 0.71, "+42", "+9", "+30"),
            ("SHAD", "Shadows", 0.44, "-12", "-4", "-9"),
            ("HI_LIGHT", "Highs", 0.39, "-22", "-7", "-15"),
            ("SAT", "Sat", 0.5, "0", "0", "+4"),
            ("HUE", "Temp", 0.13, "8200 K", "5650 K", "6400 K"),
            ("LUM_MIX", "Blending", 0.5, "0", "0", "0")
        ]
        return row.enumerated().map { index, entry in
            let (control, label, value, now, past, tangent) = entry
            let changed = Double(index) / 12.0 < rolledBack
            let display = onTangent ? tangent : (changed ? past : now)
            return RewindKnobValue(control: control, label: label,
                                   value: changed ? 0.5 + (value - 0.5) * 0.3 : value,
                                   display: display, isChanged: changed || onTangent && index % 3 == 1)
        }
    }
}
