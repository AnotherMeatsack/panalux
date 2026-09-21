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
        
        var (whiteBits, colorBits) = IntroLEDChoreography.frame(scene: scene, t: t)

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
