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
                ConnectionDoctorView()
                general
                hud
                panelSection
                rewindSection
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
            Text("Lights only show for keys you press or for the active mode. If your panel looks dark, pick \"All keys on\".")
                .font(.callout).foregroundStyle(.secondary)
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
            Picker("Hold a key for", selection: $settings.holdDelay) {
                Text("0.35 s · quick").tag(0.35)
                Text("0.5 s").tag(0.5)
                Text("0.7 s · deliberate").tag(0.7)
                Text("1 s").tag(1.0)
            }
            .help("How long a key must be down before it switches modes instead of firing its tap. Longer means an ordinary press never brings a mode up by accident.")
            Toggle("Quit Photoshop when its last document closes", isOn: $settings.quitPhotoshopWhenEmpty)
                .help("Off by default. Lightroom hands a whole stack to a Photoshop that is already open; to one it has to launch it often hands over only the first photo.")
            Toggle("Auto-align layers in Photoshop", isOn: $settings.autoAlignLayers)
                .help("After Open as Layers, PanaLux waits for the stack to finish arriving and runs Auto-Align once. Turn this off to align by hand.")
            Button("Learn Key Positions…") { showCalibration = true }
        }
    }

    /// Rewind's feel. These are read on every turn, so change one and try the ring straight away.
    private var rewindSection: some View {
        Section {
            LabeledContent("Click size") {
                HStack {
                    Slider(value: $settings.rewindClickUnits, in: 10...150, step: 5)
                        .frame(width: 160)
                    Text(String(format: "%.0f", settings.rewindClickUnits))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .help("How far the scrub ring turns for one step. Smaller is more sensitive: each click lands on one thing that changed.")
            LabeledContent("Spin speed") {
                HStack {
                    Slider(value: $settings.rewindAcceleration, in: 0...1, step: 0.05)
                        .frame(width: 160)
                    Text(String(format: "%.0f%%", settings.rewindAcceleration * 100))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .help("How quickly a hard spin crosses a long session. Turning the ring slowly is always one step per click, whatever this says.")
            Button("Use right-ring timeline layout") {
                var layer = engine.profile.layers["REWIND"] ?? LayerSpec()
                var rings = layer.rings ?? [:]
                rings["RING_GAMMA"] = RingBinding(param: RewindCommands.tangents)
                rings["RING_LIFT"] = RingBinding(param: RewindCommands.landmarks)
                rings["RING_GAIN"] = RingBinding(param: RewindCommands.scrub)
                layer.rings = rings
                engine.profile.layers["REWIND"] = layer
            }
            Text("Right ring travels, left ring visits landmarks, center ring compares tangents. Trackballs rest while rewinding; release Undo to grade. Map Undo restores your previous assignments.")
                .font(.caption).foregroundStyle(.secondary)
            Text(bridge.previewStatus).font(.caption).foregroundStyle(.secondary)
            Button("Reset Rewind feel") {
                settings.rewindClickUnits = 40
                settings.rewindAcceleration = 0.5
            }
        } header: {
            Text("Rewind")
        } footer: {
            Text("Hold Undo: right ring scrubs, left visits landmarks, center switches tangents. Spin the scrub ring faster to travel farther. Custom layouts stay as you set them.")
        }
    }

    private var mapsSection: some View {
        Section {
            Button("Map Library & Community…") { MapLibraryWindowController.shared.show() }
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
            Button("Suggest a Feature…") { FeatureSuggestionWindow.shared.show() }
            Button("Report a Bug…") { BugReport.present() }
            Link("GitHub", destination: URL(string: BugReport.github)!)
            Link("MIDI2LR command list", destination: URL(string: "https://github.com/rsjaffe/MIDI2LR/wiki/Commands")!)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Button("What’s New…") { ReleaseNotesWindowController.shared.show() }
            Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
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
