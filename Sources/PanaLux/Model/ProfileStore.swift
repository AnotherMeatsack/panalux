import Foundation

/// A map file people can share: `Name.panalux.json`.
/// Version 2 carries Fine speed, mask-knob layout, key calibration, and a readable guide
/// so another machine (or a human opening the file) gets the whole setup.
public struct SharedMap: Codable {
    public var format: String = "panalux-map"
    public var version: Int = 2
    public var name: String
    public var notes: String?
    public var app: String?
    public var build: String?
    public var exported: String?
    public var settings: SharedMapSettings?
    public var hardware: [String: String]?
    public var readme: [String]?
    public var profile: Profile
}

public struct SharedMapSettings: Codable, Equatable {
    public var masksMatchBase: Bool
    public var fine: Double
    public var focusDial: String

    enum CodingKeys: String, CodingKey {
        case masksMatchBase = "masks_match_base"
        case fine
        case focusDial = "focus_dial"
    }

    public static func current() -> SharedMapSettings {
        let s = AppSettings.shared
        return SharedMapSettings(
            masksMatchBase: s.mirrorMaskToBase,
            fine: s.fineMultiplier,
            focusDial: s.focusDialControl
        )
    }

    public func apply() {
        let s = AppSettings.shared
        s.mirrorMaskToBase = masksMatchBase
        s.fineMultiplier = fine
        s.focusDialControl = focusDial
    }
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
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let file = SharedMap(
            format: "panalux-map",
            version: 2,
            name: name,
            notes: "Drop this file on the PanaLux window, or Maps → Import. It is the full setup: every knob, ring, ball, key, and mode, plus Fine speed, mask knob layout, and key calibration.",
            app: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev",
            exported: iso.string(from: Date()),
            settings: SharedMapSettings.current(),
            hardware: HardwareMap.shared.exportBits(),
            readme: MapReadme.lines(for: profile),
            profile: profile
        )
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    /// JSON string for the pasteboard. Same contents as a `.panalux.json` file.
    public static func exportJSON(_ profile: Profile, name: String) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("panalux-export.json")
        try export(profile, name: name, to: url)
        return try Data(contentsOf: url)
    }

    /// Accepts a shared map or a bare profile (older exports, backups).
    public static func load(from url: URL) throws -> (name: String, profile: Profile) {
        let packet = try loadPacket(from: url)
        return (packet.name, packet.profile)
    }

    public static func loadPacket(from url: URL) throws -> SharedMap {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let fallbackName = url.lastPathComponent
            .replacingOccurrences(of: fileSuffix, with: "")
            .replacingOccurrences(of: ".json", with: "")
        if let shared = try? decoder.decode(SharedMap.self, from: data), shared.format == "panalux-map" {
            var packet = shared
            packet.profile = repaired(shared.profile)
            return packet
        }
        let bare = try decoder.decode(Profile.self, from: data)
        return SharedMap(name: fallbackName, profile: repaired(bare))
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

/// Plain-language lines stored in a map file so a person can read the setup without running PanaLux.
public enum MapReadme {
    public static func lines(for profile: Profile) -> [String] {
        let db = CommandDatabase.shared
        var lines: [String] = []
        lines.append("Base")
        for (i, id) in PanelLayout.knobs.enumerated() {
            if let p = profile.knobs[id]?.param {
                lines.append("  Knob \(i + 1)  \(db.label(for: p))")
            }
        }
        for id in PanelLayout.rings {
            if let p = profile.rings[id]?.param {
                lines.append("  \(PanelLayout.shortLabel(forControl: id))  \(db.label(for: p))")
            }
        }
        for id in PanelLayout.balls {
            lines.append("  \(PanelLayout.shortLabel(forControl: id))  \(ballLine(profile.balls[id], db: db))")
        }
        lines.append("Keys")
        for id in PanelLayout.allButtons {
            guard let spec = profile.buttons[id], spec.hasAnyAssignment else { continue }
            let tap = tapLine(spec)
            let hold = holdLine(spec)
            var bits: [String] = []
            if !tap.isEmpty { bits.append("tap \(tap)") }
            if !hold.isEmpty { bits.append("hold \(hold)") }
            if bits.isEmpty { continue }
            lines.append("  \(PanelLayout.label(forControl: id))  \(bits.joined(separator: " · "))")
        }
        let order = ["MIXER", "TRANSFORM", "OFFSET", "MASK", "CROP", "CULL", "MULTISELECT", "TONE", "DETAIL", "EFFECTS", "LENS", "PRESETS"]
        let rest = profile.layers.keys.filter { !order.contains($0) }.sorted()
        for layerName in order + rest {
            guard let layer = profile.layers[layerName] else { continue }
            let title = layer.title ?? LayerNames.defaultTitle(layerName)
            lines.append(title)
            if let knobs = layer.knobs {
                for (i, id) in PanelLayout.knobs.enumerated() {
                    if let p = knobs[id]?.param {
                        lines.append("  Knob \(i + 1)  \(db.label(for: p))")
                    }
                }
            }
            if let rings = layer.rings {
                for id in PanelLayout.rings {
                    if let p = rings[id]?.param {
                        lines.append("  \(PanelLayout.shortLabel(forControl: id))  \(db.label(for: p))")
                    }
                }
            }
            if let balls = layer.balls {
                for id in PanelLayout.balls {
                    if let b = balls[id] {
                        lines.append("  \(PanelLayout.shortLabel(forControl: id))  \(ballLine(b, db: db))")
                    }
                }
            }
            if let buttons = layer.buttons {
                for id in PanelLayout.allButtons {
                    guard let spec = buttons[id], spec.hasAnyAssignment else { continue }
                    let tap = tapLine(spec)
                    let hold = holdLine(spec)
                    var bits: [String] = []
                    if !tap.isEmpty { bits.append("tap \(tap)") }
                    if !hold.isEmpty { bits.append("hold \(hold)") }
                    if bits.isEmpty { continue }
                    lines.append("  \(PanelLayout.label(forControl: id))  \(bits.joined(separator: " · "))")
                }
            }
        }
        return lines
    }

    private static func ballLine(_ b: BallBinding?, db: CommandDatabase) -> String {
        guard let b else { return "-" }
        if let p = b.param, !p.isEmpty {
            return db.label(for: p)
        }
        return "\(db.label(for: b.hue)) / \(db.label(for: b.sat))"
    }

    private static func tapLine(_ b: ButtonBinding) -> String {
        let db = CommandDatabase.shared
        if let a = b.action { return db.label(for: a) }
        if b.ps != nil { return "Photoshop Open as Layers" }
        if let l = b.layer { return "toggle \(LayerNames.defaultTitle(l))" }
        if let v = b.set_variant { return "bank \(v)" }
        if let prog = b.tapProgram { return prog.summary }
        if let enter = b.enter_layer { return "enter \(LayerNames.defaultTitle(enter))" }
        return ""
    }

    private static func holdLine(_ b: ButtonBinding) -> String {
        let db = CommandDatabase.shared
        if let l = b.hold_layer { return LayerNames.defaultTitle(l) }
        if b.hold_picker != nil { return "mask tool wheel" }
        if b.modifier != nil { return "Fine" }
        if let a = b.hold_action { return db.label(for: a) }
        if let prog = b.holdProgram { return prog.summary }
        return ""
    }
}
