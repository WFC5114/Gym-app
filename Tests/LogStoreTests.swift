import XCTest
@testable import GymApp

@MainActor
final class LogStoreTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_791_800_000)

    func makeStore() -> LogStore { LogStore(persistence: MemoryPersistence()) }

    func testCommittingTheSameEntryTwiceLogsOnce() {
        let store = makeStore()
        let entry = FoodEntry.quickAdd(kcal: 250, at: t0)
        XCTAssertTrue(store.commitFood(entry))
        XCTAssertFalse(store.commitFood(entry))
        XCTAssertEqual(store.foods(on: t0).count, 1)
    }

    func testQuickAddKeepsMacrosUnknown() {
        let totals = DayTotals(entries: [.quickAdd(kcal: 500, at: t0)])
        XCTAssertEqual(totals.kcal, 500)
        XCTAssertEqual(totals.protein, 0)
        XCTAssertEqual(totals.entriesWithUnknownMacros, 1)
        XCTAssertNil(FoodEntry.quickAdd(kcal: 500, at: t0).nutrients.protein)
    }

    func testUndoRevertsAddDeleteAndEdit() {
        let store = makeStore()
        let item = BuiltInFoods.all[0]
        let entry = FoodEntry.food(item, grams: 200, at: t0)
        store.commitFood(entry)
        store.updateFood(id: entry.id, grams: 100)
        XCTAssertEqual(store.foods(on: t0).first?.nutrients.kcal ?? 0, 165, accuracy: 0.01)
        store.undoFood()
        XCTAssertEqual(store.foods(on: t0).first?.nutrients.kcal ?? 0, 330, accuracy: 0.01)
        store.deleteFood(id: entry.id)
        XCTAssertTrue(store.foods(on: t0).isEmpty)
        store.undoFood()
        XCTAssertEqual(store.foods(on: t0).count, 1)
        store.undoFood()
        XCTAssertTrue(store.foods(on: t0).isEmpty)
        XCTAssertFalse(store.canUndoFood)
    }

    func testPersistsAcrossRelaunch() {
        let disk = MemoryPersistence()
        let a = LogStore(persistence: disk)
        a.commitFood(.quickAdd(kcal: 100, at: t0))
        let squat = Exercise.named("Back squat")!
        a.completeSet(exercise: squat, loadKg: 100, reps: 5, restSeconds: 180, recommendedSeconds: 180, at: t0)
        let b = LogStore(persistence: disk)
        XCTAssertEqual(b.foods(on: t0).count, 1)
        XCTAssertNotNil(b.activeRest, "A running rest survives relaunch")
    }

    func testRestAdditionsAreLoggedSeparately() {
        let store = makeStore()
        let squat = Exercise.named("Back squat")!
        store.completeSet(exercise: squat, loadKg: 100, reps: 5, restSeconds: 180, recommendedSeconds: 165, at: t0)
        store.addRestTime(30, at: t0.addingTimeInterval(100))
        store.addRestTime(30, at: t0.addingTimeInterval(170))
        let rest = store.activeRest!
        XCTAssertEqual(rest.plannedSeconds, 180)
        XCTAssertEqual(rest.recommendedSeconds, 165)
        XCTAssertEqual(rest.additions.map(\.seconds), [30, 30])
        XCTAssertEqual(rest.totalSeconds, 240)
        XCTAssertEqual(rest.endsAt, t0.addingTimeInterval(240))
    }

    func testRestThatRanOutWhileSuspendedEndsAtItsTrueTime() {
        let store = makeStore()
        let bench = Exercise.named("Bench press")!
        store.completeSet(exercise: bench, loadKg: 80, reps: 8, restSeconds: 120, recommendedSeconds: nil, at: t0)
        store.settleElapsedRests(now: t0.addingTimeInterval(3600))
        let rest = store.data.rests.last!
        XCTAssertEqual(rest.endedAt, t0.addingTimeInterval(120))
        XCTAssertEqual(rest.endReason, .elapsed)
    }

    func testNextSetClosesTheRestEarlyAndRecordsTheGap() {
        let store = makeStore()
        let bench = Exercise.named("Bench press")!
        store.completeSet(exercise: bench, loadKg: 80, reps: 8, restSeconds: 150, recommendedSeconds: nil, at: t0)
        store.completeSet(exercise: bench, loadKg: 80, reps: 7, restSeconds: 150, recommendedSeconds: nil, at: t0.addingTimeInterval(95))
        let first = store.data.rests[0]
        XCTAssertEqual(first.endReason, .nextSet)
        XCTAssertEqual(first.actualSeconds, 95)
        XCTAssertEqual(store.data.sets.map(\.setNumber), [1, 2])
        XCTAssertEqual(store.data.rests[1].afterSet, 2)
    }

    func testPlannedRestIsClamped() {
        let store = makeStore()
        let rest = store.completeSet(exercise: Exercise.library[0], loadKg: 1, reps: 1, restSeconds: 9999, recommendedSeconds: nil, at: t0)
        XCTAssertEqual(rest.plannedSeconds, RestLimits.maxSeconds)
    }
}
