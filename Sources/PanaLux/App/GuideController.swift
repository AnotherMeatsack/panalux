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
        guard let index = walkthroughStep, index < steps.count, !stepSatisfied else { return }
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
                 body: "Click any control on the drawing (or touch it on the panel). Pick a command on the right, or drag a tile onto a knob or key. Search covers all 999 Lightroom commands.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .inspector, title: "Every key has two jobs",
                 body: "“On tap” runs when you press and let go. “While held” can be a mode, Fine, a compare view, or a slider you park on the knobs. Hover a key to see arrows to what it drives.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .toolbar, title: "Safety nets",
                 body: "⌘Z undoes map changes. Every map change is backed up. Pause stops all output so you can practice, and Back to Base drops every mode. Both are also in the menu bar.",
                 goal: .none, highlight: nil),
        TourStep(anchor: .toolbar, title: "Find anything with ⌘K",
                 body: "Type a Lightroom command to run it once, assign it, see where it lives on the panel, or park it on a knob for a minute. Print your map from the Reference Card.",
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
