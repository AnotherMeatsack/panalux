import SwiftUI

public struct LayerBannerView: View {
    public let layer: String
    public let variant: String?
    public let hint: String?
    public let chips: [String]
    public let latched: Bool
    public let grid: [KnobCell]

    public init(layer: String, variant: String?, hint: String?, chips: [String] = [], latched: Bool = false, grid: [KnobCell] = []) {
        self.layer = layer
        self.variant = variant
        self.hint = hint
        self.chips = chips
        self.latched = latched
        self.grid = grid
    }

    public var body: some View {
        VStack(spacing: 6) {
            ControlFlashView(
                symbol: symbolForLayer(layer),
                kicker: resolvedKicker,
                title: hint ?? LayerNames.defaultTitle(layer),
                role: latched ? "ON" : "HOLD",
                roleSymbol: latched ? "lock.fill" : "hand.point.down.fill",
                chips: chips,
                variant: variant,
                accent: colorForLayer(layer),
                phase: nil
            )
            if !grid.isEmpty {
                KnobRowGrid(cells: grid, accent: colorForLayer(layer))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private var resolvedKicker: String {
        let engine = StudioEngine.shared
        if let name = engine.physicallyHeldControlNames.first(where: {
            let spec = engine.profile.buttons[$0]
            return spec?.hold_layer?.uppercased() == layer.uppercased()
                || spec?.layer?.uppercased() == layer.uppercased()
        }) {
            return "Holding \(PanelLayout.label(forControl: name))"
        }
        if latched {
            if let key = engine.profile.buttons.first(where: { $0.value.layer == layer })?.key {
                return "Tap \(PanelLayout.label(forControl: key)) to leave"
            }
            return "Back to Base from the menu bar"
        }
        return LayerNames.defaultTitle(layer) == layer.capitalized ? layer : "Mode"
    }
}

/// The twelve knobs, two rows of six, like the missing panel screens.
struct KnobRowGrid: View {
    let cells: [KnobCell]
    let accent: Color

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                HStack(spacing: 3) {
                    if let band = LayerNames.bandColor(in: cell.label), cell.isOverlay {
                        Circle().fill(band).frame(width: 5, height: 5)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(cell.isOverlay ? accent : .white.opacity(0.3))
                    }
                    Text(cell.label)
                        .font(.system(size: 10, weight: cell.isOverlay ? .semibold : .regular, design: .rounded))
                        .foregroundColor(cell.isOverlay ? .white : .white.opacity(0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    // Where that slider is sitting, so the mode can be read without
                    // turning anything first.
                    if let value = cell.value {
                        Text(value)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(cell.isOverlay ? accent : .white.opacity(0.3))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 5)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(cell.isOverlay ? accent.opacity(0.14) : Color.white.opacity(0.04))
                )
            }
        }
    }
}

public struct ButtonFlashView: View {
    public let name: String
    public let label: String
    public let phase: ActionPhase

    public init(name: String, label: String, phase: ActionPhase = .sent) {
        self.name = name
        self.label = label
        self.phase = phase
    }

    public var body: some View {
        ControlFlashView(
            symbol: iconForButton(name),
            kicker: kicker,
            title: label,
            role: roleText,
            roleSymbol: nil,
            chips: [],
            variant: nil,
            accent: PhaseStyle.color(phase),
            phase: phase
        )
    }

    private var kicker: String {
        switch name {
        case "BASE", "PAUSE", "FOCUS": return "PanaLux"
        default: return PanelLayout.label(forControl: name)
        }
    }

    private var roleText: String {
        switch phase {
        case .sent: return "TAP"
        case .working: return "WORKING"
        case .done: return "DONE"
        case .failed: return "FAILED"
        case .blocked: return "NOT SENT"
        }
    }
}

/// Shared tap/hold readout — same 52pt well + type hierarchy as knobs, rings, and balls.
struct ControlFlashView: View {
    let symbol: String
    let kicker: String
    let title: String
    let role: String
    let roleSymbol: String?
    let chips: [String]
    let variant: String?
    let accent: Color
    let phase: ActionPhase?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                    .frame(width: 52, height: 52)
                if phase == .working {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                } else {
                    Image(systemName: phase.flatMap(PhaseStyle.symbol) ?? symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accent)
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let variant {
                        Text(variant.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.18)))
                    }
                }
                Text(kicker.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)

                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(chips.prefix(2)), id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 2)

            HStack(spacing: 3) {
                if let roleSymbol {
                    Image(systemName: roleSymbol)
                        .font(.system(size: 7, weight: .bold))
                }
                Text(role)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .fixedSize()
            .foregroundColor(accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent.opacity(role == "ON" ? 0.2 : 0)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private func symbolForLayer(_ l: String) -> String {
    let symbol = LayerNames.symbol(l)
    if symbol == "square.3.layers.3d" {
        return iconForButton(l.uppercased().replacingOccurrences(of: " ", with: "_"))
    }
    return symbol
}

private func colorForLayer(_ l: String) -> Color {
    LayerNames.color(l)
}

private func iconForButton(_ name: String) -> String {
    switch name {
    case "GRAB_STILL": return "camera.fill"
    case "PLAY", "PLAY_STILL": return "square.and.arrow.up"
    case "COPY": return "doc.on.doc"
    case "PASTE": return "doc.on.clipboard"
    case "UNDO": return "arrow.uturn.backward"
    case "REDO": return "arrow.uturn.forward"
    case "AUTO_COLOR": return "wand.and.stars"
    case "LOOP": return "arrow.triangle.2.circlepath"
    case "USER": return "person.crop.square"
    case "SHIFT": return "shift.fill"
    case "OFFSET": return "circle.grid.cross.fill"
    case "DELETE": return "flag.fill"
    case "RESET_ALL", "STOP": return "arrow.counterclockwise"
    case "PREV_FRAME", "PREV_CLIP", "PREV_NODE", "PREV_STILL", "PREV_KEYFRM": return "chevron.left"
    case "NEXT_FRAME", "NEXT_STILL", "NEXT_NODE", "NEXT_CLIP", "NEXT_KEYFRM": return "chevron.right"
    case "SELECT": return "star.fill"
    case "VIEWER": return "rectangle.split.3x1"
    case "WIPE_STILL": return "rectangle.lefthalf.inset.filled"
    case "H/LITE": return "circle.lefthalf.filled"
    case "CURSOR": return "lasso"
    case "ADD_WINDOW", "ADD_NODE", "ADD_KEYFRM": return "plus.circle"
    case "BASE": return "house.fill"
    case "PAUSE": return "pause.fill"
    case "FOCUS": return "dial.medium.fill"
    default: return "button.programmable"
    }
}
