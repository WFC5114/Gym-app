import Foundation

/// Damped harmonic spring parameters. Every motion in the machine uses one of these;
/// easing curves are not allowed (docs/DESIGN_LANGUAGE.md).
struct SpringConfig: Equatable {
    let mass: Double
    let stiffness: Double
    let damping: Double

    /// Below 1 the spring overshoots and bounces; 1 is critically damped.
    var dampingRatio: Double { damping / (2 * (mass * stiffness).squareRoot()) }

    /// DIET deck slam: ultra-heavy and underdamped, three decaying bounces.
    static let deck = SpringConfig(mass: 3.5, stiffness: 450, damping: 22)
    /// TRAIN piston firing into its upper limit.
    static let piston = SpringConfig(mass: 1.0, stiffness: 800, damping: 35)
    /// BODY numbers following the scrubber.
    static let bodyNumbers = SpringConfig(mass: 1.2, stiffness: 180, damping: 28)
    /// Prism rotation: about 8% overshoot on the 120° turn.
    static let prism = SpringConfig(mass: 1.0, stiffness: 300, damping: 21.7)
    /// Reduce Motion: critically damped, no overshoot, nothing travels far.
    static let calm = SpringConfig(mass: 1.0, stiffness: 300, damping: 34.64)
    /// Display values that track a moving target closely (sand level, glass size).
    static let follow = SpringConfig(mass: 1.0, stiffness: 400, damping: 40)
}

/// One spring-driven value, integrated every frame (semi-implicit Euler).
struct SpringState: Equatable {
    var position: Double
    var velocity: Double = 0
    var target: Double

    mutating func step(_ dt: Double, config: SpringConfig) {
        let force = -config.stiffness * (position - target) - config.damping * velocity
        velocity += force / config.mass * dt
        position += velocity * dt
    }

    /// Integrates a real frame interval in bounded fixed substeps (≤ 1/480 s), so
    /// the result does not depend on frame rate and a long hitch cannot explode.
    mutating func advance(_ dt: Double, config: SpringConfig) {
        let clamped = min(max(dt, 0), 1.0 / 15)
        let steps = max(1, Int((clamped * 480).rounded(.up)))
        let h = clamped / Double(steps)
        for _ in 0..<steps { step(h, config: config) }
    }

    func isSettled(tolerance: Double = 0.001) -> Bool {
        abs(position - target) < tolerance && abs(velocity) < tolerance
    }
}

/// The prism has three faces 120° apart.
enum PrismFace: Int, CaseIterable {
    case diet, train, body

    var yaw: Double { Double(rawValue) * 120 }

    func next() -> PrismFace { PrismFace(rawValue: (rawValue + 1) % 3)! }
    func previous() -> PrismFace { PrismFace(rawValue: (rawValue + 2) % 3)! }
}

/// The DIET deck's resting depth: it sits lower as the day fills.
enum Deck {
    static let maxCompression: Double = 1

    static func restingDepth(eaten: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(eaten / target, 0), 1.2) * maxCompression
    }

    static let weights: [Int] = [50, 100, 250, 500]
}
