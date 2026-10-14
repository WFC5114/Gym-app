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

    func testGlassKeepsClearOfTheCoachNoteAndInsideTheFace() {
        let model = makeModel()
        let g = model.glassGeometry
        let l = model.layout
        for h in stride(from: g.minHeight, through: g.maxHeight, by: 10) {
            let c = g.center(forHeight: h)
            let half = h * HourglassGeometry.aspect / 2
            XCTAssertGreaterThanOrEqual(c.x - half, l.side + l.contentWidth * HourglassGeometry.noteShare, "height \(h)")
            XCTAssertLessThanOrEqual(c.x + half, l.side + l.contentWidth + 0.5, "height \(h)")
        }
    }

    // MARK: Desk hourglass

    func testDeskHourglassStandsOneUnitTallAndSymmetric() {
        typealias H = DeskHourglass
        XCTAssertEqual(2 * (H.nutY + H.nutRadius), 1, accuracy: 0.02, "nut to foot fills the glass height")
        XCTAssertGreaterThan(H.bulbEnd, H.collarY - H.collarHeight / 2, "each open bulb end sits in its cup")
        XCTAssertLessThanOrEqual(H.bulbEnd, H.plateInner, "and stops at the plate")
        XCTAssertLessThan(H.collarY + H.collarHeight / 2, H.plateInner + 0.001)
        for y: Float in [0.1, 0.2, 0.3, 0.4] { XCTAssertEqual(H.outerRadius(y), H.outerRadius(-y)) }
        let widest = H.profile.map(\.y).max()!
        XCTAssertLessThan(widest, H.postOffset * Float(2).squareRoot() - H.postRadius, "the bulbs clear the corner posts")
        XCTAssertLessThan(widest, H.slabHalfSide, "and stay inside the plates")
    }

    func testHourglassGlassIsThickAllTheWayRound() {
        typealias H = DeskHourglass
        for y in stride(from: Float(0.05), through: 0.35, by: 0.05).map({ $0 * H.unit }) {
            let gap = H.outerRadius(y) - H.innerRadius(y)
            XCTAssertGreaterThan(gap, H.wall * 0.6, "at \(y)")
            XCTAssertLessThan(gap, H.wall * 3, "at \(y)")
        }
        XCTAssertGreaterThan(H.innerRadius(0), 0, "sand still passes the neck")
        XCTAssertLessThan(H.innerRadius(0), H.outerRadius(0) - H.wall * 0.9, "and the neck is heavy glass")
        let loop = H.glassLoop
        XCTAssertEqual(loop.first!.x, -H.bulbEnd, accuracy: 0.0001)
        XCTAssertGreaterThan(loop.count, 300, "dense enough to read smooth and round")
    }

    /// Clay keys and trays: the slab fills its outline, sits on its flat back
    /// and swells forward only at the middle.
    func testClaySlabKeepsItsOutlineAndPuffsForward() {
        let rings = Geometry.slabRings(halfWidth: 1, halfHeight: 0.3, depth: 0.2, corner: 0.12, bevel: 0.06, puff: 0.03)
        let points = rings.flatMap { $0 }
        XCTAssertEqual(points.map(\.x).max()!, 1, accuracy: 0.0001)
        XCTAssertEqual(points.map(\.y).min()!, -0.3, accuracy: 0.0001)
        XCTAssertEqual(points.map(\.z).min()!, 0, accuracy: 0.0001)
        XCTAssertEqual(points.map(\.z).max()!, 0.23, accuracy: 0.0001, "front centre is the puff above the face")
        XCTAssertTrue(rings.allSatisfy { $0.count == rings[0].count }, "every ring has the same points")
        XCTAssertEqual(rings.first!.first!, SIMD3(0, 0, 0.23), "front pole")
        // A capsule (bevel as round as the corner) keeps a front outline, never a collapsed line.
        let tube = Geometry.slabRings(halfWidth: 1, halfHeight: 0.1, depth: 0.2, corner: 0.1, bevel: 0.1)
        XCTAssertTrue(tube.flatMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }

    func testSandStaysInsideTheGlass() {
        typealias H = DeskHourglass
        for a: Float in [0.05, 0.5, 1] {
            for p in H.drainProfile(a) + H.heapProfile(a) {
                XCTAssertLessThanOrEqual(p.y, H.innerRadius(p.x) + 0.0001)
                XCTAssertLessThanOrEqual(abs(p.x), H.bulbEnd)
            }
        }
    }

    func testDrainingSandSinksAndThePileRisesBelowTheNeck() {
        typealias H = DeskHourglass
        let tops = [0.1, 0.5, 1].map { H.drainProfile(Float($0)).map(\.x).max()! }
        XCTAssertLessThan(tops[0], tops[1])
        XCTAssertLessThan(tops[1], tops[2])
        XCTAssertGreaterThan(tops[0], H.neckY)
        let apexes = [0.1, 0.5, 1].map { H.heapApex(Float($0)) }
        XCTAssertLessThan(apexes[0], apexes[1])
        XCTAssertLessThan(apexes[1], apexes[2])
        XCTAssertLessThan(apexes[2], -H.neckY, "a full pile still peaks under the neck")
    }

    func testDrainAndPileHoldTheSameSand() {
        typealias H = DeskHourglass
        let top = H.level(from: H.neckY, holding: 0.5 * H.fullVolume, limit: H.fullLevel)
        XCTAssertEqual(H.volume(from: H.neckY, to: top) / H.fullVolume, 0.5, accuracy: 0.01)
    }

    // MARK: BODY

    func testMoreFatFillsOutTheFigure() {
        let lean = FigureShape.from(fatPercent: 12, leanKg: 66)
        let soft = FigureShape.from(fatPercent: 28, leanKg: 66)
        XCTAssertGreaterThan(soft.waist, lean.waist)
        XCTAssertGreaterThan(soft.depth, lean.depth)
        XCTAssertGreaterThan(soft.limb, lean.limb)
        XCTAssertGreaterThan(soft.waist - lean.waist, soft.shoulders - lean.shoulders, "fat shows at the waist first")
    }

    func testMoreLeanMassBroadensShouldersAndLimbs() {
        let small = FigureShape.from(fatPercent: 16, leanKg: 55)
        let big = FigureShape.from(fatPercent: 16, leanKg: 80)
        XCTAssertGreaterThan(big.shoulders, small.shoulders)
        XCTAssertGreaterThan(big.limb, small.limb)
        XCTAssertGreaterThan(big.shoulders - small.shoulders, big.waist - small.waist, "muscle shows at the shoulders first")
    }

    func testFigureStaysInRangeForExtremeReadings() {
        XCTAssertEqual(FigureShape.from(fatPercent: 80, leanKg: 200), FigureShape.from(fatPercent: 45, leanKg: 100))
        XCTAssertEqual(FigureShape.from(fatPercent: nil, leanKg: nil), FigureShape.neutral)
        for fat in [0.0, 5, 16, 30, 45, 90] {
            for lean in [10.0, 35, 66, 100, 150] {
                let f = FigureShape.from(fatPercent: fat, leanKg: lean)
                for v in [f.shoulders, f.waist, f.depth, f.limb] { XCTAssertTrue(FigureShape.range.contains(v)) }
                XCTAssertLessThan(f.height, 1.04)
                XCTAssertGreaterThan(f.height, 0.95)
            }
        }
    }

    func testArmsHangClearOfTheHipsAndLegsStayApart() {
        for fat in [5.0, 16, 30, 45] {
            for lean in [35.0, 66, 100] {
                let f = FigureShape.from(fatPercent: fat, leanKg: lean)
                let p = Mannequin.positions(shape: f, pose: Mannequin.Pose(swing: f.armSwing))
                for wrist in [Mannequin.Joint.wristL, .wristR] {
                    XCTAssertGreaterThan(abs(p[wrist]!.x) - 0.0132, Mannequin.pelvisTop * f.pelvisScale.x,
                                         "fat \(fat) lean \(lean): hand clear of the hips")
                }
                XCTAssertGreaterThanOrEqual(f.hipX - Mannequin.thighTop * f.legScale, 0, "thighs apart")
                XCTAssertGreaterThanOrEqual(f.armSwing, Mannequin.minimumSwing)
                XCTAssertGreaterThan(p[.shoulderL]!.x, 0)
                XCTAssertLessThan(p[.shoulderR]!.x, 0)
            }
        }
    }

    func testMannequinStandsOnTheDialAndHasTallProportions() {
        let p = Mannequin.positions(shape: .neutral, pose: Mannequin.Pose())
        for ankle in [Mannequin.Joint.ankleL, .ankleR] {
            XCTAssertEqual(p[ankle]!.y, 0.022, accuracy: 0.012, "ankles just above the dial")
        }
        let headHeight = 2 * Mannequin.skull.y
        XCTAssertGreaterThan(Mannequin.headTop / headHeight, 6.5, "a tall artist's mannequin, not a squat toy")
    }

    func testTapFlexesTheRightArmThenLetsGo() {
        let model = makeModel()
        let rest = Mannequin.positions(shape: model.figure, pose: model.figurePose)
        model.pokeFigure()
        run(model, seconds: 0.6)
        XCTAssertGreaterThan(model.figureFlex.position, 0.8)
        let flexed = Mannequin.positions(shape: model.figure, pose: model.figurePose)
        XCTAssertGreaterThan(flexed[.wristR]!.y, flexed[.shoulderR]!.y, "the fist rises above the shoulder")
        XCTAssertEqual(flexed[.wristL]!.y, rest[.wristL]!.y, accuracy: 0.001, "the other arm stays put")
        run(model, seconds: 4)
        XCTAssertEqual(model.figureFlex.position, 0, accuracy: 0.01, "and back down")
        XCTAssertFalse(model.needsFrames)
    }

    func testFixtureFigureHoldsStill() {
        let model = makeModel()
        model.yaw = SpringState(position: 240, target: 240)
        run(model, seconds: 2)
        XCTAssertEqual(model.bodyClock, 0, "no idle life in fixtures, so captures repeat exactly")
        XCTAssertFalse(model.figureIsAlive)
    }

    func testFatBetweenScansFollowsTheScaleTrend() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let history = (0..<15).map { i in
            BodyObservation(date: cal.date(byAdding: .day, value: i, to: start)!,
                            weightKg: 80 - Double(i) * 0.1,
                            bodyFatPercent: i == 0 ? 20 : nil, leanKg: i == 0 ? 64 : nil, isScan: i == 0)
        }
        let scanDay = BodyComposition.on(history, upTo: 0)
        XCTAssertEqual(scanDay.fatPercent, 20)
        XCTAssertFalse(scanDay.fatIsEstimate)
        let later = BodyComposition.on(history, upTo: 14)
        XCTAssertTrue(later.fatIsEstimate, "between scans the fat figure is an estimate")
        XCTAssertEqual(later.leanKg, 64, "lean is held at the last scan")
        XCTAssertLessThan(later.fatPercent!, 20, "the trend went down, so estimated fat did too")
        XCTAssertGreaterThan(later.fatPercent!, 18.5, "the trend lags the raw scale, so the change is gentle")
    }

    func testTrainingTiltLeansGentlyTowardTheMostTrainedParts() {
        let end = Date(timeIntervalSince1970: 1_791_800_000)
        func sets(_ part: BodyPart, _ count: Int) -> [SetRecord] {
            (0..<count).map { i in
                SetRecord(id: UUID(), exercise: "x", bodyPart: part, loadKg: 80, reps: 8, setNumber: i + 1,
                          completedAt: end.addingTimeInterval(-Double(i) * 3_600))
            }
        }
        XCTAssertEqual(MuscleTilt.from(sets(.legs, 5), endingAt: end), MuscleTilt.none, "too few sets to say anything")
        let legDay = MuscleTilt.from(sets(.legs, 30) + sets(.chest, 6), endingAt: end)
        XCTAssertGreaterThan(legDay.legs, 0)
        XCTAssertLessThan(legDay.arms, 0)
        for v in [legDay.legs, legDay.arms, legDay.shoulders, legDay.torso] {
            XCTAssertLessThanOrEqual(abs(v), MuscleTilt.limit)
        }
        let old = MuscleTilt.from(sets(.legs, 30), endingAt: end.addingTimeInterval(40 * 86_400))
        XCTAssertEqual(old, MuscleTilt.none, "sets older than 28 days no longer count")
        let shaped = FigureShape.from(fatPercent: 16, leanKg: 66, tilt: legDay)
        XCTAssertGreaterThan(shaped.legScale, FigureShape.neutral.legScale)
        XCTAssertLessThan(shaped.armScale, FigureShape.neutral.armScale)
    }

    func testFigureFollowsTheScrubbedDayOnASpring() {
        let model = makeModel()
        let today = BodyObservation.carried(model.bodyHistory, upTo: model.bodyHistory.count - 1)
        XCTAssertEqual(model.figureFat.position, today.fat!, accuracy: 0.001)
        model.scrubBody(toFraction: 0)
        run(model, seconds: 0.1)
        let first = BodyObservation.carried(model.bodyHistory, upTo: 0)
        XCTAssertGreaterThan(model.figureFat.position, today.fat!, "on its way back")
        XCTAssertLessThan(model.figureFat.position, first.fat!, "not there instantly")
        run(model, seconds: 4)
        XCTAssertEqual(model.figureFat.position, first.fat!, accuracy: 0.01)
        XCTAssertEqual(model.figureLean.position, first.lean!, accuracy: 0.01)
    }

    func testScrubbingSwingsTheTurntableThenItSettlesBack() {
        let model = makeModel()
        model.scrubBody(toFraction: 0)
        var widest = 0.0
        for _ in 0..<60 { model.step(1.0 / 240); widest = max(widest, abs(model.figureSpin.position)) }
        XCTAssertGreaterThan(widest, 0.1)
        XCTAssertLessThanOrEqual(widest, FigureGeometry.maxSwing * 1.25, "one soft overshoot at most")
        run(model, seconds: 5)
        XCTAssertEqual(model.figureSpin.position, 0, accuracy: 0.001)
        XCTAssertFalse(model.needsFrames)
    }

    func testReduceMotionDoesNotSwingTheFigure() {
        let model = makeModel()
        model.reduceMotion = true
        model.scrubBody(toFraction: 0)
        for _ in 0..<120 { model.step(1.0 / 240); XCTAssertEqual(model.figureSpin.position, 0, accuracy: 0.0001) }
    }

    func testGhostShowsTheBodyEightWeeksEarlier() {
        let model = makeModel()
        let ghost = model.ghostFigure
        XCTAssertEqual(ghost?.daysBack, 56)
        let then = BodyObservation.carried(model.bodyHistory, upTo: 0)
        XCTAssertEqual(ghost?.shape, FigureShape.from(fatPercent: then.fat, leanKg: then.lean))
        XCTAssertGreaterThan(ghost!.shape.waist, model.figure.waist, "the sample lost fat, so the outline is wider")
        model.scrubBody(toFraction: 3.0 / 56)
        run(model, seconds: 2)
        XCTAssertNil(model.ghostFigure, "less than a week of history behind day 3")
    }
}
