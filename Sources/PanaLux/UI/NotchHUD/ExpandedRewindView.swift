import SwiftUI

/// A pinned mouse workspace inside the existing notch panel. Selecting a node only
/// inspects it; View and Merge are explicit edits to the Lightroom photo.
struct ExpandedRewindView: View {
    @ObservedObject var rewind = RewindEngine.shared
    @ObservedObject var studio = StudioEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sourceID = ""
    @State private var checked: Set<String> = []
    @State private var message = "Select a node to inspect its settings."
    @State private var confirmingDelete = false
    init(rewind: RewindEngine = .shared, initialSourceID: String = "") {
        self.rewind = rewind
        self._sourceID = State(initialValue: initialSourceID)
    }
    private var branches: [TrailBranch] { rewind.trail?.branches ?? [] }
    private var source: TrailBranch? { branches.first { $0.id == sourceID } }
    private var candidates: [String: Double] { rewind.mergeCandidates(from: sourceID) }
    private var blocked: Bool { studio.outputBlocked || rewind.trail == nil }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "backward.end.fill").font(.title2).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rewind+").font(.system(size: 23, weight: .bold, design: .rounded))
                    Text("Explore · connect · keep every direction").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Pinned open", systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
                Button { NotchHUDWindowController.shared.collapseRewind() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .help("Collapse Rewind+ · Escape").keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    transport
                    HStack(spacing: 18) {
                        Text("Hold Undo").fontWeight(.semibold)
                        ForEach(Array(PanelLayout.rings.enumerated()), id: \.offset) { index, id in
                            let command = studio.profile.layers["REWIND"]?.rings?[id]?.param ?? ""
                            Text(["Left", "Center", "Right"][index] + ": " + RewindCommands.title(command))
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Your editing branches").font(.headline)
                            Spacer()
                            Button("New Tangent", systemImage: "plus") { rewind.startBranch(reason: "New tangent") }
                                .disabled(blocked).keyboardShortcut("n", modifiers: [.command, .shift])
                        }
                        if branches.isEmpty {
                            Text("Select a photo in Lightroom to see its editing history.").foregroundStyle(.secondary).padding(24)
                        } else {
                            ScrollView([.horizontal, .vertical]) {
                                TangentNodeGraph(branches: branches, activeID: rewind.trail?.activeBranchID ?? "", selectedID: $sourceID)
                                    .padding(12)
                            }.frame(height: min(270, max(135, CGFloat(branches.count) * 88 + 24)))
                        }
                    }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    if let source { inspector(source) }
                    HStack {
                        Image(systemName: "info.circle")
                        Text(message).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if rewind.canRestoreDeletedTangent {
                            Button("Undo Delete") { rewind.restoreDeletedTangent(); message = "Tangent restored." }
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                    Text("Space: play/pause · ←/→: step · ⌘M: merge checked settings · ⇧⌘N: new tangent · ⌘⌫: delete selected leaf")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.bottom, 8)
            }
        }
        .padding(20)
        .background {
            ZStack {
                Color.black.opacity(0.35)
                LinearGradient(colors: [.cyan.opacity(0.13), .clear, .purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.16)))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .onChange(of: sourceID) { _, _ in checked = []; message = "Selecting a node does not change your photo. Choose View or merge checked sliders." }
        .onChange(of: rewind.photoID) { _, _ in sourceID = ""; checked = []; message = "Photo changed. Select a node to inspect it." }
        .confirmationDialog("Delete this tangent?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Tangent", role: .destructive) {
                if rewind.deleteTangent(sourceID) { sourceID = ""; message = "Tangent deleted. Undo Delete restores it during this session." }
            }
        } message: { Text("Only this inactive branch is removed. The current edit and other branches stay intact.") }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: sourceID)
    }

    private var transport: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rewind.state.branchName ?? "Original").font(.title3.bold())
                    Text(rewind.state.caption).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text("\(rewind.state.stepNumber) / \(rewind.state.stepCount)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Slider(value: Binding(get: {
                let span = rewind.state.tip - rewind.state.origin
                return span > 0 ? min(1, max(0, (rewind.state.playhead - rewind.state.origin) / span)) : 1
            }, set: { rewind.seekToFraction($0) }), in: 0...1) { editing in
                if !editing { rewind.pausePlayback(announce: false) }
            }.tint(.cyan).disabled(blocked || rewind.state.stepCount == 0)
                .accessibilityLabel("Position in editing history")
            HStack(spacing: 18) {
                Button { rewind.beginRewind(); rewind.step(forward: false) } label: { Image(systemName: "backward.end.fill") }
                    .keyboardShortcut(.leftArrow, modifiers: []).help("Previous edit")
                Button {
                    rewind.beginRewind()
                    if rewind.isPlaying { rewind.pausePlayback() } else { rewind.play(forward: true) }
                } label: { Label(rewind.isPlaying ? "Pause" : "Play", systemImage: rewind.isPlaying ? "pause.fill" : "play.fill") }
                    .keyboardShortcut(.space, modifiers: [])
                Button { rewind.beginRewind(); rewind.step(forward: true) } label: { Image(systemName: "forward.end.fill") }
                    .keyboardShortcut(.rightArrow, modifiers: []).help("Next edit")
                Button("Mark", systemImage: "bookmark") { rewind.mark() }
                Spacer()
                Text("\(RewindEngine.clock(rewind.state.playhead)) / \(RewindEngine.clock(rewind.state.tip))").monospacedDigit().foregroundStyle(.secondary)
                Button("Latest", systemImage: "forward.end") { rewind.beginRewind(); rewind.jumpToTip() }
            }.disabled(blocked)
        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func inspector(_ source: TrailBranch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(source.name).font(.headline)
                Spacer()
                Button("View This Tangent") { rewind.selectTangent(source.id); checked = []; message = "Viewing “\(source.name)” in Lightroom." }
                    .disabled(blocked || source.id == rewind.trail?.activeBranchID)
                Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }
                    .disabled(blocked || !rewind.canDeleteTangent(source.id))
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete an inactive leaf. Original, current, and branches used by other tangents are protected.")
            }
            if source.id == rewind.trail?.activeBranchID {
                Text("This is your current edit. Select another node to merge settings into a new result.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Label(source.name, systemImage: "circle.hexagongrid.fill")
                    Image(systemName: "plus")
                    Text(rewind.trail?.activeBranch.name ?? "Current")
                    Image(systemName: "arrow.right")
                    Label("New result", systemImage: "sparkles").foregroundStyle(.cyan)
                }.font(.callout.bold()).lineLimit(1)
                Text("Choose the sliders to bring over. Both originals stay saved. Masks and crop are excluded.")
                    .font(.callout).foregroundStyle(.secondary)
                if candidates.isEmpty {
                    Text("No different recorded sliders to merge.").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Select All") { checked = Set(candidates.keys) }
                        Button("Clear") { checked = [] }
                        Spacer()
                        Button("Merge \(checked.intersection(candidates.keys).count) Settings", systemImage: "arrow.triangle.merge") {
                            if rewind.mergeParameters(from: source.id, names: checked) {
                                sourceID = rewind.trail?.activeBranchID ?? ""; checked = []
                                message = "New merged result created. Both original branches are kept."
                            }
                        }.buttonStyle(.borderedProminent).tint(.cyan)
                            .disabled(blocked || checked.intersection(candidates.keys).isEmpty)
                            .keyboardShortcut("m", modifiers: .command)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(candidates.keys.sorted(), id: \.self) { key in
                            Toggle(isOn: Binding(get: { checked.contains(key) }, set: { if $0 { checked.insert(key) } else { checked.remove(key) } })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(CommandDatabase.shared.label(for: key)).lineLimit(1)
                                    Text(ValueFormatter.format(param: key, value: candidates[key] ?? 0)).font(.caption).foregroundStyle(.cyan)
                                }
                            }.toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct TangentNodeGraph: View {
    let branches: [TrailBranch]
    let activeID: String
    @Binding var selectedID: String
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var positions: [String: CGPoint] { Self.positions(for: branches) }
    static func positions(for branches: [TrailBranch]) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        for (index, branch) in branches.enumerated() {
            let parentX = branch.parent.flatMap { result[$0]?.x } ?? -110
            result[branch.id] = CGPoint(x: min(parentX + 200, 710), y: CGFloat(index) * 88 + 40)
        }
        return result
    }
    var body: some View {
        let points = positions
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for branch in branches {
                    guard let to = points[branch.id] else { continue }
                    for parent in [branch.parent, branch.mergeSourceID].compactMap({ $0 }) {
                        guard let from = points[parent] else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: from.x + 76, y: from.y))
                        path.addCurve(to: CGPoint(x: to.x - 76, y: to.y),
                                      control1: CGPoint(x: from.x + 112, y: from.y),
                                      control2: CGPoint(x: to.x - 112, y: to.y))
                        context.stroke(path, with: .color(parent == branch.mergeSourceID ? .purple.opacity(0.8) : .cyan.opacity(0.55)), lineWidth: 2)
                    }
                }
            }
            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                let selected = selectedID == branch.id
                let active = activeID == branch.id
                Button { selectedID = branch.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: branch.mergeSourceID == nil ? "circle.dotted" : "arrow.triangle.merge")
                            Text(active ? "CURRENT" : (selected ? "SOURCE" : "TANGENT \(index + 1)"))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }.foregroundStyle(active ? .cyan : .secondary)
                        Text(branch.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    }.frame(width: 130, height: 48, alignment: .leading).padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Color.cyan : Color.white.opacity(active ? 0.4 : 0.15), lineWidth: selected ? 2 : 1))
                        .shadow(color: .cyan.opacity(selected ? 0.2 : 0), radius: 12)
                }.buttonStyle(.plain)
                    .scaleEffect(hovered == branch.id ? 1.035 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: hovered)
                    .onHover { inside in hovered = inside ? branch.id : nil }
                    .position(points[branch.id] ?? .zero)
                    .help(branch.name)
                    .accessibilityLabel(branch.name + (active ? ", current edit" : ", inspect tangent"))
            }
        }.frame(width: max(360, (points.values.map(\.x).max() ?? 90) + 95), height: max(90, CGFloat(branches.count) * 88))
    }
}
