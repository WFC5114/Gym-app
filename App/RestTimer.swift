import ActivityKit
import Foundation
import WidgetKit

/// The rest Live Activity (lock screen and Dynamic Island). Its end time always
/// comes from the logged rest, including time added mid-rest.
enum RestActivity {
    static var isDisabled = false

    static func start(_ rest: RestPeriod, setNumber: Int) {
        guard !isDisabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            await endAll()
            _ = try? Activity.request(
                attributes: RestTimerAttributes(workoutName: "Workout"),
                content: ActivityContent(state: state(rest), staleDate: rest.endsAt.addingTimeInterval(60))
            )
        }
    }

    static func update(_ rest: RestPeriod) {
        guard !isDisabled else { return }
        Task {
            for activity in Activity<RestTimerAttributes>.activities {
                await activity.update(ActivityContent(state: state(rest), staleDate: rest.endsAt.addingTimeInterval(60)))
            }
        }
    }

    static func endAll() async {
        for activity in Activity<RestTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func state(_ rest: RestPeriod) -> RestTimerAttributes.ContentState {
        RestTimerAttributes.ContentState(startedAt: rest.startedAt, endsAt: rest.endsAt,
                                         exercise: rest.exercise, setNumber: rest.afterSet)
    }
}

enum WidgetReload {
    static var isDisabled = false
    static func request() {
        guard !isDisabled else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
