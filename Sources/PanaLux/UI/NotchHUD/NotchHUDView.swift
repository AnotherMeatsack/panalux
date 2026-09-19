import SwiftUI

public struct NotchHUDView: View {
    @ObservedObject var feed = HUDFeed.shared
    @ObservedObject var settings = AppSettings.shared
    /// Which tangent is being edited, so a tangent is never invisible.
    @ObservedObject var rewind = RewindEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pinnedMode: ActiveDisplayMode = .idle

    public init() {}

    /// Keep the last live readout on screen while the window slides into the notch.
    private var displayedMode: ActiveDisplayMode {
        if feed.mode == .idle {
            return pinnedMode
        }
        return feed.mode
    }

    private var isExpanded: Bool {
        displayedMode != .idle
    }

    private var isRewind: Bool {
        if case .rewind = displayedMode { return true }
        return false
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                VStack(spacing: 0) {
                    if settings.hudStyle == "minimal" {
                        MinimalReadout(mode: displayedMode)
                    } else {
                        ZStack {
                            contentBody
                                .id(kindKey)
                                .transition(.blurReplace.combined(with: .opacity))
                                .overlay(alignment: .topTrailing) { tangentBadge }
                        }
                        .animation(.smooth(duration: 0.24), value: kindKey)
                        .animation(.smooth(duration: 0.18), value: nameKey)
                    }
                }
                .frame(minWidth: 260, maxWidth: isRewind ? NotchHUDWindowController.rewindWidth : 400)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .modifier(HUDChrome())
                // The window itself slides from the notch; the content only fades, so it moves once.
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.2), value: isExpanded)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .onAppear {
            if feed.mode != .idle {
                pinnedMode = feed.mode
            }
        }
        .onChange(of: feed.mode) { _, newMode in
            if newMode != .idle {
                pinnedMode = newMode
            }
        }
    }

    /// On a tangent, every readout wears the tangent's badge. Rewind draws its own, and the original
    /// is the quiet default, so it only ever appears when it means something.
    @ViewBuilder
    private var tangentBadge: some View {
        if let tangent = rewind.tangentInfo, !isRewind {
            TangentBadge(tangent)
                .padding(.top, 7)
                .padding(.trailing, 10)
                .transition(.scale(scale: 0.7, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    /// The layout family. Changing family cross-fades; changing control within a family
    /// keeps the view and animates only its text.
    private var kindKey: String {
        switch displayedMode {
        case .idle: return "idle"
        case .knob: return "knob"
        case .ring: return "ring"
        case .trackball: return "ball"
        case .multi(let r): return "multi-\(r.count > 3 ? 2 : 1)"
        case .layerBanner(let layer, _, _, _, _, let grid): return "banner-\(layer)-\(grid.isEmpty)"
        case .action: return "action"
        case .rewind: return "rewind"
        }
    }

    private var nameKey: String {
        switch displayedMode {
        case .knob(let name, let param, _, _, _, _), .ring(let name, let param, _, _, _, _): return name + param
        case .trackball(let name, _, _, _): return name
        case .action(let name, let label, _): return name + label
        case .multi(let r): return r.map(\.control).joined()
        default: return ""
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch displayedMode {
        case .idle:
            EmptyView()

        case .knob(let name, let param, let value, let displayValue, let isFine, let angle):
            VirtualOLEDReadout(
                name: name,
                param: param,
                value: value,
                displayValue: displayValue,
                isFine: isFine,
                angleDegrees: angle
            )

        case .ring(let name, let param, _, let displayValue, let isFine, let angle):
            RingReadout(
                name: name,
                param: param,
                displayValue: displayValue,
                isFine: isFine,
                angleDegrees: angle
            )

        case .trackball(let name, let state, let isFine, let companion):
            VectorscopeView(name: name, state: state, isFine: isFine, companion: companion)

        case .layerBanner(let layer, let variant, let hint, let chips, let latched, let grid):
            LayerBannerView(layer: layer, variant: variant, hint: hint, chips: chips, latched: latched, grid: grid)

        case .action(let name, let label, let phase):
            ButtonFlashView(name: name, label: label, phase: phase)

        case .multi(let readings):
            MultiReadout(readings: readings)

        case .rewind(let state):
            RewindView(state: state)
        }
    }
}

/// One quiet line: what you touched and where it is.
struct MinimalReadout: View {
    let mode: ActiveDisplayMode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(accent)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var symbol: String {
        switch mode {
        case .knob: return "dial.medium"
        case .ring: return "circle.circle"
        case .trackball: return "circle.dotted"
        case .layerBanner(let layer, _, _, _, _, _): return LayerNames.symbol(layer)
        case .action(_, _, let phase): return PhaseStyle.symbol(phase) ?? "button.programmable"
        case .multi: return "dial.medium"
        case .rewind: return "gobackward"
        case .idle: return "circle"
        }
    }

    private var accent: Color {
        switch mode {
        case .layerBanner(let layer, _, _, _, _, _): return LayerNames.color(layer)
        case .action(_, _, let phase): return PhaseStyle.color(phase)
        case .rewind(let state): return state.branchName == nil ? RewindState.accent : RewindState.branchAccent
        default: return .orange
        }
    }

    private var title: String {
        switch mode {
        case .knob(_, let param, _, _, _, _), .ring(_, let param, _, _, _, _): return param
        case .trackball(let name, _, _, _): return name.replacingOccurrences(of: "TB_", with: "").capitalized
        case .layerBanner(let layer, _, let hint, _, _, _): return hint ?? LayerNames.defaultTitle(layer)
        case .action(_, let label, _): return label
        case .multi(let r): return r.map(\.param).joined(separator: " · ")
        case .rewind(let state): return state.branchName ?? "Rewind"
        case .idle: return ""
        }
    }

    private var value: String {
        switch mode {
        case .knob(_, _, _, let v, _, _), .ring(_, _, _, let v, _, _): return v
        case .trackball(_, let state, _, _):
            return "\(Int((state.hueAngle * 360).rounded()))° · \(Int((state.saturation * 100).rounded()))%"
        case .layerBanner(_, let variant, _, _, let latched, _):
            return [variant, latched ? "ON" : "HOLD"].compactMap { $0 }.joined(separator: " · ")
        case .multi(let r): return r.map(\.value).joined(separator: " · ")
        case .rewind(let state): return state.caption
        default: return ""
        }
    }
}

/// Up to six controls at once, in panel order. two hands on the panel.
struct MultiReadout: View {
    let readings: [LiveReading]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(3, max(2, readings.count)))
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(readings, id: \.control) { r in
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.param.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(r.value)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

enum PhaseStyle {
    static func symbol(_ phase: ActionPhase) -> String? {
        switch phase {
        case .sent: return nil
        case .working: return nil
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .blocked: return "pause.circle.fill"
        }
    }

    static func color(_ phase: ActionPhase) -> Color {
        switch phase {
        case .sent, .working: return .orange
        case .done: return .green
        case .failed: return .red
        case .blocked: return .yellow
        }
    }
}

/// Liquid Glass is applied by NSGlassEffectView on macOS 26+. Older systems keep the frosted fallback.
private struct HUDChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 20))
        } else if #available(macOS 26.0, *) {
            content.background(Color.black.opacity(contrast == .increased ? 0.5 : 0.14), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.16), lineWidth: 0.75))
        } else {
            content.glassmorphism(cornerRadius: 20, specularAlpha: 0.35)
        }
    }
}
