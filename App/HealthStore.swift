import Foundation
import HealthKit

/// Reads Apple Health. InBody writes its scans (weight, body fat, lean mass, BMI)
/// into Health, so they arrive here too.
@MainActor
final class HealthStore: ObservableObject {
    @Published private(set) var latestWeightKg: Double?
    @Published private(set) var latestBodyFatPercent: Double?
    @Published private(set) var latestLeanMassKg: Double?
    @Published private(set) var stepsToday: Int?
    @Published private(set) var errorMessage: String?

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        let quantities: [HKQuantityTypeIdentifier] = [
            .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex,
            .stepCount, .activeEnergyBurned, .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
        ]
        var types = Set<HKObjectType>(quantities.map { HKQuantityType($0) as HKObjectType })
        types.insert(HKObjectType.workoutType())
        types.insert(HKCategoryType(.sleepAnalysis))
        return types
    }

    func requestAccessAndLoad() async {
        guard isAvailable else {
            errorMessage = "Apple Health is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load() async {
        latestWeightKg = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        latestBodyFatPercent = await latest(.bodyFatPercentage, unit: .percent()).map { $0 * 100 }
        latestLeanMassKg = await latest(.leanBodyMass, unit: .gramUnit(with: .kilo))
        stepsToday = await todaySum(.stepCount, unit: .count()).map { Int($0) }
    }

    /// Recovery signals for the rest coach. Missing data stays nil.
    func readiness(now: Date = .now) async -> Readiness {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        let ms = HKUnit.secondUnit(with: .milli)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrvToday = await average(.heartRateVariabilitySDNN, unit: ms, from: cal.date(byAdding: .hour, value: -12, to: today)!, to: now)
        let hrvBase = await average(.heartRateVariabilitySDNN, unit: ms, from: weekAgo, to: today)
        let rhrToday = await average(.restingHeartRate, unit: bpm, from: today, to: now)
        let rhrBase = await average(.restingHeartRate, unit: bpm, from: weekAgo, to: today)
        let sleep = await sleepHours(endingAt: now)
        return Readiness(hrvToday: hrvToday, hrvBaseline: hrvBase, restingHRToday: rhrToday,
                         restingHRBaseline: rhrBase, sleepHours: sleep)
    }

    /// One observation per day for the BODY ruler, newest last.
    func bodyHistory(days: Int = 120, now: Date = .now) async -> [BodyObservation] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))!
        let kg = HKUnit.gramUnit(with: .kilo)
        let weights = await samples(.bodyMass, from: start, to: now)
        let fats = await samples(.bodyFatPercentage, from: start, to: now)
        let leans = await samples(.leanBodyMass, from: start, to: now)
        var byDay: [Date: BodyObservation] = [:]
        func day(_ d: Date) -> Date { cal.startOfDay(for: d) }
        for s in weights {
            let d = day(s.endDate)
            byDay[d, default: BodyObservation(date: d, isScan: false)].weightKg = s.quantity.doubleValue(for: kg)
        }
        for s in fats {
            let d = day(s.endDate)
            byDay[d, default: BodyObservation(date: d, isScan: false)].bodyFatPercent = s.quantity.doubleValue(for: .percent()) * 100
            byDay[d]?.isScan = true
        }
        for s in leans {
            let d = day(s.endDate)
            byDay[d, default: BodyObservation(date: d, isScan: false)].leanKg = s.quantity.doubleValue(for: kg)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    private func samples(_ id: HKQuantityTypeIdentifier, from: Date, to: Date) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        let values = await samples(id, from: from, to: to).map { $0.quantity.doubleValue(for: unit) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func sleepHours(endingAt now: Date) async -> Double? {
        let cal = Calendar.current
        let from = cal.date(byAdding: .hour, value: -18, to: cal.startOfDay(for: now))!
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let seconds = samples.filter { asleep.contains($0.value) }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 3600 : nil
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try? await descriptor.result(for: store)
        return samples?.first?.quantity.doubleValue(for: unit)
    }

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit)
    }
}
