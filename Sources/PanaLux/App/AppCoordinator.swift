import Foundation
import AppKit
import Combine
import ApplicationServices

/// Watches the other apps PanaLux works with and hands the panel to Resolve when asked.
public class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    @Published public var isResolveRunning: Bool = false
    @Published public var isLightroomRunning: Bool = false
    @Published public var isPhotoshopRunning: Bool = false
    /// The MIDI2LR desktop app competes for the plugin's connection. PanaLux replaces it.
    @Published public var isMIDI2LRAppRunning: Bool = false
    /// PanaLux Bridge or a regular MIDI2LR plugin is in Lightroom's Modules folder.
    @Published public var isPluginInstalled: Bool = false
    @Published public var isBridgeInstalled: Bool = false
    /// The installed bridge differs from the one inside this app (older PanaLux).
    @Published public var isBridgeOutdated: Bool = false
    /// A regular MIDI2LR plugin is installed; it launches the MIDI2LR app, which takes the connection.
    @Published public var isStockMIDI2LRInstalled: Bool = false
    /// Lightroom was running before the bridge was installed, so it hasn't loaded it yet.
    @Published public var needsLightroomRestart: Bool = false
    @Published public var isAccessibilityTrusted: Bool = false
    @Published public var conflictingProcessPID: Int32? = nil


    private var timer: Timer?
    private var releasedForResolve = false

    private init() {
        guard !AppRuntime.isRenderingStills else { return }
        checkRunningApps()
        startMonitoring()
    }

    public func startMonitoring() {
        timer?.invalidate()
        timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkRunningApps()
        }
        // .common, not the default mode: a timer in the default mode stops firing
        // while a menu is open or a list is being scrolled.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private static func matches(_ app: NSRunningApplication, _ needles: [String]) -> Bool {
        let id = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""
        return needles.contains { id.contains($0) || name.contains($0) }
    }

    public func checkRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
        let resolve = apps.contains { Self.matches($0, ["davinciresolve", "davinci resolve"]) }
        let lightroom = apps.contains { Self.matches($0, ["lightroomclassic", "lightroom classic"]) }
        let photoshop = apps.contains { Self.matches($0, ["photoshop"]) }
        let midi2lr = apps.contains { app in
            let name = app.localizedName?.lowercased() ?? ""
            let id = app.bundleIdentifier?.lowercased() ?? ""
            return name == "midi2lr" || id.hasSuffix(".midi2lr")
        }

        var pid: Int32? = nil
        if let content = try? String(contentsOfFile: AppPaths.panelLockPath, encoding: .utf8) {
            let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if parts.count >= 2, let parsedPid = Int32(parts[1]),
               parsedPid != getpid(), kill(parsedPid, 0) == 0 {
                pid = parsedPid
            }
        }

        let bridge = FileManager.default.fileExists(atPath: Self.bridgeInstallURL.path)
        let stock = Self.findStockPlugin() != nil
        let outdated = bridge && !Self.installedBridgeMatchesBundle()
        let trusted = AXIsProcessTrusted()

        DispatchQueue.main.async {
            self.isResolveRunning = resolve
            self.isLightroomRunning = lightroom
            self.isPhotoshopRunning = photoshop
            self.isMIDI2LRAppRunning = midi2lr
            self.isBridgeInstalled = bridge
            self.isStockMIDI2LRInstalled = stock
            self.isBridgeOutdated = outdated
            self.isPluginInstalled = bridge || stock
            if !lightroom { self.needsLightroomRestart = false }
            self.isAccessibilityTrusted = trusted
            self.conflictingProcessPID = pid
            self.handleResolve(running: resolve)
        }
    }

    private func handleResolve(running: Bool) {
        let settings = AppSettings.shared
        if running && settings.autoCloseResolve {
            closeDaVinciResolve()
            return
        }
        if running && settings.handPanelToResolve && !releasedForResolve {
            releasedForResolve = true
            releasePanel()
        } else if !running && releasedForResolve {
            releasedForResolve = false
            // Give Resolve a moment to let go of the USB interface.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.reclaimPanel() }
        }
    }

    public func releasePanel() {
        StudioEngine.shared.returnToBase(announce: false)
        PanelManager.shared.release()
    }

    public func reclaimPanel() {
        PanelManager.shared.reclaim()
    }

    public static var modulesDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Adobe/Lightroom/Modules", isDirectory: true)
    }
    
    public static let bridgeName = "PanaLux Bridge.lrplugin"
    public static var bridgeInstallURL: URL { modulesDir.appendingPathComponent(bridgeName, isDirectory: true) }
    public static var bundledBridgeURL: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let url = res.appendingPathComponent(bridgeName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Every file in the bundled plugin must match the installed one, and the installed one must
    /// have nothing else. Comparing only three files let a changed Lua file go unnoticed.
    static func installedBridgeMatchesBundle() -> Bool {
        guard let bundled = bundledBridgeURL else { return true }
        return pluginFolder(bundled, matches: bridgeInstallURL)
    }

    static func pluginFolder(_ a: URL, matches b: URL) -> Bool {
        func files(_ root: URL) -> [String: Data] {
            var out: [String: Data] = [:]
            let base = root.resolvingSymlinksInPath().path
            guard let walker = FileManager.default.enumerator(at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey]) else { return out }
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      url.lastPathComponent != ".DS_Store" else { continue }
                let rel = String(url.resolvingSymlinksInPath().path.dropFirst(base.count))
                out[rel] = try? Data(contentsOf: url)
            }
            return out
        }
        return files(a) == files(b)
    }

    /// Copy the plugin that ships inside PanaLux into Lightroom's Modules folder.
    @discardableResult
    public func installBridge() -> Bool {
        guard let source = Self.bundledBridgeURL else {
            showError("The Lightroom plugin is missing from this copy of PanaLux. Download PanaLux again.")
            return false
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.modulesDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: Self.bridgeInstallURL.path) {
                try fm.removeItem(at: Self.bridgeInstallURL)
            }
            try fm.copyItem(at: source, to: Self.bridgeInstallURL)
            needsLightroomRestart = isLightroomRunning
            checkRunningApps()
            return true
        } catch {
            showError("Couldn’t install the Lightroom plugin: \(error.localizedDescription)")
            return false
        }
    }
    
    /// A regular MIDI2LR plugin makes Lightroom open the MIDI2LR app, which takes PanaLux’s connection.
    /// Move it aside (not deleted) so it can be put back from Finder.
    public func disableStockMIDI2LR() {
        guard let stock = Self.findStockPlugin() else { return }
        let alert = NSAlert()
        alert.messageText = "Turn off the MIDI2LR plugin?"
        alert.informativeText = "It opens the MIDI2LR app whenever Lightroom starts, and that app takes the connection PanaLux needs. PanaLux Bridge does the same job. The plugin is moved to PanaLux’s folder, not deleted, so you can put it back later."
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let dest = AppPaths.supportDir.appendingPathComponent("Turned Off Plugins", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let target = dest.appendingPathComponent(stock.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: stock, to: target)
            quitMIDI2LRApp()
            needsLightroomRestart = isLightroomRunning
            checkRunningApps()
        } catch {
            showError("Couldn’t move the MIDI2LR plugin: \(error.localizedDescription)")
        }
    }
    
    /// Lightroom loads plugins at launch. Ask first: it may be in the middle of something.
    public func restartLightroom() {
        let alert = NSAlert()
        alert.messageText = "Restart Lightroom Classic?"
        alert.informativeText = "Lightroom loads plugins when it starts. It saves your catalog as it quits."
        alert.addButton(withTitle: "Restart Lightroom")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let running = NSWorkspace.shared.runningApplications.filter { Self.matches($0, ["lightroomclassic", "lightroom classic"]) }
        running.forEach { $0.terminate() }
        DispatchQueue.global().async {
            for _ in 0..<120 where running.contains(where: { !$0.isTerminated }) {
                Thread.sleep(forTimeInterval: 0.5)
            }
            DispatchQueue.main.async {
                guard running.allSatisfy(\.isTerminated) else {
                    self.showError("Lightroom is still open. Finish any dialogs in Lightroom, then try Restart Lightroom again.")
                    return
                }
                self.needsLightroomRestart = false
                self.launchLightroomClassic()
            }
        }
    }
    
    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text
        alert.runModal()
    }
    
    /// The regular MIDI2LR plugin, wherever its installer put it.
    public static func findStockPlugin() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            "Library/Application Support/Adobe/Lightroom/Modules/MIDI2LR.lrplugin",
            "Library/Application Support/Adobe/Lightroom/Modules/MIDI2LR.lrdevplugin"
        ].map { home.appendingPathComponent($0) }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    public func quitMIDI2LRApp() {
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName?.lowercased() ?? ""
            if name == "midi2lr" { app.terminate() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.checkRunningApps() }
    }

    public func closeDaVinciResolve() {
        for app in NSWorkspace.shared.runningApplications where Self.matches(app, ["davinciresolve", "davinci resolve"]) {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkRunningApps()
        }
    }

    public func launchLightroomClassic() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.adobe.LightroomClassicCC7") {
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
        let path = "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
        }
    }

    public func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Another copy of PanaLux holds the panel lock. Ask it to quit, then take over.
    public func reclaimPanelHardware() {
        guard let pid = conflictingProcessPID,
              let other = NSRunningApplication(processIdentifier: pid) else {
            conflictingProcessPID = nil
            return
        }
        other.terminate()
        conflictingProcessPID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PanelManager.shared.reclaim()
        }
    }
}
