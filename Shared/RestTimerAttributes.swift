import ActivityKit
import Foundation

/// Live Activity shown on the lock screen and in the Dynamic Island during a rest.
/// TRAIN logs rests only (Wei, 15 Oct 2026): `exercise` is the body part, and
/// `setNumber` is which of today's rests for it this is.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var endsAt: Date
        var exercise: String
        var setNumber: Int
    }

    var workoutName: String
}
