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

    func jarPoint(_ m: MachineModel) -> CGPoint {
        CGPoint(x: m.jarGeometry.outer.midX, y: m.landingRect.minY + 20)
    }

    // MARK: DIET

    func testDropInTheJarCommitsExactlyOnce() {
        let model = makeModel()
        drop(250, on: model, at: jarPoint(model))
        XCTAssertEqual(model.blocks.first?.phase, .falling)
        run(model, seconds: 3)
        XCTAssertEqual(model.today.count, 1)
        XCTAssertEqual(model.totals.kcal, 250)
        XCTAssertTrue(model.blocks.isEmpty)
        run(model, seconds: 3)
        XCTAssertEqual(model.today.count, 1, "contact must not fire twice")
    }

    func testReleaseOutsideTheJarLogsNothing() {
        let model = makeModel()
        drop(100, on: model, at: CGPoint(x: model.layout.side + 10, y: 40))
        XCTAssertEqual(model.blocks.first?.phase, .returning)
        run(model, seconds: 3)
        XCTAssertTrue(model.today.isEmpty)
        XCTAssertTrue(model.blocks.isEmpty, "the block springs home and rejoins the rail")
    }

    func testRegrabbingAFallingBlockLogsNothing() throws {
        let model = makeModel()
        let id = drop(500, on: model, at: jarPoint(model))
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
        drop(50, on: model, at: jarPoint(model))
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

    func sampleEntries() -> [FoodEntry] {
        let items = BuiltInFoods.all
        return [
            .food(items[0], grams: 80, at: clock.addingTimeInterval(-3000)),
            .food(items[1], grams: 250, at: clock.addingTimeInterval(-2900)),
            .quickAdd(kcal: 100, at: clock.addingTimeInterval(-2000)),
            .food(items[2], grams: 200, at: clock.addingTimeInterval(-1000)),
            .quickAdd(kcal: 500, at: clock.addingTimeInterval(-500)),
        ]
    }

    func testBiggerMealsMakeBiggerBlocks() {
        let g = makeModel().jarGeometry
        var previous: CGFloat = 0
        for kcal in [50.0, 100, 250, 500, 900] {
            let size = g.blockSize(kcal: kcal, seed: 42)
            XCTAssertGreaterThan(size.width * size.height, previous)
            XCTAssertLessThanOrEqual(size.width, g.interior.width)
            previous = size.width * size.height
        }
    }

    func testBlocksRestInsideTheJarWalls() {
        let model = makeModel(foods: sampleEntries())
        let g = model.jarGeometry
        let pile = model.pile
        XCTAssertEqual(pile.poses.count, 5)
        XCTAssertFalse(pile.scaled)
        for pose in pile.poses {
            XCTAssertLessThanOrEqual(abs(pose.angle), JarGeometry.maxTilt + 0.001)
            for corner in JarGeometry.corners(of: pose) {
                XCTAssertGreaterThanOrEqual(corner.x, g.interior.minX - 0.5)
                XCTAssertLessThanOrEqual(corner.x, g.interior.maxX + 0.5)
                XCTAssertLessThanOrEqual(corner.y, g.floorY + 0.5, "nothing sinks through the floor")
            }
        }
    }

    func testTheSameDayAlwaysPilesTheSameWay() {
        let entries = sampleEntries()
        XCTAssertEqual(makeModel(foods: entries).pile, makeModel(foods: entries).pile)
    }

    func testHugeDayShrinksTheBlocksToStayInTheFace() {
        // 8,000 kcal against 2,450: far past the target and the overflow room.
        let entries = (0..<16).map { i in FoodEntry.quickAdd(kcal: 500, at: clock.addingTimeInterval(Double(-i) * 60)) }
        let model = makeModel(foods: entries)
        run(model, seconds: 2)
        XCTAssertTrue(model.isPileScaled)
        XCTAssertGreaterThanOrEqual(model.pile.top, model.jarGeometry.ceilingY - 0.5)
        for piece in model.jarPieces() {
            XCTAssertGreaterThanOrEqual(piece.center.y, model.layout.mechanismRect.minY)
            XCTAssertLessThanOrEqual(piece.center.y, model.layout.mechanismRect.maxY)
        }
    }

    func testDroppedBlockTumblesIntoItsPlaceInThePile() throws {
        let model = makeModel(foods: sampleEntries())
        drop(250, on: model, at: jarPoint(model))
        run(model, seconds: 4)
        XCTAssertEqual(model.today.count, 6)
        let last = try XCTUnwrap(model.today.last)
        let pose = try XCTUnwrap(model.pile.poses.last)
        let motion = try XCTUnwrap(model.pieces[last.id])
        XCTAssertEqual(motion.x.position, Double(pose.center.x), accuracy: 0.5)
        XCTAssertEqual(motion.y.position, Double(pose.center.y), accuracy: 0.5)
        XCTAssertEqual(motion.angle.position, pose.angle, accuracy: 0.01)
    }

    func testDeletingABlockLetsTheOnesAboveSettle() throws {
        let model = makeModel(foods: sampleEntries())
        let first = try XCTUnwrap(model.today.first)
        model.deleteFood(first.id)
        run(model, seconds: 4)
        XCTAssertNil(model.pieces[first.id])
        XCTAssertEqual(model.pieces.count, 4)
        XCTAssertTrue(model.pieces.values.allSatisfy(\.isSettled))
        model.undoFood()
        run(model, seconds: 4)
        XCTAssertEqual(model.pieces.count, 5, "undo drops it back in")
    }

    func testTappingABlockOpensThatFood() throws {
        let model = makeModel(foods: sampleEntries())
        let entry = try XCTUnwrap(model.today.first)
        model.openInset(.entry(entry.id))
        XCTAssertEqual(model.inset, .entry(entry.id))
    }

    // MARK: Juice

    /// Steps until the first block lands, then returns.
    func stepUntilLanded(_ model: MachineModel, count: Int = 1) {
        for _ in 0..<2400 where model.today.count < count { model.step(1.0 / 240) }
    }

    func testContactFiresOneBurstAndPunchesTheNumber() {
        let model = makeModel()
        let before = model.heroKcal.position
        drop(250, on: model, at: jarPoint(model))
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
        drop(250, on: model, at: jarPoint(model))
        stepUntilLanded(model)
        XCTAssertEqual(model.today.count, 1)
        XCTAssertTrue(model.bursts.isEmpty)
    }

    func testCrossingTheTargetFiresASecondBurst() {
        let target = Int(AppData().targets.kcal)
        let model = makeModel(foods: [FoodEntry.quickAdd(kcal: target - 100, at: clock)])
        drop(250, on: model, at: jarPoint(model))
        stepUntilLanded(model, count: 2)
        XCTAssertEqual(model.bursts.count, 2)
    }

    func testHoldingABlockOverTheJarWindsItUp() throws {
        let model = makeModel()
        let resting = model.jarBob.position
        let home = model.rail.quickBlockHome(kcal: 500)
        let id = try XCTUnwrap(model.grabQuick(kcal: 500, at: home, time: 0))
        model.dragBlock(id, to: jarPoint(model), time: 0.1)
        run(model, seconds: 1)
        XCTAssertGreaterThan(model.charge.position, 0.9)
        XCTAssertGreaterThan(model.jarBob.position, resting, "the jar sinks a little under the held block")
        XCTAssertGreaterThan(model.blocks.first?.sizeMix.position ?? 0, 0.9, "the block swells to its jar size")
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
