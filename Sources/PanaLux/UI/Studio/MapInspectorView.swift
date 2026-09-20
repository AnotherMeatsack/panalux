import SwiftUI

struct CommandTileView: View {
    let item: CatalogCommand
    var selected: Bool = false
    var action: () -> Void

    static func shortTitle(_ raw: String) -> String {
        var t = raw
        for prefix in ["Hold: ", "Toggle: ", "Mixer Bank: ", "Hold ", "Global "] {
            if t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        }
        t = t.replacingOccurrences(of: "Color Temperature", with: "Temp")
        t = t.replacingOccurrences(of: "Open as Layers in Photoshop", with: "Photoshop Layers")
        if let paren = t.firstIndex(of: "(") {
            t = String(t[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    var body: some View {
        // Not a Button: a Button eats the mouse-down, so the tile could never be dragged.
        VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selected ? Color.accentColor : (item.isParameter ? Color.orange : Color.primary.opacity(0.8)))
                    )
                    .frame(height: 44)
                Text(Self.shortTitle(item.title))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onDrag { NSItemProvider(object: item.id as NSString) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, action)
        .help("\(item.title)\n\(item.subtitle)")
        .accessibilityLabel(item.title)
    }
}

/// Everything about the selected control: what it does, how fast, and what to change it to.
public struct MapInspectorView: View {
    @Binding var selectedControl: String?
    @ObservedObject var engine = StudioEngine.shared
    @ObservedObject var db = CommandDatabase.shared
    @ObservedObject var guide = GuideController.shared

    @State private var showCombinations = false
    @State private var searchText = ""
    @State private var shortcutText = ""
    @State private var assignSlot: Slot = .tap
    @State private var showModesHelp = false
    @State private var browseGroup: String = "Featured"
    @FocusState private var searchFocused: Bool

    private enum Slot: String, CaseIterable {
        case tap = "On tap"
        case hold = "While held"
    }

    public init(selectedControl: Binding<String?>) {
        self._selectedControl = selectedControl
    }

    private var control: String? {
        guard let c = selectedControl else { return nil }
        return PanelControlMapping.toProfileId(c)
    }

    private var isButton: Bool {
        guard let c = control else { return false }
        return PanelLayout.isButton(c)
    }

    private var editLayer: String? { engine.effectiveEditLayer }

    /// The hold key whose "while held" knobs you are editing (selected key or key held on the panel).
    private var holdOwner: String? {
        editLayer == nil ? (engine.engagedHoldActivator ?? engine.inspectorHoldEdit) : nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            DisclosureGroup("Presses & Combinations", isExpanded: $showCombinations) {
                ScrollView { CombinationEditorView().padding(.vertical, 8) }
                    .frame(height: engine.combinationEditorActive ? 340 : 180)
            }
            if engine.combinationEditorActive {
                Button("Done Programming") { engine.setProgrammingButtons(false) }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let c = control, !engine.combinationEditorActive {
                actionRow(c)
                if isButton {
                    DisclosureGroup("Press a Key…") {
                        VStack(alignment: .leading, spacing: 7) {
                            TextField("For example: cmd+shift+e", text: $shortcutText)
                                .textFieldStyle(.roundedBorder)
                            Text("Modifiers: cmd, shift, opt, ctrl. Requires Accessibility access.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Assign shortcut") {
                                assign(db.catalogCommand(for: "key:" + shortcutText.trimmingCharacters(in: .whitespaces)))
                            }
                            .disabled(KeyCommands.parse("key:" + shortcutText.trimmingCharacters(in: .whitespaces)) == nil)
                        }.padding(.top, 6)
                    }
                    buttonSlots(c)
                } else if PanelLayout.isBall(c) {
                    ballCard(c)
                } else {
                    if PanelLayout.isKnob(c) {
                        Button("Customize knob press…") {
                            showCombinations = true
                            engine.setProgrammingButtons(true)
                            engine.combinationEditorActive = true
                            engine.combinationHeld = []
                            engine.combinationTrigger = "PRESS_" + c
                        }
                        Button("Disable knob press") { engine.profile.buttons["PRESS_" + c] = ButtonBinding() }
                        Button("Restore press to reset") { engine.profile.buttons.removeValue(forKey: "PRESS_" + c) }
                        Text("Press resets the knob’s current parameter unless you assign another action.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    speedRow(c)
                }
            }
            if !engine.mapStatusMessage.isEmpty {
                Label(engine.mapStatusMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .transition(.opacity)
            }
            searchField
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                groupChips
            }
            tileGrid
            modesHelp
        }
        .padding(14)
        .animation(.smooth(duration: 0.2), value: engine.mapStatusMessage)
        .onAppear { if engine.combinationEditorActive { showCombinations = true } }
        .onChange(of: engine.combinationEditorActive) { _, active in
            if active { showCombinations = true }
        }
        .onChange(of: control) { _, new in
            // Clicking a knob, ring, or ball keeps the hold you were editing, so
            // "LOOP while held → Y Lift → Vignette" sets only that knob.
            if let new, !PanelLayout.isButton(new) {
                // keep inspectorHoldEdit
            } else {
                engine.inspectorHoldEdit = (isButton && assignSlot == .hold) ? new : nil
            }
            engine.mapStatusMessage = ""
        }
        .onChange(of: engine.programmingHoldControl) { _, held in
            if let held { selectedControl = held; assignSlot = .hold }
            else if engine.isProgrammingButtons { assignSlot = .tap }
        }
        .onChange(of: assignSlot) { _, slot in
            engine.inspectorHoldEdit = (isButton && slot == .hold) ? control : nil
        }
        .onChange(of: searchFocused) { _, focused in
            guide.isEditingText = focused
        }
        .onDisappear {
            engine.inspectorHoldEdit = nil
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if let c = control {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(kindLabel(c))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let owner = holdOwner, !isButton {
                        Button {
                            engine.inspectorHoldEdit = nil
                        } label: {
                            Label("While holding \(PanelLayout.label(forControl: owner))", systemImage: "hand.point.down.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.engagedHoldActivator != nil)
                        .help("Picks here only apply while this key is held. Click to edit Base instead.")
                    }
                    if let layer = editLayer {
                        Label(engine.layerTitle(layer), systemImage: LayerNames.symbol(layer))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LayerNames.color(layer))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(LayerNames.color(layer).opacity(0.15)))
                    }
                }
                Text(PanelLayout.label(forControl: c))
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(summaryLine(c))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            Text("Click a control on the panel drawing, or touch one on your desk.")
                .foregroundStyle(.secondary)
        }
    }

    private func actionRow(_ c: String) -> some View {
        HStack(spacing: 6) {
            Button { engine.copyControl(c) } label: { Label("Copy", systemImage: "doc.on.doc") }
                .help("Copy this control’s assignment")
            Button { engine.pasteControl(onto: c) } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .disabled(!engine.canPaste(onto: c))
                .help(engine.clipboard.map { "Paste \($0.summary)" } ?? "Copy a control first")
            Button {
                if engine.swapSource == c {
                    engine.swapSource = nil
                    engine.mapStatusMessage = ""
                } else {
                    engine.swapSource = c
                    engine.mapStatusMessage = "Swap: now click or touch the other control"
                }
            } label: {
                Label("Swap", systemImage: "arrow.left.arrow.right")
            }
            .background(engine.swapSource == c ? Capsule().fill(Color.accentColor.opacity(0.3)) : nil)
            .help("Trade assignments with another control of the same kind")
            Spacer()
            if isButton {
                Menu {
                    Button("Clear On Tap") { engine.clearControl(c, slot: .tap) }
                    Button("Clear While Held") { engine.clearControl(c, slot: .hold) }
                    Button("Clear Both", role: .destructive) { engine.clearControl(c, slot: .both) }
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .fixedSize()
            } else {
                Button(role: .destructive) { engine.clearControl(c) } label: {
                    Label(editLayer == nil ? "Clear" : "Use Base", systemImage: "xmark.circle")
                }
                .help(editLayer == nil ? "Remove this assignment" : "Let this control fall through to the base map in this mode")
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
    }

    // MARK: Buttons

    private func buttonSlots(_ c: String) -> some View {
        let spec = editLayer.flatMap { engine.profile.layers[$0]?.buttons?[c] } ?? engine.profile.buttons[c]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                slotCard(title: "On tap", detail: tapSummary(spec), active: assignSlot == .tap) {
                    assignSlot = .tap
                }
                slotCard(title: "While held", detail: holdSummary(spec), active: assignSlot == .hold) {
                    assignSlot = .hold
                }
            }
            Text(assignSlot == .hold
                 ? "Choose an action or mode for this hold. The tap stays unchanged."
                 : "Pick a command below, or drag a tile onto the key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func layerKeyCard(_ c: String, layer: String) -> some View {
        let spec = engine.profile.layers[layer]?.buttons?[c]
        let base = engine.profile.buttons[c]
        return VStack(alignment: .leading, spacing: 4) {
            Text("IN \(engine.layerTitle(layer).uppercased())")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(spec.map { tapSummary($0) } ?? "Same as Base. \(tapSummary(base))")
                .font(.headline)
            Text("Keys inside a mode fire one command. Base still decides what this key does when no mode is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LayerNames.color(layer).opacity(0.12)))
    }

    private func slotCard(title: String, detail: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(active ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Analog

    @ViewBuilder
    private func speedRow(_ c: String) -> some View {
        if let scale = engine.dialScale(c) {
            let param = currentParam(c) ?? ""
            if RepeatCommands.isRepeat(param) {
                Label("Each detent sends one step.", systemImage: "dial.medium")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "tortoise").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { log2(scale / 0.0003) },
                        set: { engine.setDialScale(c, 0.0003 * pow(2, $0)) }
                    ), in: -2...2, step: 0.5)
                    Image(systemName: "hare").foregroundStyle(.secondary)
                    Text(String(format: "%.2g×", scale / 0.0003))
                        .font(.callout.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                .help("How far one turn moves the slider. 1× is the factory feel.")
            }
        }
    }

    private func ballCard(_ c: String) -> some View {
        let current = holdOwner.map { engine.profile.buttons[$0]?.holdProgram?.balls?[c] }
            ?? editLayer.map { engine.profile.layers[$0]?.balls?[c] } ?? engine.profile.balls[c]
        return VStack(alignment: .leading, spacing: 8) {
            Text(current?.param.map { "Rolling drives \(CommandDatabase.shared.label(for: $0)). Pick a color wheel or another slider below." }
                 ?? "Color wheel: rolling sets hue and strength together. Or pick any slider below to roll it up and down.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Drives")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(WheelChoice.all) { choice in
                Button {
                    engine.setBall(c, to: choice)
                } label: {
                    HStack {
                        Image(systemName: isWheel(current, choice) ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isWheel(current, choice) ? Color.accentColor : .secondary)
                        Text(choice.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isWheel(_ b: BallBinding?, _ choice: WheelChoice) -> Bool {
        b?.param == nil && b?.hue == choice.hue
    }

    // MARK: Browse

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search all \(db.commands.count) Lightroom commands", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(browseChipNames, id: \.self) { name in
                    Button {
                        browseGroup = name
                    } label: {
                        Text(chipLabel(name))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(browseGroup == name ? Color.white : Color.primary.opacity(0.8))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(browseGroup == name ? Color.accentColor : Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var browseChipNames: [String] {
        ["Featured", "Modes", "All"] + db.browseGroups()
    }

    private func chipLabel(_ name: String) -> String {
        if ["All", "Featured", "Modes"].contains(name) { return name }
        return Self.groupNames[name] ?? name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let groupNames: [String: String] = [
        "mask": "Masks", "basicTone": "Basic", "colorAdjustments": "Color Mixer", "colorGrading": "Color Grading",
        "localizedAdjustments": "Mask Sliders", "localadjresets": "Mask Resets", "locadjpre": "Mask Presets",
        "developPresets": "Presets", "keyshortcuts": "Keyboard Keys", "commandseries": "Command Series",
        "keywordtoggle": "Keyword Toggles", "lensBlur": "Lens Blur", "lensCorrections": "Lens",
        "toneCurve": "Tone Curve", "quickdev": "Quick Develop", "resetColorAdjustments": "Mixer Resets",
        "secondaryDisplay": "Second Display", "gotoToolModulePanel": "Modules", "HDR": "HDR",
        "Next": "Next", "Previous": "Previous"
    ]

    private var tileGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty, browseGroup == "Featured" {
                    section(featuredTitle, analogSafe(featuredTiles))
                    section("Masks", analogSafe(maskTiles))
                } else {
                    let items = tiles
                    Text("\(items.count) commands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    tileWrap(items)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func analogSafe(_ items: [CatalogCommand]) -> [CatalogCommand] {
        if engine.combinationEditorActive { return items.filter { !$0.isParameter && !$0.id.hasPrefix("hold_") && !$0.id.hasPrefix("modifier:") } }
        return isButton || control == nil ? items : items.filter(\.isParameter)
    }

    private func section(_ title: String, _ items: [CatalogCommand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            tileWrap(items)
        }
    }

    private func tileWrap(_ items: [CatalogCommand]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 10) {
            ForEach(items) { item in
                CommandTileView(item: item, selected: isSelected(item)) {
                    assign(item)
                }
            }
        }
    }

    private var modesHelp: some View {
        DisclosureGroup(isExpanded: $showModesHelp) {
            VStack(alignment: .leading, spacing: 8) {
                helpBlock("Base", "What every control does with nothing held.")
                helpBlock("Hold a key", "A second map sits on top until you let go. Up Shift = Color Mixer, User = Upright, Viewer = Crop, Select = Cull, Cursor = Masks.")
                helpBlock("Hold Add Node", "A circular tool wheel appears. Spin a ring or roll a ball to pick Linear, Radial, Brush, Subject… The left ring (or Prev/Next Node and Frame) chooses New, Add, Subtract, or Intersect. Release to create it, then place it with the mouse. Knobs grade the selected mask. Using the balls to place a mask is coming soon.")
                helpBlock("Tap a key", "Some keys turn a mode on and leave it on (Offset, Cursor). The notch readout says ON. Tap again, or use Back to Base.")
                helpBlock("Edit a mode", "Pick it in the menu above the drawing, then assign as usual. Controls a mode doesn’t set fall through to Base.")
                helpBlock("Undo", "⌘Z undoes map changes. Every whole-map change is backed up in Settings → Maps.")
            }
            .padding(.top, 6)
        } label: {
            Text("How holds and modes work")
                .font(.callout.weight(.medium))
        }
    }

    private func helpBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.bold))
            Text(body).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuredTitle: String {
        if engine.combinationEditorActive { return "Presets & commands" }
        guard let c = control else { return "Popular" }
        if isButton { return assignSlot == .hold ? "For holding" : "Popular commands" }
        return PanelLayout.isRing(c) ? "Good on a ring" : "Popular sliders"
    }

    private var featuredTiles: [CatalogCommand] {
        let ids: [String]
        if engine.combinationEditorActive {
            ids = ["Preset_1", "Preset_2", "Preset_3", "ActionSeries1", "AutoTone", "Undo", KeyCommands.beforeAfter]
        } else if let c = control, !PanelLayout.isButton(c) {
            ids = ["Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks",
                   "Temperature", "Tint", "Vibrance", "Saturation", "Texture", "Clarity", "Dehaze",
                   "PostCropVignetteAmount", "GrainAmount", "LensBlurAmount", "straightenAngle",
                   "NextPrev", "ZoomInOut", "PresetPreviousNext", "ChangeBrushSize"]
        } else if assignSlot == .hold {
            ids = ["hold_layer:MIXER", "hold_layer:TRANSFORM", "hold_layer:MASK", "hold_layer:CROP",
                   "hold_layer:CULL", "hold_layer:TONE", "hold_layer:DETAIL", "hold_layer:EFFECTS",
                   "hold_layer:LENS", "hold_layer:PRESETS", "modifier:FINE", "hold_compare",
                   "hold_picker:mask_tools", "PostCropVignetteAmount", "Exposure"]
        } else {
            ids = ["AutoTone", "WhiteBalanceAuto", "UprightAuto", "ResetAll", "LRCopy", "LRPaste",
                   "Undo", "Redo", "Pick", "Reject", "SetRating5", "VirtualCopy", "Next", "Prev",
                   "ShoVwdevelop_before_after_horiz", "ShowClipping", "openExportWithPreviousDialog",
                   "smart_roundtrip", "layer:MASK", "layer:OFFSET", "EnableLensCorrections", "ActionSeries1"]
        }
        return ids.map { db.catalogCommand(for: $0) }
    }

    private var maskTiles: [CatalogCommand] {
        let ids: [String]
        if let c = control, !PanelLayout.isButton(c) {
            ids = ["local_Exposure", "local_Contrast", "local_Highlights", "local_Shadows", "local_Whites",
                   "local_Blacks", "local_Saturation", "local_Temperature", "local_Clarity", "local_Amount",
                   "ChangeBrushSize", "ChangeFeatherSize", "pointer:move", "pointer:size"]
        } else {
            ids = ["MaskNewRad", "MaskNewGrad", "MaskNewBrush", "MaskNewObj", "MaskNewSubject", "MaskNewSky",
                   "MaskNewPeople", "MaskNewBack", "MaskNewColor", "MaskNewLum", "MaskInvert", "MaskNext",
                   "MaskPrevious", "MaskHide", "MaskDelete", "layer:MASK", "hold_picker:mask_tools",
                   "pointer:click"]
        }
        return ids.map { db.catalogCommand(for: $0) }
    }

    /// Knobs, rings, and balls only list what they can drive, so a same-named
    /// key command (Reset Sharpness) can't be mistaken for the slider.
    private var tiles: [CatalogCommand] {
        let all = unfilteredTiles
        return isButton || control == nil ? all : all.filter(\.isParameter)
    }

    private var unfilteredTiles: [CatalogCommand] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return db.search(q, preferButtons: isButton)
        }
        switch browseGroup {
        case "Featured": return featuredTiles
        case "Modes": return CommandCatalog.shared.categories.first { $0.id == "layers" }?.items ?? []
        case "All": return db.allItems()
        default: return db.items(inGroup: browseGroup)
        }
    }

    private func isSelected(_ item: CatalogCommand) -> Bool {
        guard let c = control else { return false }
        return currentParam(c) == item.id || currentKeyIds(c).contains(item.id)
    }

    private func currentParam(_ c: String) -> String? {
        if let owner = holdOwner, !isButton {
            return engine.holdProgramParam(owner: owner, control: c)
        }
        if let layer = editLayer, let spec = engine.profile.layers[layer] {
            if let v = engine.activeVariants[layer], let k = spec.variants?[v]?.knobs?[c] { return k.param }
            return spec.knobs?[c]?.param ?? spec.rings?[c]?.param ?? spec.balls?[c]?.param
        }
        return engine.profile.knobs[c]?.param ?? engine.profile.rings[c]?.param ?? engine.profile.balls[c]?.param
    }

    private func currentKeyIds(_ c: String) -> Set<String> {
        if let layer = editLayer {
            return ids(for: engine.profile.layers[layer]?.buttons?[c], hold: assignSlot == .hold)
        }
        return ids(for: engine.profile.buttons[c], hold: assignSlot == .hold)
    }

    private func ids(for spec: ButtonBinding?, hold: Bool) -> Set<String> {
        guard let spec else { return [] }
        var out = Set<String>()
        if hold {
            if let h = spec.hold_layer { out.insert("hold_layer:\(h)") }
            if let m = spec.modifier { out.insert("modifier:\(m)") }
            if let p = spec.hold_picker { out.insert("hold_picker:\(p)") }
            if spec.hold_action == MomentaryCommands.compareBefore { out.insert(StudioEngine.holdCompareID) }
            else if spec.hold_action == PointerCommands.down { out.insert(PointerCommands.click) }
            else if let a = spec.hold_action { out.insert(a) }
            if let f = spec.holdProgram?.focusParam { out.insert(f) }
        } else {
            if let a = spec.action { out.insert(a) }
            if let l = spec.layer { out.insert("layer:\(l)") }
            if let v = spec.set_variant { out.insert("set_variant:\(v)") }
            if let ps = spec.ps { out.insert(ps) }
            if let f = spec.tapProgram?.focusParam { out.insert(f) }
        }
        return out
    }

    private func assign(_ item: CatalogCommand) {
        if engine.combinationEditorActive { engine.saveCombination(command: item.id); return }
        guard let c = control else { return }
        if isButton {
            engine.applyDroppedCommand(commandId: item.id, ontoControl: c, preferHold: assignSlot == .hold)
        } else {
            engine.applyDroppedCommand(commandId: item.id, ontoControl: c)
        }
    }

    private func kindLabel(_ c: String) -> String {
        if PanelLayout.isRing(c) { return "RING" }
        if PanelLayout.isBall(c) { return "TRACKBALL" }
        if PanelLayout.isKnob(c) { return "KNOB" }
        return "KEY"
    }

    private func summaryLine(_ c: String) -> String {
        let label = { (id: String) in CommandDatabase.shared.label(for: id) }
        if let owner = holdOwner, !PanelLayout.isButton(c) {
            if let p = currentParam(c) { return label(p) }
            let base = (engine.profile.knobs[c]?.param ?? engine.profile.rings[c]?.param).map(label) ?? "its Base job"
            return "Not set while holding \(PanelLayout.label(forControl: owner)). keeps \(base)"
        }
        if let layer = editLayer, let spec = engine.profile.layers[layer] {
            if let p = currentParam(c) { return label(p) }
            if let b = spec.balls?[c] { return b.param.map(label) ?? "\(label(b.hue)) · \(label(b.sat))" }
            if spec.buttons?[c] != nil { return tapSummary(spec.buttons?[c]) }
            let base = PanelLayout.isButton(c) ? tapSummary(engine.profile.buttons[c]) : (currentBaseParam(c).map(label) ?? "Unassigned")
            return "Same as Base: \(base)"
        }
        if let p = currentParam(c) { return label(p) }
        if let ball = engine.profile.balls[c] { return ball.param.map(label) ?? "\(label(ball.hue)) · \(label(ball.sat))" }
        if let spec = engine.profile.buttons[c], spec.hasAnyAssignment {
            return "Tap: \(tapSummary(spec))  ·  Hold: \(holdSummary(spec))"
        }
        return "Unassigned. pick a command below"
    }

    private func currentBaseParam(_ c: String) -> String? {
        engine.profile.knobs[c]?.param ?? engine.profile.rings[c]?.param
    }

    private func tapSummary(_ spec: ButtonBinding?) -> String {
        guard let spec else { return "-" }
        if let p = spec.tapProgram { return p.summary }
        if let a = spec.action { return CommandDatabase.shared.label(for: a) }
        if spec.ps != nil { return "Photoshop Layers" }
        if let l = spec.layer { return "Toggle \(engine.layerTitle(l))" }
        if let v = spec.set_variant { return "Mixer bank: \(v.capitalized)" }
        return "-"
    }

    private func holdSummary(_ spec: ButtonBinding?) -> String {
        guard let spec else { return "-" }
        if let p = spec.holdProgram { return p.summary }
        if let h = spec.hold_layer { return engine.layerTitle(h) }
        if spec.hold_picker != nil { return "Mask tool wheel" }
        if spec.modifier != nil { return "Fine" }
        if spec.hold_action == MomentaryCommands.compareBefore { return "Compare Before" }
        if let a = spec.hold_action { return CommandDatabase.shared.label(for: a) }
        return "-"
    }
}

/// Color-wheel targets a trackball can drive.
public struct WheelChoice: Identifiable, Hashable {
    public var id: String { hue }
    public let title: String
    public let hue: String
    public let sat: String

    public static let all: [WheelChoice] = [
        WheelChoice(title: "Shadows", hue: "SplitToningShadowHue", sat: "SplitToningShadowSaturation"),
        WheelChoice(title: "Midtones", hue: "ColorGradeMidtoneHue", sat: "ColorGradeMidtoneSat"),
        WheelChoice(title: "Highlights", hue: "SplitToningHighlightHue", sat: "SplitToningHighlightSaturation"),
        WheelChoice(title: "Global", hue: "ColorGradeGlobalHue", sat: "ColorGradeGlobalSat"),
        WheelChoice(title: "Mask color", hue: "local_ToningHue", sat: "local_ToningSaturation")
    ]
}

extension StudioEngine {
    public func setBall(_ control: String, to choice: WheelChoice) {
        if let layer = effectiveEditLayer {
            var spec = profile.layers[layer] ?? LayerSpec()
            var balls = spec.balls ?? [:]
            balls[control] = BallBinding(hue: choice.hue, sat: choice.sat)
            spec.balls = balls
            profile.layers[layer] = spec
        } else {
            let old = profile.balls[control]
            profile.balls[control] = BallBinding(hue: choice.hue, sat: choice.sat,
                                                 radius: old?.radius ?? 3000, invert_x: old?.invert_x ?? true, invert_y: old?.invert_y ?? true)
            profileStructureChanged()
        }
        mapStatusMessage = "\(PanelLayout.shortLabel(forControl: control)) → \(choice.title)"
    }
}
