import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · SET \(context.state.setNumber)").font(Brutal.label(11))
                    Text(context.state.exercise.uppercased()).font(Brutal.label(15))
                }
                Spacer()
                timer(context.state)
                    .font(Brutal.display(40))
                    .foregroundStyle(Brutal.signal)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            .padding(16)
            .foregroundStyle(Brutal.paper)
            .activityBackgroundTint(Brutal.ink)
            .activitySystemActionForegroundColor(Brutal.paper)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("SET \(context.state.setNumber)")
                        .font(Brutal.label(14))
                        .foregroundStyle(Brutal.paper)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state)
                        .font(Brutal.display(28))
                        .foregroundStyle(Brutal.signal)
                        .frame(maxWidth: 100, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.exercise.uppercased())
                            .font(Brutal.label(13))
                            .foregroundStyle(Brutal.paper)
                        ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(Brutal.signal)
                    }
                }
            } compactLeading: {
                Text("REST")
                    .font(Brutal.label(12))
                    .foregroundStyle(Brutal.signal)
            } compactTrailing: {
                timer(context.state)
                    .font(Brutal.label(13))
                    .foregroundStyle(Brutal.paper)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Brutal.signal)
            }
            .keylineTint(Brutal.signal)
        }
    }

    private func timer(_ state: RestTimerAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt...state.endsAt, countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}
