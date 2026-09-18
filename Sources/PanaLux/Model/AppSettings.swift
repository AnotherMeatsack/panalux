import Foundation
import SwiftUI
import ServiceManagement

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    @AppStorage("notchHudEnabled") public var notchHudEnabled: Bool = true
    /// "full" shows glyphs and the knob row; "minimal" is one quiet line.
    @AppStorage("hudStyle") public var hudStyle: String = "full"
    @AppStorage("hudDuration") public var hudDuration: Double = 4.0
    @AppStorage("showVectorscope") public var showVectorscope: Bool = true
    @AppStorage("fineMultiplier") public var fineMultiplier: Double = 0.25
    @AppStorage("autoCloseResolve") public var autoCloseResolve: Bool = false
    /// Let go of the panel while DaVinci Resolve runs, take it back when Resolve quits.
    @AppStorage("handPanelToResolve") public var handPanelToResolve: Bool = true
    @AppStorage("ledMode") public var ledMode: String = "pulse" // "pulse", "layer", "all", "stealth"
    @AppStorage("backlightBrightness") public var backlightBrightness: Double = 100.0
    @AppStorage("highlightHardwareOnSelect") public var highlightHardwareOnSelect: Bool = true
    @AppStorage("hasCompletedOnboarding") public var hasCompletedOnboarding: Bool = false
    @AppStorage("hasCompletedTour") public var hasCompletedTour: Bool = false
    @AppStorage("showWindowAtLaunch") public var showWindowAtLaunch: Bool = true
    /// The knob that "Temporary Focus Dial" borrows.
    @AppStorage("focusDialControl") public var focusDialControl: String = "LUM_MIX"
    /// When on, Masks put Exposure on the Exposure knob, Contrast on Contrast, and so on.
    @AppStorage("mirrorMaskToBase") public var mirrorMaskToBase: Bool = true
    @AppStorage("autoAlignLayers") public var autoAlignLayers: Bool = true
    
    private init() {
        migrateHudDurationIfNeeded()
    }
    
    public var hudHidden: Bool { !notchHudEnabled }
    
    /// Old builds defaulted to 30s. One-shot move to 4s unless the user already picked another value.
    private func migrateHudDurationIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "hudDurationMigratedTo4") == nil else { return }
        if defaults.object(forKey: "hudDuration") != nil, defaults.double(forKey: "hudDuration") == 30.0 {
            defaults.set(4.0, forKey: "hudDuration")
        }
        defaults.set(true, forKey: "hudDurationMigratedTo4")
    }
    
    // MARK: Open at login
    
    public var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    @discardableResult
    public func setOpensAtLogin(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
            return true
        } catch {
            print("[Settings] Login item change failed: \(error)")
            objectWillChange.send()
            return false
        }
    }
}
