import SwiftUI
import WidgetKit

struct DashboardView: View {
    @StateObject private var health = HealthStore()
    @State private var snapshot = SnapshotStore.load() ?? DailySnapshot.placeholder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brutal.grid * 3) {
                header
                caloriesCard
                proteinCard
                bodyCard
                actions
                if let error = health.errorMessage {
                    Text(error.uppercased())
                        .font(Brutal.label(11))
                        .foregroundStyle(Brutal.signal)
                }
            }
            .padding(Brutal.grid * 2)
            .padding(.trailing, Brutal.shadowOffset)
        }
        .background(Brutal.paper.ignoresSafeArea())
        .foregroundStyle(Brutal.ink)
        .task {
            await health.requestAccessAndLoad()
            syncBodyNumbers()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month()).uppercased())
                .font(Brutal.label())
                .foregroundStyle(Brutal.muted)
            HStack(alignment: .firstTextBaseline) {
                Text("GYM").font(Brutal.display(56))
                Spacer()
                Text("\(snapshot.streakDays)D STREAK")
                    .font(Brutal.label(13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Brutal.signal)
            }
        }
    }

    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: Brutal.grid) {
            Text("KCAL LEFT").font(Brutal.label())
            Text("\(snapshot.caloriesLeft)")
                .font(Brutal.display(72))
                .contentTransition(.numericText(value: Double(snapshot.caloriesLeft)))
            BrutalBar(progress: snapshot.caloriesProgress)
            Text("\(snapshot.caloriesEaten) / \(snapshot.caloriesTarget)")
                .font(Brutal.label(11))
                .foregroundStyle(Brutal.muted)
                .contentTransition(.numericText())
        }
        .brutalCard()
    }

    private var proteinCard: some View {
        VStack(alignment: .leading, spacing: Brutal.grid) {
            Text("PROTEIN LEFT").font(Brutal.label())
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.proteinLeft)")
                    .font(Brutal.display(56))
                    .contentTransition(.numericText(value: Double(snapshot.proteinLeft)))
                Text("G").font(Brutal.display(24))
            }
            BrutalBar(progress: snapshot.proteinProgress, fill: Brutal.signal)
        }
        .brutalCard()
    }

    private var bodyCard: some View {
        HStack(spacing: Brutal.grid * 2) {
            metric("WEIGHT", value: health.latestWeightKg.map { String(format: "%.1f", $0) }, unit: "KG")
            metric("BODY FAT", value: health.latestBodyFatPercent.map { String(format: "%.1f", $0) }, unit: "%")
            metric("LEAN", value: health.latestLeanMassKg.map { String(format: "%.1f", $0) }, unit: "KG")
        }
        .brutalCard(fill: Brutal.ink)
        .foregroundStyle(Brutal.paper)
    }

    private func metric(_ title: String, value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Brutal.label(10))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "--")
                    .font(Brutal.display(24))
                    .contentTransition(.numericText())
                Text(unit).font(Brutal.label(10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: Brutal.grid * 2) {
            BrutalButton(title: "+ LOG 30G PROTEIN / 400 KCAL") {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Brutal.snap) {
                    snapshot.proteinEaten += 30
                    snapshot.caloriesEaten += 400
                }
                save()
            }
            BrutalButton(title: "START 90S REST", fill: Brutal.signal) {
                RestTimer.start(seconds: 90, exercise: "Bench press", setNumber: 3)
            }
            BrutalButton(title: "RESET TODAY", fill: Brutal.paper) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Brutal.settle) {
                    snapshot.proteinEaten = 0
                    snapshot.caloriesEaten = 0
                }
                save()
                Task { await RestTimer.endAll() }
            }
        }
    }

    private func syncBodyNumbers() {
        snapshot.weightKg = health.latestWeightKg ?? snapshot.weightKg
        snapshot.bodyFatPercent = health.latestBodyFatPercent ?? snapshot.bodyFatPercent
        save()
    }

    private func save() {
        snapshot.date = .now
        SnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct BrutalBar: View {
    var progress: Double
    var fill: Color = Brutal.ink

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Brutal.paper)
                Rectangle()
                    .fill(fill)
                    .frame(width: proxy.size.width * progress)
                    .animation(Brutal.snap, value: progress)
            }
            .overlay(Rectangle().stroke(Brutal.ink, lineWidth: Brutal.border))
        }
        .frame(height: 20)
    }
}

struct BrutalButton: View {
    var title: String
    var fill: Color = Brutal.ink
    var action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Text(title)
                .font(Brutal.label(14))
                .foregroundStyle(fill == Brutal.ink ? Brutal.paper : Brutal.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Brutal.grid * 2)
                .background(fill)
                .overlay(Rectangle().stroke(Brutal.ink, lineWidth: Brutal.border))
                .background(
                    Rectangle().fill(Brutal.ink).offset(x: 4, y: 4)
                )
        }
        .buttonStyle(PressDownStyle())
        .sensoryFeedback(.impact(weight: .heavy), trigger: taps)
    }
}

/// Buttons sink into their hard shadow when pressed.
struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(Brutal.snap, value: configuration.isPressed)
    }
}
