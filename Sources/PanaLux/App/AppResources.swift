import Foundation

/// Finds bundled resources without `Bundle.module`, which traps if the SwiftPM
/// resource bundle is missing from a hand-assembled .app.
public enum AppResources {
    public static let bundleName = "PanaLux_PanaLux.bundle"

    private static let searchRoots: [URL] = {
        var roots: [URL] = []
        if let res = Bundle.main.resourceURL {
            roots.append(res)
            roots.append(res.appendingPathComponent(bundleName))
        }
        let exeDir = Bundle.main.bundleURL
        roots.append(exeDir.appendingPathComponent(bundleName))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(exe.appendingPathComponent(bundleName))
        }
        // `swift test`: the resource bundle sits next to the .xctest bundle.
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            roots.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName))
        }
        return roots
    }()

    public static func url(_ name: String, _ ext: String) -> URL? {
        let fm = FileManager.default
        for root in searchRoots {
            for sub in ["", "Resources", "Contents/Resources"] {
                let dir = sub.isEmpty ? root : root.appendingPathComponent(sub)
                let candidate = dir.appendingPathComponent("\(name).\(ext)")
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    public static func data(_ name: String, _ ext: String) -> Data? {
        guard let url = url(name, ext) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func string(_ name: String, _ ext: String) -> String? {
        guard let url = url(name, ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// On-disk locations. Everything lives under ~/Library/Application Support/PanaLux.
public enum AppPaths {
    public static let appName = "PanaLux"
    public static let bundleID = "com.panalux.app"
    public static let panelLockPath = "/tmp/panalux-panel.lock"

    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static var profileURL: URL { supportDir.appendingPathComponent("profile.json") }
    public static var homeURL: URL { supportDir.appendingPathComponent("home.json") }
    public static var backupsDir: URL { supportDir.appendingPathComponent("Backups", isDirectory: true) }
    public static var mapsDir: URL { supportDir.appendingPathComponent("Maps", isDirectory: true) }

    public static func ensureSupportDir() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }
}


/// Offscreen stills must never start hardware, sockets, or migrate the user's map.
enum AppRuntime {
    static var isRenderingStills: Bool {
        ProcessInfo.processInfo.environment["PANALUX_RENDER_DIR"] != nil
    }
}
