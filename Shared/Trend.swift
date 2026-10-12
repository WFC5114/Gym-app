import Foundation

/// Smoothed body-weight trend: an exponentially weighted moving average that
/// ignores day-to-day water swings. `alpha` of 0.1 follows the classic
/// "Hacker's Diet" trend line.
enum Trend {
    struct Point: Equatable {
        var date: Date
        var value: Double
    }

    static func smooth(_ points: [Point], alpha: Double = 0.1) -> [Point] {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        var trend = first.value
        return sorted.map { point in
            trend += alpha * (point.value - trend)
            return Point(date: point.date, value: trend)
        }
    }

    /// Change in trend weight per week between the first and last smoothed points.
    static func weeklyRate(_ smoothed: [Point]) -> Double? {
        guard let first = smoothed.first, let last = smoothed.last else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        guard days >= 1 else { return nil }
        return (last.value - first.value) / days * 7
    }
}
