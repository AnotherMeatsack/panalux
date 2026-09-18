import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var engine = StudioEngine.shared
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var panel = PanelManager.shared
    @ObservedObject var bridge = LightroomBridge.shared
    @ObservedObject var guide = GuideController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showCalibration = false
    @State private var openAtLogin = AppSettings.shared.opensAtLogin
    @State private var backups: [MapFile] = []
    @State private var maps: [MapFile] = []
    @State private var confirmFactory = false
    @State private var newMapName = ""

    public init() {}

    private var hudStyle: Binding<String> {
        Binding(
            get: { settings.notchHudEnabled ? settings.hudStyle : "hidden" },
            set: { value in
                if value == "hidden" {
                    settings.notchHudEnabled = false
                } else {
                    settings.notchHudEnabled = true
                    settings.hudStyle = value
                }
            }
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                general
                hud
                panelSection
                mapsSection
                helpSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 640)
        .onAppear(perform: reload)
        .sheet(isPresented: $showCalibration) {
            HardwareCalibrationView()
        }
        .confirmationDialog("Replace your map with the factory map?", isPresented: $confirmFactory) {
            Button("Use Factory Map", role: .destructive) {
                engine.replaceProfile(Profile.loadDefault(), reason: "before factory reset")
                reload()
            }
        } message: {
            Text("Your current map is backed up first, and ⌘Z brings it back.")
        }
    }

    // MARK: Sections

    private var general: some View {
        Section("General") {
            Toggle("Open at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    if !settings.setOpensAtLogin(on) { openAtLogin = settings.opensAtLogin }
                }
            Toggle("Show this window when PanaLux opens", isOn: $settings.showWindowAtLaunch)
            Toggle("Hand the panel to DaVinci Resolve while it’s open", isOn: $settings.handPanelToResolve)
            Toggle("Quit DaVinci Resolve automatically", isOn: $settings.autoCloseResolve)
                .help("PanaLux asks Resolve to quit whenever it opens. Most people leave this off.")
            LabeledContent("Lightroom") {
                status(bridge.isConnected, bridge.isConnected ? "Connected" : (coordinator.isLightroomRunning ? "Waiting for plugin" : "Not open"))
            }
            LabeledContent("Lightroom plugin") {
                if coordinator.isBridgeInstalled && !coordinator.isBridgeOutdated {
                    status(true, "PanaLux Bridge installed")
                } else {
                    Button(coordinator.isBridgeOutdated ? "Update Plugin" : "Install Plugin") { coordinator.installBridge() }
                }
            }
            LabeledContent("Panel") {
                status(panel.isConnected, panel.isReleased ? "Handed to Resolve" : (panel.isConnected ? "Connected" : "Not found"))
            }
        }
    }

    private var hud: some View {
        Section {
            Picker("Style", selection: hudStyle) {
                Text("Full").tag("full")
                Text("Minimal").tag("minimal")
                Text("Hidden").tag("hidden")
            }
            .pickerStyle(.segmented)
            Picker("Stay after you stop turning", selection: $settings.hudDuration) {
                Text("2 seconds").tag(2.0)
                Text("4 seconds").tag(4.0)
                Text("8 seconds").tag(8.0)
                Text("15 seconds").tag(15.0)
                Text("30 seconds").tag(30.0)
                Text("Until next change").tag(120.0)
            }
            Toggle("Vectorscope for trackballs", isOn: $settings.showVectorscope)
        } header: {
            Text("Notch HUD")
        } footer: {
            Text("Key taps show for 2 seconds. Held modes stay while the key is down, and modes you tap on stay as a small reminder.")
        }
    }

    private var panelSection: some View {
        Section("Panel") {
            LabeledContent("Backlight") {
                Slider(value: $settings.backlightBrightness, in: 0...100, step: 5)
                    .frame(width: 200)
                    .onChange(of: settings.backlightBrightness) { _, v in
                        PanelManager.shared.setBrightness(level: Int(v))
                    }
            }
            Picker("Key lights", selection: $settings.ledMode) {
                Text("Light keys as you press them").tag("pulse")
                Text("Light only the active mode").tag("layer")
                Text("All keys on").tag("all")
                Text("All keys off").tag("stealth")
            }
            .onChange(of: settings.ledMode) { _, _ in engine.updateLeds() }
            Toggle("Light the key I click in the Map", isOn: $settings.highlightHardwareOnSelect)
            LabeledContent("Fine speed") {
                HStack {
                    Slider(value: $settings.fineMultiplier, in: 0.1...0.5, step: 0.05)
                        .frame(width: 160)
                    Text(String(format: "%.2f×", settings.fineMultiplier))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Focus dial knob", selection: $settings.focusDialControl) {
                ForEach(PanelLayout.knobs, id: \.self) { id in
                    Text(PanelLayout.label(forControl: id)).tag(id)
                }
            }
            Toggle("Masks use the same knobs as Base", isOn: $settings.mirrorMaskToBase)
                .help("Exposure stays on the Exposure knob, Contrast on Contrast, and so on. Turn this off to map Mask knobs yourself.")
            Toggle("Auto-align layers in Photoshop", isOn: $settings.autoAlignLayers)
                .help("After Open as Layers, PanaLux waits for the stack to finish arriving and runs Auto-Align once. Turn this off to align by hand.")
            Button("Learn Key Positions…") { showCalibration = true }
        }
    }

    private var mapsSection: some View {
        Section {
            HStack {
                Button("Import Map…") { MapImporter.chooseAndImport(); reload() }
                Button("Export Map…") { MapImporter.chooseAndExport() }
                Button("Copy Map") { MapImporter.copyCurrentMap() }
                Spacer()
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: AppPaths.mapsDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.mapsDir])
                }
            }
            HStack {
                TextField("Save current map as…", text: $newMapName)
                Button("Save") {
                    let name = newMapName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    _ = try? ProfileStore.saveToMaps(engine.profile, name: name)
                    newMapName = ""
                    reload()
                }
                .disabled(newMapName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(maps) { map in
                LabeledContent(map.name) {
                    Button("Use") { MapImporter.confirmAndImport(map.url) }
                }
            }
            Menu("Restore a Backup") {
                if backups.isEmpty {
                    Text("No backups yet")
                }
                ForEach(backups.prefix(20)) { backup in
                    Button(backup.name) { MapImporter.confirmAndImport(backup.url) }
                }
            }
            Button("Use Factory Map…", role: .destructive) { confirmFactory = true }
        } header: {
            Text("Maps")
        } footer: {
            Text("A .panalux.json file is the whole setup: every knob, ring, ball, key, and mode, plus Fine speed, mask knob layout, and key calibration. Drop it on the PanaLux window or choose Import. PanaLux backs up your map at launch and before every import, preset, or reset.")
        }
    }

    private var helpSection: some View {
        Section("Help") {
            Button("Watch the Intro") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { guide.presentIntro() }
            }
            Button("Take the Hands-On Tour") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { guide.startWalkthrough() }
            }
            Button("Setup Assistant…") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { guide.presentSetup() }
            }
            Button("Open Reference Card") { ReferenceCard.open() }
            Button("Quick Reference") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { guide.presentQuickReference() }
            }
            Button("Report a Bug…") { BugReport.present() }
            Link("GitHub", destination: URL(string: BugReport.github)!)
            Link("MIDI2LR command list", destination: URL(string: "https://github.com/rsjaffe/MIDI2LR/wiki/Commands")!)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            Text("PanaLux is a free, unofficial, open-source macOS app. It is not affiliated with, endorsed by, or related to Blackmagic Design, Adobe, or Apple. It talks to a Micro Color Panel you already purchased and to Lightroom Classic through PanaLux Bridge, a lightly modified copy of the free community plugin MIDI2LR (GPL-3.0). You are not buying anything.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("MIT License.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func status(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func reload() {
        backups = ProfileStore.backups()
        maps = ProfileStore.savedMaps()
    }
}
