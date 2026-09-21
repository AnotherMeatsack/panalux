import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything reads settings or the map.
        AppPaths.ensureSupportDir()
        SingleInstance.enter()
        ProfileStore.backup(reason: "launch")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = StudioEngine.shared
        _ = AppCoordinator.shared

        NotchHUDWindowController.shared.setup()
        ToolWheelWindowController.shared.setup()
        RewindEdgeWindowController.shared.setup()
        MenuBarController.shared.setup()
        AppUpdater.shared.start()

        let settings = AppSettings.shared
        let firstRun = !settings.hasCompletedOnboarding
        let atLogin = Self.launchedAtLogin
        if firstRun || FeatureWalkthroughController.shared.pending || (settings.showWindowAtLaunch && !atLogin) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                StudioWindowController.shared.show()
                FeatureWalkthroughController.shared.presentAutomatically()
                if firstRun {
                    GuideController.shared.presentSetup()
                }
            }
        }
    }

    /// Login items launch without a user click; stay in the menu bar and leave focus with Lightroom.
    /// Only valid while the launch event is being handled.
    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StudioWindowController.shared.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Double-clicked or dropped `.panalux.json` maps.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            StudioWindowController.shared.show()
            MapImporter.confirmAndImport(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Profile.save(StudioEngine.shared.profile)
        // The trail has to outlive quitting, so this one waits.
        RewindEngine.shared.flush(synchronously: true)
        PanelManager.shared.setLEDs(activeBits: [])
    }
}

@main
struct PanaLuxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Import with a confirmation. The current map is backed up first and the import is undoable.
public enum MapImporter {
    public static func confirmAndImport(_ url: URL) {
        do {
            let packet = try ProfileStore.loadPacket(from: url)
            let alert = NSAlert()
            alert.messageText = "Use the map “\(packet.name)”?"
            var info = "Your current map is backed up first. You can undo with ⌘Z or restore it from Settings → Maps."
            if packet.settings != nil || packet.hardware != nil {
                info += " Fine speed, mask knob layout, and key calibration in this file are applied too."
            }
            alert.informativeText = info
            alert.addButton(withTitle: "Use Map")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            StudioEngine.shared.replaceProfile(packet.profile, reason: "before import")
            packet.settings?.apply()
            if let bits = packet.hardware {
                HardwareMap.shared.applyShared(bits)
            }
            StudioEngine.shared.mapStatusMessage = "Loaded “\(packet.name)”"
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "That file isn’t a PanaLux map."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    public static func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppPaths.mapsDir
        if panel.runModal() == .OK, let url = panel.url {
            confirmAndImport(url)
        }
    }

    public static func chooseAndExport() {
        let panel = NSSavePanel()
        panel.title = "Export Map"
        panel.nameFieldStringValue = "My Map" + ProfileStore.fileSuffix
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message = "This file is the whole setup. Anyone can drop it on PanaLux to load it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
            .replacingOccurrences(of: ProfileStore.fileSuffix, with: "")
            .replacingOccurrences(of: ".json", with: "")
        do {
            try ProfileStore.export(StudioEngine.shared.profile, name: name, to: url)
            StudioEngine.shared.mapStatusMessage = "Exported “\(name)”"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    public static func copyCurrentMap() {
        do {
            let name = "PanaLux Map"
            try FileManager.default.createDirectory(at: AppPaths.mapsDir, withIntermediateDirectories: true)
            let url = AppPaths.mapsDir.appendingPathComponent(name + ProfileStore.fileSuffix)
            try ProfileStore.export(StudioEngine.shared.profile, name: name, to: url)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
            if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                pb.setString(text, forType: .string)
            }
            StudioEngine.shared.mapStatusMessage = "Map copied · paste a message or drop the file"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
