import AppKit
import Combine
import SwiftUI

struct CommunityMapEntry: Codable, Identifiable {
    var id: String
    var name: String
    var author: String
    var summary: String
    var file: String
}

@MainActor final class MapLibrary: ObservableObject {
    @Published var maps: [SharedMap] = []
    @Published var files: [URL] = []
    @Published var community: [CommunityMapEntry] = []
    @Published var status = ""
    @Published var loading = false
    static let repository = "https://github.com/AnotherMeatsack/panalux"
    static let base = URL(string: "https://raw.githubusercontent.com/AnotherMeatsack/panalux/main/CommunityMaps/")!

    init() { reload() }
    func reload() {
        let entries = ProfileStore.savedMaps().compactMap { file -> (URL, SharedMap)? in
            guard let map = try? ProfileStore.loadPacket(from: file.url) else { return nil }
            return (file.url, map)
        }
        files = entries.map(\.0); maps = entries.map(\.1)
    }
    @discardableResult func save(_ packet: SharedMap) throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.mapsDir, withIntermediateDirectories: true)
        let name = ProfileStore.safeFileName(packet.name)
        var url = AppPaths.mapsDir.appendingPathComponent(name + ProfileStore.fileSuffix)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = AppPaths.mapsDir.appendingPathComponent(name + " (\(n))" + ProfileStore.fileSuffix); n += 1
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(packet).write(to: url, options: .atomic)
        reload(); return url
    }
    func rename(_ index: Int, to name: String, notes: String? = nil) throws {
        guard maps.indices.contains(index), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var packet = maps[index]; packet.name = name; packet.notes = notes
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(packet).write(to: files[index], options: .atomic)
        reload()
    }
    func refreshCommunity() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let data = try await fetch("index.json")
            community = try JSONDecoder().decode([CommunityMapEntry].self, from: data)
            status = community.isEmpty ? "No community submissions yet. Share the first one." : "Reviewed community maps"
        } catch { status = "Community is unavailable right now. Your saved maps and file imports still work." }
    }
    func download(_ entry: CommunityMapEntry) async throws -> SharedMap {
        let data = try await fetch(entry.file)
        let packet = try JSONDecoder().decode(SharedMap.self, from: data)
        guard packet.format == "panalux-map", packet.version <= 2 else { throw CocoaError(.fileReadCorruptFile) }
        return packet
    }
    private func fetch(_ file: String) async throws -> Data {
        guard !file.contains("/"), !file.contains("\\"), !file.contains(".."), file.hasSuffix(".json") else { throw CocoaError(.fileReadInvalidFileName) }
        var request = URLRequest(url: Self.base.appendingPathComponent(file))
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    static func submissionURL(name: String, notes: String) -> URL {
        var url = URLComponents(string: repository + "/issues/new")!
        url.queryItems = [URLQueryItem(name: "title", value: "[Map] " + name), URLQueryItem(name: "body", value: "## Map name\n" + name + "\n\n## What it helps with\n" + notes + "\n\n## Attach your exported .panalux.json file below\n\n\n## Sharing permission\nI created this map and agree to share it in the public PanaLux gallery under the repository’s MIT license.\n\nPlease review this statement before submitting; remove it if you do not agree.")]
        return url.url!
    }
}

struct FeatureSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    var onCancel: (() -> Void)? = nil
    @State private var title = ""
    @State private var workflow = ""
    @State private var idea = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Suggest a Feature", systemImage: "lightbulb.fill").font(.title.bold())
            Text("What would make your panel better? Describe the result you want.").foregroundStyle(.secondary)
            TextField("Give your idea a short name", text: $title)
            TextField("What are you trying to do?", text: $workflow)
            TextEditor(text: $idea).frame(height: 150).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
            Text("Opens a public GitHub draft. A GitHub account is required. You review and submit it yourself; nothing is sent automatically.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { if let onCancel { onCancel() } else { dismiss() } }; Spacer()
                Button("Review on GitHub") {
                    var url = URLComponents(string: MapLibrary.repository + "/issues/new")!
                    url.queryItems = [URLQueryItem(name: "title", value: "[Feature] " + title), URLQueryItem(name: "body", value: "## Workflow\n" + workflow + "\n\n## Suggested improvement\n" + idea)]
                    if let target = url.url { NSWorkspace.shared.open(target) }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 510)
    }
}

@MainActor final class FeatureSuggestionWindow {
    static let shared = FeatureSuggestionWindow()
    private var window: NSWindow?
    func show() {
        ContactWindowController.shared.show(kind: .idea)
    }
    func showLegacy() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Suggest a Feature"; w.contentView = NSHostingView(rootView: FeatureSuggestionView(onCancel: { [weak w] in w?.close() }))
            w.isReleasedWhenClosed = false; w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
