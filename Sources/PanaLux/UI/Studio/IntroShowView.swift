import SwiftUI
import AppKit

/// A short keynote-style presentation that plays before the hands-on tour.
struct IntroShowView: View {
    @ObservedObject var guide = GuideController.shared
    @State private var scene = 0
    @State private var playing = true
    @State private var sceneStart = Date()
    @FocusState private var focused: Bool

    private let sceneLengths: [TimeInterval] = [7.0, 8.0, 8.0, 9.5, 18.0, 14.0, 18.0, IntroRewindDemo.length, 9.0, 60]
    private var sceneCount: Int { sceneLengths.count }

    var body: some View {
        ZStack {
            backdrop
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(sceneStart)
                ZStack {
                    content(for: scene, t: t)
                        .id(scene)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 18)),
                            removal: .opacity.combined(with: .scale(scale: 1.03))
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: timeline.date) { _, now in
                    if playing, scene < sceneCount - 1, now.timeIntervalSince(sceneStart) > sceneLengths[scene] {
                        go(scene + 1)
                    }
                }
            }
            .padding(.bottom, 70)

            VStack {
                Spacer()
                controls
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true; sceneStart = Date() }
        .onKeyPress(.rightArrow) { go(scene + 1); return .handled }
        .onKeyPress(.leftArrow) { go(scene - 1); return .handled }
        .onKeyPress(.space) { playing.toggle(); sceneStart = Date(); return .handled }
        .onKeyPress(.escape) { guide.finishIntro(startTour: false); return .handled }
        .environment(\.colorScheme, .dark)
    }

    /// One frame of one scene, for rendering stills.
    static func still(scene: Int, at t: TimeInterval) -> some View {
        let show = IntroShowView()
        return ZStack {
            show.backdrop(for: scene)
            show.content(for: scene, t: t)
        }
    }

    /// Prefer the bundled icon. XCTest has no app icon, so stills used to show a folder.
    fileprivate static func panaluxIcon() -> NSImage {
        let names: [(String, String)] = [("AppIcon", "icns"), ("AppIcon-1024", "png")]
        for (name, ext) in names {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
            if let url = AppResources.url(name, ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return NSApplication.shared.applicationIconImage
    }

    private func go(_ next: Int) {
        guard next >= 0 else { return }
        guard next < sceneCount else {
            guide.finishIntro(startTour: true)
            return
        }
        withAnimation(.smooth(duration: 0.7)) {
            scene = next
            sceneStart = Date()
        }
    }

    // MARK: Chrome

    private var backdrop: some View { backdrop(for: scene) }

    fileprivate func backdrop(for scene: Int) -> some View {
        ZStack {
            Color.black
            RadialGradient(colors: [accent(scene).opacity(0.35), .clear], center: .top, startRadius: 40, endRadius: 700)
                .animation(.smooth(duration: 1.2), value: scene)
            RadialGradient(colors: [Color.blue.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 600)
        }
        .ignoresSafeArea()
    }

    private func accent(_ scene: Int) -> Color {
        [Color.orange, .cyan, .orange, .purple, .pink, .yellow, Color(red: 1.00, green: 0.72, blue: 0.30), RewindState.tangentColor(0), .green, .orange][scene % 10]
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button("Skip Intro") { guide.finishIntro(startTour: false) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<sceneCount, id: \.self) { i in
                    Capsule()
                        .fill(i == scene ? Color.white : Color.white.opacity(0.25))
                        .frame(width: i == scene ? 22 : 7, height: 7)
                        .onTapGesture { go(i) }
                }
            }
            .animation(.smooth, value: scene)
            Spacer()
            Button { go(scene - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(scene == 0)
            Button {
                playing.toggle()
                sceneStart = Date()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
            }
            Button { go(scene + 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    // MARK: Scenes

    @ViewBuilder
    fileprivate func content(for scene: Int, t: TimeInterval) -> some View {
        switch scene {
        case 0: titleScene(t)
        case 1: panelScene(t)
        case 2: knobScene(t)
        case 3: wheelScene(t)
        case 4: modesScene(t)
        case 5: holdToggleScene(t)
        case 6: maskWheelScene(t)
        case 7: rewindScene(t)
        case 8: safetyScene(t)
        default: finaleScene(t)
        }
    }

    private func headline(_ title: String, _ subtitle: String, t: TimeInterval) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 44, weight: .bold))
                .multilineTextAlignment(.center)
                .opacity(fade(t, from: 0.1))
                .offset(y: (1 - fade(t, from: 0.1)) * 14)
            Text(subtitle)
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
                .opacity(fade(t, from: 0.5))
        }
    }

    /// 0 → 1 over 0.6s starting at `from`.
    private func fade(_ t: TimeInterval, from: TimeInterval, length: TimeInterval = 0.6) -> Double {
        min(1, max(0, (t - from) / length))
    }

    private func titleScene(_ t: TimeInterval) -> some View {
        VStack(spacing: 26) {
            Image(nsImage: Self.panaluxIcon())
                .resizable()
                .frame(width: 150, height: 150)
                .scaleEffect(0.7 + 0.3 * easeOut(fade(t, from: 0, length: 1.1)))
                .shadow(color: .orange.opacity(0.5 * fade(t, from: 0.4)), radius: 40)
                .opacity(fade(t, from: 0))
            Text("PanaLux")
                .font(.system(size: 72, weight: .bold))
                .tracking(12 - 10 * easeOut(fade(t, from: 0.5, length: 1.4)))
                .opacity(fade(t, from: 0.5))
            Text("One panel. Every job.")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .opacity(fade(t, from: 1.6))
        }
    }

    private func panelScene(_ t: TimeInterval) -> some View {
        VStack(spacing: 30) {
            headline("The panel you already own.", "Twelve knobs, three trackballs, three rings, forty keys. Now they drive Lightroom Classic.", t: t)
            PanelStage(t: t, knobLabels: nil, labelColor: .white, changed: [], heldKeys: [], keyColor: .white, sweep: true)
                .frame(width: 760, height: 388)
                .opacity(fade(t, from: 0.8))
                .offset(y: (1 - easeOut(fade(t, from: 0.8, length: 1))) * 40)
        }
    }

    private func knobScene(_ t: TimeInterval) -> some View {
        let exposure = 0.47 * easeOut(min(1, max(0, (t - 1.2) / 2.5)))
        return VStack(spacing: 34) {
            headline("Knobs move real sliders.", "Exposure, contrast, highlights. Turn one and the photo changes as you turn.", t: t)
            HStack(spacing: 50) {
                KnobGlyph(angle: exposure * 900)
                    .frame(width: 170, height: 170)
                MockReadout(title: "EXPOSURE", subtitle: "Knob 2 · Y Gamma",
                            value: ValueFormatter.signed(exposure * 1.0, decimals: 2, suffix: " EV"),
                            bar: exposure)
            }
            .opacity(fade(t, from: 0.9))
            Text("The readout slides out under your menu bar, then tucks itself away.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(fade(t, from: 2.8))
        }
    }

    private func wheelScene(_ t: TimeInterval) -> some View {
        let values: [(String, String)] = [
            ("EXPOSURE", ValueFormatter.signed(0.3 * sin(t * 1.3), decimals: 2, suffix: " EV")),
            ("CONTRAST", ValueFormatter.signed(24 * sin(t * 0.9 + 1), decimals: 0)),
            ("SHADOWS", "\(Int(180 + 140 * sin(t * 0.7)))° · \(Int(30 + 20 * sin(t)))%"),
            ("MIDTONES", "\(Int(40 + 30 * cos(t * 0.8)))° · \(Int(18 + 10 * cos(t)))%"),
            ("HIGHLIGHTS", "\(Int(210 + 20 * sin(t * 1.1)))° · \(Int(12 + 6 * sin(t * 2)))%"),
            ("MIDTONE LUM", ValueFormatter.signed(12 * sin(t * 1.6), decimals: 0))
        ]
        return VStack(spacing: 30) {
            headline("Both hands. Everything at once.", "Trackballs are color wheels. Roll all three, turn knobs and rings together. Every move lands in real time.", t: t)
            HStack(spacing: 40) {
                ForEach(0..<3, id: \.self) { i in
                    WheelGlyph(t: t + Double(i) * 1.7, tint: [Color.orange, .yellow, .cyan][i])
                        .frame(width: 130, height: 130)
                }
            }
            .opacity(fade(t, from: 0.8))
            Grid(horizontalSpacing: 20, verticalSpacing: 10) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { col in
                            wheelValue(values[row * 3 + col])
                        }
                    }
                }
            }
            .padding(18)
            .modifier(GlassCard())
            .opacity(fade(t, from: 2.0))
        }
    }

    private func wheelValue(_ item: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.0).font(.system(size: 11, weight: .bold, design: .rounded))
            Text(item.1)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.orange)
        }
        .frame(width: 150, alignment: .leading)
    }


    private func modesScene(_ t: TimeInterval) -> some View {
        let modes = IntroModes.all
        let index = t < 1.8 ? 0 : min(modes.count - 1, Int((t - 1.8) / 3.2))
        let mode = modes[index]
        return VStack(spacing: 22) {
            headline("Hold a key. Get a new panel.", "While you hold it, every knob changes job, and the readout names all twelve. The screens this panel never had.", t: t)
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(mode.color)
                        .frame(width: 30)
                    Text(mode.title)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 240, alignment: .leading)
                    Spacer()
                    Label(mode.how, systemImage: mode.key == nil ? "hand.raised.slash" : "hand.point.down.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mode.key == nil ? Color.secondary : mode.color)
                        .frame(width: 220, alignment: .trailing)
                }
                .frame(width: 820)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.55), value: index)
                PanelStage(
                    t: t,
                    knobLabels: mode.knobs,
                    labelColor: mode.color,
                    changed: mode.changed,
                    heldKeys: mode.key.map { [$0] } ?? [],
                    keyColor: mode.color
                )
                .frame(width: 820, height: 419)
                .animation(.smooth(duration: 0.7), value: index)
            }
            .opacity(fade(t, from: 0.6))
        }
    }

    private func holdToggleScene(_ t: TimeInterval) -> some View {
        // 1.2–5.0s: User held. 5.0–8.0s: released, back to Base. 8.0s: Cursor tapped, Masks stays on.
        let userDown = t > 1.2 && t < 5.0
        let cursorFlash = t > 8.0 && t < 8.5
        let masksOn = t > 8.0
        let readout: IntroReadout
        if masksOn {
            readout = IntroReadout(title: "MASKS", detail: "Tap Cursor again to leave", badge: "ON", badgeSymbol: "lock.fill",
                                   symbol: "lasso.and.sparkles", color: LayerNames.color("MASK"))
        } else if userDown {
            readout = IntroReadout(title: "UPRIGHT & TRANSFORM", detail: "Holding User", badge: "HOLD", badgeSymbol: "hand.point.down.fill",
                                   symbol: "perspective", color: LayerNames.color("TRANSFORM"))
        } else {
            readout = IntroReadout(title: "BASE", detail: t < 1.2 ? "Nothing held" : "Let go. Back to Base.", badge: "", badgeSymbol: nil,
                                   symbol: "square", color: .white)
        }
        let step: String
        if t < 5.0 { step = "1  Hold User: Upright appears" }
        else if t < 8.0 { step = "2  Let go: it’s gone" }
        else { step = "3  Tap Cursor: Masks stays on" }
        var keys: [String] = []
        if userDown { keys.append("button_user") }
        if cursorFlash || masksOn { keys.append("button_cursor") }
        return VStack(spacing: 22) {
            headline("Hold to peek. Tap to stay.", "Some keys work while you hold them. Others turn a mode on until you tap again. The readout always says which.", t: t)
            IntroReadoutView(readout: readout)
                .animation(.smooth(duration: 0.3), value: readout)
            Text(step)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 420)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: step)
            PanelStage(t: t, knobLabels: nil, labelColor: .white, changed: [],
                       heldKeys: keys, keyColor: masksOn ? LayerNames.color("MASK") : LayerNames.color("TRANSFORM"),
                       pressedFlash: cursorFlash)
                .frame(width: 640, height: 327)
                .animation(.smooth(duration: 0.25), value: keys)
        }
        .opacity(fade(t, from: 0.3))
    }

    private func maskWheelScene(_ t: TimeInterval) -> some View {
        let sequence: [(Int, MaskCombine)] = [
            (0, .create), (1, .create), (2, .create), (1, .add), (4, .create), (5, .create)
        ]
        let slot = t < 1.8 ? 0 : min(sequence.count - 1, Int((t - 1.8) / 2.5))
        let (index, combine) = sequence[slot]
        let held = t > 0.9
        return VStack(spacing: 22) {
            headline("Hold Add Node. Pick any mask.",
                     "A circular wheel appears. Spin a ring or roll a ball. The left ring chooses New, Add, Subtract, or Intersect. Let go to create it, then place it with the mouse. Using the balls to place a mask is coming soon.",
                     t: t)
            HStack(spacing: 36) {
                PanelStage(t: t, knobLabels: nil, labelColor: LayerNames.color("MASK"), changed: [],
                           heldKeys: held ? ["button_add_node"] : [], keyColor: LayerNames.color("MASK"))
                    .frame(width: 420, height: 215)
                ToolWheelCanvas(
                    selectedIndex: index,
                    combine: combine,
                    ownerLabel: "Add Node",
                    tick: slot,
                    size: 280
                )
                .scaleEffect(held ? 1 : 0.82)
                .opacity(held ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.82), value: held)
                .animation(.smooth(duration: 0.5), value: index)
                .animation(.smooth(duration: 0.5), value: combine)
            }
            .opacity(fade(t, from: 0.4))
            Text(held ? "\(combine.title) \(MaskToolPicker.tool(at: index).title)  ·  release to create" : "Press and hold Add Node")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LayerNames.color("MASK"))
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.45), value: slot)
        }
    }

    /// Hold Undo. The readout here is the real one, driven by a scripted session, so the tape, the
    /// lanes and the springs are exactly what the panel does.
    private func rewindScene(_ t: TimeInterval) -> some View {
        let frame = IntroRewindDemo.frame(at: t)
        let accent = RewindState.tangentColor(frame.state.tangentColorIndex)
        // Sized for two lanes from the start, so nothing shifts when the tangent appears.
        let readoutHeight = RewindView.height(tangentCount: 2, hasKnobs: true)
        return VStack(spacing: 22) {
            headline("Hold Undo. Rewind+.",
                     "Your whole edit becomes a tape. Step through every change, play it back, and start a tangent from any moment. Nothing is ever lost.",
                     t: t)
            HStack(spacing: 34) {
                PanelStage(t: t, knobLabels: IntroModes.base, labelColor: accent, changed: frame.changedKnobs,
                           heldKeys: frame.keys, keyColor: accent, pressedFlash: frame.flashing, ringGlow: frame.rings)
                    .frame(width: 400, height: 205)
                RewindView(state: frame.state)
                    .frame(width: 560, height: readoutHeight, alignment: .top)
                    .modifier(GlassCard())
                    .opacity(frame.readoutOpacity)
                    .scaleEffect(0.96 + 0.04 * frame.readoutOpacity)
            }
            .opacity(fade(t, from: 0.3))
            Text(frame.step)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .frame(width: 620)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: frame.step)
        }
    }

    private func safetyScene(_ t: TimeInterval) -> some View {
        let items: [(String, String, String)] = [
            ("arrow.uturn.backward", "Undo", "⌘Z takes back any change to your map."),
            ("clock.arrow.circlepath", "Backups", "Saved at launch and before every big change."),
            ("pause.fill", "Pause", "Practice on the panel. Nothing reaches the photo."),
            ("house.fill", "Back to Base", "One click turns every mode off."),
            ("magnifyingglass", "Find Anything", "⌘K searches every Lightroom command."),
            ("exclamationmark.bubble.fill", "Plain Answers", "If a knob does nothing, the readout says why.")
        ]
        return VStack(spacing: 30) {
            headline("You can’t break anything.", "Experiment freely. PanaLux always keeps a way back.", t: t)
            Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { col in
                            safetyCard(items[row * 3 + col], index: row * 3 + col, t: t)
                        }
                    }
                }
            }
        }
    }

    private func safetyCard(_ item: (String, String, String), index i: Int, t: TimeInterval) -> some View {
        let shown = fade(t, from: 0.9 + Double(i) * 0.3, length: 0.5)
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: item.0)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.green.opacity(0.15)))
            Text(item.1).font(.system(size: 18, weight: .semibold))
            Text(item.2)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 38, alignment: .top)
        }
        .padding(18)
        .frame(width: 250, alignment: .leading)
        .modifier(GlassCard())
        .opacity(shown)
        .scaleEffect(0.94 + 0.06 * easeOut(shown))
    }


    private func finaleScene(_ t: TimeInterval) -> some View {
        VStack(spacing: 30) {
            headline("Now try it on your panel.", "The tour watches the panel: turn a knob, hold a key, and it moves on by itself.", t: t)
            PanelStage(t: t, knobLabels: nil, labelColor: .white, changed: [], heldKeys: [], keyColor: .green, chase: true)
                .frame(width: 560, height: 286)
                .opacity(fade(t, from: 0.6))
            HStack(spacing: 14) {
                Button("Maybe Later") { guide.finishIntro(startTour: false) }
                    .controlSize(.large)
                Button {
                    guide.finishIntro(startTour: true)
                } label: {
                    Label("Start the Hands-On Tour", systemImage: "hand.point.up.left.fill")
                        .padding(.horizontal, 6)
                }
                .controlSize(.extraLarge)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .opacity(fade(t, from: 1.0))
        }
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}

// MARK: - Pieces

struct GlassCard: ViewModifier {
    /// Offscreen renders can't draw Liquid Glass; stills use the material fallback.
    static var forceFallback = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !Self.forceFallback {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

/// The panel drawing with live overlays: knob labels, glowing keys, moving light.
struct PanelStage: View {
    let t: TimeInterval
    let knobLabels: [String]?
    let labelColor: Color
    let changed: Set<Int>
    let heldKeys: [String]
    let keyColor: Color
    var pressedFlash = false
    var chase = false
    var sweep = false
    /// Rings being turned right now: 0 left, 1 centre, 2 right.
    var ringGlow: Set<Int> = []

    // Positions in the drawing's 1080 × 552 space.
    static let knobX: [CGFloat] = [70, 152, 232, 313, 418, 499, 580, 660, 767, 848, 929, 1008]
    static let knobY: CGFloat = 125
    static let labelY: CGFloat = 160
    static let balls: [CGPoint] = [CGPoint(x: 293, y: 380), CGPoint(x: 540, y: 380), CGPoint(x: 788, y: 380)]
    static let keys: [String: CGRect] = [
        "button_user": CGRect(x: 48, y: 414, width: 49, height: 33),
        "button_corner_upper_left": CGRect(x: 48, y: 457, width: 49, height: 33),
        "button_cursor": CGRect(x: 545, y: 179, width: 49, height: 33),
        "button_viewer": CGRect(x: 487, y: 179, width: 49, height: 33),
        "button_select": CGRect(x: 603, y: 179, width: 49, height: 33),
        "button_add_node": CGRect(x: 706, y: 179, width: 49, height: 33),
        "button_undo": CGRect(x: 48, y: 266, width: 49, height: 33),
        "button_previous_node": CGRect(x: 925, y: 266, width: 49, height: 33),
        "button_next_node": CGRect(x: 984, y: 266, width: 49, height: 33),
        "button_transport_reverse": CGRect(x: 925, y: 414, width: 49, height: 33),
        "button_transport_forward": CGRect(x: 984, y: 414, width: 49, height: 33),
        "button_transport_stop": CGRect(x: 925, y: 457, width: 108, height: 33)
    ]

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 1080
            let sy = geo.size.height / 552
            ZStack(alignment: .topLeading) {
                if let image = PanelGlyph.image(named: "micro-color-panel") {
                    Image(nsImage: image).resizable()
                }
                if sweep {
                    LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 180 * sx * 1.4)
                        .offset(x: CGFloat((t * 260).truncatingRemainder(dividingBy: 1400)) * sx - 200 * sx)
                        .blendMode(.plusLighter)
                    ForEach(0..<3, id: \.self) { i in
                        let on = sin(t * 2 + Double(i) * 2) > 0
                        Circle()
                            .stroke([Color.orange, .yellow, .cyan][i], lineWidth: 3)
                            .frame(width: 212 * sx, height: 212 * sy)
                            .position(x: Self.balls[i].x * sx, y: Self.balls[i].y * sy)
                            .opacity(on ? 0.9 : 0.12)
                            .animation(.smooth(duration: 0.5), value: on)
                    }
                }
                ForEach(Array(ringGlow), id: \.self) { i in
                    Circle()
                        .stroke(keyColor, lineWidth: 5)
                        .frame(width: 212 * sx, height: 212 * sy)
                        .position(x: Self.balls[i].x * sx, y: Self.balls[i].y * sy)
                        .shadow(color: keyColor, radius: 14)
                }
                if chase {
                    let lit = Int(t * 6) % 12
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(Color.green.opacity(i == lit ? 0.75 : 0))
                            .frame(width: 42 * sx, height: 42 * sx)
                            .blur(radius: 5)
                            .position(x: Self.knobX[i] * sx, y: Self.knobY * sy)
                    }
                }
                if let labels = knobLabels {
                    ForEach(0..<12, id: \.self) { i in
                        let isChanged = changed.contains(i)
                        Text(labels[i])
                            .font(.system(size: max(9, 12.5 * sx), weight: .bold, design: .rounded))
                            .foregroundStyle(isChanged ? Color.black : Color.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 76 * sx, height: 20 * sy)
                            .background(
                                Capsule().fill(isChanged ? labelColor : Color(white: 0.11))
                            )
                            .contentTransition(.opacity)
                            .position(x: Self.knobX[i] * sx, y: Self.labelY * sy)
                        Circle()
                            .stroke(labelColor, lineWidth: 2.5)
                            .frame(width: 44 * sx, height: 44 * sx)
                            .position(x: Self.knobX[i] * sx, y: Self.knobY * sy)
                            .opacity(isChanged ? 0.9 : 0)
                    }
                }
                ForEach(heldKeys, id: \.self) { key in
                    if let r = Self.keys[key] {
                        RoundedRectangle(cornerRadius: 6 * sx, style: .continuous)
                            .fill(keyColor.opacity(pressedFlash ? 0.95 : 0.55))
                            .overlay(RoundedRectangle(cornerRadius: 6 * sx, style: .continuous).stroke(keyColor, lineWidth: 2))
                            .shadow(color: keyColor, radius: 12)
                            .frame(width: r.width * sx, height: r.height * sy)
                            .scaleEffect(pressedFlash ? 0.92 : 1)
                            .position(x: r.midX * sx, y: r.midY * sy)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28 * sx, style: .continuous))
        }
        .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
    }
}

struct IntroMode {
    let title: String
    let how: String
    let symbol: String
    let color: Color
    let key: String?
    let knobs: [String]
    let changed: Set<Int>
}

enum IntroModes {
    static let base = ["Blacks", "Exposure", "Whites", "Contrast", "Clarity", "Texture", "Vibrance", "Shadows", "Highlights", "Saturation", "Temp", "Blending"]

    static let all: [IntroMode] = [
        IntroMode(title: "Base", how: "Nothing held", symbol: "square", color: .white, key: nil,
                  knobs: base, changed: []),
        IntroMode(title: "Color Mixer", how: "Hold Up Shift", symbol: LayerNames.symbol("MIXER"), color: LayerNames.color("MIXER"),
                  key: "button_corner_upper_left",
                  knobs: ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"] + base.suffix(4),
                  changed: Set(0..<8)),
        IntroMode(title: "Upright & Transform", how: "Hold User", symbol: LayerNames.symbol("TRANSFORM"), color: LayerNames.color("TRANSFORM"),
                  key: "button_user",
                  knobs: ["Vertical", "Horizontal", "Rotate", "Aspect", "Scale", "Offset X", "Offset Y"] + base.suffix(5),
                  changed: Set(0..<7)),
        IntroMode(title: "Crop & Straighten", how: "Hold Viewer", symbol: LayerNames.symbol("CROP"), color: LayerNames.color("CROP"),
                  key: "button_viewer",
                  knobs: ["Left", "Right", "Top", "Bottom", "Straighten"] + base.suffix(7),
                  changed: Set(0..<5)),
        IntroMode(title: "Masks", how: "Tap Cursor", symbol: LayerNames.symbol("MASK"), color: LayerNames.color("MASK"),
                  key: "button_cursor",
                  knobs: ["Blacks", "Exposure", "Whites", "Contrast", "Clarity", "Texture", "Dehaze", "Shadows", "Highlights", "Saturation", "Temp", "Amount"],
                  changed: Set(0..<12))
    ]
}

struct IntroReadout: Equatable {
    let title: String
    let detail: String
    let badge: String
    let badgeSymbol: String?
    let symbol: String
    let color: Color
}

/// A still of the notch readout, same proportions as the real one.
struct IntroReadoutView: View {
    let readout: IntroReadout

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: readout.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(readout.color)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.black.opacity(0.7)))
            VStack(alignment: .leading, spacing: 3) {
                Text(readout.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(readout.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 250, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let symbol = readout.badgeSymbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                }
                Text(readout.badge).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(readout.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(readout.color.opacity(readout.badge.isEmpty ? 0 : 0.2)))
            .frame(width: 70, alignment: .trailing)
        }
        .contentTransition(.opacity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 440, height: 74)
        .modifier(GlassCard())
    }
}

private struct KnobGlyph: View {
    let angle: Double
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.07))
            if let img = PanelGlyph.image(named: "hud-knob") {
                Image(nsImage: img).resizable().padding(8).rotationEffect(.degrees(angle))
            }
        }
        .shadow(color: .orange.opacity(0.35), radius: 24)
    }
}

private struct WheelGlyph: View {
    let t: TimeInterval
    let tint: Color
    var body: some View {
        ZStack {
            if let img = PanelGlyph.image(named: "hud-ball") {
                Image(nsImage: img).resizable()
            }
            Circle()
                .fill(tint)
                .frame(width: 14, height: 14)
                .shadow(color: tint, radius: 8)
                .offset(x: CGFloat(cos(t * 1.1)) * 30 * CGFloat(0.6 + 0.4 * sin(t * 0.7)),
                        y: CGFloat(sin(t * 1.1)) * 30 * CGFloat(0.6 + 0.4 * sin(t * 0.7)))
        }
    }
}

private struct MockReadout: View {
    let title: String
    let subtitle: String
    let value: String
    let bar: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(subtitle).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 30)
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Color.orange)
                        .frame(width: max(4, geo.size.width / 2 * bar / 0.5))
                        .offset(x: geo.size.width / 2)
                    Rectangle().fill(Color.white.opacity(0.4)).frame(width: 2).offset(x: geo.size.width / 2)
                }
            }
            .frame(height: 8)
        }
        .padding(22)
        .frame(width: 380)
        .modifier(GlassCard())
    }
}
