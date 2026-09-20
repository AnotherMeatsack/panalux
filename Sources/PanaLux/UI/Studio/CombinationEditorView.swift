import SwiftUI

/// A frozen gesture lets one hand return to the mouse after capturing the panel.
struct CombinationEditorView: View {
    @ObservedObject var engine = StudioEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targeted = false
    @State private var shortcut = ""
    private var controls: [String] { PanelLayout.allButtons + PanelLayout.knobs.map { "PRESS_" + $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Edit a press or combination", isOn: Binding(
                get: { engine.combinationEditorActive },
                set: { enabled in
                    if enabled { engine.setProgrammingButtons(true) }
                    engine.combinationEditorActive = enabled
                }))
            if engine.combinationEditorActive {
                Text("Hold your buttons, then press the target. Let go: your combination stays here while you choose or drag an action. Output is paused during programming.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("1 · Hold").font(.caption.bold())
                ForEach(engine.combinationHeld.sorted(), id: \.self) { control in
                    HStack {
                        Label(PanelLayout.label(forControl: control), systemImage: "lock.fill")
                        Spacer()
                        Button { engine.combinationHeld.remove(control) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Remove " + PanelLayout.label(forControl: control))
                    }
                    .padding(7).background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                Menu("Add a held button…") {
                    ForEach(controls.filter { $0 != engine.combinationTrigger }, id: \.self) { control in
                        Button(PanelLayout.label(forControl: control)) { engine.combinationHeld.insert(control) }
                    }
                }
                Text("Leave Hold empty to customize a single press.").font(.caption).foregroundStyle(.secondary)
                Picker("2 · Press", selection: $engine.combinationTrigger) {
                    ForEach(controls, id: \.self) { Text(PanelLayout.label(forControl: $0)).tag($0) }
                }.onChange(of: engine.combinationTrigger) { _, value in engine.combinationHeld.remove(value) }
                Label("3 · Drop a command here", systemImage: targeted ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.headline).frame(maxWidth: .infinity).padding(14)
                    .background(Color.accentColor.opacity(targeted ? 0.25 : 0.10), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5])))
                    .scaleEffect(targeted && !reduceMotion ? 1.02 : 1)
                    .onDrop(of: [.text], isTargeted: $targeted) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: String.self) { value, _ in
                            guard let value else { return }
                            DispatchQueue.main.async { engine.saveCombination(command: value) }
                        }
                        return true
                    }
                Text("Or click a command in the catalog. Preset slots use the presets configured in Lightroom’s plug-in options. Combinations take priority over mode keys.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Keyboard shortcut…") {
                    TextField("For example: cmd+shift+e", text: $shortcut).textFieldStyle(.roundedBorder)
                    Button("Assign shortcut") { engine.saveCombination(command: "key:" + shortcut.trimmingCharacters(in: .whitespaces)) }
                        .disabled(KeyCommands.parse("key:" + shortcut.trimmingCharacters(in: .whitespaces)) == nil)
                }
                HStack {
                    Button("Clear Hold") { engine.combinationHeld = [] }
                    Spacer()
                    Button("Done") { engine.setProgrammingButtons(false) }.buttonStyle(.borderedProminent)
                }
            }
            DisclosureGroup("Saved combinations (\(engine.effectiveCombinations.count))") {
                ForEach(engine.effectiveCombinations) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(CommandDatabase.shared.label(for: entry.binding.action ?? entry.binding.layer ?? entry.binding.ps ?? "Command"))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Edit") {
                                engine.setProgrammingButtons(true)
                                engine.combinationEditorActive = true
                                engine.combinationTrigger = entry.trigger
                                engine.combinationHeld = Set(entry.held)
                            }
                            Button("Remove") { engine.removeCombination(entry.id) }
                        }.font(.caption)
                    }.padding(.vertical, 5)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: engine.combinationHeld)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: targeted)
    }
}
