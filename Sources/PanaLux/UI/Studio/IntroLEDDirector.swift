import Foundation
import Combine

/// Directs synchronized physical hardware LED lighting on the Micro Color Panel
/// during the keynote-style Intro sequence (`IntroShowView`).
/// Every scene's hardware illumination correlates directly to what is being taught on screen:
/// - Title: Opening illumination flourish across clusters and color channels.
/// - Panel Overview: Sweeps across the 3 physical button banks and color keys.
/// - Knobs: Illuminates the active knob reset and adjustment controls.
/// - Trackballs: Sweeps light waves across Lift, Gamma, and Gain clusters.
/// - Modes/Layers: Physically lights the exact modifier keys (H/LITE green, SHIFT green, USER, etc.).
/// - Hold vs. Toggle: Shows USER lighting while held, turning off upon release, and CURSOR staying GREEN upon tap!
/// - Mask Wheel: ADD_NODE and CURSOR green illuminate as mask creation is taught.
/// - Rewind+: UNDO illuminates, SHIFT blinks green in reverse correlation, and transport keys animate.
public final class IntroLEDDirector {
    public static let shared = IntroLEDDirector()
    
    public private(set) var isActive = false
    /// Active and still being updated. If the intro window vanished without saying so, this lapses.
    public var isLive: Bool { isActive && Date().timeIntervalSince(lastUpdate) < 6 }
    private var lastUpdate: Date = .distantPast
    private var lastScene: Int = -1
    
    private init() {}
    
    public func start() {
        isActive = true
        lastUpdate = Date()
        lastScene = -1
        StudioEngine.shared.isLightShowActive = true
    }
    
    public func stop() {
        guard isActive else { return }
        isActive = false
        lastScene = -1
        StudioEngine.shared.isLightShowActive = false
        PanelManager.shared.setColorLEDs(activeBits: [])
        StudioEngine.shared.updateLEDs()
    }
    
    public func update(scene: Int, t: TimeInterval) {
        guard isActive else { return }
        let now = Date()
        if scene == lastScene && now.timeIntervalSince(lastUpdate) < 0.030 {
            return
        }
        lastScene = scene
        lastUpdate = now
        
        var whiteBits = Set<Int>()
        var colorBits = Set<Int>()
        
        switch scene {
        case 0:
            // Scene 0: Title Scene ("PanaLux · One panel. Every job.") - 0..7.0s
            // Rhythmic flourish across clusters and colors
            let phase = t.truncatingRemainder(dividingBy: 2.4)
            if phase < 0.8 {
                whiteBits = [12, 13, 14, 15, 20, 21, 22, 23, 24] // Left cluster
            } else if phase < 1.6 {
                whiteBits = [16, 17, 19, 26, 27, 28, 33, 34, 35] // Center cluster
            } else {
                whiteBits = [29, 30, 31, 32, 36, 37, 49, 50, 51] // Right cluster
            }
            if t > 2.0 && t < 5.0 {
                // Synchronized color reveal
                colorBits = [
                    PanelColorLED.bypassRed.rawValue,
                    PanelColorLED.disableRed.rawValue,
                    PanelColorLED.offsetGreen.rawValue,
                    PanelColorLED.shiftUpGreen.rawValue,
                    PanelColorLED.playStillGreen.rawValue,
                    PanelColorLED.wipeStillGreen.rawValue,
                    PanelColorLED.cursorGreen.rawValue
                ]
            }
            
        case 1:
            // Scene 1: The Panel You Already Own ("Twelve knobs, three trackballs, forty keys...") - 0..8.0s
            if t < 2.5 {
                whiteBits = [12, 13, 14, 15, 20, 21, 22, 23, 24]
                colorBits = [PanelColorLED.offsetGreen.rawValue]
            } else if t < 5.0 {
                whiteBits = [16, 17, 19, 26, 27, 28, 33, 34, 35]
                colorBits = [PanelColorLED.playStillGreen.rawValue, PanelColorLED.wipeStillGreen.rawValue]
            } else {
                whiteBits = [29, 30, 31, 32, 36, 37, 49, 50, 51]
                colorBits = [PanelColorLED.cursorGreen.rawValue]
            }
            
        case 2:
            // Scene 2: Knobs Move Real Sliders ("Exposure, contrast, highlights...") - 0..8.0s
            whiteBits = [33, 34, 35, 16, 17]
            if Int(t * 3.5) % 2 == 0 {
                whiteBits.insert(34) // RESET_GAMMA pulses in sync with exposure slider
            }
            
        case 3:
            // Scene 3: Both Hands. Everything At Once (Three Trackballs / Color Wheels) - 0..9.5s
            if t < 3.2 {
                whiteBits = [12, 13, 14, 15, 20, 22, 23, 24] // Lift region
            } else if t < 6.4 {
                whiteBits = [16, 17, 19, 26, 27, 28, 33, 34, 35] // Gamma region
            } else {
                whiteBits = [29, 30, 31, 32, 36, 37, 49, 50, 51] // Gain region
            }
            
        case 4:
            // Scene 4: Hold A Key. Get A New Panel (5 modes walked through) - 0..18.0s
            // index = t < 1.8 ? 0 : min(modes.count - 1, Int((t - 1.8) / 3.2))
            if t < 1.8 {
                // Mode 0: Base -> clean base keys
                whiteBits = [12, 13, 14, 15, 16, 17, 18, 19, 26, 27, 28, 49, 50, 51]
            } else if t < 5.0 {
                // Mode 1: Color Mixer -> Hold Up Shift
                colorBits = [PanelColorLED.shiftUpGreen.rawValue]
                whiteBits = [12, 13, 14, 15, 20, 21, 22, 23]
            } else if t < 8.2 {
                // Mode 2: Upright & Transform -> Hold User
                whiteBits = [22, 12, 13, 14, 15, 23, 24]
            } else if t < 11.4 {
                // Mode 3: Crop & Straighten -> Hold Viewer
                colorBits = [PanelColorLED.viewerGreen.rawValue]
                whiteBits = [26, 27, 28, 33, 34, 35]
            } else {
                // Mode 4: Masks -> Tap Cursor
                colorBits = [PanelColorLED.cursorGreen.rawValue]
                whiteBits = [29, 30, 31, 32, 36, 37]
            }
            
        case 5:
            // Scene 5: Hold To Peek. Tap To Stay - 0..14.0s
            // 1.2–5.0s: User held -> USER white
            // 5.0–8.0s: released, back to Base -> OFF
            // 8.0s+: Cursor tapped -> CURSOR GREEN stays ON!
            if t > 1.2 && t < 5.0 {
                whiteBits = [22] // USER held
            } else if t > 8.0 {
                colorBits = [PanelColorLED.cursorGreen.rawValue] // CURSOR Green stays ON
            }
            
        case 6:
            // Scene 6: Hold Add Node. Pick Any Mask - 0..18.0s
            // ADD_NODE held (36), CURSOR in green (31)
            whiteBits = [36, 37, 32]
            colorBits = [PanelColorLED.cursorGreen.rawValue]
            
        case 7:
            // Scene 7: Hold Undo. Rewind+ - 0..36.0s
            whiteBits = [16] // UNDO held
            // Shift Up blinks green in direct correlation with reverse wheel ticks
            if Int(t * 3.5) % 2 == 0 {
                colorBits.insert(PanelColorLED.shiftUpGreen.rawValue)
            }
            // Transport keys animate with playback direction
            let cycle = Int(t) % 3
            if cycle == 0 { whiteBits.insert(49) } // PLAY_REV
            else if cycle == 1 { whiteBits.insert(51) } // STOP
            else { whiteBits.insert(50) } // PLAY
            
        case 8:
            // Scene 8: Safety & Escape Hatches - 0..9.0s
            // "Let go. Back to base." Clean base keys
            whiteBits = [16, 17, 51]
            
        default:
            // Scene 9: Finale & Hands-On Ready
            let tick = Int(t * 4) % 2
            if tick == 0 {
                whiteBits = [12, 13, 16, 17, 26, 27, 29, 30, 49, 50, 51]
            } else {
                whiteBits = [14, 15, 18, 19, 28, 31, 32, 36, 37]
            }
        }
        
        // Suppress white LED behind any active color LED so colors are 100% vibrant
        let colorToWhite: [PanelColorLED: Int] = [
            .bypassRed: 20, .disableRed: 21, .offsetGreen: 13,
            .shiftUpGreen: 24, .shiftDownGreen: 25, .playStillGreen: 26,
            .wipeStillGreen: 27, .hliteGreen: 29, .viewerGreen: 30, .cursorGreen: 31
        ]
        for (ch, w) in colorToWhite {
            if colorBits.contains(ch.rawValue) {
                whiteBits.remove(w)
            }
        }
        
        PanelManager.shared.setDualLEDs(whiteBits: whiteBits, colorBits: colorBits)
    }
}
