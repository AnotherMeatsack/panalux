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
            case .lift:  return (0.20, 0.35)
            case .gamma: return (0.50, 0.35)
            case .gain:  return (0.80, 0.35)
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
    private var decayWorkItem: DispatchWorkItem?
    private var activeOrigin: TrackballOrigin = .gamma
    private var activeDirection: (dx: Double, dy: Double) = (0, 1)
    private var currentVector: (dx: Double, dy: Double) = (0, 0)
    private var waveReach: Double = 0.0   // Current radius of wavefront (0.0 to 1.1)
    private var waveEnergy: Double = 0.0  // Wave intensity (0.0 to 1.0)
    
    public init() {
        buildControlPoints()
    }
    
    private func buildControlPoints() {
        var points: [ControlPoint] = []
        // 12 Top Knobs (Y ≈ 0.90, X from 0.08 to 0.92)
        for (i, knob) in PanelLayout.knobs.enumerated() {
            if let bit = HardwareMap.shared.buttonBit(forControl: "PRESS_" + knob) {
                let x = 0.08 + (Double(i) / 11.0) * 0.84
                points.append(ControlPoint(bit: bit, x: x, y: 0.90))
            }
        }
        // Left button cluster (Lift region)
        let leftButtons: [(String, Double, Double)] = [
            ("AUTO_COLOR", 0.10, 0.65), ("OFFSET", 0.20, 0.65), ("BYPASS", 0.30, 0.65),
            ("USER", 0.10, 0.50), ("LOOP", 0.20, 0.50), ("DISABLE", 0.30, 0.50),
            ("COPY", 0.10, 0.18), ("PASTE", 0.20, 0.18), ("SHIFT", 0.30, 0.18)
        ]
        for (name, x, y) in leftButtons {
            if let bit = HardwareMap.shared.buttonBit(forControl: name) {
                points.append(ControlPoint(bit: bit, x: x, y: y))
            }
        }
        // Center button cluster (Gamma region)
        let centerButtons: [(String, Double, Double)] = [
            ("PLAY_STILL", 0.42, 0.65), ("WIPE_STILL", 0.50, 0.65), ("GRAB_STILL", 0.58, 0.65),
            ("RESET_LIFT", 0.42, 0.50), ("RESET_GAMMA", 0.50, 0.50), ("RESET_GAIN", 0.58, 0.50),
            ("UNDO", 0.42, 0.18), ("REDO", 0.50, 0.18), ("RESET_ALL", 0.58, 0.18)
        ]
        for (name, x, y) in centerButtons {
            if let bit = HardwareMap.shared.buttonBit(forControl: name) {
                points.append(ControlPoint(bit: bit, x: x, y: y))
            }
        }
        // Right button cluster (Gain region & Transport)
        let rightButtons: [(String, Double, Double)] = [
            ("H/LITE", 0.72, 0.65), ("VIEWER", 0.80, 0.65), ("CURSOR", 0.88, 0.65),
            ("SELECT", 0.72, 0.50), ("ADD_NODE", 0.80, 0.50), ("ADD_WINDOW", 0.88, 0.50),
            ("PLAY_REV", 0.72, 0.18), ("PLAY", 0.80, 0.18), ("STOP", 0.88, 0.18),
            ("DELETE", 0.95, 0.35), ("CORNER_LOWER_RIGHT", 0.95, 0.18)
        ]
        for (name, x, y) in rightButtons {
            if let bit = HardwareMap.shared.buttonBit(forControl: name) {
                points.append(ControlPoint(bit: bit, x: x, y: y))
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
        
        if origin != activeOrigin {
            activeOrigin = origin
            waveReach = min(waveReach, 0.25)
        }
        
        if axis == "X" {
            currentVector.dx = currentVector.dx * 0.5 + delta * 1.5
        } else {
            currentVector.dy = currentVector.dy * 0.5 + delta * 1.5
        }
        
        let speed = sqrt(currentVector.dx * currentVector.dx + currentVector.dy * currentVector.dy)
        if speed > 0.005 {
            activeDirection = (currentVector.dx / speed, currentVector.dy / speed)
        }
        
        // Gradual outward growth increment as the ball moves
        let impulse = abs(delta)
        waveReach = min(1.1, waveReach + impulse * 0.035 + 0.02)
        waveEnergy = min(1.0, waveEnergy + impulse * 0.06 + 0.03)
        
        let now = Date()
        guard now.timeIntervalSince(lastWriteTime) >= 0.030 else { return }
        lastWriteTime = now
        
        applyWave()
        scheduleDecay()
    }
    
    private func scheduleDecay() {
        decayWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stepDecay()
        }
        decayWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
    }
    
    private func stepDecay() {
        // Multi-stage gradual receding: wave gently shrinks and fades without an abrupt stop
        waveReach = max(0, waveReach - 0.065)
        waveEnergy *= 0.85
        currentVector = (currentVector.dx * 0.75, currentVector.dy * 0.75)
        
        if waveReach <= 0.05 || waveEnergy <= 0.05 {
            isAnimating = false
            waveReach = 0
            waveEnergy = 0
            decayWorkItem = nil
            StudioEngine.shared.updateLeds()
        } else {
            applyWave()
            scheduleDecay()
        }
    }
    
    private func applyWave() {
        let (ox, oy) = activeOrigin.position
        let (dirX, dirY) = activeDirection
        
        var litBits = Set<Int>()
        for cp in controlPoints {
            let dx = cp.x - ox
            let dy = cp.y - oy
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 0.01 else { continue }
            
            // Dot product evaluates directional alignment:
            let dot = (dx * dirX + dy * dirY) / dist
            
            // Only light controls in the forward arc of the push and within current wave reach
            if dot > 0.15 && dist <= waveReach {
                let distFraction = dist / max(0.1, waveReach)
                let radialScore = dot * (1.0 - distFraction * 0.65) * waveEnergy
                if radialScore > 0.10 {
                    litBits.insert(cp.bit)
                }
            }
        }
        
        isAnimating = true
        let baseWhite = StudioEngine.shared.currentBaseWhiteBits()
        let currentColor = StudioEngine.shared.currentSemanticColorBits()
        
        var combinedWhite = baseWhite.union(litBits)
        // Ensure active color channels aren't washed out by white bits
        let colorKeyBits: [PanelColorLED: Int] = [
            .bypassRed: 20,
            .disableRed: 21,
            .offsetGreen: 13,
            .shiftUpGreen: 24,
            .shiftDownGreen: 25,
            .playStillGreen: 26,
            .wipeStillGreen: 27,
            .hliteGreen: 29,
            .viewerGreen: 30,
            .cursorGreen: 31
        ]
        for (colorLed, whiteBit) in colorKeyBits {
            if currentColor.contains(colorLed.rawValue) {
                combinedWhite.remove(whiteBit)
            }
        }
        
        PanelManager.shared.setDualLEDs(whiteBits: combinedWhite, colorBits: currentColor)
    }
}
