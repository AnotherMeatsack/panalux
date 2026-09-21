import Foundation
import Combine

/// Manages physical lighting reactions during Rewind mode.
///
/// Features:
/// 1. Direct, tactile 1-to-1 wheel tick correlation: slow turns advance keys one-by-one;
///    fast turns accelerate lighting proportionally.
/// 2. Alternates and flickers between Red & White (Bypass, Disable) and Green & White
///    (Offset, Shift Up, Shift Down, Play Still, Wipe Still, H/Lite, Viewer, Cursor) plus transport keys.
/// 3. Shift Up (Green) prominently blinks and flickers in direct synchronization with reverse rotation.
/// 4. Settle timeout restores quiet resting lighting when rotation ceases, with zero polling timers
///    and zero HID writes while at rest so button releases are never swallowed or delayed.
public final class RewindLEDAnimator {
    public static let shared = RewindLEDAnimator()
    
    private var isAnimating = false
    private var stepIndex: Int = 0
    private var deltaAccumulator: Double = 0
    private var lastWriteTime: Date = .distantPast
    private var settleWorkItem: DispatchWorkItem?
    
    // 30ms rate limit prevents saturating USB HID bus on high-velocity spins
    private let minWriteInterval: TimeInterval = 0.030
    // 2.0 raw delta units per discrete step produces crisp, 1-to-1 tactile detent stepping
    private let stepThreshold: Double = 2.0

    public init() {}

    /// Called by StudioEngine on wheel/ring rotation in driveRewind
    public func noteWheelDelta(command: String, deltaUnits: Double) {
        guard RewindEngine.shared.isRewinding, isAnimating else { return }
        guard AppSettings.shared.rewindReactiveLighting else { return }
        
        deltaAccumulator += deltaUnits
        let steps = Int(deltaAccumulator / stepThreshold)
        guard steps != 0 else { return }
        deltaAccumulator -= Double(steps) * stepThreshold
        stepIndex &+= steps
        
        let now = Date()
        guard now.timeIntervalSince(lastWriteTime) >= minWriteInterval else { return }
        lastWriteTime = now
        
        applyStepLighting(isReverse: deltaUnits < 0)
        
        // Settle cleanly to resting state 200ms after the wheel stops turning
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settleToRest()
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
    }
    
    public func start() {
        guard !isAnimating else { return }
        isAnimating = true
        stepIndex = 0
        deltaAccumulator = 0
        lastWriteTime = .distantPast
        settleWorkItem?.cancel()
        settleWorkItem = nil
        
        // Apply resting rewind state once on entry (no background timer)
        applyRestingLighting()
    }
    
    public func stop() {
        isAnimating = false
        settleWorkItem?.cancel()
        settleWorkItem = nil
        stepIndex = 0
        deltaAccumulator = 0
        
        // Cleanly restore standard profile lighting
        StudioEngine.shared.updateLEDs()
    }
    
    private func applyStepLighting(isReverse: Bool) {
        var whiteBits = Set<Int>()
        var colorBits = Set<Int>()
        let phase = abs(stepIndex) % 2
        
        // UNDO is held to rewind: keep it solidly illuminated
        if let undoBit = HardwareMap.shared.buttonBit(forControl: "UNDO") {
            whiteBits.insert(undoBit)
        }
        
        // Transport keys correlate with scrub direction
        if isReverse {
            if let playRevBit = HardwareMap.shared.buttonBit(forControl: "PLAY_REV") {
                whiteBits.insert(playRevBit)
            }
        } else {
            if let playBit = HardwareMap.shared.buttonBit(forControl: "PLAY") {
                whiteBits.insert(playBit)
            }
        }
        if phase == 0, let stopBit = HardwareMap.shared.buttonBit(forControl: "STOP") {
            whiteBits.insert(stopBit)
        }
        
        // Interlaced alternation across all dual-color keys:
        // Group A: Bypass, Offset, Play Still, H/Lite, Cursor
        // Group B: Disable, Shift Down, Wipe Still, Viewer
        if phase == 0 {
            // Group A in COLOR, Group B in WHITE
            colorBits.insert(PanelColorLED.bypassRed.rawValue)
            colorBits.insert(PanelColorLED.offsetGreen.rawValue)
            colorBits.insert(PanelColorLED.playStillGreen.rawValue)
            colorBits.insert(PanelColorLED.hliteGreen.rawValue)
            colorBits.insert(PanelColorLED.cursorGreen.rawValue)
            
            if let b = HardwareMap.shared.buttonBit(forControl: "DISABLE") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "CORNER_LOWER_RIGHT") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "WIPE_STILL") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "VIEWER") { whiteBits.insert(b) }
        } else {
            // Group A in WHITE, Group B in COLOR
            if let b = HardwareMap.shared.buttonBit(forControl: "BYPASS") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "OFFSET") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "PLAY_STILL") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "H/LITE") { whiteBits.insert(b) }
            if let b = HardwareMap.shared.buttonBit(forControl: "CURSOR") { whiteBits.insert(b) }
            
            colorBits.insert(PanelColorLED.disableRed.rawValue)
            colorBits.insert(PanelColorLED.shiftDownGreen.rawValue)
            colorBits.insert(PanelColorLED.wipeStillGreen.rawValue)
            colorBits.insert(PanelColorLED.viewerGreen.rawValue)
        }
        
        // Shift Up (Green): Correlates with reverse rotation ticks
        if isReverse {
            if phase == 0 {
                colorBits.insert(PanelColorLED.shiftUpGreen.rawValue)
            } else if let shiftBit = HardwareMap.shared.buttonBit(forControl: "SHIFT") {
                whiteBits.insert(shiftBit)
            }
        } else {
            if phase == 1 {
                colorBits.insert(PanelColorLED.shiftUpGreen.rawValue)
            } else if let shiftBit = HardwareMap.shared.buttonBit(forControl: "SHIFT") {
                whiteBits.insert(shiftBit)
            }
        }
        
        PanelManager.shared.setDualLEDs(whiteBits: whiteBits, colorBits: colorBits)
    }
    
    private func settleToRest() {
        guard RewindEngine.shared.isRewinding, isAnimating else { return }
        deltaAccumulator = 0
        applyRestingLighting()
    }
    
    private func applyRestingLighting() {
        var whiteBits = Set<Int>()
        var colorBits = Set<Int>()
        
        if let undoBit = HardwareMap.shared.buttonBit(forControl: "UNDO") {
            whiteBits.insert(undoBit)
        }
        if let stopBit = HardwareMap.shared.buttonBit(forControl: "STOP") {
            whiteBits.insert(stopBit)
        }
        
        // Maintain semantic Bypass view state at rest
        if StudioEngine.shared.isBeforeViewActive {
            colorBits.insert(PanelColorLED.bypassRed.rawValue)
        } else if let bypassBit = HardwareMap.shared.buttonBit(forControl: "BYPASS") {
            whiteBits.insert(bypassBit)
        }
        
        PanelManager.shared.setDualLEDs(whiteBits: whiteBits, colorBits: colorBits)
    }
}
