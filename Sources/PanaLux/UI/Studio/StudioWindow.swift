import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct StudioWindowView: View {
    @ObservedObject var engine = StudioEngine.shared
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var guide = GuideController.shared
    @ObservedObject var panel = PanelManager.shared
    @ObservedObject var bridge = LightroomBridge.shared

    @State private var selectedControl: String? = "Y_GAMMA"
    @State private var dropTargeted = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            banners
            HStack(spacing: 0) {
                PanelCanvasView(selectedControl: $selectedControl)
                    .spotlightAnchor(.map)
                    .frame(minWidth: 600)
                Divider()
                MapInspectorView(selectedControl: $selectedControl)
                    .frame(width: 370)
                    .spotlightAnchor(.inspector)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .navigationTitle("PanaLux")
        .toolbar { toolbarContent }
        .overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
            WalkthroughOverlay(anchors: anchors)
        }
        .overlay {
            if guide.showIntro {
                IntroShowView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: guide.showIntro)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8)
                    .overlay(Text("Drop a map to use it").font(.title2.weight(.semibold)))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "json" else { return }
                DispatchQueue.main.async { MapImporter.confirmAndImport(url) }
            }
            return true
        }
        .sheet(isPresented: $guide.showSetup) { SetupAssistantView() }
        .sheet(isPresented: $guide.showSettings) { SettingsView() }
        .sheet(isPresented: $guide.showQuickReference) { QuickReferenceView() }
        .sheet(isPresented: $guide.showPalette) { CommandPaletteView(selectedControl: $selectedControl) }
        .confirmationDialog("Keep the tour edits?", isPresented: $guide.showTourWrapUp, titleVisibility: .visible) {
            Button("Keep Changes") { guide.keepTourEdits() }
            Button("Put the Photo Back", role: .destructive) { guide.restoreTourPhoto() }
        } message: {
            Text("The tour moved this photo so you could watch it on another screen. Keep those edits, or restore what it looked like before.")
        }
        .onDisappear { engine.setProgrammingButtons(false) }
        .onChange(of: guide.showSettings) { _, _ in syncSettingsLock() }
        .onChange(of: engine.lastButtonName) { _, name in
            if let name, PanelLayout.isButton(name) { selectedControl = name }
        }
        .onChange(of: engine.lastAnalogName) { _, name in
            guard let name else { return }
            // Trackball axes arrive as TB_LIFT_X; the Map shows the ball.
            if name.hasPrefix("TB_"), let cut = name.lastIndex(of: "_") {
                selectedControl = String(name[..<cut])
            } else {
                selectedControl = name
            }
        }
        .onChange(of: selectedControl) { _, new in
            if guide.walkthroughStep == nil { engine.foundControls = [] }
            if let source = engine.swapSource, let new, new != source {
                engine.swapSource = nil
                engine.swapControls(source, new)
            }
        }
    }


    private func syncSettingsLock() {
        engine.setSettingsOpen(guide.showSettings)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ConnectionPill(title: "Panel", ok: panel.isConnected, detail: panelDetail)
            ConnectionPill(title: "Lightroom", ok: bridge.isConnected, detail: lightroomDetail)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { engine.isProgrammingButtons }, set: { engine.setProgrammingButtons($0) })) {
                Label("Program Buttons", systemImage: "hand.point.down")
            }
            .help("Learn any button’s tap or hold without sending edits to Lightroom. Drop an action to assign it.")
            Button { TangentWindowController.shared.show() } label: {
                Label("Tangents", systemImage: "arrow.triangle.branch")
            }
            .help("Name, compare and merge selected settings from your saved tangents")

            Button { ControlHelpWindowController.shared.show() } label: {
                Label("Your Controls", systemImage: "questionmark.circle")
            }
            .keyboardShortcut("?", modifiers: .command)
            .help("Your current controls and shortcuts (⌘?)")
            ControlGroup {
                Button {
                    engine.undoMapChange()
                } label: {
                    Label("Undo Map Change", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!engine.canUndoMap || guide.isEditingText)
                .help("Undo map change (⌘Z)")

                Button {
                    engine.redoMapChange()
                } label: {
                    Label("Redo Map Change", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!engine.canRedoMap || guide.isEditingText)
                .help("Redo map change (⇧⌘Z)")
            }

            ControlGroup {
                Toggle(isOn: Binding(get: { engine.isOutputPaused }, set: { engine.setOutputPaused($0) })) {
                    Label("Pause Output", systemImage: engine.isOutputPaused ? "pause.circle.fill" : "pause.circle")
                }
                .help("Pause: nothing reaches Lightroom. Practice freely.")

                Button {
                    engine.returnToBase()
                } label: {
                    Label("Back to Base", systemImage: "house")
                }
                .help("Drop every held, toggled, and temporary mode")
            }

            Menu {
                Section("Starting maps") {
                    ForEach(ProfilePresets.all) { preset in
                        Button(preset.title) { ProfilePresets.apply(preset, to: engine) }
                    }
                }
                let saved = ProfileStore.savedMaps()
                if !saved.isEmpty {
                    Section("My maps") {
                        ForEach(saved) { map in
                            Button(map.name) { MapImporter.confirmAndImport(map.url) }
                        }
                    }
                }
                Divider()
                Button("Save Current Map as My Home") { ProfilePresets.snapshotHome(engine.profile) }
                Button("Import Map…") { MapImporter.chooseAndImport() }
                Button("Export Map…") { MapImporter.chooseAndExport() }
                Button("Copy Map") { MapImporter.copyCurrentMap() }
            } label: {
                Label("Maps", systemImage: "square.stack.3d.up")
            }
            .help("Starting maps, your saved maps, import and export")

            Button {
                guide.showPalette = true
            } label: {
                Label("Find Command", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("k", modifiers: .command)
            .help("Find a Lightroom command (⌘K)")

            Menu {
                Button("Watch the Intro") { guide.presentIntro() }
                Button("Take the Hands-On Tour") { guide.startWalkthrough() }
                Button("Setup Assistant…") { guide.presentSetup() }
                Button("Quick Reference") { guide.presentQuickReference() }
                Button("Reference Card") { ReferenceCard.open() }
                Divider()
                Button("Report a Bug…") { BugReport.present() }
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }

            Button {
                guide.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var panelDetail: String {
        if panel.isReleased { return "Handed to DaVinci Resolve" }
        return panel.isConnected ? "Connected" : "Not found. plug it in over USB-C"
    }

    private var lightroomDetail: String {
        if bridge.isConnected { return "Connected" }
        if !coordinator.isLightroomRunning { return "Lightroom Classic isn’t open" }
        if coordinator.isMIDI2LRAppRunning { return "Quit the MIDI2LR app. PanaLux replaces it" }
        if !coordinator.isPluginInstalled { return "Lightroom plugin not installed" }
        return "Waiting for the Lightroom plugin"
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if panel.isReleased {
            Banner(symbol: "arrow.up.circle.fill", tint: .blue,
                   text: coordinator.isResolveRunning
                       ? "The panel is with DaVinci Resolve. PanaLux takes it back when Resolve quits."
                       : "PanaLux let go of the panel.",
                   actionTitle: "Take Panel Back") {
                coordinator.reclaimPanel()
            }
        } else if coordinator.conflictingProcessPID != nil {
            Banner(symbol: "lock.fill", tint: .orange,
                   text: "Another copy of PanaLux is using the panel.",
                   actionTitle: "Quit It and Take Over") {
                coordinator.reclaimPanelHardware()
            }
        }
        if !bridge.isConnected {
            if coordinator.isMIDI2LRAppRunning {
                Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: "The MIDI2LR app is open and holding Lightroom’s connection. PanaLux replaces it.",
                       actionTitle: "Quit MIDI2LR App") {
                    coordinator.quitMIDI2LRApp()
                }
            } else if !coordinator.isLightroomRunning {
                Banner(symbol: "photo", tint: .secondary,
                       text: "Open Lightroom Classic to start grading. PanaLux connects by itself.",
                       actionTitle: "Open Lightroom") {
                    coordinator.launchLightroomClassic()
                }
            } else if !coordinator.isPluginInstalled {
                Banner(symbol: "puzzlepiece.extension", tint: .orange,
                       text: "Lightroom needs the PanaLux Bridge plugin.",
                       actionTitle: "Install Plugin") {
                    coordinator.installBridge()
                }
            } else if coordinator.needsLightroomRestart {
                Banner(symbol: "arrow.clockwise", tint: .orange,
                       text: "Restart Lightroom so it loads the PanaLux Bridge plugin.",
                       actionTitle: "Restart Lightroom…") {
                    coordinator.restartLightroom()
                }
            }
        }
    }
}

private struct Banner: View {
    let symbol: String
    let tint: Color
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer()
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ConnectionPill: View {
    let title: String
    let ok: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 8)
        .help("\(title): \(detail)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }
}

// MARK: - Window

public class StudioWindowController: NSObject, NSWindowDelegate {
    public static let shared = StudioWindowController()
    private var window: NSWindow?

    private override init() {}

    public func show() {
        if window == nil {
            let controller = NSHostingController(rootView: StudioWindowView())
            // Let SwiftUI's .toolbar and .navigationTitle drive the real window toolbar.
            controller.sceneBridgingOptions = [.toolbars, .title]
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.contentViewController = controller
            win.title = "PanaLux"
            win.toolbarStyle = .unified
            // The panel drawing and HUD are designed on dark; match them.
            win.appearance = NSAppearance(named: .darkAqua)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.setFrameAutosaveName("PanaLuxMainWindow")
            if !win.setFrameUsingName("PanaLuxMainWindow") {
                win.center()
            }
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func windowWillClose(_ notification: Notification) {
        GuideController.shared.walkthroughStep = nil
        // Back to a menu bar app: no Dock icon while the window is closed.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
