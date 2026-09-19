import SwiftUI
import AppKit
import Combine

/// A click-through perimeter on Lightroom's display. The photograph's centre stays clear.
final class RewindEdgeWindowController {
    static let shared = RewindEdgeWindowController()
    private var window: NSPanel?
    private var subscriptions = Set<AnyCancellable>()

    func setup() {
        guard window == nil, !AppRuntime.isRenderingStills else { return }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: LiveRewindEdges())
        window = panel
        RewindEngine.shared.$isRewinding.receive(on: DispatchQueue.main).sink { [weak self] active in
            guard let panel = self?.window else { return }
            if active, let screen = NotchHUDWindowController.lightroomScreen() ?? NSScreen.main {
                panel.setFrame(screen.frame, display: true)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    panel.animator().alphaValue = 1
                }
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    if !RewindEngine.shared.isRewinding { panel.orderOut(nil) }
                })
            }
        }.store(in: &subscriptions)
    }
}

private struct LiveRewindEdges: View {
    @ObservedObject var engine = RewindEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var movementAt = Date.distantPast
    @State private var direction = -1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !engine.isRewinding || reduceMotion)) { context in
            let age = context.date.timeIntervalSince(movementAt)
            let energy = engine.isPlaying ? 0.8 : (reduceMotion ? 0.5 : RewindEdgeEffect.glowEnergy(age: age))
            RewindEdgeEffect(phase: engine.state.playhead / max(1, engine.state.window),
                             energy: energy, direction: direction, reduceMotion: reduceMotion, state: engine.state)
        }
        .onChange(of: engine.state.playhead) { old, new in
            direction = new < old ? -1 : 1
            movementAt = Date()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Deterministic drawing also used by visual regression renders.
struct RewindEdgeEffect: View {
    var phase: Double
    var energy: Double
    var direction: Double
    var reduceMotion = false
    var state: RewindState = .empty

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size)
            let bounds = screen.insetBy(dx: 6, dy: 6)
            let boundary = Path(roundedRect: bounds, cornerRadius: 32)
            var corners = Path(screen)
            corners.addPath(boundary)
            context.fill(corners, with: .color(.black), style: FillStyle(eoFill: true))
            context.clip(to: boundary)
            let aqua = Color(red: 0.28, green: 0.87, blue: 1)
            let violet = Color(red: 0.52, green: 0.40, blue: 1)
            // Broad feathered light on all four edges, with no tint over the central image.
            let depth = min(210.0, min(size.width, size.height) * 0.22)
            let strength = 0.27 + energy * 0.43
            for edge in 0..<4 {
                let start: CGPoint
                let end: CGPoint
                switch edge {
                case 0: start = CGPoint(x: 0, y: 0); end = CGPoint(x: 0, y: depth)
                case 1: start = CGPoint(x: 0, y: size.height); end = CGPoint(x: 0, y: size.height - depth)
                case 2: start = CGPoint(x: 0, y: 0); end = CGPoint(x: depth, y: 0)
                default: start = CGPoint(x: size.width, y: 0); end = CGPoint(x: size.width - depth, y: 0)
                }
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [(edge % 2 == 0 ? aqua : violet).opacity(strength), .clear]),
                    startPoint: start, endPoint: end))
            }
            // Expanding/contracting rounded light echoes make direction visible in peripheral vision.
            let count = reduceMotion ? 1 : 7
            for i in 0..<count {
                let travel = reduceMotion ? 0.15 : (Double(i) / Double(count) + phase * 0.9).truncatingRemainder(dividingBy: 1)
                let fraction = travel < 0 ? travel + 1 : travel
                let inset = 3 + fraction * depth
                let rect = bounds.insetBy(dx: inset, dy: inset)
                let opacity = (1 - fraction) * (0.16 + energy * 0.46)
                context.stroke(Path(roundedRect: rect, cornerRadius: 24 + fraction * 35),
                               with: .linearGradient(Gradient(colors: [aqua.opacity(opacity), violet.opacity(opacity), aqua.opacity(opacity)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                               lineWidth: 1 + (1 - fraction) * energy * 2)
            }
            // These are the exact nearby stops supplied to the small Rewind timeline.
            let rail = bounds.insetBy(dx: 14, dy: 14)
            for stop in state.steps {
                let offset = (stop - state.playhead) / max(1, state.window)
                let unit = (0.5 + offset).truncatingRemainder(dividingBy: 1)
                let point = Self.perimeter(unit < 0 ? unit + 1 : unit, in: rail, radius: 30)
                let isCurrent = abs(stop - state.playhead) < 0.00001
                let length = isCurrent ? 30.0 : 14.0 + energy * 7
                var tick = Path()
                tick.move(to: point.0)
                tick.addLine(to: CGPoint(x: point.0.x + point.1.dx * length, y: point.0.y + point.1.dy * length))
                context.stroke(tick, with: .color(isCurrent ? .white : aqua.opacity(0.6 + energy * 0.35)),
                               style: StrokeStyle(lineWidth: isCurrent ? 3 : 1.5, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: point.0.x - 2, y: point.0.y - 2, width: 4, height: 4)), with: .color(aqua))
            }
            context.stroke(Path(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerRadius: 32),
                           with: .color(aqua.opacity(0.25 + energy * 0.35)), lineWidth: 2)
        }
    }
    /// Brightness has a pause cushion; position never has one. New input restarts the hold
    /// from the same full intensity, so a brief stop cannot produce a dark flash.
    static func glowEnergy(age: TimeInterval) -> Double {
        let progress = min(1, max(0, (age - 0.35) / 0.55))
        return 1 - progress * progress * (3 - 2 * progress)
    }

    static func perimeter(_ unit: Double, in rect: CGRect, radius: Double) -> (CGPoint, CGVector) {
        let w = rect.width - 2 * radius, h = rect.height - 2 * radius
        let arc = Double.pi * radius / 2
        var distance = unit * (2 * w + 2 * h + 4 * arc)
        let lengths = [w, arc, h, arc, w, arc, h, arc]
        for segment in 0..<8 {
            let length = lengths[segment]
            if distance > length { distance -= length; continue }
            let f = length > 0 ? distance / length : 0
            switch segment {
            case 0: return (CGPoint(x: rect.minX + radius + distance, y: rect.minY), CGVector(dx: 0, dy: 1))
            case 2: return (CGPoint(x: rect.maxX, y: rect.minY + radius + distance), CGVector(dx: -1, dy: 0))
            case 4: return (CGPoint(x: rect.maxX - radius - distance, y: rect.maxY), CGVector(dx: 0, dy: -1))
            case 6: return (CGPoint(x: rect.minX, y: rect.maxY - radius - distance), CGVector(dx: 1, dy: 0))
            default:
                let corner = (segment - 1) / 2
                let centers = [CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                               CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                               CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                               CGPoint(x: rect.minX + radius, y: rect.minY + radius)]
                let angle = (-Double.pi / 2) + Double(corner) * Double.pi / 2 + f * Double.pi / 2
                let center = centers[corner]
                return (CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius),
                        CGVector(dx: -cos(angle), dy: -sin(angle)))
            }
        }
        return (CGPoint(x: rect.minX + radius, y: rect.minY), CGVector(dx: 0, dy: 1))
    }

}
