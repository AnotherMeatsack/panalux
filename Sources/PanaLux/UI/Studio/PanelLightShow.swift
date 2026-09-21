import Foundation
import Combine

public struct LightShowFrame: Codable, Equatable, Sendable {
    public let active: Bool
    public let whiteControls: [String]
    public let colorControls: [String: String] // controlName -> "red" or "green"
    public let title: String
    public let subtitle: String
    
    public static let inactive = LightShowFrame(active: false, whiteControls: [], colorControls: [:], title: "", subtitle: "")
}

/// Orchestrates the startup / celebratory light show across the physical Micro Color Panel
/// and publishes synchronized frames for the on-screen interactive SVG panel diagram:
/// Phase 1 (0.0s – 2.4s): Dancing gradient wave across knobs and button banks.
/// Phase 2 (2.4s – 4.2s): Line up organized (12 knobs -> 2 reds -> 8 greens -> transport).
/// Phase 3 (4.2s – 5.4s): Show ALL ON (all 40 white keys + all 10 color keys).
/// Phase 4 (5.4s – 6.6s): Flick/strobe a couple times (OFF -> ON -> OFF -> ON -> OFF -> ON).
/// Phase 5 (6.6s – end): Turn ALL OFF, followed by clean idle profile restoration.
public final class PanelLightShow: ObservableObject {
    public static let shared = PanelLightShow()
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentFrame: LightShowFrame = .inactive
    
    private var timer: Timer?
    private var startTime: Date = .distantPast
    private var initialBrightness: Int = 100
    private var completionCallback: (() -> Void)?
    private var isBurst = false
    private var lastBurst: Date = .distantPast
    private static let burstDuration: TimeInterval = 1.3
    
    public init() {}

    /// Plugging the panel in: one quick burst of light and color, then back to normal.
    public func startBurst() {
        guard !isRunning, !IntroLEDDirector.shared.isActive, !GuideController.shared.showIntro,
              Date().timeIntervalSince(lastBurst) > 4 else { return }
        lastBurst = Date()
        isBurst = true
        start()
    }
    
    public func start(completion: (() -> Void)? = nil) {
        guard !isRunning && !IntroLEDDirector.shared.isActive else { return }
        if !isBurst { lastBurst = Date() }
        isRunning = true
        startTime = Date()
        initialBrightness = Int(AppSettings.shared.backlightBrightness)
        completionCallback = completion
        
        // Suppress regular layer LED updates during light show
        StudioEngine.shared.isLightShowActive = true
        
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.tick(timer: timer)
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isBurst = false
        timer?.invalidate()
        timer = nil
        currentFrame = .inactive
        
        // Turn all color channels completely off at the hardware level
        PanelManager.shared.setColorLEDs(activeBits: [])
        
        // Restore initial brightness and normal profile LED state
        PanelManager.shared.setBrightness(level: initialBrightness)
        StudioEngine.shared.isLightShowActive = false
        StudioEngine.shared.updateLEDs()
        
        let cb = completionCallback
        completionCallback = nil
        cb?()
    }
    
    private func tick(timer: Timer) {
        let elapsed = Date().timeIntervalSince(startTime)
        if isBurst { tickBurst(elapsed); return }
        let totalDuration: TimeInterval = 6.8
        
        if elapsed >= totalDuration {
            stop()
            return
        }
        
        var whiteBits = Set<Int>()
        var colorBits = Set<Int>()
        var whiteNames: [String] = []
        var colorDict: [String: String] = [:]
        var title = ""
        var subtitle = ""
        
        // MARK: - Phase 1: Dancing Gradient Wave Across the Panel (0.0s – 2.4s)
        if elapsed < 2.4 {
            title = "PanaLux 1.2.4"
            subtitle = "Micro Color Panel Gradient Awakening"
            
            // Sweep position across panel: 0.0 -> 1.0 -> 0.0
            let tNorm = elapsed / 2.4
            let sweepProgress = sin(tNorm * .pi)
            
            // Knobs sweep across top (0..11)
            let knobCount = PanelLayout.knobs.count
            let centerKnob = Double(knobCount - 1) * sweepProgress
            for (idx, knob) in PanelLayout.knobs.enumerated() {
                let dist = abs(Double(idx) - centerKnob)
                if dist <= 1.5 {
                    if let b = HardwareMap.shared.buttonBit(forControl: "PRESS_" + knob) {
                        whiteBits.insert(b)
                        whiteNames.append("PRESS_" + knob)
                    }
                }
            }
            
            // Lower button banks dance in gradient sequence
            if sweepProgress < 0.35 {
                // Left bank dancing
                colorBits.insert(PanelColorLED.bypassRed.rawValue)
                colorBits.insert(PanelColorLED.offsetGreen.rawValue)
                colorDict["BYPASS"] = "red"
                colorDict["OFFSET"] = "green"
                if let b = HardwareMap.shared.buttonBit(forControl: "DISABLE") {
                    whiteBits.insert(b)
                    whiteNames.append("DISABLE")
                }
            } else if sweepProgress < 0.70 {
                // Center bank dancing
                colorBits.insert(PanelColorLED.shiftUpGreen.rawValue)
                colorBits.insert(PanelColorLED.shiftDownGreen.rawValue)
                colorBits.insert(PanelColorLED.playStillGreen.rawValue)
                colorBits.insert(PanelColorLED.wipeStillGreen.rawValue)
                colorDict["SHIFT"] = "green"
                colorDict["CORNER_LOWER_RIGHT"] = "green"
                colorDict["PLAY_STILL"] = "green"
                colorDict["WIPE_STILL"] = "green"
                if let b = HardwareMap.shared.buttonBit(forControl: "UNDO") {
                    whiteBits.insert(b)
                    whiteNames.append("UNDO")
                }
                if let b = HardwareMap.shared.buttonBit(forControl: "STOP") {
                    whiteBits.insert(b)
                    whiteNames.append("STOP")
                }
            } else {
                // Right bank dancing
                colorBits.insert(PanelColorLED.hliteGreen.rawValue)
                colorBits.insert(PanelColorLED.viewerGreen.rawValue)
                colorBits.insert(PanelColorLED.cursorGreen.rawValue)
                colorDict["H/LITE"] = "green"
                colorDict["VIEWER"] = "green"
                colorDict["CURSOR"] = "green"
                if let b = HardwareMap.shared.buttonBit(forControl: "AUTO_COLOR") {
                    whiteBits.insert(b)
                    whiteNames.append("AUTO_COLOR")
                }
                if let b = HardwareMap.shared.buttonBit(forControl: "PLAY") {
                    whiteBits.insert(b)
                    whiteNames.append("PLAY")
                }
            }
        }
        
        // MARK: - Phase 2: Line Up Organized (2.4s – 4.2s)
        else if elapsed < 4.2 {
            title = "Organized Architecture"
            let orgTime = elapsed - 2.4
            
            // Step A: Top 12 knobs line up
            for knob in PanelLayout.knobs {
                if let b = HardwareMap.shared.buttonBit(forControl: "PRESS_" + knob) {
                    whiteBits.insert(b)
                    whiteNames.append("PRESS_" + knob)
                }
            }
            subtitle = "12 Primary Knobs Aligned"
            
            // Step B (2.8s+): Red indicators ignite
            if orgTime >= 0.4 {
                colorBits.insert(PanelColorLED.bypassRed.rawValue)
                colorBits.insert(PanelColorLED.disableRed.rawValue)
                colorDict["BYPASS"] = "red"
                colorDict["DISABLE"] = "red"
                subtitle = "Red Indicators: Bypass & Disable"
            }
            
            // Step C (3.2s+): Green indicators ignite in organized symmetry
            if orgTime >= 0.8 {
                let greenChannels: [PanelColorLED] = [
                    .offsetGreen, .shiftUpGreen, .shiftDownGreen,
                    .playStillGreen, .wipeStillGreen, .hliteGreen, .viewerGreen, .cursorGreen
                ]
                for ch in greenChannels {
                    colorBits.insert(ch.rawValue)
                    colorDict[ch.controlName] = "green"
                }
                subtitle = "Green Indicators: Modes, Stills & Tools"
            }
            
            // Step D (3.7s+): Transport keys join
            if orgTime >= 1.3 {
                for name in ["UNDO", "REDO", "STOP", "PLAY_REV", "PLAY"] {
                    if let b = HardwareMap.shared.buttonBit(forControl: name) {
                        whiteBits.insert(b)
                        whiteNames.append(name)
                    }
                }
                subtitle = "Transport Controls Aligned"
            }
        }
        
        // MARK: - Phase 3: Show ALL ON (4.2s – 5.4s)
        else if elapsed < 5.4 {
            title = "Full Panel Illumination"
            subtitle = "40 Tactile Keys + 10 Dual-Color Indicators"
            
            // All 40 white keys ON
            for (bit, name) in HardwareMap.shared.buttonBitToControl {
                whiteBits.insert(bit)
                whiteNames.append(name)
            }
            
            // All 10 color channels ON
            for ch in PanelColorLED.allCases {
                colorBits.insert(ch.rawValue)
                colorDict[ch.controlName] = ch.isRed ? "red" : "green"
            }
        }
        
        // MARK: - Phase 4: Flick / Strobe a Couple Times (5.4s – 6.6s)
        else if elapsed < 6.6 {
            title = "Panel Calibrated"
            subtitle = "Ready to Grade"
            
            let flickTime = elapsed - 5.4
            // Strobe timing:
            // 0.00..0.20: OFF
            // 0.20..0.40: ON
            // 0.40..0.60: OFF
            // 0.60..0.80: ON
            // 0.80..0.95: OFF
            // 0.95..1.20: ON
            let isStrobeOn: Bool
            switch flickTime {
            case 0.00..<0.20: isStrobeOn = false
            case 0.20..<0.40: isStrobeOn = true
            case 0.40..<0.60: isStrobeOn = false
            case 0.60..<0.80: isStrobeOn = true
            case 0.80..<0.95: isStrobeOn = false
            default:          isStrobeOn = true
            }
            
            if isStrobeOn {
                for (bit, name) in HardwareMap.shared.buttonBitToControl {
                    whiteBits.insert(bit)
                    whiteNames.append(name)
                }
                for ch in PanelColorLED.allCases {
                    colorBits.insert(ch.rawValue)
                    colorDict[ch.controlName] = ch.isRed ? "red" : "green"
                }
            }
        }
        
        // MARK: - Phase 5: Turn ALL OFF (6.6s – end)
        else {
            title = "Panel Ready"
            subtitle = "All Indicators Resting"
            // Both whiteBits and colorBits are empty (all lights OFF)
        }
        
        PanelManager.shared.setDualLEDs(whiteBits: whiteBits, colorBits: colorBits)
        
        currentFrame = LightShowFrame(
            active: true,
            whiteControls: whiteNames,
            colorControls: colorDict,
            title: title,
            subtitle: subtitle
        )
    }

    /// An explosion from the center: everything flashes on, then the keys flicker out from the
    /// middle to the edges as the burst fades, and the normal lights come back.
    private func tickBurst(_ elapsed: TimeInterval) {
        guard elapsed < Self.burstDuration else { stop(); return }
        let n = elapsed / Self.burstDuration
        // Density of lit keys: full for the first instant, then decaying to nothing.
        let density = n < 0.12 ? 1.0 : pow(1 - (n - 0.12) / 0.88, 1.6)
        // The wavefront runs outward from the middle of the panel; keys behind it flicker.
        let front = min(1.0, n / 0.45)
        let bucket = Int(elapsed / 0.05)
        func lit(_ bit: Int) -> Bool {
            let dist = Double(bit % 13) / 13.0 * 0.5 + Double(bit % 5) / 5.0 * 0.5   // stable spread per key
            if dist > front { return false }
            var h = UInt64(truncatingIfNeeded: bit &* 73856093 ^ bucket &* 19349663)
            h = (h ^ (h >> 13)) &* 0x9E3779B97F4A7C15
            return Double(h % 1000) / 1000.0 < density
        }
        var whiteBits = Set<Int>(), colorBits = Set<Int>()
        var whiteNames: [String] = [], colorDict: [String: String] = [:]
        for (bit, name) in HardwareMap.shared.buttonBitToControl where lit(bit) {
            whiteBits.insert(bit); whiteNames.append(name)
        }
        for ch in PanelColorLED.allCases where lit(ch.rawValue + 1000) {
            colorBits.insert(ch.rawValue)
            colorDict[ch.controlName] = ch.isRed ? "red" : "green"
        }
        PanelManager.shared.setDualLEDs(whiteBits: whiteBits, colorBits: colorBits)
        currentFrame = LightShowFrame(active: true, whiteControls: whiteNames, colorControls: colorDict, title: "", subtitle: "")
    }
}
