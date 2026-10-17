import CoreHaptics
import Foundation

/// The four machine events from the sensory table in docs/DESIGN_LANGUAGE.md.
enum SensoryEvent: CaseIterable {
    case dropWeight
    case setDone
    case scrubTick
    case scrubInBodyDay
    case rotatePrism
    /// The hourglass has run out.
    case restDone

    var intensity: Float {
        switch self {
        case .dropWeight: return 0.85
        case .setDone: return 1.0
        case .scrubTick: return 0.25
        case .scrubInBodyDay: return 1.0
        case .rotatePrism: return 0.6
        case .restDone: return 0.7
        }
    }

    var sharpness: Float {
        switch self {
        case .dropWeight: return 0.20
        case .setDone: return 0.95
        case .scrubTick: return 0.80
        case .scrubInBodyDay: return 0.80
        case .rotatePrism: return 0.5
        case .restDone: return 0.4
        }
    }
}

enum HapticPatterns {
    /// Builds the Core Haptics pattern for an event. `weight` (0...1) scales the
    /// food-log rumble with meal size.
    static func pattern(for event: SensoryEvent, weight: Float = 0.5) throws -> CHHapticPattern {
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)
        var events: [CHHapticEvent] = []
        switch event {
        case .dropWeight:
            // Dense train of low events that settles like a heavy weight.
            let count = 6 + Int(weight * 10)
            for n in 0..<count {
                let fade = 1 - Float(n) / Float(count)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity * fade), s],
                    relativeTime: Double(n) * 0.03
                ))
            }
        case .setDone, .scrubTick, .scrubInBodyDay:
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0))
        case .restDone:
            // Two soft knocks, like tapping the glass.
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0))
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0.16))
        case .rotatePrism:
            // Swells to the 60° midpoint, then a crisp seating pulse at 120°.
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [i, s], relativeTime: 0, duration: 0.35))
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1), CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)],
                relativeTime: 0.35
            ))
        }
        let curves: [CHHapticParameterCurve] = event == .rotatePrism ? [
            CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0.2),
                .init(relativeTime: 0.17, value: 1.0),
                .init(relativeTime: 0.35, value: 0.3),
            ], relativeTime: 0)
        ] : []
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }
}

/// Plays the custom patterns. Honours the haptics toggle; does nothing on
/// hardware without a Taptic Engine (simulator).
final class HapticEngine {
    static let shared = HapticEngine()
    private var engine: CHHapticEngine?
    static let enabledKey = "haptics.enabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Silences haptics for this launch only (fixtures, tests); not saved.
    var isMuted = false

    private func ready() -> CHHapticEngine? {
        guard isEnabled, !isMuted, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if let engine { return engine }
        guard let e = try? CHHapticEngine() else { return nil }
        e.isAutoShutdownEnabled = true
        e.resetHandler = { [weak e] in try? e?.start() }
        try? e.start()
        engine = e
        return e
    }

    /// `scale` multiplies the event's intensity (impact speed, load size).
    func play(_ event: SensoryEvent, weight: Float = 0.5, scale: Float = 1) {
        guard let engine = ready(), let pattern = try? HapticPatterns.pattern(for: event, weight: weight) else { return }
        guard let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        if scale != 1 {
            try? player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: min(max(scale, 0.1), 1), relativeTime: 0)], atTime: CHHapticTimeImmediate)
        }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    /// One light tick (rotation detents, steppers).
    func tick(intensity: Float, sharpness: Float) {
        guard let engine = ready() else { return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? engine.start()
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
