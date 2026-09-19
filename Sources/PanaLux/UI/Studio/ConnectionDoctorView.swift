import SwiftUI
import ApplicationServices

/// Every link PanaLux depends on, checked live, each with the one button that fixes it.
public struct ConnectionDoctorView: View {
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var panel = PanelManager.shared
    @ObservedObject var bridge = LightroomBridge.shared

    public init() {}

    static func inputs(coordinator c: AppCoordinator, panel: PanelManager, bridge: LightroomBridge) -> DoctorInputs {
        var i = DoctorInputs()
        i.panelConnected = panel.isConnected
        i.panelHandedOver = panel.isReleased
        i.resolveRunning = c.isResolveRunning
        i.otherPanelHolderPID = c.conflictingProcessPID
        i.lightroomRunning = c.isLightroomRunning
        i.lightroomConnected = bridge.isConnected
        i.bridgeInstalled = c.isBridgeInstalled
        i.pluginOutdated = c.isBridgeOutdated
        i.stockMIDI2LRInstalled = c.isStockMIDI2LRInstalled
        i.needsLightroomRestart = c.needsLightroomRestart
        i.accessibilityTrusted = c.isAccessibilityTrusted
        i.photoshopRunning = c.isPhotoshopRunning
        return i
    }

    public var body: some View {
        let checks = ConnectionDoctor.checks(Self.inputs(coordinator: coordinator, panel: panel, bridge: bridge))
        Section("Connection check") {
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(check.status))
                        .foregroundStyle(color(check.status))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                        Text(check.detail).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if check.fix != .none, check.status == .problem {
                        Button(check.fix.title) { run(check.fix) }
                    }
                }
            }
        }
        .onAppear { coordinator.checkRunningApps() }
    }

    private func symbol(_ s: DoctorCheck.Status) -> String {
        switch s { case .ok: return "checkmark.circle.fill"; case .problem: return "exclamationmark.triangle.fill"; case .unknown: return "minus.circle" }
    }
    private func color(_ s: DoctorCheck.Status) -> Color {
        switch s { case .ok: return .green; case .problem: return .orange; case .unknown: return .secondary }
    }

    private func run(_ fix: DoctorCheck.Fix) {
        switch fix {
        case .quitResolve: coordinator.closeDaVinciResolve()
        case .reinstallPlugin: coordinator.installBridge()
        case .restartLightroom: coordinator.restartLightroom()
        case .openLightroom: coordinator.launchLightroomClassic()
        case .reconnectPanel: PanelManager.shared.reclaim()
        case .openAccessibility:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .none: break
        }
    }
}
