import ActivityKit
import Foundation

enum RestTimer {
    static func start(seconds: Int, exercise: String, setNumber: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        let state = RestTimerAttributes.ContentState(
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(seconds)),
            exercise: exercise,
            setNumber: setNumber
        )
        _ = try? Activity.request(
            attributes: RestTimerAttributes(workoutName: "Workout"),
            content: ActivityContent(state: state, staleDate: state.endsAt)
        )
    }

    static func endAll() async {
        for activity in Activity<RestTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
