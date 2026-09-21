import AppKit
import Foundation

/// One-click bug report. Opens a GitHub issue with diagnostics already filled in.
/// No home-folder paths. The map is a separate Finder file they can attach.
public enum BugReport {
    public static let github = "https://github.com/AnotherMeatsack/panalux"
    public static let newIssue = github + "/issues/new"

    public static func present() {
        Task { @MainActor in ContactWindowController.shared.show(kind: .bug) }
    }

    static func presentLegacyAlert() {
        let alert = NSAlert()
        alert.messageText = "Report a bug"
        alert.informativeText = "Write what happened. PanaLux adds version, connections, and the active mode. You can attach your map on GitHub if the bug is about mapping."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Copy Report")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 72))
        field.placeholderString = "What went wrong?"
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        let choice = alert.runModal()
        let what = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = markdown(whatHappened: what)
        switch choice {
        case .alertFirstButtonReturn:
            writeMapForAttach()
            openGitHub(title: title(from: what), body: body)
        case .alertSecondButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            StudioEngine.shared.mapStatusMessage = "Bug report copied"
        default:
            break
        }
    }

    public static func diagnostics() -> String {
        let engine = StudioEngine.shared
        let panel = PanelManager.shared
        let coord = AppCoordinator.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        var rows: [(String, String)] = [
            ("PanaLux", "\(version) (\(build))"),
            ("macOS", osText),
            ("Panel", panel.isReleased ? "handed to Resolve" : (panel.isConnected ? "connected" : "not found")),
            ("Lightroom", LightroomBridge.shared.isConnected ? "connected" : (coord.isLightroomRunning ? "open, plugin waiting" : "not open")),
            ("Plugin", coord.isBridgeInstalled ? "PanaLux Bridge" : (coord.isPluginInstalled ? "MIDI2LR" : "not installed")),
            ("Resolve", coord.isResolveRunning ? "open" : "not open"),
            ("Mode", engine.statusMessage),
            ("Output", engine.isOutputPaused ? "paused" : (engine.isLiveGradingEnabled ? "live" : "safe setup")),
            ("Accessibility", coord.isAccessibilityTrusted ? "allowed" : "not allowed")
        ]
        if coord.isMIDI2LRAppRunning {
            rows.append(("MIDI2LR app", "running (quit it so PanaLux can talk to Lightroom)"))
        }
        return rows.map { "- \($0): \($1)" }.joined(separator: "\n")
    }

    private static func markdown(whatHappened: String) -> String {
        var parts: [String] = []
        if !whatHappened.isEmpty {
            parts.append(whatHappened)
            parts.append("")
        }
        parts.append("### Setup")
        parts.append(diagnostics())
        parts.append("")
        parts.append("A `.panalux.json` map is in Finder if you want to attach it.")
        return parts.joined(separator: "\n")
    }

    private static func title(from what: String) -> String {
        let trimmed = what.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Bug" }
        if trimmed.count <= 72 { return trimmed }
        return String(trimmed.prefix(69)) + "..."
    }

    private static func openGitHub(title: String, body: String) {
        var parts = URLComponents(string: newIssue)!
        parts.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = parts.url {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    private static func writeMapForAttach() -> URL? {
        let dir = AppPaths.mapsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("PanaLux bug map" + ProfileStore.fileSuffix)
        do {
            try ProfileStore.export(StudioEngine.shared.profile, name: "Bug report map", to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return url
        } catch {
            return nil
        }
    }
}
