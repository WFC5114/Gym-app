import Foundation

enum BodyPart: String, Codable, CaseIterable, Identifiable {
    case legs, back, chest, shoulders, arms, core
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

struct Exercise: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var bodyPart: BodyPart
    /// Multi-joint lifts get longer rest than isolation work.
    var isCompound: Bool
    var id: String { name }

    static let library: [Exercise] = [
        Exercise(name: "Back squat", bodyPart: .legs, isCompound: true),
        Exercise(name: "Deadlift", bodyPart: .legs, isCompound: true),
        Exercise(name: "Romanian deadlift", bodyPart: .legs, isCompound: true),
        Exercise(name: "Leg press", bodyPart: .legs, isCompound: true),
        Exercise(name: "Walking lunge", bodyPart: .legs, isCompound: true),
        Exercise(name: "Leg curl", bodyPart: .legs, isCompound: false),
        Exercise(name: "Leg extension", bodyPart: .legs, isCompound: false),
        Exercise(name: "Calf raise", bodyPart: .legs, isCompound: false),
        Exercise(name: "Bench press", bodyPart: .chest, isCompound: true),
        Exercise(name: "Incline dumbbell press", bodyPart: .chest, isCompound: true),
        Exercise(name: "Cable fly", bodyPart: .chest, isCompound: false),
        Exercise(name: "Pull-up", bodyPart: .back, isCompound: true),
        Exercise(name: "Barbell row", bodyPart: .back, isCompound: true),
        Exercise(name: "Lat pulldown", bodyPart: .back, isCompound: true),
        Exercise(name: "Seated cable row", bodyPart: .back, isCompound: true),
        Exercise(name: "Overhead press", bodyPart: .shoulders, isCompound: true),
        Exercise(name: "Lateral raise", bodyPart: .shoulders, isCompound: false),
        Exercise(name: "Rear delt fly", bodyPart: .shoulders, isCompound: false),
        Exercise(name: "Barbell curl", bodyPart: .arms, isCompound: false),
        Exercise(name: "Triceps pushdown", bodyPart: .arms, isCompound: false),
        Exercise(name: "Hammer curl", bodyPart: .arms, isCompound: false),
        Exercise(name: "Plank", bodyPart: .core, isCompound: false),
        Exercise(name: "Hanging leg raise", bodyPart: .core, isCompound: false),
    ]

    static func named(_ name: String) -> Exercise? {
        library.first { $0.name == name } ?? BodyPart.allCases.map(rest(for:)).first { $0.name == name }
    }

    /// TRAIN is a rest timer (Wei, 15 Oct 2026: "I don't need to add sets or
    /// record sets, only rest times"): rests are logged per body part, as if
    /// for that part's main lift.
    static func rest(for part: BodyPart) -> Exercise {
        Exercise(name: part.label.capitalized, bodyPart: part, isCompound: part != .arms && part != .core)
    }
}

struct SetRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var exercise: String
    var bodyPart: BodyPart
    var loadKg: Double
    var reps: Int
    var setNumber: Int
    var completedAt: Date
}

/// Time added to a rest while it was running. Each press is its own record.
struct RestAddition: Codable, Equatable {
    var at: Date
    var seconds: Int
}

enum RestEnd: String, Codable {
    /// The glass ran out.
    case elapsed
    /// SET DONE was pressed for the next set before the glass ran out.
    case nextSet
    /// Rest was cancelled (workout ended).
    case cancelled
}

/// One rest between sets. Elapsed wall-clock time is the source of truth; the
/// hourglass is only a picture of it.
struct RestPeriod: Codable, Equatable, Identifiable {
    var id: UUID
    var exercise: String
    var bodyPart: BodyPart
    /// The set this rest follows.
    var afterSet: Int
    var startedAt: Date
    /// What the glass was set to when it flipped.
    var plannedSeconds: Int
    /// What the coach recommended at that moment, for later comparison.
    var recommendedSeconds: Int?
    var additions: [RestAddition] = []
    var endedAt: Date?
    var endReason: RestEnd?
    /// When the next set was logged, which may be well after the glass ran out.
    var nextSetAt: Date?

    var addedSeconds: Int { additions.reduce(0) { $0 + $1.seconds } }
    var totalSeconds: Int { plannedSeconds + addedSeconds }
    var endsAt: Date { startedAt.addingTimeInterval(TimeInterval(totalSeconds)) }
    var isActive: Bool { endedAt == nil }

    func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }

    /// Share of sand still in the top bulb, 1 → 0.
    func remainingFraction(at now: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return remaining(at: now) / Double(totalSeconds)
    }

    /// Seconds actually rested: until the next set if one was logged, else until the end.
    var actualSeconds: Int? {
        if let next = nextSetAt { return Int(next.timeIntervalSince(startedAt).rounded()) }
        if let end = endedAt { return Int(end.timeIntervalSince(startedAt).rounded()) }
        return nil
    }
}

/// Remembered per exercise so the next session starts where the last one ended.
struct ExerciseMemory: Codable, Equatable {
    var loadKg: Double
    var reps: Int
    var restSeconds: Int?
}

enum RestLimits {
    static let minSeconds = 30
    static let maxSeconds = 300
    static let step = 15
    static let addStep = 30

    static func clamp(_ s: Int) -> Int { min(max(s, minSeconds), maxSeconds) }
}
