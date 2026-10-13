import XCTest
@testable import GymApp

/// Physics and commit rules of the machine, run deterministically with
/// `step(_:)`. Models are built with `isFixture: true` so no display link
/// starts and time stays frozen unless a test moves it.
@MainActor
final class MachineModelTests: XCTestCase {
    var clock = Date(timeIntervalSince1970: 1_791_800_000)

    override func setUp() {
        super.setUp()
        SoundEngine.shared.isMuted = true
        HapticEngine.shared.isMuted = true
        RestActivity.isDisabled = true
        WidgetReload.isDisabled = true
    }

    func makeModel(foods: [FoodEntry] = []) -> MachineModel {
        var data = AppData()
        data.foods = foods
        let store = LogStore(persistence: MemoryPersistence(data))
        return MachineModel(store: store, now: { [unowned self] in self.clock }, isFixture: true)
    }

    func run(_ model: MachineModel, seconds: Double) {
        for _ in 0..<Int(seconds * 240) { model.step(1.0 / 240) }
    }

    /// Drags a rail block to `point` over a few samples and lets go.
    @discardableResult
    func drop(_ kcal: Int, on model: MachineModel, at point: CGPoint) -> UUID? {
        let home = model.rail.quickBlockHome(kcal: kcal)
        guard let id = model.grabQuick(kcal: kcal, at: home, time: 0) else { return nil }
        for k in 1...10 {
            let t = CGFloat(k) / 10
            let p = CGPoint(x: home.x + (point.x - home.x) * t, y: home.y + (point.y - home.y) * t)
            model.dragBlock(id, to: p, time: Double(k) / 60)
            model.step(1.0 / 60)
        }
        model.releaseBlock(id)
        return id
    }

    func deckPoint(_ m: MachineModel) -> CGPoint {
        CGPoint(x: m.deckGeometry.centerX, y: m.landingRect.minY + 20)
    }

    // MARK: DIET

    func testDropOnDeckCommitsExactlyOnce() {
        let model = makeModel()
        drop(250, on: model, at: deckPoint(model))
        XCTAssertEqual(model.blocks.first?.phase, .falling)
        run(model, seconds: 3)
        XCTAssertEqual(model.today.count, 1)
        XCTAssertEqual(model.totals.kcal, 250)
        XCTAssertTrue(model.blocks.isEmpty)
        run(model, seconds: 3)
        XCTAssertEqual(model.today.count, 1, "contact must not fire twice")
    }

    func testReleaseOutsideTheDeckLogsNothing() {
        let model = makeModel()
        drop(100, on: model, at: CGPoint(x: model.layout.side + 10, y: 40))
        XCTAssertEqual(model.blocks.first?.phase, .returning)
        run(model, seconds: 3)
        XCTAssertTrue(model.today.isEmpty)
        XCTAssertTrue(model.blocks.isEmpty, "the block springs home and rejoins the rail")
    }

    func testRegrabbingAFallingBlockLogsNothing() throws {
        let model = makeModel()
        let id = drop(500, on: model, at: deckPoint(model))
        model.step(1.0 / 240)
        guard let falling = model.blocks.first(where: { $0.id == id }) else { return XCTFail("block landed too early") }
        XCTAssertEqual(falling.phase, .falling)
        XCTAssertEqual(model.grabQuick(kcal: 500, at: falling.position, time: 1), id, "same block, caught mid-fall")
        XCTAssertEqual(model.blocks.first?.phase, .held)
        model.cancelBlock(try XCTUnwrap(id))
        run(model, seconds: 3)
        XCTAssertTrue(model.today.isEmpty)
    }

    func testUndoRemovesTheDroppedBlock() {
        let model = makeModel()
        drop(50, on: model, at: deckPoint(model))
        run(model, seconds: 3)
        XCTAssertEqual(model.today.count, 1)
        model.undoFood()
        XCTAssertTrue(model.today.isEmpty)
        XCTAssertFalse(model.store.canUndoFood)
    }

    func testLoggedFoodCommitsWithItsOwnIdOnce() throws {
        let model = makeModel()
        let item = try XCTUnwrap(BuiltInFoods.all.first)
        model.formBlock(item: item, grams: 150)
        let pending = try XCTUnwrap(model.pending)
        model.loadPending()
        XCTAssertEqual(model.today.map(\.id), [pending.entryID])
        XCTAssertEqual(model.today.first?.grams, 150)
        XCTAssertNil(model.pending)
        model.loadPending()
        XCTAssertEqual(model.today.count, 1)
    }

    func testDiscardingAFormedBlockLogsNothing() throws {
        let model = makeModel()
        model.formBlock(item: try XCTUnwrap(BuiltInFoods.all.first), grams: 100)
        model.discardPending()
        model.loadPending()
        XCTAssertTrue(model.today.isEmpty)
    }

    func testDeckCompressionIsBoundedAt120Percent() {
        let g = makeModel().deckGeometry
        XCTAssertEqual(g.restingDisplacement(eaten: 0), 0)
        XCTAssertEqual(g.restingDisplacement(eaten: g.targetKcal), g.travelPerTarget, accuracy: 0.001)
        XCTAssertEqual(g.restingDisplacement(eaten: g.targetKcal * 3), g.travelPerTarget * 1.2, accuracy: 0.001)
        XCTAssertGreaterThan(g.springLength(displacement: g.travelPerTarget * 1.2), 0)
    }

    func testStackScalesInsteadOfLeavingTheMechanism() {
        let g = makeModel().deckGeometry
        let small = g.slabHeights(kcals: [300, 400])
        XCTAssertFalse(small.scaled)
        let huge = g.slabHeights(kcals: Array(repeating: 900, count: 8))
        XCTAssertTrue(huge.scaled)
        XCTAssertLessThanOrEqual(huge.heights.reduce(0, +), g.maxStackHeight + 0.001)
        let top = g.plateTop(displacement: g.travelPerTarget * 1.2) - huge.heights.reduce(0, +)
        XCTAssertGreaterThan(top, g.mech.minY, "a full stack stays inside the mechanism region")
    }

    func testOverTargetDayStaysInsideTheFace() {
        // 8,000 kcal against 2,450: well past the 120% compression bound and taller than the stack allowance.
        let entries = (0..<16).map { i in FoodEntry.quickAdd(kcal: 500, at: clock.addingTimeInterval(Double(-i) * 60)) }
        let model = makeModel(foods: entries)
        run(model, seconds: 2)
        XCTAssertTrue(model.isStackScaled)
        for slab in model.slabRects() {
            XCTAssertGreaterThanOrEqual(slab.rect.minY, model.layout.mechanismRect.minY)
            XCTAssertLessThanOrEqual(slab.rect.maxY, model.layout.mechanismRect.maxY)
        }
    }

    // MARK: Juice

    /// Steps until the first block lands, then returns.
    func stepUntilLanded(_ model: MachineModel, count: Int = 1) {
        for _ in 0..<2400 where model.today.count < count { model.step(1.0 / 240) }
    }

    func testContactFiresOneBurstAndPunchesTheNumber() {
        let model = makeModel()
        let before = model.heroKcal.position
        drop(250, on: model, at: deckPoint(model))
        stepUntilLanded(model)
        XCTAssertEqual(model.bursts.count, 1)
        XCTAssertEqual(model.bursts.first?.face, .diet)
        XCTAssertGreaterThan(model.heroPunch.velocity, 0)
        run(model, seconds: 4)
        XCTAssertTrue(model.bursts.isEmpty, "rays finish and are removed")
        XCTAssertEqual(model.heroKcal.position, before - 250, accuracy: 0.5, "the number counts down to the new value")
    }

    func testReduceMotionKeepsTheLogButDropsTheBurst() {
        let model = makeModel()
        model.reduceMotion = true
        drop(250, on: model, at: deckPoint(model))
        stepUntilLanded(model)
        XCTAssertEqual(model.today.count, 1)
        XCTAssertTrue(model.bursts.isEmpty)
    }

    func testCrossingTheTargetFiresASecondBurst() {
        let target = Int(AppData().targets.kcal)
        let model = makeModel(foods: [FoodEntry.quickAdd(kcal: target - 100, at: clock)])
        drop(250, on: model, at: deckPoint(model))
        stepUntilLanded(model, count: 2)
        XCTAssertEqual(model.bursts.count, 2)
    }

    func testHoldingABlockOverTheDeckWindsItUp() throws {
        let model = makeModel()
        let resting = model.deck.position
        let home = model.rail.quickBlockHome(kcal: 500)
        let id = try XCTUnwrap(model.grabQuick(kcal: 500, at: home, time: 0))
        model.dragBlock(id, to: deckPoint(model), time: 0.1)
        run(model, seconds: 1)
        XCTAssertGreaterThan(model.charge.position, 0.9)
        XCTAssertGreaterThan(model.deck.position, resting, "the deck pre-loads under the held block")
        model.cancelBlock(id)
        run(model, seconds: 3)
        XCTAssertLessThan(model.charge.position, 0.01)
        XCTAssertTrue(model.today.isEmpty)
    }

    // MARK: Prism

    func testSwipeTurnsAtMostOneFace() {
        let model = makeModel()
        model.beginRotate(screenX: 400, time: 0)
        model.updateRotate(screenX: 0, time: 0.05)
        model.updateRotate(screenX: -600, time: 0.1)
        model.endRotate(time: 0.1)
        XCTAssertEqual(model.yaw.target, 120)
        XCTAssertEqual(model.face, .train)
    }

    func testShortSwipeSettlesBack() {
        let model = makeModel()
        model.beginRotate(screenX: 200, time: 0)
        model.updateRotate(screenX: 195, time: 1)
        model.endRotate(time: 1)
        XCTAssertEqual(model.yaw.target, 0)
    }

    // MARK: TRAIN

    func testHourglassGrowsWithRestLength() {
        let g = makeModel().glassGeometry
        var previous: CGFloat = 0
        for s in stride(from: 30.0, through: 360, by: 15) {
            let h = g.height(forSeconds: s)
            XCTAssertGreaterThan(h, previous)
            previous = h
        }
        XCTAssertEqual(g.height(forSeconds: 10), g.minHeight, accuracy: 0.001)
        XCTAssertEqual(g.height(forSeconds: 900), g.maxHeight, accuracy: 0.001)
        XCTAssertLessThanOrEqual(g.maxHeight, g.mech.height)
    }

    func testChangingRestResizesTheGlass() {
        let model = makeModel()
        model.plannedRest = 60
        model.syncGlassImmediately()
        let before = model.glassHeight.target
        model.adjustPlannedRest(by: 60)
        model.step(1.0 / 240)
        XCTAssertEqual(model.plannedRest, 120)
        XCTAssertGreaterThan(model.glassHeight.target, before)
    }

    func testSetDoneFlipsTheGlassAndLogsTheRest() throws {
        let model = makeModel()
        model.plannedRest = 90
        model.setDone()
        XCTAssertEqual(model.glassParity, 1)
        XCTAssertEqual(model.glassAngle.target, .pi, accuracy: 1e-9)
        let rest = try XCTUnwrap(model.activeRest)
        XCTAssertEqual(rest.plannedSeconds, 90)
        XCTAssertEqual(rest.bodyPart, model.exercise.bodyPart)
        XCTAssertEqual(model.topSandTarget, 1, accuracy: 0.001, "full top bulb right after the flip")

        model.addRestTime()
        XCTAssertEqual(model.activeRest?.additions.map(\.seconds), [30])
        XCTAssertEqual(model.glassSeconds, 120)

        clock = clock.addingTimeInterval(60)
        model.step(1.0 / 240)
        XCTAssertEqual(model.topSandTarget, 0.5, accuracy: 0.01)

        clock = clock.addingTimeInterval(61)
        model.step(1.0 / 240)
        XCTAssertNil(model.activeRest)
        XCTAssertEqual(model.restJustEnded?.totalSeconds, 120)
        XCTAssertEqual(model.store.data.rests.last?.endReason, .elapsed)
    }

    func testSecondSetFlipsBackTheOtherWay() {
        let model = makeModel()
        model.setDone()
        clock = clock.addingTimeInterval(200)
        model.step(1.0 / 240)
        model.setDone()
        XCTAssertEqual(model.glassParity, 2)
        XCTAssertTrue(model.aIsUp)
        XCTAssertEqual(model.store.data.sets.count, 2)
    }
}
