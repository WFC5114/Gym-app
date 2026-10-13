import Foundation

/// Launch modes. `-fixture <name>` freezes time on labelled sample data for
/// render captures; `-demo` runs live physics on sample data; no argument is
/// the real app with data on disk and Apple Health.
enum LaunchMode: Equatable {
    case live
    case demo
    case fixture(String)

    static func from(_ arguments: [String]) -> LaunchMode {
        if let i = arguments.firstIndex(of: "-fixture"), i + 1 < arguments.count { return .fixture(arguments[i + 1]) }
        if arguments.contains("-demo") { return .demo }
        return .live
    }
}

@MainActor
enum Fixtures {
    /// 12 Oct 2026, 13:05 local: every fixture frame shows this moment.
    static let date: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 12; c.hour = 13; c.minute = 5
        return Calendar.current.date(from: c)!
    }()

    static func food(_ name: String, grams: Double, minutesAgo: Double) -> FoodEntry {
        let item = BuiltInFoods.all.first { $0.name == name }!
        return .food(item, grams: grams, at: date.addingTimeInterval(-minutesAgo * 60))
    }

    /// A believable day so far: about 1,420 kcal with one quick-add.
    static func sampleDay() -> [FoodEntry] {
        [
            food("Oats, dry", grams: 80, minutesAgo: 330),
            food("Whole milk", grams: 250, minutesAgo: 329),
            food("Banana", grams: 118, minutesAgo: 328),
            food("Chicken breast, cooked", grams: 200, minutesAgo: 40),
            food("White rice, cooked", grams: 250, minutesAgo: 39),
            .quickAdd(kcal: 100, at: date.addingTimeInterval(-20 * 60)),
        ]
    }

    /// Two weeks of logged rests so the coach has history to adapt from:
    /// leg rests were often extended, which the coach should pick up.
    static func sampleRests() -> [RestPeriod] {
        (1...10).map { i in
            let start = date.addingTimeInterval(-Double(i) * 86400 * 1.3)
            let legs = i % 2 == 0
            var rest = RestPeriod(id: UUID(), exercise: legs ? "Back squat" : "Bench press",
                                  bodyPart: legs ? .legs : .chest, afterSet: 2, startedAt: start,
                                  plannedSeconds: legs ? 180 : 150, recommendedSeconds: legs ? 180 : 150)
            if legs { rest.additions = [RestAddition(at: start.addingTimeInterval(150), seconds: 30)] }
            rest.endedAt = rest.endsAt
            rest.endReason = .elapsed
            rest.nextSetAt = rest.endsAt.addingTimeInterval(10)
            return rest
        }
    }

    static func sampleData(foods: [FoodEntry]) -> AppData {
        var data = AppData()
        data.foods = foods
        data.rests = sampleRests()
        data.currentExercise = "Back squat"
        data.memory["Back squat"] = ExerciseMemory(loadKg: 100, reps: 5, restSeconds: 180)
        data.memory["Bench press"] = ExerciseMemory(loadKg: 80, reps: 8, restSeconds: 150)
        data.recentFoods = [BuiltInFoods.all[0], BuiltInFoods.all[3]]
        return data
    }

    static let sampleReadiness = Readiness(hrvToday: 48, hrvBaseline: 58, restingHRToday: 56, restingHRBaseline: 54, sleepHours: 6.6)

    /// Builds the model for a launch mode.
    static func makeModel(for mode: LaunchMode) -> MachineModel {
        switch mode {
        case .live:
            return MachineModel(store: LogStore(persistence: FilePersistence.standard))
        case .demo:
            SoundEngine.shared.isMuted = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            RestActivity.isDisabled = true
            WidgetReload.isDisabled = true
            let model = MachineModel(store: LogStore(persistence: MemoryPersistence(sampleData(foods: shifted(sampleDay())))))
            model.dataCaption = "SAMPLE DATA"
            model.readiness = sampleReadiness
            model.refreshAdvice()
            return model
        case .fixture(let name):
            SoundEngine.shared.isMuted = true
            HapticEngine.shared.isMuted = true
            RestActivity.isDisabled = true
            WidgetReload.isDisabled = true
            return fixture(name)
        }
    }

    /// Demo data moved to today so it shows in a live run, squeezed into the
    /// part of today that has passed (a run just after midnight still shows the day).
    private static func shifted(_ entries: [FoodEntry]) -> [FoodEntry] {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let elapsed = max(now.timeIntervalSince(start) - 60, 60)
        let span = max(entries.map { date.timeIntervalSince($0.loggedAt) }.max() ?? 1, 1)
        let squeeze = min(1, elapsed / span)
        return entries.map { var e = $0; e.loggedAt = now.addingTimeInterval(-date.timeIntervalSince($0.loggedAt) * squeeze - 30); return e }
    }

    static func fixture(_ name: String) -> MachineModel {
        var foods = sampleDay()
        switch name {
        case "diet-empty": foods = []
        case "diet-over-target":
            foods += [food("Pasta, cooked", grams: 400, minutesAgo: 10), food("Olive oil", grams: 27, minutesAgo: 9),
                      food("Cheddar cheese", grams: 60, minutesAgo: 8)]
        case "diet-settled": foods.append(food("Salmon, cooked", grams: 180, minutesAgo: 1))
        default: break
        }
        let store = LogStore(persistence: MemoryPersistence(sampleData(foods: foods)))
        let model = MachineModel(store: store, now: { date }, isFixture: true)
        model.fixtureName = name
        model.dataCaption = "FIXTURE DATA"
        model.readiness = sampleReadiness
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-heroFraction"),
           i + 1 < ProcessInfo.processInfo.arguments.count,
           let f = Double(ProcessInfo.processInfo.arguments[i + 1]) {
            model.heroFraction = CGFloat(f)
        }
        model.refreshAdvice()
        return model
    }

    /// Poses that need the layout (block positions) are applied once it is known.
    static func pose(_ model: MachineModel, fixture name: String) {
        let g = model.deckGeometry
        switch name {
        case "diet-held":
            let rail = model.rail
            var b = FlyingBlock(id: UUID(), kind: .quick(250), size: rail.quickBlockSize(kcal: 250),
                                home: rail.quickBlockHome(kcal: 250),
                                position: CGPoint(x: g.centerX + 30, y: model.landingRect.minY + 90))
            b.phase = .held
            b.lift = SpringState(position: 1, target: 1)
            b.tilt = SpringState(position: -0.12, target: -0.12)
            model.blocks = [b]
        case "diet-contact":
            // The frame right after a 250 kcal block hit: deck at its deepest, slab mid-morph.
            let entry = FoodEntry.quickAdd(kcal: 250, at: date)
            model.store.commitFood(entry)
            let rail = model.rail
            let size = rail.quickBlockSize(kcal: 250)
            let top = model.stackTop
            model.morphs[entry.id] = SlabMorph(from: CGRect(x: g.centerX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
                                               progress: SpringState(position: 0.35, target: 1))
            let rest = Double(g.restingDisplacement(eaten: model.totals.kcal))
            model.deck = SpringState(position: rest + 34, target: rest)
        case "prism-half":
            model.yaw = SpringState(position: 60, target: 60)
        case "diet-intake":
            model.inset = .serving(BuiltInFoods.all[0])
        case "train-ready":
            model.yaw = SpringState(position: 120, target: 120)
        case "train-rest", "train-rest-added":
            model.yaw = SpringState(position: 120, target: 120)
            let started = date.addingTimeInterval(-52)
            model.now = { started }
            model.setDone()
            model.now = { date }
            if name == "train-rest-added" { model.addRestTime() }
            model.syncGlassImmediately()
        case "body-idle":
            model.yaw = SpringState(position: 240, target: 240)
        default:
            break
        }
    }
}
