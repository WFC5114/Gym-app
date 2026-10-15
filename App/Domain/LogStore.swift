import Foundation
import Observation

/// Everything the app records. Health records stay on device in Application Support.
struct AppData: Codable, Equatable {
    var foods: [FoodEntry] = []
    var sets: [SetRecord] = []
    var rests: [RestPeriod] = []
    var memory: [String: ExerciseMemory] = [:]
    /// Foods Wei has logged before, most recent first, for one-tap repeat.
    var recentFoods: [FoodItem] = []
    var targets = NutritionTargets()
    var currentExercise: String = "Bench press"
}

protocol DataPersistence {
    func load() -> AppData?
    func save(_ data: AppData)
}

struct FilePersistence: DataPersistence {
    var url: URL

    static var standard: FilePersistence {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return FilePersistence(url: dir.appendingPathComponent("gym-data.json"))
    }

    func load() -> AppData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: data)
    }

    func save(_ data: AppData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let bytes = try? encoder.encode(data) else { return }
        try? bytes.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

/// Keeps nothing on disk. Used by tests, `-demo` and `-fixture`.
final class MemoryPersistence: DataPersistence {
    var stored: AppData?
    init(_ data: AppData? = nil) { stored = data }
    func load() -> AppData? { stored }
    func save(_ data: AppData) { stored = data }
}

/// The single owner of recorded data. Every mutation is a deliberate command;
/// nothing here is driven by animation callbacks.
@MainActor
@Observable
final class LogStore {
    private(set) var data: AppData
    private let persistence: DataPersistence
    private var foodUndo: [FoodUndo] = []
    let calendar: Calendar

    enum FoodUndo: Equatable {
        case added(UUID)
        case deleted(FoodEntry)
        case edited(FoodEntry)
    }

    init(persistence: DataPersistence, calendar: Calendar = .current) {
        self.persistence = persistence
        self.calendar = calendar
        self.data = persistence.load() ?? AppData()
    }

    private func save() { persistence.save(data) }

    // MARK: Food

    func foods(on day: Date) -> [FoodEntry] {
        data.foods.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }.sorted { $0.loggedAt < $1.loggedAt }
    }

    func totals(on day: Date) -> DayTotals { DayTotals(entries: foods(on: day)) }

    var canUndoFood: Bool { !foodUndo.isEmpty }
    var lastFoodUndo: FoodUndo? { foodUndo.last }

    /// Logs a food once. Committing the same entry id again is ignored, so a
    /// repeated contact event can never double-log.
    @discardableResult
    func commitFood(_ entry: FoodEntry) -> Bool {
        guard !data.foods.contains(where: { $0.id == entry.id }) else { return false }
        data.foods.append(entry)
        foodUndo.append(.added(entry.id))
        if entry.source != .quickAdd, let per100 = entry.per100g {
            let item = FoodItem(id: "recent:\(entry.name)|\(entry.brand ?? "")", name: entry.name, brand: entry.brand,
                                source: entry.source, barcode: nil, per100g: per100, servingGrams: entry.grams, servingLabel: nil)
            data.recentFoods.removeAll { $0.name == item.name && $0.brand == item.brand }
            data.recentFoods.insert(item, at: 0)
            if data.recentFoods.count > 30 { data.recentFoods.removeLast(data.recentFoods.count - 30) }
        }
        save()
        return true
    }

    func deleteFood(id: UUID) {
        guard let index = data.foods.firstIndex(where: { $0.id == id }) else { return }
        let removed = data.foods.remove(at: index)
        foodUndo.append(.deleted(removed))
        save()
    }

    func updateFood(id: UUID, grams: Double) {
        guard grams > 0, let index = data.foods.firstIndex(where: { $0.id == id }),
              let per100 = data.foods[index].per100g else { return }
        foodUndo.append(.edited(data.foods[index]))
        data.foods[index].grams = grams
        data.foods[index].nutrients = per100.scaled(by: grams / 100)
        save()
    }

    /// Reverts the most recent food add, delete or edit. Returns what changed.
    @discardableResult
    func undoFood() -> FoodUndo? {
        guard let last = foodUndo.popLast() else { return nil }
        switch last {
        case .added(let id):
            data.foods.removeAll { $0.id == id }
        case .deleted(let entry):
            data.foods.append(entry)
        case .edited(let old):
            if let i = data.foods.firstIndex(where: { $0.id == old.id }) { data.foods[i] = old }
        }
        save()
        return last
    }

    func setTargets(_ targets: NutritionTargets) {
        data.targets = targets
        save()
    }

    // MARK: Training

    var activeRest: RestPeriod? { data.rests.last(where: { $0.isActive }) }

    func memory(for exercise: String) -> ExerciseMemory? { data.memory[exercise] }

    func remember(_ exercise: String, _ memory: ExerciseMemory) {
        data.memory[exercise] = memory
        save()
    }

    func selectExercise(_ name: String) {
        data.currentExercise = name
        save()
    }

    func setsToday(exercise: String, now: Date) -> [SetRecord] {
        data.sets.filter { $0.exercise == exercise && calendar.isDate($0.completedAt, inSameDayAs: now) }
    }

    func restsToday(bodyPart: BodyPart, now: Date) -> [RestPeriod] {
        data.rests.filter { $0.bodyPart == bodyPart && calendar.isDate($0.startedAt, inSameDayAs: now) }
    }

    /// START REST: closes any running rest (the next one starting early counts
    /// as starting the next set early) and starts a new one. No set is logged.
    @discardableResult
    func startRest(exercise: Exercise, restSeconds: Int, recommendedSeconds: Int?, at now: Date) -> RestPeriod {
        let number = restsToday(bodyPart: exercise.bodyPart, now: now).count + 1
        closeRests(at: now, reason: .nextSet, nextSetAt: now)
        let rest = RestPeriod(id: UUID(), exercise: exercise.name, bodyPart: exercise.bodyPart, afterSet: number,
                              startedAt: now, plannedSeconds: RestLimits.clamp(restSeconds),
                              recommendedSeconds: recommendedSeconds)
        data.rests.append(rest)
        var memory = data.memory[exercise.name] ?? ExerciseMemory(loadKg: 0, reps: 0, restSeconds: RestLimits.clamp(restSeconds))
        memory.restSeconds = RestLimits.clamp(restSeconds)
        data.memory[exercise.name] = memory
        save()
        return rest
    }

    /// SET DONE: records the set, closes any running rest, and starts the next one.
    /// Returns the new rest.
    @discardableResult
    func completeSet(exercise: Exercise, loadKg: Double, reps: Int, restSeconds: Int,
                     recommendedSeconds: Int?, at now: Date) -> RestPeriod {
        let setNumber = setsToday(exercise: exercise.name, now: now).count + 1
        closeRests(at: now, reason: .nextSet, nextSetAt: now)
        data.sets.append(SetRecord(id: UUID(), exercise: exercise.name, bodyPart: exercise.bodyPart,
                                   loadKg: loadKg, reps: reps, setNumber: setNumber, completedAt: now))
        let rest = RestPeriod(id: UUID(), exercise: exercise.name, bodyPart: exercise.bodyPart, afterSet: setNumber,
                              startedAt: now, plannedSeconds: RestLimits.clamp(restSeconds),
                              recommendedSeconds: recommendedSeconds)
        data.rests.append(rest)
        data.memory[exercise.name] = ExerciseMemory(loadKg: loadKg, reps: reps, restSeconds: RestLimits.clamp(restSeconds))
        save()
        return rest
    }

    /// Adds time to the running rest; each press is logged on its own.
    func addRestTime(_ seconds: Int, at now: Date) {
        guard let i = data.rests.lastIndex(where: { $0.isActive }), seconds != 0 else { return }
        data.rests[i].additions.append(RestAddition(at: now, seconds: seconds))
        save()
    }

    /// Closes a rest whose glass ran out. Uses the true end time, not the time
    /// the app noticed, so a rest that finished while suspended is logged exactly.
    func settleElapsedRests(now: Date) {
        var changed = false
        for i in data.rests.indices where data.rests[i].isActive && data.rests[i].endsAt <= now {
            data.rests[i].endedAt = data.rests[i].endsAt
            data.rests[i].endReason = .elapsed
            changed = true
        }
        if changed { save() }
    }

    func cancelRest(at now: Date) { closeRests(at: now, reason: .cancelled, nextSetAt: nil) }

    private func closeRests(at now: Date, reason: RestEnd, nextSetAt: Date?) {
        for i in data.rests.indices {
            if data.rests[i].isActive {
                let ranOut = data.rests[i].endsAt <= now
                data.rests[i].endedAt = ranOut ? data.rests[i].endsAt : now
                data.rests[i].endReason = ranOut ? .elapsed : reason
            }
            // The latest finished rest of this session learns when the next set came.
            if let nextSetAt, data.rests[i].nextSetAt == nil, i == data.rests.count - 1,
               nextSetAt.timeIntervalSince(data.rests[i].startedAt) < 20 * 60 {
                data.rests[i].nextSetAt = nextSetAt
            }
        }
    }
}
