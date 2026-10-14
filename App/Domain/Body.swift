import Foundation

/// One day on the BODY ruler. Missing values stay missing (never zero).
struct BodyObservation: Equatable, Identifiable {
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var leanKg: Double?
    /// True when the values came from an InBody scan (via Apple Health).
    var isScan: Bool
    var id: Date { date }

    /// Clearly labelled sample history for `-demo`, fixtures and first launch
    /// before Health has data. Never mixed with real readings.
    static let sample: [BodyObservation] = {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return (0..<57).map { i in
            let day = cal.date(byAdding: .day, value: i - 56, to: end)!
            let t = Double(i) / 56
            let scan = i % 14 == 0
            let weight = 81.6 - 1.8 * t + 0.35 * sin(Double(i) * 0.9)
            let fat = 17.4 - 1.6 * t
            return BodyObservation(
                date: day,
                weightKg: (weight * 10).rounded() / 10,
                bodyFatPercent: scan ? (fat * 10).rounded() / 10 : nil,
                leanKg: scan ? ((weight * (1 - fat / 100)) * 10).rounded() / 10 : nil,
                isScan: scan
            )
        }
    }()

    /// Latest known fat and lean values at or before this index (scans are sparse).
    static func carried(_ history: [BodyObservation], upTo index: Int) -> (fat: Double?, lean: Double?) {
        guard !history.isEmpty else { return (nil, nil) }
        var fat: Double?, lean: Double?
        for i in stride(from: min(index, history.count - 1), through: 0, by: -1) {
            if fat == nil { fat = history[i].bodyFatPercent }
            if lean == nil { lean = history[i].leanKg }
            if fat != nil && lean != nil { break }
        }
        return (fat, lean)
    }
}

/// What the BODY figure is shaped from on one day, and how sure that is.
struct BodyComposition: Equatable {
    var fatPercent: Double?
    var leanKg: Double?
    /// True when fat comes from the scale's trend since the last scan rather than
    /// from a scan itself: lean is held at the scan's value and the trend change
    /// is counted as fat. Shown with "≈" and labelled an estimate.
    var fatIsEstimate: Bool

    /// Between scans, the smoothed weight trend moves fat; a scan resets it.
    /// Estimates stop 90 days after the last scan.
    static func on(_ history: [BodyObservation], upTo index: Int) -> BodyComposition {
        guard !history.isEmpty else { return BodyComposition(fatPercent: nil, leanKg: nil, fatIsEstimate: false) }
        let last = min(max(index, 0), history.count - 1)
        let carried = BodyObservation.carried(history, upTo: last)
        guard let scanIndex = (0...last).last(where: { history[$0].bodyFatPercent != nil }),
              let scanFat = history[scanIndex].bodyFatPercent,
              scanIndex < last,
              history[last].date.timeIntervalSince(history[scanIndex].date) <= 90 * 86_400 else {
            return BodyComposition(fatPercent: carried.fat, leanKg: carried.lean, fatIsEstimate: false)
        }
        let points = history[0...last].compactMap { o in o.weightKg.map { Trend.Point(date: o.date, value: $0) } }
        let trend = Trend.smooth(points)
        guard let scanWeight = history[scanIndex].weightKg ?? trend.last(where: { $0.date <= history[scanIndex].date })?.value,
              let atScan = trend.last(where: { $0.date <= history[scanIndex].date })?.value,
              let now = trend.last?.value else {
            return BodyComposition(fatPercent: carried.fat, leanKg: carried.lean, fatIsEstimate: false)
        }
        let change = now - atScan
        let fatKg = max(scanFat / 100 * scanWeight + change, 0.03 * scanWeight)
        let weight = max(scanWeight + change, 1)
        return BodyComposition(fatPercent: min(fatKg / weight * 100, 60), leanKg: carried.lean, fatIsEstimate: true)
    }
}

/// A gentle, per-region lean towards the body parts trained most: each region's
/// share of the last 28 days' lifted volume (load × reps) against an even
/// programme. An ESTIMATE from training logs, not a measurement (InBody's
/// per-limb readings are not in Apple Health). At most ±5% on any region.
struct MuscleTilt: Equatable {
    var legs: Float = 0
    var arms: Float = 0
    var shoulders: Float = 0
    var torso: Float = 0

    static let none = MuscleTilt()
    static let limit: Float = 0.05
    /// Fewer sets than this in the window and the figure stays even.
    static let minimumSets = 12

    /// A balanced programme's share of volume by region.
    static let balanced: [BodyPart: Double] = [.legs: 0.32, .back: 0.2, .chest: 0.15, .shoulders: 0.11, .arms: 0.12, .core: 0.1]

    static func from(_ sets: [SetRecord], endingAt end: Date, days: Int = 28) -> MuscleTilt {
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        let window = sets.filter { $0.completedAt > start && $0.completedAt <= end }
        guard window.count >= minimumSets else { return .none }
        var volume: [BodyPart: Double] = [:]
        for s in window {
            // Bodyweight work (load 0) still counts, as if a light load.
            volume[s.bodyPart, default: 0] += max(s.loadKg, 10) * Double(max(s.reps, 1))
        }
        let total = volume.values.reduce(0, +)
        guard total > 0 else { return .none }
        func tilt(_ parts: [BodyPart]) -> Float {
            let share = parts.reduce(0) { $0 + (volume[$1] ?? 0) } / total
            let even = parts.reduce(0) { $0 + (balanced[$1] ?? 0) }
            let t = Float((share / even - 1) * 0.04)
            return min(max(t, -limit), limit)
        }
        return MuscleTilt(legs: tilt([.legs]), arms: tilt([.arms]), shoulders: tilt([.shoulders]), torso: tilt([.chest, .back]))
    }

    var isEven: Bool { self == .none }
}
