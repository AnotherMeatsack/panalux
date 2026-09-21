import Foundation
import SwiftUI

/// First-run setup, the spotlight tour, and the sheets opened from the menu bar.
public class GuideController: ObservableObject {
    public static let shared = GuideController()

    public enum HardwareEvent {
        case buttonDown(String)
        case holdEngaged(String)
        case analogMoved(String)
    }

    @Published public var showSetup: Bool = false
    @Published public var showQuickReference: Bool = false
    @Published public var showSettings: Bool = false
    @Published public var showPalette: Bool = false
    /// The presentation that plays before the hands-on tour.
    @Published public var showIntro: Bool = false
    @Published public var walkthroughStep: Int? = nil
    /// The current tour step's hardware goal was met.
    @Published public var stepSatisfied: Bool = false
    /// After the tour: keep the photo as-is, or restore it.
    @Published public var showTourWrapUp: Bool = false
    /// Set by the Map search field so ⌘Z edits text instead of the map.
    @Published public var isEditingText: Bool = false

    private var advanceWork: DispatchWorkItem?
    private var tourCopiedSettings = false
    private var tourSnapshot: [String: Double] = [:]

    private init() {}

    public var steps: [TourStep] { TourStep.all }

    public func presentSetup() {
        walkthroughStep = nil
        showSetup = true
    }

    public func presentIntro() {
        showSetup = false
        walkthroughStep = nil
        showIntro = true
    }
    
    public func finishIntro(startTour: Bool) {
        showIntro = false
        AppSettings.shared.hasCompletedOnboarding = true
        if startTour {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.startWalkthrough() }
        }
    }
    
    public func presentQuickReference() {
        showQuickReference = true
    }

    public func startWalkthrough() {
        showSetup = false
        stepSatisfied = false
        captureTourPhoto()
        walkthroughStep = 0
        PanelLightShow.shared.start()
    }

    public func goToStep(_ index: Int) {
        advanceWork?.cancel()
        stepSatisfied = false
        if index >= steps.count {
            finishWalkthrough()
        } else {
            walkthroughStep = max(0, index)
        }
    }

    public func finishWalkthrough() {
        advanceWork?.cancel()
        walkthroughStep = nil
        stepSatisfied = false
        AppSettings.shared.hasCompletedOnboarding = true
        AppSettings.shared.hasCompletedTour = true
        if tourCopiedSettings || !tourSnapshot.isEmpty {
            showTourWrapUp = true
        } else {
            clearTourPhoto()
        }
    }

    public func keepTourEdits() {
        showTourWrapUp = false
        clearTourPhoto()
    }

    public func restoreTourPhoto() {
        if tourCopiedSettings {
            LightroomBridge.shared.fireAction("LRPaste")
        }
        for (name, value) in tourSnapshot {
            _ = LightroomBridge.shared.setParameter(name, value: value)
        }
        LightroomBridge.shared.markStale()
        LightroomBridge.shared.requestFullRefresh(force: true)
        showTourWrapUp = false
        clearTourPhoto()
    }

    private func captureTourPhoto() {
        clearTourPhoto()
        guard LightroomBridge.shared.isConnected else { return }
        tourSnapshot = LightroomBridge.shared.allKnownValues()
        LightroomBridge.shared.fireAction("LRCopy")
        tourCopiedSettings = true
    }

    private func clearTourPhoto() {
        tourCopiedSettings = false
        tourSnapshot = [:]
    }

    /// The panel drives the tour: doing the thing a step asks for moves you on.
    public func hardwareEvent(_ event: HardwareEvent) {
        guard WhatsNewController.shared.spotlightIndex == nil, let index = walkthroughStep, index < steps.count, !stepSatisfied else { return }
        guard steps[index].goal.isMet(by: event) else { return }
        stepSatisfied = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.walkthroughStep == index else { return }
            self.goToStep(index + 1)
        }
        advanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

public struct TourStep {
    public enum Goal {
        case none
        case anyHardware
        case anyKnob
        case anyBall
        case anyRing
        case hold(String)
        case press(String)

        func isMet(by event: GuideController.HardwareEvent) -> Bool {
            switch (self, event) {
            case (.anyHardware, _): return true
            case (.anyKnob, .analogMoved(let name)): return PanelLayout.isKnob(name)
            case (.anyBall, .analogMoved(let name)): return PanelLayout.isBall(name)
            case (.anyRing, .analogMoved(let name)): return PanelLayout.isRing(name)
            case (.hold(let key), .holdEngaged(let name)): return key == name
            case (.press(let key), .buttonDown(let name)): return key == name
            default: return false
            }
        }

        var prompt: String? {
            switch self {
            case .none: return nil
            case .anyHardware: return "Touch anything on the panel"
            case .anyKnob: return "Turn any knob"
            case .anyBall: return "Roll any trackball"
            case .anyRing: return "Turn any ring"
            case .hold(let key): return "Hold \(PanelLayout.label(forControl: key))"
            case .press(let key): return "Press \(PanelLayout.label(forControl: key))"
            }
        }
    }

    public let anchor: SpotlightAnchor
    public let title: String
    public let body: String
    public let goal: Goal
    public let highlight: String?

    static let all: [TourStep] = [
        TourStep(anchor: .map, title: "This is your panel",
                 body: "The drawing matches the panel on your desk. Touch any key or turn any knob, and the same control lights up here. The photo will move so you can watch it on another screen. At the end you can keep those edits or put the photo back.",
                 goal: .anyHardware, highlight: nil),
        TourStep(anchor: .map, title: "Knobs grade",
                 body: "Knob 2 is Exposure out of the box. Turn a knob and watch the readout slide out under your menu bar. It tucks away 4 seconds after you stop.",
                 goal: .anyKnob, highlight: "Y_GAMMA"),
        TourStep(anchor: .map, title: "Trackballs are color wheels",
                 body: "Roll a ball to push shadows, midtones, or highlights toward a color. The rings set their brightness. The readout turns into a vectorscope.",
                 goal: .anyBall, highlight: "TB_GAMMA"),
        TourStep(anchor: .map, title: "Hold Up Shift for the Color Mixer",
                 body: "Holding a key adds a second map on top. While you hold the upper-left triangle, knobs 1–8 are the eight color bands. Let go and you are back.",
                 goal: .hold("SHIFT"), highlight: "SHIFT"),
        TourStep(anchor: .map, title: "Hold User for Upright",
                 body: "Knobs become perspective sliders, and Auto Color becomes Upright Auto, only while User is down. The readout lists all twelve knobs.",
                 goal: .hold("USER"), highlight: "USER"),
        TourStep(anchor: .map, title: "Tap Cursor to stay in Masks",
                 body: "A tap turns a mode on and it stays on. The readout says ON. Knobs now drive the selected mask. Tap Cursor again to leave.",
                 goal: .press("CURSOR"), highlight: "CURSOR"),
        TourStep(anchor: .map, title: "Hold Add Node for the tool wheel",
                 body: "A circular wheel appears over Lightroom. Spin a ring or roll a ball to Radial, Brush, Subject, Sky… Left ring (or Prev/Next Node and Frame) chooses New, Add, Subtract, or Intersect. Let go to create it, then place it with the mouse. Knobs grade the selected mask. Using the balls to place a mask is coming soon.",
                 goal: .hold("ADD_NODE"), highlight: "ADD_NODE"),
        TourStep(anchor: .inspector, title: "Change anything",
                 body: "Click any control on the drawing (or touch it on the panel). Pick a command on the right, or drag a tile onto a knob or key. Search includes Lightroom commands, keyboard shortcuts, and PanaLux actions.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .inspector, title: "Program knob presses and combinations",
                 body: "Press a knob to reset its current parameter. To customize, open Presses & Combinations in the inspector. Enable the editor, hold your modifier buttons and press a target. Release everything: the gesture stays selected. Drop a preset or command, then choose Done. You can also pick every button with the mouse. ",
                 goal: .none, highlight: nil),
        TourStep(anchor: .map, title: "Reset color, brightness, or both",
                 body: "Reset Lift, Gamma and Gain affect shadows, midtones and highlights. Press Reset alone for both color and brightness. Hold Up Shift and press Reset for ball color only; hold Down Shift and press Reset for ring luminance only. If you changed only brightness, Up Shift has nothing visible to clear. These combinations can be edited in Presses & Combinations.",
                 goal: .none, highlight: "RESET_GAMMA"),
        TourStep(anchor: .map, title: "Travel through your edit",
                 body: "With the default map, hold Undo and turn the right ring. Every small movement scrubs the supported sliders; a slow full click reaches the next recorded stop. Turn faster to travel farther. Reverse the ring to move forward. Release Undo to keep what you see.",
                 goal: .none, highlight: "UNDO"),
        TourStep(anchor: .toolbar, title: "Keep another direction",
                 body: "Editing after rewinding starts a tangent and keeps your earlier work. Hover briefly over the Rewind+ preview or click it to expand. It stays open after releasing Undo. Scrub with the slider or use playback. Select a source node, check the sliders you want, then merge into a new result. Both sources stay saved; masks and crop are excluded.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .toolbar, title: "Keep Rewind+ tidy",
                 body: "Selecting a node only inspects it; choose View This Tangent to apply it. Delete an inactive leaf with confirmation, then Undo Delete if needed during this photo session. Original, current and depended-on branches are protected. Click inside for shortcuts: Space plays, arrows step, Command-M merges checked sliders, Shift-Command-N creates a tangent and Command-Delete deletes. Escape or Collapse closes the workspace. What’s New in the menu bar or Settings keeps the full update history.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .toolbar, title: "Collect and remix your setups",
                 body: "Open Map Library & Community from the menu bar or Settings. Save Current names your setup. Preview another map, choose Whole control, Tap only or Hold only, then click controls or drag a section to your panel. Highlights show the pending transfer. Review it and choose Merge Selected. Save the result under a new name; Use switches between saved setups. Your calibration stays local. Export & Share and Suggest a Feature open public GitHub drafts for you to review and submit.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .toolbar, title: "Safety nets",
                 body: "⌘Z undoes map changes. Every map change is backed up. Pause stops all output so you can practice, and Back to Base drops every mode. Both are also in the menu bar.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .toolbar, title: "Find anything with ⌘K",
                 body: "Type a Lightroom command to run it once, assign it, see where it lives on the panel, or park it on a knob for a minute. Print / Panel Guide opens the physical reference. Choose a mode and gesture, then print a view, complete guide or enlarged sections, or save PNG. Help → What’s New replays the latest changes.",
                 goal: .none, highlight: nil)
    ]
}

public enum SpotlightAnchor: String, Hashable {
    case map
    case inspector
    case toolbar
}

public struct SpotlightAnchorKey: PreferenceKey {
    public static var defaultValue: [SpotlightAnchor: Anchor<CGRect>] = [:]
    public static func reduce(value: inout [SpotlightAnchor: Anchor<CGRect>], nextValue: () -> [SpotlightAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

public extension View {
    func spotlightAnchor(_ anchor: SpotlightAnchor) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { [anchor: $0] }
    }
}
