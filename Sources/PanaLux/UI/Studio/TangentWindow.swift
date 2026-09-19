import SwiftUI
import AppKit

final class TangentWindowController {
    static let shared = TangentWindowController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Tangents"
            let hosting = NSHostingView(rootView: TangentManagerView())
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setContentSize(NSSize(width: 660, height: 620))
            window.minSize = NSSize(width: 560, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct TangentManagerView: View {
    @ObservedObject var engine = RewindEngine.shared
    @ObservedObject var studio = StudioEngine.shared
    @State private var sourceID = ""
    @State private var selected = Set<String>()
    @State private var name = ""
    @State private var result = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep every direction.").font(.title2.bold())
            Text("A tangent is another version of this photo. Rewind, stop where you like, then edit to start one. Your original stays saved.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let trail = engine.trail {
                HStack {
                    Text("Editing: \(trail.activeBranch.name)").font(.headline)
                    Spacer()
                    Button("New Tangent") { engine.startBranch(reason: "New tangent"); syncName() }
                        .disabled(studio.outputBlocked)
                }
                HStack {
                    TextField("Tangent name", text: $name)
                    Button("Rename") { engine.renameTangent(trail.activeBranchID, to: name) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Picker("Source tangent", selection: $sourceID) {
                    Text("Choose another tangent").tag("")
                    ForEach(trail.branches.filter { $0.id != trail.activeBranchID }) { branch in
                        Text(branch.name).tag(branch.id)
                    }
                }
                if !sourceID.isEmpty {
                    HStack {
                        Button("View This Tangent") {
                            engine.selectTangent(sourceID); sourceID = ""; selected = []; syncName()
                        }.disabled(studio.outputBlocked)
                        Text("Changes the photo to this saved version.").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Bring selected settings into a new tangent").font(.headline)
                    Text("Only the checked sliders change. Both source tangents are kept. Masks and crop are not copied by this merge.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    let values = engine.mergeCandidates(from: sourceID)
                    if values.isEmpty {
                        Text("No different recorded sliders are available to merge.").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Button("Select All") { selected = Set(values.keys) }
                            Button("Clear") { selected = [] }
                            Spacer()
                            Text("\(selected.count) selected").foregroundStyle(.secondary)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(values.keys.sorted(), id: \.self) { key in
                                    Toggle(isOn: Binding(get: { selected.contains(key) }, set: { on in
                                        if on { selected.insert(key) } else { selected.remove(key) }
                                    })) {
                                        HStack {
                                            Text(CommandDatabase.shared.label(for: key))
                                            Spacer()
                                            Text(ValueFormatter.format(param: key, value: values[key] ?? 0))
                                                .monospacedDigit().foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.padding(4)
                        }
                        Button("Merge \(selected.count) Settings into New Tangent") {
                            if engine.mergeParameters(from: sourceID, names: selected) {
                                result = "Merged. Both earlier tangents are still available."
                                selected = []; sourceID = ""; syncName()
                            }
                        }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || studio.outputBlocked)
                    }
                } else {
                    Text("Choose a source to compare its finished version or copy selected sliders.").foregroundStyle(.secondary)
                    Spacer()
                }
                if !result.isEmpty { Text(result).foregroundStyle(.secondary) }
            } else {
                ContentUnavailableView("Select a photo in Lightroom", systemImage: "photo",
                                       description: Text("PanaLux Bridge supplies the photo’s saved edit trail."))
            }
        }
        .padding(24)
        .onAppear { syncName() }
        .onChange(of: engine.photoID) { _, _ in sourceID = ""; selected = []; syncName() }
        .onChange(of: engine.trail?.activeBranchID) { _, active in
            syncName()
            if sourceID == active { sourceID = ""; selected = [] }
        }
        .onChange(of: sourceID) { _, _ in selected = []; result = "" }
    }
    private func syncName() { name = engine.trail?.activeBranch.name ?? "" }
}
