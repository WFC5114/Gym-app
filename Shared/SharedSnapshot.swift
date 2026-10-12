import Foundation

enum AppGroup {
    static let id = "group.com.wfc5114.gymapp"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// Today's numbers, written by the app and read by widgets through the App Group.
struct DailySnapshot: Codable, Equatable {
    var date: Date
    var caloriesEaten: Int
    var caloriesTarget: Int
    var proteinEaten: Int
    var proteinTarget: Int
    var weightKg: Double?
    var bodyFatPercent: Double?
    var streakDays: Int

    var caloriesLeft: Int { max(caloriesTarget - caloriesEaten, 0) }
    var proteinLeft: Int { max(proteinTarget - proteinEaten, 0) }

    var caloriesProgress: Double {
        guard caloriesTarget > 0 else { return 0 }
        return min(Double(caloriesEaten) / Double(caloriesTarget), 1)
    }

    var proteinProgress: Double {
        guard proteinTarget > 0 else { return 0 }
        return min(Double(proteinEaten) / Double(proteinTarget), 1)
    }

    static let placeholder = DailySnapshot(
        date: Date(timeIntervalSince1970: 0),
        caloriesEaten: 1420,
        caloriesTarget: 2400,
        proteinEaten: 118,
        proteinTarget: 180,
        weightKg: 78.4,
        bodyFatPercent: 15.2,
        streakDays: 12
    )
}

enum SnapshotStore {
    static let key = "dailySnapshot"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> DailySnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailySnapshot.self, from: data)
    }

    static func save(_ snapshot: DailySnapshot, to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
