import Foundation
import Combine

/// Animates radiant gradient light waves that ripple outward from physical trackballs
/// in the exact direction of ball motion across the Micro Color Panel.
public final class TrackballLightAnimator {
    public static let shared = TrackballLightAnimator()
    
    // Normalized physical positions of the three trackballs on the panel:
    // X: 0.0 (left) to 1.0 (right), Y: 0.0 (bottom) to 1.0 (top)
    public enum TrackballOrigin {
        case lift   // Left ball
        case gamma  // Center ball
        case gain   // Right ball
        
        var position: (x: Double, y: Double) {
            switch self {
            case .lift:  return (0.271, 0.31)
            case .gamma: return (0.500, 0.31)
            case .gain:  return (0.729, 0.31)
            }
        }
    }
    
    // Normalized coordinates for physical buttons & top knobs
    private struct ControlPoint {
        let bit: Int
        let x: Double
        let y: Double
    }
    
    private var controlPoints: [ControlPoint] = []
    public private(set) var isAnimating = false
    private var lastWriteTime: Date = .distantPast
    private var tickWorkItem: DispatchWorkItem?
    private var activeOrigin: TrackballOrigin = .gamma
    private var originPoint: (x: Double, y: Double) = (0.5, 0.35)
    /// nil spreads the wave in every direction below the origin (knobs); a vector limits it to a forward arc (balls).
    private var activeDirection: (dx: Double, dy: Double)? = (0, 1)
    private var currentVector: (dx: Double, dy: Double) = (0, 0)
    private var maxReach: Double = 1.1
    private var waveReach: Double = 0.0   // Radius of the wavefront
    private var waveEnergy: Double = 0.0  // Brightness of the wave, 0…1
    private var lastInput: Date = .distantPast
    private var waveKey: String = ""
    /// How thick the travelling ring of light is.
    static let ringBand = 0.17
    
    public init() {
        buildControlPoints()
    }
    
    /// Key centres come from the real panel drawing so a wave crosses the keys that are actually beside the knob.
    /// Coordinates are 0…1 with y pointing up, like the origins above.
    private func buildControlPoints() {
        var points: [ControlPoint] = []
        if let svg = AppResources.string("micro-color-panel", "svg"),
           let regex = try? NSRegularExpression(pattern: #"<g id="(button_[a-z_0-9]+)"[^>]*>.*?<rect[^>]*?x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)""#,
                                                options: [.dotMatchesLineSeparators]) {
            let ns = svg as NSString
            for m in regex.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
                let id = ns.substring(with: m.range(at: 1))
                guard let name = PanelControlMapping.svgToProfile[id],
                      let bit = HardwareMap.shared.buttonBit(forControl: name),
                      let x = Double(ns.substring(with: m.range(at: 2))), let y = Double(ns.substring(with: m.range(at: 3))),
                      let w = Double(ns.substring(with: m.range(at: 4))), let h = Double(ns.substring(with: m.range(at: 5))) else { continue }
                points.append(ControlPoint(bit: bit, x: (x + w / 2) / 1080, y: 1 - (y + h / 2) / 552))
            }
        }
        self.controlPoints = points
    }

    public func noteMotion(ballName: String, axis: String, delta: Double) {
        guard !RewindEngine.shared.isRewinding else { return }
        let origin: TrackballOrigin
        if ballName.contains("LIFT") { origin = .lift }
        else if ballName.contains("GAIN") { origin = .gain }
        else { origin = .gamma }
        activeOrigin = origin

        if axis == "X" {
            currentVector.dx = currentVector.dx * 0.5 + delta * 1.5
        } else {
            currentVector.dy = currentVector.dy * 0.5 + delta * 1.5
        }
        let speed = sqrt(currentVector.dx * currentVector.dx + currentVector.dy * currentVector.dy)
        var direction = activeDirection ?? (0, 1)
        if speed > 0.005 { direction = (currentVector.dx / speed, currentVector.dy / speed) }
        startWave(key: "ball-\(ballName)", origin: origin.position, direction: direction, maxReach: 1.1)
    }

    /// A knob turned. The wave spreads from the knob's spot on the top row across the keys nearest it,
    /// so Y Lift reaches the left-hand keys and Y Gamma the centre ones.
    public func noteKnob(_ name: String) {
        guard !RewindEngine.shared.isRewinding, AppSettings.shared.knobRadiantLighting,
              let index = PanelLayout.knobs.firstIndex(of: name), index < PanelStage.knobX.count else { return }
        let x = Double(PanelStage.knobX[index]) / 1080.0
        startWave(key: "knob-\(name)", origin: (x, Self.knobRowY), direction: nil, maxReach: Self.knobReach(x: x))
    }

    static let knobRowY = 1 - 125.0 / 552.0
    /// Sideways distance counts fully and vertical only a third, so a knob's wave runs down its own column of keys.
    static func distance(from o: (x: Double, y: Double), to x: Double, _ y: Double) -> Double {
        hypot(x - o.x, (y - o.y) * 0.35)
    }
    /// Knobs at the outer edges reach a short way; those toward the middle have neighbours on both sides.
    static func knobReach(x: Double) -> Double { 0.18 + 0.14 * max(0, 1 - abs(x - 0.5) / 0.44) }

    /// Every control a knob's wave can ever reach, for tests and the guide.
    func controlsReached(byKnob name: String) -> Set<Int> {
        guard let index = PanelLayout.knobs.firstIndex(of: name), index < PanelStage.knobX.count else { return [] }
        let x = Double(PanelStage.knobX[index]) / 1080.0
        return Set(controlPoints.filter { Self.distance(from: (x, Self.knobRowY), to: $0.x, $0.y) <= Self.knobReach(x: x) }.map(\.bit))
    }

    private func startWave(key: String, origin: (x: Double, y: Double), direction: (dx: Double, dy: Double)?, maxReach: Double) {
        lastInput = Date()
        if key != waveKey {
            waveKey = key
            waveReach = 0
        }
        originPoint = origin
        activeDirection = direction
        self.maxReach = maxReach
        waveEnergy = 1.0
        if !isAnimating {
            isAnimating = true
            waveReach = 0
            applyWave()
            scheduleTick()
        }
    }

    private func scheduleTick() {
        tickWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tick() }
        tickWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
    }

    /// The ring keeps travelling outward while you keep turning, then lets the last one run out and fade.
    private func tick() {
        let turning = Date().timeIntervalSince(lastInput) < 0.25
        waveReach += 0.05
        if !turning { waveEnergy *= 0.9 }
        if waveReach > maxReach + Self.ringBand {
            if turning {
                waveReach = 0
            } else {
                finish()
                return
            }
        }
        if waveEnergy < 0.12 { finish(); return }
        applyWave()
        scheduleTick()
    }

    private func finish() {
        isAnimating = false
        waveReach = 0
        waveEnergy = 0
        waveKey = ""
        tickWorkItem = nil
        StudioEngine.shared.updateLeds()
    }

    /// Which controls the ring is passing over right now.
    static func ringBits(points: [(bit: Int, x: Double, y: Double)], origin: (x: Double, y: Double),
                         direction: (dx: Double, dy: Double)?, reach: Double, maxReach: Double) -> Set<Int> {
        var lit = Set<Int>()
        for cp in points {
            let dx = cp.x - origin.x, dy = cp.y - origin.y
            let dist = direction == nil ? distance(from: origin, to: cp.x, cp.y) : sqrt(dx * dx + dy * dy)
            guard dist > 0.005, dist <= maxReach else { continue }
            if let d = direction {
                guard (dx * d.dx + dy * d.dy) / dist > 0.15 else { continue }
            }
            if dist <= reach && dist >= reach - ringBand { lit.insert(cp.bit) }
        }
        return lit
    }

    private func applyWave() {
        guard !StudioEngine.shared.ledsOwnedByShow, !RewindEngine.shared.isRewinding else { return }
        let points = controlPoints.map { (bit: $0.bit, x: $0.x, y: $0.y) }
        let ring = Self.ringBits(points: points, origin: originPoint, direction: activeDirection,
                                 reach: waveReach, maxReach: maxReach)
        let baseWhite = StudioEngine.shared.currentBaseWhiteBits()
        let currentColor = StudioEngine.shared.currentSemanticColorBits()

        // With every key already lit the ring would be invisible, so it passes through as a dark band instead.
        var combinedWhite = AppSettings.shared.ledMode == "all" ? baseWhite.subtracting(ring) : baseWhite.union(ring)
        let colorKeyBits: [PanelColorLED: Int] = [
            .bypassRed: 20, .disableRed: 21, .offsetGreen: 13, .shiftUpGreen: 24, .shiftDownGreen: 25,
            .playStillGreen: 26, .wipeStillGreen: 27, .hliteGreen: 29, .viewerGreen: 30, .cursorGreen: 31
        ]
        for (colorLed, whiteBit) in colorKeyBits where currentColor.contains(colorLed.rawValue) {
            combinedWhite.remove(whiteBit)
        }
        PanelManager.shared.setDualLEDs(whiteBits: combinedWhite, colorBits: currentColor)
    }
}
