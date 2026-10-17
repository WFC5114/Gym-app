import Foundation

/// Today's recovery signals from Apple Health. Any of them can be missing.
struct Readiness: Equatable {
    /// Last night's HRV (SDNN, ms) and the 7-day average before it.
    var hrvToday: Double?
    var hrvBaseline: Double?
    /// Resting heart rate today and the 7-day average before it.
    var restingHRToday: Double?
    var restingHRBaseline: Double?
    /// Hours asleep last night.
    var sleepHours: Double?

    static let unknown = Readiness()
}

struct RestAdvice: Equatable {
    var seconds: Int
    var bodyPart: BodyPart
    /// Plain reasons, shown on the TRAIN face and passed to the AI review.
    var reasons: [String]
}

/// Recommends rest per body part and adapts it each day.
///
/// The numbers are deterministic rules so they can be tested and explained.
/// The AI weekly review reads the same rest log and can propose new baselines;
/// it does not silently change these rules.
enum RestCoach {
    /// Starting rest in seconds before any adaptation.
    static func baseline(_ part: BodyPart, compound: Bool) -> Int {
        switch (part, compound) {
        case (.legs, true): return 180
        case (.legs, false): return 105
        case (.back, true), (.chest, true): return 150
        case (.shoulders, true): return 120
        case (.back, false), (.chest, false), (.shoulders, false): return 90
        case (.arms, _): return 75
        case (.core, _): return 60
        }
    }

    static func recommend(for exercise: Exercise, setNumber: Int, history: [RestPeriod],
                          readiness: Readiness, now: Date) -> RestAdvice {
        let part = exercise.bodyPart
        var seconds = Double(baseline(part, compound: exercise.isCompound))
        var reasons = ["\(part.label) \(exercise.isCompound ? "COMPOUND" : "ISOLATION") BASE \(format(Int(seconds)))"]

        // What Wei actually did on this body part over the last 14 days.
        let recent = history.filter {
            $0.bodyPart == part && $0.endedAt != nil && now.timeIntervalSince($0.startedAt) < 14 * 86400
        }
        if recent.count >= 4 {
            let extended = recent.filter { $0.addedSeconds > 0 }
            if Double(extended.count) / Double(recent.count) >= 0.4 {
                let added = extended.map(\.addedSeconds).sorted()
                let median = added[added.count / 2]
                let bump = min(Double(median), 60)
                seconds += bump
                reasons.append("YOU ADDED TIME ON \(extended.count) OF \(recent.count) \(part.label) RESTS: +\(Int(bump)) S")
            }
            let cutShort = recent.filter {
                $0.endReason == .nextSet && ($0.actualSeconds ?? $0.totalSeconds) < Int(Double($0.totalSeconds) * 0.8)
            }
            if Double(cutShort.count) / Double(recent.count) >= 0.4 {
                seconds -= 15
                reasons.append("YOU STARTED EARLY ON \(cutShort.count) OF \(recent.count) \(part.label) RESTS: −15 S")
            }
        } else {
            reasons.append("NOT ENOUGH \(part.label) RESTS LOGGED YET TO ADAPT")
        }

        // Today's recovery.
        var factor = 1.0
        if let hrv = readiness.hrvToday, let base = readiness.hrvBaseline, base > 0 {
            if hrv < base * 0.9 { factor += 0.15; reasons.append("HRV \(Int(hrv)) MS, BELOW YOUR \(Int(base)): +15%") }
            else if hrv > base * 1.05 { factor -= 0.05; reasons.append("HRV \(Int(hrv)) MS, ABOVE YOUR \(Int(base)): −5%") }
        } else {
            reasons.append("NO HRV READING TODAY")
        }
        if let rhr = readiness.restingHRToday, let base = readiness.restingHRBaseline, rhr > base + 5 {
            factor += 0.10
            reasons.append("RESTING HR \(Int(rhr)), \(Int(rhr - base)) ABOVE NORMAL: +10%")
        }
        if let sleep = readiness.sleepHours {
            if sleep < 6 { factor += 0.10; reasons.append(String(format: "SLEPT %.1f H: +10%%", sleep)) }
        } else {
            reasons.append("NO SLEEP DATA FOR LAST NIGHT")
        }
        seconds *= factor

        // Heavy leg work accumulates fatigue across sets.
        if part == .legs, exercise.isCompound, setNumber >= 3 {
            seconds += 15
            reasons.append("SET \(setNumber) OF HEAVY LEGS: +15 S")
        }

        let rounded = Int((seconds / Double(RestLimits.step)).rounded()) * RestLimits.step
        return RestAdvice(seconds: RestLimits.clamp(rounded), bodyPart: part, reasons: reasons)
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The training part of the AI weekly review input.
struct RestDigest: Codable, Equatable {
    struct Line: Codable, Equatable {
        var date: Date
        var exercise: String
        var bodyPart: BodyPart
        var afterSet: Int
        var plannedSeconds: Int
        var recommendedSeconds: Int?
        var addedSeconds: Int
        var additions: [RestAddition]
        var actualSeconds: Int?
        var endReason: RestEnd?
    }
    var rests: [Line]

    init(rests: [RestPeriod]) {
        self.rests = rests.map {
            Line(date: $0.startedAt, exercise: $0.exercise, bodyPart: $0.bodyPart, afterSet: $0.afterSet,
                 plannedSeconds: $0.plannedSeconds, recommendedSeconds: $0.recommendedSeconds,
                 addedSeconds: $0.addedSeconds, additions: $0.additions, actualSeconds: $0.actualSeconds,
                 endReason: $0.endReason)
        }
    }
}
