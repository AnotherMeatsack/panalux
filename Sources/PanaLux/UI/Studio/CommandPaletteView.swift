import SwiftUI

/// ⌘K: find any Lightroom command, then run it, assign it, find it, or park it on a knob.
struct CommandPaletteView: View {
    @Binding var selectedControl: String?
    @ObservedObject var engine = StudioEngine.shared
    @ObservedObject var bridge = LightroomBridge.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var highlighted: String?
    @State private var uses: [StudioEngine.ControlUse] = []
    @State private var didFind = false
    @FocusState private var searchFocused: Bool

    private var results: [CatalogCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return ["Exposure", "Dehaze", "WhiteBalanceAuto", "AutoTone", "MaskNewSubject", "ChangeBrushSize",
                    "LensBlurAmount", "straightenAngle", "PresetPreviousNext", "openExportWithPreviousDialog"]
                .map { CommandDatabase.shared.catalogCommand(for: $0) }
        }
        return Array(CommandDatabase.shared.search(q, preferButtons: false).prefix(60))
    }

    private var current: CatalogCommand? {
        let list = results
        return list.first { $0.id == highlighted } ?? list.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Find a Lightroom command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($searchFocused)
                    .onSubmit(runDefault)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                List(results, selection: $highlighted) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .frame(width: 18)
                            .foregroundStyle(item.isParameter ? Color.orange : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).lineLimit(1)
                            Text(item.isParameter ? "Slider" : "Command")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(item.id)
                }
                .listStyle(.sidebar)
                .frame(width: 300)

                Divider()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
            }
        }
        .frame(width: 680, height: 440)
        .onAppear {
            searchFocused = true
            GuideController.shared.isEditingText = true
        }
        .onDisappear {
            GuideController.shared.isEditingText = false
            // Leave found controls glowing on the Map for a moment after the palette closes.
            let engine = engine
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { engine.foundControls = [] }
        }
        .onChange(of: query) { _, _ in
            highlighted = results.first?.id
            uses = []
            didFind = false
        }
        .onChange(of: highlighted) { _, _ in
            uses = []
            didFind = false
        }
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private var detail: some View {
        if let item = current {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.title2.weight(.semibold))
                    Text(item.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !item.isParameter && !item.id.contains(":") {
                        actionButton("Run Once", "play.fill", enabled: bridge.isConnected && !engine.isOutputPaused) {
                            StudioEngine.shared.runKeyCommand(item.id)
                            engine.mapStatusMessage = "Ran \(item.title)"
                            dismiss()
                        }
                        if !bridge.isConnected {
                            Text("Lightroom isn’t connected.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let target = selectedControl {
                        let canAssign = PanelLayout.isButton(target) || item.isParameter
                        actionButton("Assign to \(PanelLayout.label(forControl: target))", "arrow.down.to.line", enabled: canAssign) {
                            engine.applyDroppedCommand(commandId: item.id, ontoControl: target)
                            dismiss()
                        }
                        if PanelLayout.isButton(target) && engine.effectiveEditLayer == nil {
                            actionButton("Assign to \(PanelLayout.label(forControl: target)). While Held", "hand.point.down", enabled: true) {
                                engine.applyDroppedCommand(commandId: item.id, ontoControl: target, preferHold: true)
                                dismiss()
                            }
                        }
                    } else {
                        Text("Select a control on the Map to assign.").font(.caption).foregroundStyle(.secondary)
                    }
                    actionButton("Find on Panel", "scope", enabled: true) {
                        uses = engine.findOnPanel(item.id)
                        didFind = true
                    }
                    if item.isParameter && !RepeatCommands.isRepeat(item.id) {
                        actionButton("Put on \(PanelLayout.shortLabel(forControl: settings.focusDialControl)) for Now", "dial.medium", enabled: true) {
                            engine.setTempFocus(item.id)
                            dismiss()
                        }
                    }
                }

                if !uses.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On your panel").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(uses) { use in
                            Label("\(PanelLayout.label(forControl: use.control)). \(use.context)", systemImage: "smallcircle.filled.circle")
                                .font(.callout)
                        }
                    }
                } else if didFind {
                    Text("Not on your panel yet.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("No matches").foregroundStyle(.secondary)
        }
    }

    private func actionButton(_ title: String, _ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!enabled)
    }

    private func move(_ delta: Int) {
        let list = results
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == current?.id } ?? 0
        highlighted = list[max(0, min(list.count - 1, index + delta))].id
    }

    private func runDefault() {
        guard let item = current else { return }
        if !item.isParameter && !item.id.contains(":") && bridge.isConnected && !engine.isOutputPaused {
            StudioEngine.shared.runKeyCommand(item.id)
            engine.mapStatusMessage = "Ran \(item.title)"
            dismiss()
        } else {
            uses = engine.findOnPanel(item.id)
            didFind = true
        }
    }
}
