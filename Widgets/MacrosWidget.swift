import SwiftUI
import WidgetKit

struct MacrosEntry: TimelineEntry {
    let date: Date
    /// nil means the widget could not read the App Group: either the app has not run yet,
    /// or the install did not keep the App Group entitlement.
    let snapshot: DailySnapshot?
}

struct MacrosProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacrosEntry {
        MacrosEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacrosEntry) -> Void) {
        let snapshot = context.isPreview ? DailySnapshot.placeholder : SnapshotStore.load()
        completion(MacrosEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacrosEntry>) -> Void) {
        let entry = MacrosEntry(date: .now, snapshot: SnapshotStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MacrosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacrosWidget", provider: MacrosProvider()) { entry in
            MacrosWidgetView(entry: entry)
                .containerBackground(for: .widget) { Brutal.paper }
        }
        .configurationDisplayName("Macros left")
        .description("Calories and protein left today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct MacrosWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacrosEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: snapshot.proteinProgress) {
                    Text("P")
                } currentValueLabel: {
                    Text("\(snapshot.proteinLeft)")
                        .contentTransition(.numericText(value: Double(snapshot.proteinLeft)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    Text("KCAL LEFT").font(Brutal.label(10))
                    Text("\(snapshot.caloriesLeft)")
                        .font(Brutal.display(24))
                        .contentTransition(.numericText(value: Double(snapshot.caloriesLeft)))
                    Text("\(snapshot.proteinLeft)G PROTEIN").font(Brutal.label(10))
                }
            case .systemMedium:
                HStack(spacing: 12) {
                    block(title: "KCAL LEFT", value: snapshot.caloriesLeft, progress: snapshot.caloriesProgress, fill: Brutal.ink)
                    block(title: "PROTEIN", value: snapshot.proteinLeft, progress: snapshot.proteinProgress, fill: Brutal.signal)
                }
                .foregroundStyle(Brutal.ink)
            default:
                block(title: "KCAL LEFT", value: snapshot.caloriesLeft, progress: snapshot.caloriesProgress, fill: Brutal.ink)
                    .foregroundStyle(Brutal.ink)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("NO DATA").font(Brutal.display(20))
                Text("OPEN GYM ONCE").font(Brutal.label(10))
            }
            .foregroundStyle(Brutal.ink)
        }
    }

    private func block(title: String, value: Int, progress: Double, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Brutal.label(10))
            Text("\(value)")
                .font(Brutal.display(34))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(value)))
            Spacer(minLength: 0)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Brutal.paper)
                    Rectangle().fill(fill).frame(width: proxy.size.width * progress)
                }
                .overlay(Rectangle().stroke(Brutal.ink, lineWidth: 2))
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
