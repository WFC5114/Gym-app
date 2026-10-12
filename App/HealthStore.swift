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
            .stepCount, .activeEnergyBurned, .restingHeartRate,
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
