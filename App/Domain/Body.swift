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
