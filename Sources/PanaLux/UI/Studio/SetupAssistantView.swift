import SwiftUI

/// First-run setup with live checks, then hands off to the hands-on tour.
public struct SetupAssistantView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var guide = GuideController.shared
    @ObservedObject var panel = PanelManager.shared
    @ObservedObject var bridge = LightroomBridge.shared

    @State private var step: Int = 0
    @State private var openAtLogin = AppSettings.shared.opensAtLogin

    private let titles = ["Welcome", "Plugin", "Lightroom", "Panel", "Photoshop", "Ready"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(titles.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Group {
                switch step {
                case 0: welcome
                case 1: plugin
                case 2: lightroom
                case 3: panelStep
                case 4: photoshop
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.top, 22)

            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < titles.count - 1 {
                    Button("Skip Setup") { finish(tour: false) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { finish(tour: false) }
                    Button("Watch the Intro") { finish(tour: true) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(18)
        }
        .frame(width: 620, height: 520)
        .onAppear { coordinator.checkRunningApps() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("One panel. Every job.")
                .font(.system(size: 26, weight: .bold))
            Text("PanaLux turns a Micro Color Panel into a Lightroom Classic controller. Knobs grade, trackballs are color wheels, and holding a key swaps in a whole new set of controls.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Setup takes about two minutes. All you need is Lightroom Classic and the panel plugged in over USB. PanaLux installs the rest.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("PanaLux is free, unofficial, and open source. It is not affiliated with Blackmagic Design, Adobe, or Apple.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var plugin: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Add PanaLux to Lightroom", "Lightroom takes outside controls through a plugin. PanaLux carries its own. nothing to download.")
            check("PanaLux Bridge plugin", ok: coordinator.isBridgeInstalled && !coordinator.isBridgeOutdated,
                  detail: coordinator.isBridgeOutdated ? "An older version is installed."
                      : (coordinator.isBridgeInstalled ? "Installed in Lightroom’s plugin folder." : "One click puts it where Lightroom looks for plugins."))
            if !coordinator.isBridgeInstalled || coordinator.isBridgeOutdated {
                Button(coordinator.isBridgeOutdated ? "Update Plugin" : "Install Plugin") { coordinator.installBridge() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
            if coordinator.isStockMIDI2LRInstalled {
                check("A regular MIDI2LR plugin is also installed", ok: false,
                      detail: "It opens the MIDI2LR app when Lightroom starts, and that app takes PanaLux’s connection.")
                Button("Turn Off MIDI2LR Plugin…") { coordinator.disableStockMIDI2LR() }
            }
            if coordinator.needsLightroomRestart {
                check("Restart Lightroom to load the plugin", ok: false, detail: "Lightroom reads plugins when it starts.")
                Button("Restart Lightroom…") { coordinator.restartLightroom() }
            }
            Text("PanaLux Bridge is the free MIDI2LR plugin (GPL-3.0), set up to talk to PanaLux. It’s listed in Lightroom under File › Plug-in Manager.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var lightroom: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Connect to Lightroom", "PanaLux connects on its own whenever Lightroom Classic is open.")
            check("Lightroom Classic is open", ok: coordinator.isLightroomRunning, detail: nil)
            check("Connected to the Lightroom plugin", ok: bridge.isConnected,
                  detail: bridge.isConnected ? "Knobs will move sliders." : "Waiting… this can take a few seconds after Lightroom opens.")
            if !coordinator.isLightroomRunning {
                Button("Open Lightroom Classic") { coordinator.launchLightroomClassic() }
            } else if !bridge.isConnected {
                Text(coordinator.needsLightroomRestart
                     ? "Restart Lightroom so it loads the PanaLux Bridge plugin."
                     : "Still waiting? Make sure the plugin is installed (previous step) and quit the MIDI2LR app if it’s open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var panelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Plug in the panel", "Use the USB-C cable. The panel doesn’t need its own power supply for this.")
            check("Panel connected", ok: panel.isConnected,
                  detail: panel.isConnected ? "Try a knob. the drawing on the Map lights up." : "PanaLux keeps looking; no need to restart.")
            if coordinator.isResolveRunning {
                check("DaVinci Resolve is open", ok: false, detail: settings.handPanelToResolve
                      ? "PanaLux hands the panel to Resolve while it runs and takes it back when Resolve quits."
                      : "Resolve takes over the panel while it’s open.")
                Toggle("Hand the panel to Resolve automatically", isOn: $settings.handPanelToResolve)
            }
            numbered(1, "If macOS asks about Input Monitoring or USB accessories, allow it.")
            numbered(2, "Only one app can use the panel at a time.")
        }
    }

    private var photoshop: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Grab Still → Photoshop (optional)", "Grab Still opens the selected photos as layers in Photoshop, aligns them, and brings the result back. It clicks Lightroom’s menus for you, which needs one permission.")
            check("Accessibility access", ok: coordinator.isAccessibilityTrusted,
                  detail: coordinator.isAccessibilityTrusted ? "Copy, Paste, Sync, and Grab Still are ready." : "Needed for Copy, Paste, Sync, Select All, and Grab Still. Grading works without it.")
            if !coordinator.isAccessibilityTrusted {
                Button("Open Accessibility Settings") { coordinator.openAccessibilitySettings() }
                Text("Turn on PanaLux in the list. macOS may also ask to let PanaLux control Lightroom and Photoshop the first time you press Grab Still.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("You’re set", "Next: a one-minute intro, then a hands-on tour that uses the real panel. turn a knob, hold a key, and it moves on by itself.")
            Toggle("Open PanaLux when I log in", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    if settings.setOpensAtLogin(on) {
                        if on { settings.showWindowAtLaunch = false }
                    } else {
                        openAtLogin = settings.opensAtLogin
                    }
                }
            Text("PanaLux lives in the menu bar. Close this window any time; the panel keeps working.")
                .font(.callout)
                .foregroundStyle(.secondary)
            summaryRow("Plugin", coordinator.isPluginInstalled)
            summaryRow("Lightroom", bridge.isConnected)
            summaryRow("Panel", panel.isConnected)
        }
    }

    // MARK: Pieces

    private func header(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func check(_ title: String, ok: Bool, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(ok ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ ok: Bool) -> some View {
        Label(ok ? "\(title) ready" : "\(title) not ready yet", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(ok ? Color.green : Color.orange)
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.secondary.opacity(0.18)))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish(tour: Bool) {
        settings.hasCompletedOnboarding = true
        guide.showSetup = false
        if tour {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guide.presentIntro()
            }
        }
    }
}
