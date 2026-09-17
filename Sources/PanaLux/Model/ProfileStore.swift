import Foundation

/// A map file people can share: `Name.panalux.json`.
public struct SharedMap: Codable {
    public var format: String = "panalux-map"
    public var version: Int = 1
    public var name: String
    public var notes: String?
    public var profile: Profile
}

public struct MapFile: Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let date: Date
}

/// Backups, restore, and import/export. Everything is plain JSON in Application Support.
public enum ProfileStore {
    public static let fileSuffix = ".panalux.json"
    private static let maxBackups = 40

    // MARK: Backups

    /// Copy the saved map aside. Called on launch and before anything replaces the whole map.
    @discardableResult
    public static func backup(reason: String) -> URL? {
        let fm = FileManager.default
        let source = AppPaths.profileURL
        guard fm.fileExists(atPath: source.path) else { return nil }
        try? fm.createDirectory(at: AppPaths.backupsDir, withIntermediateDirectories: true)
        let dest = AppPaths.backupsDir.appendingPathComponent("\(stamp()) — \(reason).json")
        do {
            if let latest = backups().first,
               let a = try? Data(contentsOf: latest.url), let b = try? Data(contentsOf: source), a == b {
                return latest.url // identical to the newest backup; don't pile up copies
            }
            try fm.copyItem(at: source, to: dest)
            prune()
            return dest
        } catch {
            print("[ProfileStore] Backup failed: \(error)")
            return nil
        }
    }

    /// Move an unreadable file out of the way so nothing overwrites it.
    public static func quarantine(_ url: URL, reason: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.backupsDir, withIntermediateDirectories: true)
        let dest = AppPaths.backupsDir.appendingPathComponent("\(stamp()) — \(reason).json")
        try? fm.moveItem(at: url, to: dest)
    }

    public static func backups() -> [MapFile] {
        list(AppPaths.backupsDir, suffix: ".json")
    }

    private static func prune() {
        let all = backups()
        guard all.count > maxBackups else { return }
        for old in all.dropFirst(maxBackups) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    // MARK: Maps folder

    public static func savedMaps() -> [MapFile] {
        list(AppPaths.mapsDir, suffix: fileSuffix)
    }

    @discardableResult
    public static func saveToMaps(_ profile: Profile, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.mapsDir, withIntermediateDirectories: true)
        let url = AppPaths.mapsDir.appendingPathComponent(safeFileName(name) + fileSuffix)
        try export(profile, name: name, to: url)
        return url
    }

    // MARK: Import / export

    public static func export(_ profile: Profile, name: String, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = SharedMap(name: name, notes: "Made with PanaLux. Import from Settings → Maps, or drop this file on the PanaLux window.", profile: profile)
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    /// Accepts a shared map or a bare profile (older exports, backups).
    public static func load(from url: URL) throws -> (name: String, profile: Profile) {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let fallbackName = url.lastPathComponent
            .replacingOccurrences(of: fileSuffix, with: "")
            .replacingOccurrences(of: ".json", with: "")
        if let shared = try? decoder.decode(SharedMap.self, from: data), shared.format == "panalux-map" {
            return (shared.name, repaired(shared.profile))
        }
        let bare = try decoder.decode(Profile.self, from: data)
        return (fallbackName, repaired(bare))
    }

    /// Shared maps may come from older builds: fix renamed command IDs, keep factory layers they lack.
    private static func repaired(_ profile: Profile) -> Profile {
        var p = profile
        let factory = Profile.loadDefault()
        for (key, layer) in factory.layers where p.layers[key] == nil {
            p.layers[key] = layer
        }
        for (key, var spec) in p.buttons {
            if let a = spec.action, let fixed = Profile.renamedCommands[a] { spec.action = fixed }
            p.buttons[key] = spec
        }
        return p
    }

    // MARK: Helpers

    private static func list(_ dir: URL, suffix: String) -> [MapFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return urls
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let name = url.lastPathComponent.replacingOccurrences(of: suffix, with: "")
                return MapFile(url: url, name: name, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    public static func safeFileName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "My Map" : cleaned
    }
}
