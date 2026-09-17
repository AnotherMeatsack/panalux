import Foundation

public struct TrackballState: Equatable {
    public var hueAngle: Double // 0.0 to 1.0 (0 to 360 deg)
    public var saturation: Double // 0.0 to 1.0
    public var normalizedX: Double // -1.0 to 1.0
    public var normalizedY: Double // -1.0 to 1.0

    public init(hueAngle: Double = 0, saturation: Double = 0, normalizedX: Double = 0, normalizedY: Double = 0) {
        self.hueAngle = hueAngle
        self.saturation = saturation
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

public class TrackballEngine {
    public let name: String
    public var hueParam: String
    public var satParam: String
    public var radius: Double
    public var invertX: Bool
    public var invertY: Bool

    public private(set) var x: Double = 0.0
    public private(set) var y: Double = 0.0

    // Physics & Inertial Friction Deceleration
    private var vx: Double = 0.0
    private var vy: Double = 0.0
    private var lastPushTimestamp: Date = Date.distantPast
    private var inertiaTimer: Timer?
    private let frictionCoeff: Double = 0.88 // Decays ~12% per frame (gradual stop over ~350ms)
    private let minVelocityThreshold: Double = 0.35 // Velocity cutoff

    public var onInertiaStep: ((Double, Double) -> Void)?

    public init(
        name: String,
        hueParam: String,
        satParam: String,
        radius: Double = 3000.0,
        invertX: Bool = true,
        invertY: Bool = true
    ) {
        self.name = name
        self.hueParam = hueParam
        self.satParam = satParam
        self.radius = radius
        self.invertX = invertX
        self.invertY = invertY
    }

    deinit {
        stopInertia()
    }

    public func push(dx: Double, dy: Double) -> (turns: Double, saturation: Double) {
        let sx = invertX ? -1.0 : 1.0
        let sy = invertY ? -1.0 : 1.0

        let deltaX = dx * sx
        let deltaY = dy * sy

        x += deltaX
        y += deltaY

        // Track instantaneous velocity vector for inertia
        vx = deltaX * 0.75 + vx * 0.25
        vy = deltaY * 0.75 + vy * 0.25
        lastPushTimestamp = Date()

        // Clamp to color wheel boundary
        var r = hypot(x, y)
        if r > radius {
            x *= radius / r
            y *= radius / r
            r = radius
        }

        var turns = (atan2(y, x) / (2.0 * .pi)).truncatingRemainder(dividingBy: 1.0)
        if turns < 0 { turns += 1.0 }
        let sat = radius > 0 ? r / radius : 0

        // Schedule gradual stop decay loop
        startInertiaIfNeeded()

        return (turns, sat)
    }

    private func startInertiaIfNeeded() {
        guard inertiaTimer == nil else { return }

        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.stepInertia()
        }
    }

    private func stepInertia() {
        // Only apply inertia after physical movement stops (> 40ms without hardware reports)
        let elapsedSincePush = Date().timeIntervalSince(lastPushTimestamp)
        guard elapsedSincePush > 0.04 else { return }

        let speed = hypot(vx, vy)
        if speed < minVelocityThreshold {
            stopInertia()
            return
        }

        // Apply smooth exponential friction decay
        vx *= frictionCoeff
        vy *= frictionCoeff

        x += vx
        y += vy

        var r = hypot(x, y)
        if r > radius {
            x *= radius / r
            y *= radius / r
            r = radius
            // Elastic damping at boundary
            vx *= -0.2
            vy *= -0.2
        }

        var turns = (atan2(y, x) / (2.0 * .pi)).truncatingRemainder(dividingBy: 1.0)
        if turns < 0 { turns += 1.0 }
        let sat = radius > 0 ? r / radius : 0

        onInertiaStep?(turns, sat)
    }

    public func stopInertia() {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        vx = 0.0
        vy = 0.0
    }

    /// Not being rolled and not coasting.
    public var isSettled: Bool {
        inertiaTimer == nil && Date().timeIntervalSince(lastPushTimestamp) > 0.3
    }

    /// Put the ball where Lightroom says the color is.
    public func sync(turns: Double, saturation: Double) {
        stopInertia()
        let r = max(0, min(1, saturation)) * radius
        let angle = turns * 2.0 * .pi
        x = r * cos(angle)
        y = r * sin(angle)
    }

    public func recenter() {
        stopInertia()
        x = 0.0
        y = 0.0
    }

    public var currentState: TrackballState {
        let r = hypot(x, y)
        var turns = (atan2(y, x) / (2.0 * .pi)).truncatingRemainder(dividingBy: 1.0)
        if turns < 0 { turns += 1.0 }
        let sat = radius > 0 ? min(1.0, r / radius) : 0
        let normX = radius > 0 ? x / radius : 0
        let normY = radius > 0 ? y / radius : 0
        return TrackballState(hueAngle: turns, saturation: sat, normalizedX: normX, normalizedY: normY)
    }
}
