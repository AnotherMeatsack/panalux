import SwiftUI
import AppKit
import Combine

/// A click-through glassmorphic time-portal perimeter on Lightroom's display.
/// Features subtle chromatic aberration (cyan/magenta color separation along the lens rim),
/// delicate organic blooming, continuous cascading ripple wavefronts that hug the bezel edge,
/// and native GPU-accelerated directional motion blur.
/// Strictly overlays ONLY the display containing Lightroom, keeping the center 100% clear.
final class RewindEdgeWindowController {
    static let shared = RewindEdgeWindowController()
    private var window: NSPanel?
    private var subscriptions = Set<AnyCancellable>()

    func setup() {
        guard window == nil, !AppRuntime.isRenderingStills else { return }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: LiveRewindEdges())
        window = panel

        RewindEngine.shared.$isRewinding.receive(on: DispatchQueue.main).sink { [weak self] active in
            guard let self = self, let panel = self.window else { return }
            RewindEdgeAnimator.shared.reset()
            if active {
                // Strictly target ONLY the screen Lightroom is currently on
                guard let screen = NotchHUDWindowController.lightroomScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
                panel.setFrame(screen.frame, display: true)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 1
                }
            } else {
                RewindEdgeAnimator.shared.reset()
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    panel.orderOut(nil)
                })
            }
        }.store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let panel = self.window, panel.isVisible else { return }
                if let screen = NotchHUDWindowController.lightroomScreen() ?? NSScreen.main {
                    panel.setFrame(screen.frame, display: true)
                }
            }
            .store(in: &subscriptions)

        // Ensure the overlay disappears and rewind ends if the user activates an external editor (e.g. Photoshop)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let id = app.bundleIdentifier else { return }
                let isExternalCreative = id.contains("Photoshop") || id.contains("Resolve") || id.contains("FinalCut") || id.contains("Premiere")
                if isExternalCreative {
                    if RewindEngine.shared.isRewinding {
                        RewindEngine.shared.endRewind(announce: false)
                    }
                    self?.window?.orderOut(nil)
                }
            }
            .store(in: &subscriptions)
    }

    static func isLightroomFrontmost() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return id == "com.adobe.LightroomClassicCC7" || id == "com.adobe.Lightroom"
    }
}

/// Physics-driven animator tracking continuous physical wheel rotation,
/// angular momentum, velocity-based motion blur, and reactive energy.
public final class RewindEdgeAnimator: ObservableObject {
    public static let shared = RewindEdgeAnimator()

    /// Continuous rotation phase without jumping or snapping
    @Published public private(set) var continuousPhase: Double = 0.0
    /// Where the wheel has actually taken the phase; the drawn phase eases toward it so packets never step.
    private var targetPhase: Double = 0.0
    /// Smoothed angular velocity (0.0 … 3.0+) for motion blur and line width
    @Published public private(set) var smoothedVelocity: Double = 0.0
    /// Reactive energy (0.15 … 1.0) governing subtle glow bloom and intensity
    @Published public private(set) var reactiveEnergy: Double = 0.20
    /// Direction of motion: -1.0 for rewind/counter-clockwise, +1.0 for forward/clockwise
    @Published public private(set) var currentDirection: Double = -1.0

    /// When the overlay last (re)started; drives the opening colour sweep
    public private(set) var startedAt: Date = Date()

    private var lastTickTime: Date = .distantPast
    private var lastWheelTime: Date = .distantPast

    // 0.025 phase per wheel unit: 40 units (one full detent click) equals exactly 1.0 ripple cycle
    private let phaseSensitivity: Double = 0.025

    public init() {}

    /// Called on hardware wheel/ring rotation packets in Rewind mode
    public func noteWheelDelta(command: String, deltaUnits: Double) {
        guard deltaUnits.isFinite, deltaUnits != 0 else { return }

        // Continuous phase accumulation: turning in reverse cascades inward, forward cascades outward
        targetPhase += deltaUnits * phaseSensitivity
        currentDirection = deltaUnits < 0 ? -1.0 : 1.0

        let now = Date()
        let dt = max(0.005, min(0.10, now.timeIntervalSince(lastWheelTime)))
        lastWheelTime = now

        let instantVelocity = min(3.0, abs(deltaUnits) / (dt * 50.0))
        smoothedVelocity = smoothedVelocity * 0.85 + instantVelocity * 0.15

        // Reactive energy flares subtly with rotation intensity
        reactiveEnergy = min(0.7, reactiveEnergy + min(0.05, abs(deltaUnits) * 0.005 + instantVelocity * 0.012))
    }

    /// 60fps frame tick to update inertia decay and playback tracking
    public func tick(date: Date, isPlaying: Bool, playSpeed: Double, playDirection: Double, reduceMotion: Bool) {
        guard !reduceMotion else {
            smoothedVelocity = 0
            reactiveEnergy = 0.18
            return
        }

        let now = date
        let dt = lastTickTime == .distantPast ? 0.016 : max(0.001, min(0.05, now.timeIntervalSince(lastTickTime)))
        lastTickTime = now
        // Glide the drawn phase toward the wheel's phase so motion is continuous, not packet by packet.
        continuousPhase += (targetPhase - continuousPhase) * (1 - exp(-dt * 5))

        if isPlaying {
            // During auto-playback, continuously advance the ripple cascade
            let playDelta = playDirection * playSpeed * dt * 0.75
            targetPhase += playDelta
            currentDirection = playDirection < 0 ? -1.0 : 1.0
            smoothedVelocity = max(smoothedVelocity, min(2.0, abs(playSpeed) * 0.4))
            reactiveEnergy = max(reactiveEnergy, 0.65)
        } else {
            // Natural momentum: residual drift glides smoothly
            if smoothedVelocity > 0.01 {
                targetPhase += currentDirection * smoothedVelocity * dt * 0.2
            }

            // Exponential deceleration (smooth friction over ~280ms)
            let decay = pow(0.95, dt * 60.0)
            smoothedVelocity *= decay
            if smoothedVelocity < 0.004 { smoothedVelocity = 0 }

            // Smooth decay down to organic living floor
            let idleFloor = 0.18
            if now.timeIntervalSince(lastWheelTime) > 0.08 {
                let energyDecay = dt * 0.5
                reactiveEnergy = max(idleFloor, reactiveEnergy - energyDecay)
            }
        }
    }

    public func reset() {
        smoothedVelocity = 0
        reactiveEnergy = 0.20
        targetPhase = continuousPhase
        startedAt = Date()
        lastTickTime = .distantPast
        lastWheelTime = .distantPast
    }
}

private struct LiveRewindEdges: View {
    @ObservedObject var engine = RewindEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !engine.isRewinding)) { context in
            RewindEdgeEffect(
                phase: RewindEdgeAnimator.shared.continuousPhase,
                energy: RewindEdgeAnimator.shared.reactiveEnergy,
                direction: RewindEdgeAnimator.shared.currentDirection,
                velocity: RewindEdgeAnimator.shared.smoothedVelocity,
                reduceMotion: reduceMotion,
                state: engine.state,
                age: context.date.timeIntervalSince(RewindEdgeAnimator.shared.startedAt)
            )
            .onChange(of: context.date) { _, newDate in
                RewindEdgeAnimator.shared.tick(
                    date: newDate,
                    isPlaying: engine.isPlaying,
                    playSpeed: engine.playSpeed,
                    playDirection: engine.playDirection,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Slim, Transparent Glassmorphic Time-Portal with Chromatic Aberration,
/// Edge-Hugging Cascading Wavefronts, and Directional Motion Blur.
public struct RewindEdgeEffect: View {
    public var phase: Double
    public var energy: Double
    public var direction: Double = -1.0
    public var velocity: Double = 0.0
    public var reduceMotion: Bool = false
    public var state: RewindState = .empty
    /// Seconds since the overlay opened; the colour sweep plays over the first 1.3s
    public var age: Double = 10

    public init(phase: Double, energy: Double, direction: Double = -1.0, velocity: Double = 0.0, reduceMotion: Bool = false, state: RewindState = .empty, age: Double = 10) {
        self.age = age
        self.phase = phase
        self.energy = energy
        self.direction = direction
        self.velocity = velocity
        self.reduceMotion = reduceMotion
        self.state = state
    }

    public var body: some View {
        Canvas { outer, size in
            // Organic, not crisp: everything is drawn into one softly blurred, mostly transparent layer.
            outer.opacity = 0.42
            outer.drawLayer { context in
            context.addFilter(.blur(radius: reduceMotion ? 1.5 : 3.2))
            let bounds = CGRect(origin: .zero, size: size)
            let cornerRadius: CGFloat = 26

            // Subtle living breathing shimmer: delicate organic pulse
            let t = Date().timeIntervalSinceReferenceDate
            let organicPulse = reduceMotion ? 0.0 : (0.012 * sin(t * 0.9))
            let totalEnergy = min(1.0, max(0.12, energy + organicPulse))

            // Slim perimeter depth: hugs the outer screen bezel tightly (32px to 48px max)
            // Leaves 96%+ of the display area completely clear and unobstructed
            let baseRimDepth: CGFloat = 32.0
            let bloomExpansion = CGFloat(min(8.0, totalEnergy * 6.0))
            let rimDepth = baseRimDepth + bloomExpansion

            let cyan = Color(red: 0.15, green: 0.88, blue: 1.0)
            let magenta = Color(red: 1.0, green: 0.22, blue: 0.70)
            let violet = Color(red: 0.58, green: 0.38, blue: 1.0)
            let tangentColor = RewindState.tangentColor(state.tangentColorIndex)
            let glassWhite = Color(white: 0.98)

            // MARK: - Layer 1: Delicate Feathered Edge Shadow
            // Ultra-subtle, whisper-soft feathered edge framing (never darkens or dims the photo)
            let edgeShadowDepth = rimDepth * 0.85
            let edgeShadowOpacity = 0.06 + totalEnergy * 0.10
            for edge in 0..<4 {
                let start: CGPoint
                let end: CGPoint
                switch edge {
                case 0: start = CGPoint(x: 0, y: 0); end = CGPoint(x: 0, y: edgeShadowDepth)
                case 1: start = CGPoint(x: 0, y: size.height); end = CGPoint(x: 0, y: size.height - edgeShadowDepth)
                case 2: start = CGPoint(x: 0, y: 0); end = CGPoint(x: edgeShadowDepth, y: 0)
                default: start = CGPoint(x: size.width, y: 0); end = CGPoint(x: size.width - edgeShadowDepth, y: 0)
                }
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [violet.opacity(edgeShadowOpacity), .clear]),
                    startPoint: start, endPoint: end))
            }

            // MARK: - Layer 2: Compact Corner Lens Glints
            // Subtle luminescent optical highlights nestled in the very corner radii
            let cornerBloomRadius = rimDepth * 1.5
            let cornerOpacity = 0.14 + totalEnergy * 0.16
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(colors: [cyan.opacity(cornerOpacity), .clear]),
                center: .zero, startRadius: 4, endRadius: cornerBloomRadius))
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(colors: [magenta.opacity(cornerOpacity * 0.9), .clear]),
                center: CGPoint(x: size.width, y: 0), startRadius: 4, endRadius: cornerBloomRadius))
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(colors: [violet.opacity(cornerOpacity), .clear]),
                center: CGPoint(x: 0, y: size.height), startRadius: 4, endRadius: cornerBloomRadius))
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(colors: [tangentColor.opacity(cornerOpacity * 0.9), .clear]),
                center: CGPoint(x: size.width, y: size.height), startRadius: 4, endRadius: cornerBloomRadius))

            // MARK: - Layer 3: Prismatic Glass Rim (Refractive Dispersion)
            // Crisp, razor-thin refractive glass contours along the bezel border
            let dispersion = CGFloat(1.4 + totalEnergy * 0.6)

            // Cyan refraction fringe
            let cyanBounds = bounds.offsetBy(dx: -dispersion, dy: -dispersion * 0.7)
            context.stroke(
                Path(roundedRect: cyanBounds, cornerRadius: cornerRadius),
                with: .color(cyan.opacity(0.18 + totalEnergy * 0.18)),
                lineWidth: 1.4
            )

            // Magenta refraction fringe
            let magentaBounds = bounds.offsetBy(dx: dispersion, dy: dispersion * 0.7)
            context.stroke(
                Path(roundedRect: magentaBounds, cornerRadius: cornerRadius),
                with: .color(magenta.opacity(0.18 + totalEnergy * 0.18)),
                lineWidth: 1.4
            )

            // Specular Frosted Glass Rim with rotating optical phase reflection
            let rimAngle = phase * 0.3
            let startP = CGPoint(x: size.width * (0.5 + 0.5 * cos(rimAngle)), y: size.height * (0.5 + 0.5 * sin(rimAngle)))
            let endP = CGPoint(x: size.width * (0.5 - 0.5 * cos(rimAngle)), y: size.height * (0.5 - 0.5 * sin(rimAngle)))
            context.stroke(
                Path(roundedRect: bounds, cornerRadius: cornerRadius),
                with: .linearGradient(
                    Gradient(colors: [
                        glassWhite.opacity(0.40 + totalEnergy * 0.22),
                        cyan.opacity(0.24),
                        glassWhite.opacity(0.50),
                        magenta.opacity(0.24),
                        tangentColor.opacity(0.28)
                    ]),
                    startPoint: startP,
                    endPoint: endP
                ),
                lineWidth: 1.5
            )

            // MARK: - Layer 3b: Colour Wave Sweep
            // A prismatic band of light travels across the screen and shows on the rim as it passes.
            // It plays once on open, then again whenever the wheel carries the phase around.
            if !reduceMotion {
                let intro = age < 1.3 ? age / 1.3 : nil
                let loop = phase * 0.35
                let cycle = loop - loop.rounded(.down)
                let loopFade = min(1.0, max(0.0, (energy - 0.2) / 0.35))
                let progress = intro.map { 1 - pow(1 - $0, 2) } ?? (loopFade > 0.01 ? cycle : nil)
                if let progress {
                    let diag = hypot(size.width, size.height)
                    let along = CGVector(dx: size.width / diag, dy: size.height / diag)
                    let bandLength = diag * 0.42
                    let travel = (progress * (1.0 + 0.42) - 0.42) * diag
                    let dirSign: CGFloat = (intro != nil || direction >= 0) ? 1 : -1
                    let base = dirSign > 0 ? 0.0 : diag
                    let head = base + dirSign * travel
                    let tail = head - dirSign * bandLength
                    let fade = intro != nil ? 1.0 : loopFade * 0.7
                    let band = Gradient(colors: [
                        .clear,
                        cyan.opacity(0.55 * fade),
                        violet.opacity(0.65 * fade),
                        magenta.opacity(0.60 * fade),
                        tangentColor.opacity(0.50 * fade),
                        .clear
                    ])
                    context.stroke(
                        Path(roundedRect: bounds, cornerRadius: cornerRadius),
                        with: .linearGradient(band,
                            startPoint: CGPoint(x: tail * along.dx, y: tail * along.dy),
                            endPoint: CGPoint(x: head * along.dx, y: head * along.dy)),
                        lineWidth: rimDepth * 1.1
                    )
                }
            }

            // MARK: - Layer 4: Edge-Hugging Cascading Ripple Lines
            // Wavefronts stay strictly within 5px to 32px of the physical screen border.
            // Continuous phase accumulation + sine envelope guarantees zero jumps and seamless looping.
            let waveCount = reduceMotion ? 3 : 5

            // Native GPU Metal Motion Blur Layer
            let blurRadius: CGFloat = 0
            if blurRadius > 0.5 && !reduceMotion {
                context.drawLayer { blurLayer in
                    blurLayer.addFilter(.blur(radius: blurRadius))
                    for i in 0..<waveCount {
                        let waveProgress = (Double(i) / Double(waveCount) - phase).truncatingRemainder(dividingBy: 1.0)
                        let fraction = waveProgress < 0 ? waveProgress + 1.0 : waveProgress
                        let envelope = sin(fraction * .pi)
                        guard envelope > 0.02 else { continue }
                        let waveOpacity = envelope * (0.16 + totalEnergy * 0.24)
                        let rippleDepth = 5.0 + fraction * (rimDepth * 0.60)
                        let waveRadius = max(14.0, cornerRadius - fraction * 8.0)

                        // Directional motion smear trail passes
                        let trailSteps = min(3, max(1, Int(velocity * 1.8)))
                        for step in 1...trailSteps {
                            let trailLag = CGFloat(Double(step) * 2.0 * min(2.0, velocity)) * (direction < 0 ? -1.0 : 1.0)
                            let trailDepth = max(3.0, rippleDepth + trailLag)
                            let trailRect = bounds.insetBy(dx: trailDepth, dy: trailDepth)
                            let trailOpacity = waveOpacity * (1.0 - Double(step) / Double(trailSteps + 1)) * 0.40

                            blurLayer.stroke(
                                Path(roundedRect: trailRect.offsetBy(dx: -dispersion * 0.5, dy: -dispersion * 0.3), cornerRadius: waveRadius),
                                with: .color(cyan.opacity(trailOpacity)),
                                lineWidth: 2.0 + CGFloat(step) * 1.0
                            )
                            blurLayer.stroke(
                                Path(roundedRect: trailRect.offsetBy(dx: dispersion * 0.5, dy: dispersion * 0.3), cornerRadius: waveRadius),
                                with: .color(magenta.opacity(trailOpacity)),
                                lineWidth: 2.0 + CGFloat(step) * 1.0
                            )
                        }
                    }
                }
            }

            let warpAmp: CGFloat = reduceMotion ? 0 : 4
            // The warp drifts on the clock, not the wheel, so it undulates slowly and never jitters.
            let drift = t * 0.10
            // Soft wavefront lines, gently warped
            for i in 0..<waveCount {
                let waveProgress = (Double(i) / Double(waveCount) - phase).truncatingRemainder(dividingBy: 1.0)
                let fraction = waveProgress < 0 ? waveProgress + 1.0 : waveProgress
                let envelope = sin(fraction * .pi)
                guard envelope > 0.02 else { continue }
                let waveOpacity = envelope * (0.18 + totalEnergy * 0.28)
                let rippleDepth = 5.0 + fraction * (rimDepth * 0.60)
                let rippleRect = bounds.insetBy(dx: rippleDepth, dy: rippleDepth)
                let waveRadius = max(14.0, cornerRadius - fraction * 8.0)

                let chromOffset: CGFloat = 1.0
                let coreWidth: CGFloat = 1.3

                // Cyan chromatic fringe
                context.stroke(
                    Self.warped(rippleRect.offsetBy(dx: -chromOffset, dy: -chromOffset * 0.5), phase: drift, seed: Double(i), amp: warpAmp),
                    with: .color(cyan.opacity(waveOpacity * 0.50)),
                    lineWidth: coreWidth
                )
                // Magenta chromatic fringe
                context.stroke(
                    Self.warped(rippleRect.offsetBy(dx: chromOffset, dy: chromOffset * 0.5), phase: drift, seed: Double(i) + 0.4, amp: warpAmp),
                    with: .color(magenta.opacity(waveOpacity * 0.50)),
                    lineWidth: coreWidth
                )
                // Specular frosted white core
                context.stroke(
                    Self.warped(rippleRect, phase: drift, seed: Double(i) + 0.2, amp: warpAmp),
                    with: .color(glassWhite.opacity(waveOpacity * 0.75)),
                    lineWidth: coreWidth * 0.8
                )
            }
            }
        }
    }

    /// A squarish outline whose edge drifts in and out, so wave lines feel like liquid, not a frame.
    static func warped(_ rect: CGRect, phase: Double, seed: Double, amp: CGFloat) -> Path {
        var path = Path()
        let steps = 140
        for n in 0..<steps {
            let a = Double(n) / Double(steps) * 2 * .pi
            let c = cos(a), sn = sin(a)
            // Superellipse: flat sides and round corners.
            let sx = c < 0 ? -1.0 : 1.0, sy = sn < 0 ? -1.0 : 1.0
            let x = sx * pow(abs(c), 0.18), y = sy * pow(abs(sn), 0.18)
            let wobble = sin(a * 3 + phase * 4 + seed * 2.3) * 0.6 + sin(a * 7 - phase * 6 + seed) * 0.4
            let inward = 1 - Double(amp * 3) * (wobble * 0.5 + 0.5) / max(1, Double(rect.width))
            let p = CGPoint(x: rect.midX + CGFloat(x * inward) * rect.width / 2 - CGFloat(x) * amp * CGFloat(wobble * 0.5 + 0.5) * 0,
                            y: rect.midY + CGFloat(y * inward) * rect.height / 2)
            if n == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    public static func glowEnergy(age: TimeInterval) -> Double {
        let progress = min(1, max(0, (age - 0.35) / 0.55))
        return 1 - progress * progress * (3 - 2 * progress)
    }
}
