import SwiftUI

/// The panel drawing plus the strip that says which map you are looking at.
public struct PanelCanvasView: View {
    @ObservedObject var engine = StudioEngine.shared
    @Binding var selectedControl: String?

    public init(selectedControl: Binding<String?>) {
        self._selectedControl = selectedControl
    }

    private var shownLayer: String? { engine.effectiveEditLayer }

    private var baseBindings: [String: String] {
        var dict: [String: String] = [:]
        for (svgId, profId) in PanelControlMapping.svgToProfile {
            dict[svgId] = baseLabel(for: profId)
        }
        return dict
    }

    private var shiftedBindings: [String: String] {
        MappingConnections.overlayBindingLabels(profile: engine.profile, layer: shownLayer, variant: shownLayer.flatMap { engine.activeVariants[$0] })
    }

    private var layerNames: [String] {
        engine.profile.layers.keys.sorted { engine.layerTitle($0) < engine.layerTitle($1) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if engine.isProgrammingButtons {
                Label("Press a button or knob to edit it. Open Presses & Combinations to capture a gesture, release your hands, then drop an action.", systemImage: "hand.point.down")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
            }
            modeStrip
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            InteractiveSVGView(
                selectedControl: $selectedControl,
                activeControl: engine.activeControlHighlight,
                isShiftHeld: shownLayer != nil,
                baseBindings: baseBindings,
                shiftedBindings: shiftedBindings.isEmpty ? baseBindings : shiftedBindings,
                heldSvgIds: MappingConnections.heldSvgIds(engine: engine),
                overlayLabel: shownLayer.map { engine.layerTitle($0).uppercased() } ?? "BASE",
                connectionsBySvg: MappingConnections.live(engine: engine),
                foundSvgIds: engine.foundControls.compactMap { PanelControlMapping.profileToSvg[$0] },
                focusOwnerSvg: (engine.effectiveEditLayer == nil ? (engine.engagedHoldActivator ?? engine.inspectorHoldEdit) : nil)
                    .flatMap { PanelControlMapping.profileToSvg[$0] }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedControl) { _, newControl in
            engine.highlightHardwareControl(newControl)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: 10) {
            Picker("Editing", selection: Binding(
                get: { engine.mapEditLayer ?? "" },
                set: { engine.mapEditLayer = $0.isEmpty ? nil : $0 }
            )) {
                Label("Base", systemImage: "square").tag("")
                Divider()
                ForEach(layerNames, id: \.self) { layer in
                    Label(engine.layerTitle(layer), systemImage: LayerNames.symbol(layer)).tag(layer)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Which map you’re editing. Holding a key on the panel shows that mode instead.")

            if let layer = shownLayer, let variants = engine.profile.layers[layer]?.variants, !variants.isEmpty {
                Picker("Bank", selection: Binding(
                    get: { engine.activeVariants[layer] ?? "" },
                    set: { engine.activeVariants[layer] = $0 }
                )) {
                    ForEach(variants.keys.sorted(), id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if let held = engine.overlayLayerName {
                chip(engine.isLayerLatched(held) ? "\(engine.layerTitle(held)) on" : "Holding \(engine.layerTitle(held))",
                     symbol: LayerNames.symbol(held), color: LayerNames.color(held)) {
                    engine.returnToBase(announce: false)
                }
            }
            if let temp = engine.tempFocusParam {
                chip("Focus dial: \(CommandDatabase.shared.label(for: temp))", symbol: "dial.medium.fill", color: .cyan) {
                    engine.setTempFocus(nil)
                }
            }
            if engine.isOutputPaused {
                chip("Output paused", symbol: "pause.fill", color: .yellow) {
                    engine.setOutputPaused(false)
                }
            }

            Spacer(minLength: 8)

            Toggle(isOn: Binding(
                get: { !engine.isLiveGradingEnabled },
                set: { engine.isLiveGradingEnabled = !$0 }
            )) {
                Label("Safe Setup", systemImage: "hand.raised")
            }
            .toggleStyle(.button)
            .help("Knobs preview on screen instead of changing the photo. Held modes and keys still work.")
        }
        .controlSize(.regular)
    }

    private func chip(_ text: String, symbol: String, color: Color, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).lineLimit(1)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Turn off")
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private func baseLabel(for control: String) -> String {
        let db = CommandDatabase.shared
        if let knob = engine.profile.knobs[control] { return db.label(for: knob.param) }
        if let ring = engine.profile.rings[control] { return db.label(for: ring.param) }
        if let ball = engine.profile.balls[control] { return db.label(for: ball.hue) }
        if let btn = engine.profile.buttons[control] {
            var parts: [String] = []
            if let p = btn.tapProgram { parts.append(p.summary) }
            else if let a = btn.action { parts.append(db.label(for: a)) }
            else if btn.ps != nil { parts.append("Photoshop Layers") }
            else if let l = btn.layer { parts.append("Toggle \(engine.layerTitle(l))") }
            else if let v = btn.set_variant { parts.append("Bank \(v)") }
            if let h = btn.hold_layer { parts.append("Hold: \(engine.layerTitle(h))") }
            else if btn.hold_picker != nil { parts.append("Hold: Mask tools") }
            else if btn.modifier != nil { parts.append("Hold: Fine") }
            else if btn.hold_action == MomentaryCommands.compareBefore { parts.append("Hold: Compare") }
            else if let a = btn.hold_action { parts.append("Hold: \(db.label(for: a))") }
            else if let p = btn.holdProgram { parts.append("Hold: \(p.summary)") }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return "-"
    }
}
