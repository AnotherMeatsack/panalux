import Foundation

/// One line of the connection check: what is wrong, in plain words, and the one thing to press.
public struct DoctorCheck: Equatable, Identifiable {
    public enum Status: Equatable { case ok, problem, unknown }
    public enum Fix: Equatable {
        case quitResolve, reinstallPlugin, restartLightroom, openAccessibility, reconnectPanel, openLightroom, none
        public var title: String {
            switch self {
            case .quitResolve: return "Quit Resolve"
            case .reinstallPlugin: return "Reinstall Plugin"
            case .restartLightroom: return "Restart Lightroom"
            case .openAccessibility: return "Open Settings"
            case .reconnectPanel: return "Reconnect"
            case .openLightroom: return "Open Lightroom"
            case .none: return ""
            }
        }
    }
    public var id: String
    public var title: String
    public var detail: String
    public var status: Status
    public var fix: Fix
}

/// Everything the check needs to know, gathered in one place so the rules can be tested.
public struct DoctorInputs: Equatable {
    public var panelConnected = false
    public var panelHandedOver = false
    public var resolveRunning = false
    public var otherPanelHolderPID: Int32? = nil
    public var lightroomRunning = false
    public var lightroomConnected = false
    public var bridgeInstalled = false
    public var pluginOutdated = false
    public var stockMIDI2LRInstalled = false
    public var needsLightroomRestart = false
    public var accessibilityTrusted = false
    public var photoshopRunning = false
    public init() {}
}

public enum ConnectionDoctor {
    public static func checks(_ i: DoctorInputs) -> [DoctorCheck] {
        var out: [DoctorCheck] = []

        // Panel
        if i.panelHandedOver || i.resolveRunning {
            out.append(.init(id: "panel", title: "Panel", detail: "DaVinci Resolve has the panel. Only one app can use it at a time.",
                             status: .problem, fix: i.resolveRunning ? .quitResolve : .reconnectPanel))
        } else if let pid = i.otherPanelHolderPID {
            out.append(.init(id: "panel", title: "Panel", detail: "Another copy of PanaLux (process \(pid)) is holding the panel. Quit it, then reconnect.",
                             status: .problem, fix: .reconnectPanel))
        } else if i.panelConnected {
            out.append(.init(id: "panel", title: "Panel", detail: "Connected.", status: .ok, fix: .none))
        } else {
            out.append(.init(id: "panel", title: "Panel", detail: "Not found. Check the USB cable, then reconnect.",
                             status: .problem, fix: .reconnectPanel))
        }

        // Plugin
        if !i.bridgeInstalled {
            out.append(.init(id: "plugin", title: "Lightroom plugin",
                             detail: i.stockMIDI2LRInstalled ? "Only the stock MIDI2LR plugin is installed. PanaLux needs its own." : "Not installed.",
                             status: .problem, fix: .reinstallPlugin))
        } else if i.pluginOutdated {
            out.append(.init(id: "plugin", title: "Lightroom plugin", detail: "The installed plugin is older than this version of PanaLux.",
                             status: .problem, fix: .reinstallPlugin))
        } else if i.needsLightroomRestart {
            out.append(.init(id: "plugin", title: "Lightroom plugin", detail: "Installed. Lightroom loads it the next time it starts.",
                             status: .problem, fix: .restartLightroom))
        } else {
            out.append(.init(id: "plugin", title: "Lightroom plugin", detail: "Installed and up to date.", status: .ok, fix: .none))
        }

        // Lightroom link
        if !i.lightroomRunning {
            out.append(.init(id: "lightroom", title: "Lightroom", detail: "Not running.", status: .problem, fix: .openLightroom))
        } else if i.lightroomConnected {
            out.append(.init(id: "lightroom", title: "Lightroom", detail: "Connected.", status: .ok, fix: .none))
        } else {
            out.append(.init(id: "lightroom", title: "Lightroom", detail: "Running, but the plugin isn't answering. Restarting Lightroom usually fixes it.",
                             status: .problem, fix: .restartLightroom))
        }

        // Accessibility
        out.append(i.accessibilityTrusted
            ? .init(id: "access", title: "Accessibility", detail: "Allowed. Keys can be typed into Lightroom.", status: .ok, fix: .none)
            : .init(id: "access", title: "Accessibility", detail: "Not allowed. Buttons that press a key can't work.", status: .problem, fix: .openAccessibility))

        // Photoshop is only needed for Grab Still.
        out.append(.init(id: "photoshop", title: "Photoshop", detail: i.photoshopRunning ? "Running." : "Not running. Only Grab Still needs it; it opens when you use it.",
                         status: i.photoshopRunning ? .ok : .unknown, fix: .none))
        return out
    }
}
