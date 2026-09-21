import Foundation

/// What the panel's own lights do in each intro scene, timed to what the screen is showing.
/// Pure and deterministic so it can be tested; the director just sends the result to the panel.
enum IntroLEDChoreography {
    typealias Frame = (white: Set<Int>, color: Set<Int>)

    /// Keys that have a red or green light of their own, by their white-light bit.
    static let colorChannelForKey: [Int: PanelColorLED] = [
        20: .bypassRed, 21: .disableRed, 13: .offsetGreen, 24: .shiftUpGreen, 25: .shiftDownGreen,
        26: .playStillGreen, 27: .wipeStillGreen, 29: .hliteGreen, 30: .viewerGreen, 31: .cursorGreen
    ]

    private static var points: [(bit: Int, x: Double, y: Double)] { TrackballLightAnimator.shared.keyPoints }

    /// Back and forth, 0…1…0.
    private static func pingPong(_ t: Double) -> Double {
        let f = t - t.rounded(.down)
        let u = Int(t.rounded(.down)) % 2 == 0 ? f : 1 - f
        return u * u * (3 - 2 * u)
    }

    /// Light a key: in its colour if it has one and colour is wanted, otherwise white.
    private static func add(_ bit: Int, colored: Bool, to frame: inout Frame) {
        if colored, let ch = colorChannelForKey[bit] { frame.color.insert(ch.rawValue) } else { frame.white.insert(bit) }
    }

    static func frame(scene: Int, t: TimeInterval) -> Frame {
        var f: Frame = ([], [])
        switch scene {
        case 0:
            // A band of light dances left and right across the whole panel, rows out of step so it ripples.
            // Colours join in when it has crossed the room a couple of times, then it all flashes.
            let pos = -0.1 + 1.2 * pingPong(t * 0.42)
            let wide = 0.13 + 0.03 * sin(t * 3)
            for k in points {
                let ripple = 0.06 * sin(k.y * 9 + t * 5)
                if abs(k.x - (pos + ripple)) < wide { add(k.bit, colored: t > 2.2, to: &f) }
            }
            if t > 6.0 {
                let on = Int(t * 5) % 2 == 0
                f = ([], [])
                if on { for k in points { add(k.bit, colored: true, to: &f) } }
            }

        case 1:
            // The same wave the screen draws across the panel, at the same speed, in the same place.
            let x = ((t * 260).truncatingRemainder(dividingBy: 1400) - 200) / 1080
            for k in points where abs(k.x - x - 0.1) < 0.12 { add(k.bit, colored: true, to: &f) }

        case 2:
            // One, two, three; one, two, three: the three banks of knobs taking turns, like a turning knob.
            let step = Int(t * 4.5) % 3
            for k in points where Int(min(2, max(0, (k.x - 0.0001) / (1.0 / 3.0)))) == step {
                add(k.bit, colored: false, to: &f)
            }

        case 3:
            // Each trackball throws rings across the keys around it, and they come back again.
            let origins: [(x: Double, y: Double)] = [(0.271, 0.31), (0.5, 0.31), (0.729, 0.31)]
            let ball = Int(t / 1.6) % 3
            let reach = 0.62 * pingPong(t * 0.9)
            for k in points {
                let d = hypot(k.x - origins[ball].x, (k.y - origins[ball].y) * 0.8)
                if abs(d - reach) < 0.11 || d < 0.05 { add(k.bit, colored: Int(t * 2) % 2 == 0, to: &f) }
            }

        case 4:
            // Holding a key: that key stays lit, and the row of keys under the knobs shows the change.
            let index = t < 1.8 ? 0 : min(4, Int((t - 1.8) / 3.2))
            let held: [Int?] = [nil, 24, 22, 30, 31]
            let topRow = points.filter { $0.y > 0.55 }.sorted { $0.x < $1.x }
            if let key = held[index] {
                add(key, colored: true, to: &f)
                let lit = Int(t * 7) % max(1, topRow.count)
                for (i, k) in topRow.enumerated() where k.bit != key && (i == lit || i == (lit + 1) % topRow.count) {
                    add(k.bit, colored: false, to: &f)
                }
            } else {
                for k in points { f.white.insert(k.bit) }
            }

        case 5:
            // Hold User (User lights), let go (dark), tap Cursor (Cursor stays green).
            if t > 1.2 && t < 5.0 {
                f.white.insert(22)
                let topRow = points.filter { $0.y > 0.55 }.sorted { $0.x < $1.x }
                let lit = Int(t * 7) % max(1, topRow.count)
                for (i, k) in topRow.enumerated() where i == lit && k.bit != 22 { f.white.insert(k.bit) }
            } else if t > 8.0 {
                f.color.insert(PanelColorLED.cursorGreen.rawValue)
                if t < 8.6 { f.white.formUnion([32, 36]) }
            }

        case 6:
            // Hold Add Node: it lights, the mask keys around it play, Cursor stays green.
            if t > 0.9 {
                f.white.insert(36)
                f.color.insert(PanelColorLED.cursorGreen.rawValue)
                let ring: [Int] = [37, 32, 38, 29]
                let lit = Int(t * 4) % ring.count
                for (i, bit) in ring.enumerated() where i == lit || i == (lit + 1) % ring.count { add(bit, colored: true, to: &f) }
            } else {
                f.color.insert(PanelColorLED.cursorGreen.rawValue)
            }

        case 7:
            // Hold Undo: Undo stays lit, Shift Up blinks with the reverse wheel, transport keys follow playback.
            f.white.insert(16)
            if Int(t * 3.5) % 2 == 0 { f.color.insert(PanelColorLED.shiftUpGreen.rawValue) }
            f.white.insert([49, 51, 50][Int(t) % 3])
            let trail = points.filter { $0.y < 0.5 }.sorted { $0.x < $1.x }
            if !trail.isEmpty { f.white.insert(trail[Int(t * 5) % trail.count].bit) }

        case 8:
            f.white = [16, 17, 51]

        default:
            // Now try your panel: the same left-to-right chase the drawing runs along the knobs,
            // lighting the keys in each knob's column.
            let columns = PanelStage.knobX.map { Double($0) / 1080.0 }
            let lit = Int(t * 6) % columns.count
            for k in points where abs(k.x - columns[lit]) < 0.055 { add(k.bit, colored: true, to: &f) }
        }
        return f
    }
}
