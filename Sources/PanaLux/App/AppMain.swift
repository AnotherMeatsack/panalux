import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything reads settings or the map.
        AppPaths.ensureSupportDir()
        ProfileStore.backup(reason: "launch")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = StudioEngine.shared
        _ = AppCoordinator.shared

        NotchHUDWindowController.shared.setup()
        ToolWheelWindowController.shared.setup()
        MenuBarController.shared.setup()

        let settings = AppSettings.shared
        let firstRun = !settings.hasCompletedOnboarding
        let atLogin = Self.launchedAtLogin
        if firstRun || (settings.showWindowAtLaunch && !atLogin) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                StudioWindowController.shared.show()
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
            let (name, profile) = try ProfileStore.load(from: url)
            let alert = NSAlert()
            alert.messageText = "Use the map “\(name)”?"
            alert.informativeText = "Your current map is backed up first. You can undo with ⌘Z or restore it from Settings → Maps."
            alert.addButton(withTitle: "Use Map")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            StudioEngine.shared.replaceProfile(profile, reason: "before import")
            StudioEngine.shared.mapStatusMessage = "Loaded “\(name)”"
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
        panel.nameFieldStringValue = "My Map" + ProfileStore.fileSuffix
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
            .replacingOccurrences(of: ProfileStore.fileSuffix, with: "")
            .replacingOccurrences(of: ".json", with: "")
        do {
            try ProfileStore.export(StudioEngine.shared.profile, name: name, to: url)
            StudioEngine.shared.mapStatusMessage = "Exported “\(name)”"
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
