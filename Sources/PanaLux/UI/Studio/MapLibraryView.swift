import SwiftUI
import UniformTypeIdentifiers

struct MapLibraryView: View {
    @ObservedObject var engine = StudioEngine.shared
    @StateObject private var library = MapLibrary()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source: SharedMap?
    @State private var selection = MapTransferSelection()
    @State private var name = "My Custom Setup"
    @State private var notes = ""
    @State private var search = ""
    @State private var message = "Select a setup, then choose the parts you want to borrow."
    @State private var suggestion = false
    @State private var showSave = false
    @State private var renameIndex: Int?
    @State private var activeName = "Current setup"
    @State private var targetHover = false
    @State private var focused: String?

    init(initialSource: SharedMap? = nil, initialSelection: MapTransferSelection = MapTransferSelection()) {
        _source = State(initialValue: initialSource)
        _selection = State(initialValue: initialSelection)
    }
    private var preview: MapTransferResult {
        MapTransfer.merge(source: source?.profile ?? engine.profile, into: engine.profile, selection: selection)
    }
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, idealWidth: 250, maxWidth: 290)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make it yours.").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Borrow a control. Blend a row. Keep your own way of working.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { suggestion = true } label: { Label("Suggest a Feature", systemImage: "lightbulb") }
                }
                HStack {
                    Picker("Copy", selection: $selection.slice) {
                        ForEach(MapSlice.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 390)
                    Spacer()
                    Button("Select All") {
                        selection.controls = Set(MapTransfer.controls.filter { selection.slice == .all || !PanelLayout.isAnalog($0) })
                        selection.combinations = Set((source?.profile.combinations ?? ButtonCombination.defaults).map(\.id))
                    }.disabled(source == nil)
                    Button("Clear") { selection.controls = []; selection.combinations = [] }
                }
                if let source {
                    HStack {
                        Text(source.notes ?? "Choose parts below, or save this whole setup to your collection.").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button("Save Source to My Setups") {
                            do { _ = try library.save(SharedMap(name: source.name, notes: source.notes, profile: source.profile)); message = "Saved source to My Setups." }
                            catch { message = error.localizedDescription }
                        }
                    }
                }
                ScrollView {
                    HStack(alignment: .top, spacing: 10) {
                        panel(profile: source?.profile ?? Profile.loadDefault(), title: source?.name ?? "Choose a source", incoming: true)
                        VStack {
                            Image(systemName: "arrow.right").font(.title2.bold()).foregroundStyle(.cyan)
                            Text("Preview").font(.caption2)
                        }.padding(.top, 95).frame(width: 42)
                        panel(profile: preview.profile, title: activeName, incoming: false)
                            .dropDestination(for: String.self) { items, _ in
                                guard source != nil else { return false }
                                var accepted = false
                                for item in items where item.hasPrefix("panalux-map-controls:") {
                                    let ids = String(item.dropFirst("panalux-map-controls:".count)).components(separatedBy: ",")
                                    selection.controls.formUnion(ids.filter { MapTransfer.controls.contains($0) && (selection.slice == .all || !PanelLayout.isAnalog($0)) })
                                    accepted = true
                                }
                                return accepted
                            } isTargeted: { targetHover = $0 }
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(targetHover ? Color.cyan : .clear, lineWidth: 3))
                    }
                    if let source { combinations(source.profile) }
                    if !preview.changes.isEmpty {
                        DisclosureGroup("Review \(preview.changes.count) transfers and included modes") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(preview.changes.enumerated()), id: \.offset) { _, change in Text(change).font(.caption) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding()
                    }
                }
                footer
            }.padding(24).frame(minWidth: 740)
        }
        .background(LinearGradient(colors: [Color.cyan.opacity(0.07), Color.purple.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(minWidth: 1000, minHeight: 680)
        .sheet(isPresented: $suggestion) { FeatureSuggestionView() }
        .sheet(isPresented: $showSave) { saveSheet }
        .onChange(of: selection.slice) { _, slice in
            if slice != .all { selection.controls = selection.controls.filter { !PanelLayout.isAnalog($0) } }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Map Library", systemImage: "square.grid.2x2.fill").font(.title2.bold())
            TextField("Search setups", text: $search)
            HStack {
                Button("Save Current…") { renameIndex = nil; name = "My Custom Setup"; notes = ""; showSave = true }
                Button { openFile() } label: { Image(systemName: "square.and.arrow.down") }.help("Preview a map file")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MY SETUPS").font(.caption.bold()).foregroundStyle(.secondary)
                    if library.maps.isEmpty { Text("Save your current setup to start your collection.").font(.callout).foregroundStyle(.secondary) }
                    ForEach(library.maps.indices, id: \.self) { i in
                        if matches(library.maps[i].name) { savedCard(i) }
                    }
                    Divider().padding(.vertical, 8)
                    HStack {
                        Text("COMMUNITY").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Button { Task { await library.refreshCommunity() } } label: { Image(systemName: "arrow.clockwise") }.disabled(library.loading)
                    }
                    Button("Explore Community Maps") { Task { await library.refreshCommunity() } }.disabled(library.loading)
                    if library.loading { ProgressView().controlSize(.small) }
                    Text(library.status.isEmpty ? "Browse reviewed maps without signing in." : library.status).font(.caption).foregroundStyle(.secondary)
                    ForEach(library.community.filter { matches($0.name + " " + $0.author + " " + $0.summary) }) { entry in
                        Button {
                            Task {
                                do { choose(try await library.download(entry)); message = "Previewing \(entry.name) by \(entry.author). Nothing applied yet." }
                                catch { message = "Couldn’t load this map: " + error.localizedDescription }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.name).font(.headline); Text("by " + entry.author).font(.caption)
                                Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.buttonStyle(.plain).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Button("Share Current Setup…") { renameIndex = nil; name = "My Custom Setup"; notes = ""; showSave = true }
            Text("Select to preview. Use switches your map. Merge applies only highlighted parts.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(.ultraThinMaterial)
    }
    private func matches(_ value: String) -> Bool { search.isEmpty || value.localizedCaseInsensitiveContains(search) }
    private func savedCard(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { choose(library.maps[i]) } label: {
                Label(library.maps[i].name, systemImage: "slider.horizontal.3").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            HStack {
                Button("Preview") { choose(library.maps[i]) }
                Button("Use") {
                    engine.replaceProfile(library.maps[i].profile, reason: "before setup switch")
                    activeName = library.maps[i].name; selection = MapTransferSelection()
                    message = "Using \(activeName). Your previous map is backed up and can be undone."
                }
                Spacer()
                Button { renameIndex = i; name = library.maps[i].name; notes = library.maps[i].notes ?? ""; showSave = true } label: { Image(systemName: "pencil") }
            }.controlSize(.small)
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    private func panel(profile: Profile, title: String, incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(incoming ? "THEIR SETUP" : "YOUR RESULT", systemImage: incoming ? "square.and.arrow.down" : "sparkles")
                .font(.caption.bold()).foregroundStyle(incoming ? Color.purple : Color.cyan)
            Text(title).font(.title3.bold()).lineLimit(2)
            Text(incoming ? "Click controls or drag a section to your panel." : "Highlighted controls are staged, not applied.").font(.caption).foregroundStyle(.secondary)
            section(profile, title: "Knob row", ids: PanelLayout.knobs, incoming: incoming, columns: 6)
            section(profile, title: "Knob presses", ids: PanelLayout.knobs.map { "PRESS_" + $0 }, incoming: incoming, columns: 6)
            section(profile, title: "Trackballs", ids: PanelLayout.balls, incoming: incoming, columns: 3)
            section(profile, title: "Luminance rings", ids: PanelLayout.rings, incoming: incoming, columns: 3)
            ForEach(PanelLayout.buttonGroups) { group in
                section(profile, title: group.title, ids: group.buttons.map(\.id), incoming: incoming, columns: 5)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.17)))
    }
    private func section(_ profile: Profile, title: String, ids: [String], incoming: Bool, columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.bold()); Spacer()
                if incoming {
                    Button { stage(ids) } label: { Image(systemName: "arrow.right.circle") }
                        .buttonStyle(.plain).help("Stage this section")
                        .disabled(source == nil || (selection.slice != .all && ids.allSatisfy { PanelLayout.isAnalog($0) }))
                }
            }.draggable(incoming && source != nil ? "panalux-map-controls:" + ids.joined(separator: ",") : "")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 6) {
                ForEach(ids, id: \.self) { id in control(profile, id: id, incoming: incoming) }
            }
        }
    }
    private func control(_ profile: Profile, id: String, incoming: Bool) -> some View {
        let selected = selection.controls.contains(id)
        let enabled = source != nil && (selection.slice == .all || !PanelLayout.isAnalog(id))
        return Button {
            focused = id
            if incoming && enabled {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76)) {
                    if selected { selection.controls.remove(id) } else { selection.controls.insert(id) }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: PanelLayout.isBall(id) ? "circle.inset.filled" : PanelLayout.isAnalog(id) ? "dial.medium" : "rectangle.roundedtop")
                    .font(.system(size: PanelLayout.isBall(id) ? 28 : 16))
                Text(PanelLayout.shortLabel(forControl: id).replacingOccurrences(of: "Press Knob", with: "Press"))
                    .font(.system(size: 9, weight: .semibold)).lineLimit(2).frame(height: 24)
            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(selected ? Color.cyan.opacity(0.24) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: PanelLayout.isBall(id) ? 24 : 8))
                .overlay(RoundedRectangle(cornerRadius: PanelLayout.isBall(id) ? 24 : 8).stroke(selected ? Color.cyan : .white.opacity(0.12), lineWidth: selected ? 2 : 1))
                .scaleEffect(selected ? 1.035 : 1)
        }.buttonStyle(.plain).opacity(incoming && !enabled ? 0.35 : 1)
            .help(PanelLayout.label(forControl: id) + "\n" + MapTransfer.label(profile, id, slice: selection.slice))
            .draggable(incoming && enabled ? "panalux-map-controls:" + id : "")
    }
    private func combinations(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Button combinations").font(.headline)
            Text("Bring over a gesture without replacing unrelated combinations.").font(.caption).foregroundStyle(.secondary)
            ForEach(profile.combinations ?? ButtonCombination.defaults) { combo in
                Toggle(isOn: Binding(get: { selection.combinations.contains(combo.id) }, set: { if $0 { selection.combinations.insert(combo.id) } else { selection.combinations.remove(combo.id) } })) {
                    HStack { Text(combo.title); Spacer(); Text(MapReadme.tapLine(combo.binding)).foregroundStyle(.secondary) }.font(.caption)
                }.toggleStyle(.checkbox)
            }
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let id = focused, let source {
                HStack {
                    Text(PanelLayout.label(forControl: id)).fontWeight(.semibold)
                    Text(MapTransfer.label(engine.profile, id, slice: selection.slice)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.cyan)
                    Text(MapTransfer.label(source.profile, id, slice: selection.slice)).foregroundStyle(.cyan)
                }.font(.caption).lineLimit(2)
            }
            Text(message).font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Calibration and personal app settings stay yours.").font(.caption)
                Spacer()
                Button("Undo Map Change") { engine.undoMapChange(); message = "Restored the previous map." }.disabled(!engine.canUndoMap)
                Button("Merge Selected") {
                    let result = preview
                    engine.replaceProfile(result.profile, reason: "before selective merge")
                    selection = MapTransferSelection(); message = "Merged selected parts. Save Current to name this new setup."
                }.buttonStyle(.borderedProminent).disabled(source == nil || preview.changes.isEmpty)
            }
        }
    }
    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(renameIndex == nil ? "Name your setup" : "Rename setup").font(.title2.bold())
            TextField("Setup name", text: $name)
            TextField("What makes this setup useful?", text: $notes)
            Text("Sharing exports a map file, then opens a public GitHub draft. Attach the file and submit it for review. No photos or panel calibration are included.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { showSave = false }; Spacer()
                if renameIndex == nil { Button("Export & Share…") { save(share: true) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Button(renameIndex == nil ? "Save Setup" : "Rename") { save(share: false) }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 520)
    }
    private func save(share: Bool) {
        do {
            if let index = renameIndex { try library.rename(index, to: name, notes: notes) }
            else {
                let packet = SharedMap(name: name, notes: notes, profile: engine.profile)
                _ = try library.save(packet)
                if share {
                    let panel = NSSavePanel(); panel.nameFieldStringValue = ProfileStore.safeFileName(name) + ProfileStore.fileSuffix
                    panel.allowedContentTypes = [.json]
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(packet).write(to: url, options: .atomic)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    NSWorkspace.shared.open(MapLibrary.submissionURL(name: name, notes: notes))
                }
            }
            message = "Saved “\(name)”."; showSave = false
        } catch { message = error.localizedDescription; showSave = false }
    }
    private func choose(_ packet: SharedMap) { source = packet; selection = MapTransferSelection(); focused = nil }
    private func stage(_ ids: [String]) {
        guard source != nil else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            selection.controls.formUnion(ids.filter { selection.slice == .all || !PanelLayout.isAnalog($0) })
        }
    }
    private func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { choose(try ProfileStore.loadPacket(from: url)); message = "File loaded for preview. Nothing applied yet." }
        catch { message = "Couldn’t read map: " + error.localizedDescription }
    }
}

@MainActor final class MapLibraryWindowController {
    static let shared = MapLibraryWindowController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "PanaLux · Map Library"; w.contentView = NSHostingView(rootView: MapLibraryView())
            w.minSize = NSSize(width: 1020, height: 720); w.isReleasedWhenClosed = false; w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
