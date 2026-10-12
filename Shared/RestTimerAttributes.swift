import ActivityKit
import Foundation

/// Live Activity shown on the lock screen and in the Dynamic Island during rest between sets.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var endsAt: Date
        var exercise: String
        var setNumber: Int
    }

    var workoutName: String
}
