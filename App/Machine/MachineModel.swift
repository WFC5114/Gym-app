import Foundation
import QuartzCore
import SwiftUI

/// A food chosen in the intake inset, waiting on the rail as a block.
/// Its entry id is fixed now, so however often contact fires it logs once.
struct PendingFood: Equatable {
    var entryID = UUID()
    var item: FoodItem
    var grams: Double
    var nutrients: Nutrients { item.nutrients(grams: grams) }
}

/// A block lifted off the rail. Positions are face-local points (block centre).
struct FlyingBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case quick(Int)
        case food(PendingFood)
    }
    enum Phase: Equatable { case resting, held, falling, returning }

    let id: UUID
    var kind: Kind
    /// Size on the rail.
    var size: CGSize
    /// Size it takes in the jar; it grows to this over the jar.
    var jarSize: CGSize
    /// Stable shape seed, handed on to the logged entry's block.
    var seed: UInt64
    var home: CGPoint
    var position: CGPoint
    var phase: Phase = .resting
    var velocity = CGVector.zero
    var grabOffset = CGSize.zero
    var tilt = SpringState(position: 0, target: 0)
    var lift = SpringState(position: 0, target: 0)
    var returnX = SpringState(position: 0, target: 0)
    var returnY = SpringState(position: 0, target: 0)
    /// 0 on the rail, 1 at its jar size.
    var sizeMix = SpringState(position: 0, target: 0)
    /// Spin while falling, radians per second.
    var spin: Double = 0
    /// Where it was let go over the jar.
    var dropX: CGFloat?
    var lastSample: (point: CGPoint, time: CFTimeInterval)?

    static func == (a: FlyingBlock, b: FlyingBlock) -> Bool {
        a.id == b.id && a.position == b.position && a.phase == b.phase && a.tilt == b.tilt && a.lift == b.lift
            && a.sizeMix == b.sizeMix
    }

    /// The size drawn now, between its rail and jar sizes.
    var drawnSize: CGSize {
        let t = CGFloat(min(max(sizeMix.position, 0), 1.2))
        return CGSize(width: size.width + (jarSize.width - size.width) * t, height: size.height + (jarSize.height - size.height) * t)
    }

    var kcal: Double {
        switch kind {
        case .quick(let k): return Double(k)
        case .food(let f): return f.nutrients.kcal
        }
    }

    var entryID: UUID? {
        if case .food(let f) = kind { return f.entryID }
        return nil
    }
}

/// What the scene and the labels draw for one logged food.
struct JarPiece: Identifiable {
    var entry: FoodEntry
    var center: CGPoint
    var angle: Double
    var size: CGSize
    var tint: FoodTint
    var id: UUID { entry.id }
}

/// How a block dropped by hand this session was let go, so its entry piles the
/// same way it fell.
struct DropInfo: Hashable {
    var x: CGFloat
    var seed: UInt64
}

/// What a laid-out pile depends on besides its items.
struct JarGeometryKey: Equatable {
    var layout: MachineLayout
    var targetKcal: Double
}

/// Hit rays thrown out from a contact point. Each burst has its own seed, so
/// no two look the same (angles and lengths vary).
struct ImpactBurst: Identifiable, Equatable {
    let id = UUID()
    /// Face-local points.
    var origin: CGPoint
    var strength: Double
    var seed: UInt64
    /// Which face the burst belongs to.
    var face: PrismFace
    var progress = SpringState(position: 0, target: 1)
}

enum Inset: Equatable {
    case closed
    case search
    case serving(FoodItem)
    case ledger
    /// One logged food, opened by tapping its block.
    case entry(UUID)
    case exercise
}

/// Owns the machine's state and physics. Domain changes go through `LogStore`
/// commands; this type maps them to positions and fires sensory events at the
/// modelled contact moments.
@MainActor
@Observable
final class MachineModel {
    let store: LogStore
    @ObservationIgnored var now: () -> Date
    let isFixture: Bool
    var reduceMotion = false
    var layout = MachineLayout.reference
    /// Hero numerals: the reference "8,888" spans this share of the screen width
    /// (62% after the 13 Oct comparison; art direction §4 started at 40%;
    /// `-heroFraction` compares alternatives).
    var heroFraction: CGFloat = 0.62
    /// Shown under the face title so sample numbers are never mistaken for real ones.
    var dataCaption = "TODAY"
    /// Set for `-fixture` launches; `posed` once the fixture's pose is applied.
    var fixtureName: String?
    var posed = false

    // Prism
    var yaw = SpringState(position: 0, target: 0)
    var isRotating = false
    @ObservationIgnored private var rotateStart: (x: CGFloat, yaw: Double)?
    @ObservationIgnored private var rotateSamples: [(x: CGFloat, t: CFTimeInterval)] = []
    @ObservationIgnored private var seatPending = false
    @ObservationIgnored private var midpointPending = false
    var showSwipeHint = false

    var faceIndex: Int { Int((yaw.target / 120).rounded()) }
    var face: PrismFace { PrismFace(rawValue: ((faceIndex % 3) + 3) % 3) ?? .diet }

    // DIET
    /// The jar sinks a little under each block and bounces back.
    var jarBob = SpringState(position: 0, target: 0)
    var blocks: [FlyingBlock] = []
    /// Logged foods' blocks as rigid bodies in the jar (JarWorld).
    @ObservationIgnored var jar = JarWorld()
    /// Bumped when a block in the jar moves, so the face redraws.
    var jarVersion = 0
    @ObservationIgnored private var piecesLayout: MachineLayout?
    @ObservationIgnored var dropInfo: [UUID: DropInfo] = [:]
    @ObservationIgnored private var pileCache: (items: [JarItem], geometry: JarGeometryKey, pile: JarPile)?
    @ObservationIgnored private var blockSeed: UInt64 = 0x51_7CC1_B727_220A
    var pending: PendingFood?
    var inset: Inset = .closed
    var lastLanded: UUID?

    // TRAIN
    var exercise: Exercise
    var loadKg: Double = 60
    var reps: Int = 8
    var plannedRest: Int = 120
    var advice: RestAdvice
    var readiness = Readiness.unknown
    var glassAngle = SpringState(position: 0, target: 0)
    var glassParity = 0
    var glassHeight = SpringState(position: 200, target: 200)
    var sandA = SpringState(position: 0, target: 0)
    var sandB = SpringState(position: 1, target: 1)
    /// The rendered glass's sand as real grains (SandGlass); nil when TRAIN is drawn in code.
    @ObservationIgnored private(set) var sand: SandGlass?
    /// Bumped when a grain moves, so the glass redraws.
    var sandVersion = 0
    @ObservationIgnored private var flipSeatPending = false
    @ObservationIgnored private var announcedRestDone: UUID?
    var restJustEnded: RestPeriod?

    // BODY
    var bodyHistory: [BodyObservation] = BodyObservation.sample
    var bodyUsesSample = true
    var bodyCaption: String { bodyUsesSample ? "SAMPLE DATA" : "APPLE HEALTH" }
    var scrubSpring = SpringState(position: 0, target: 0)
    var bodyNumbers = SpringState(position: 0, target: 0)
    /// The figurine's fat and lean follow the scrubbed day on a spring.
    var figureFat = SpringState(position: 16, target: 16)
    var figureLean = SpringState(position: 66, target: 66)
    /// Turntable swing (radians) from scrubbing; it swings back to rest.
    var figureSpin = SpringState(position: 0, target: 0)
    /// 0 at rest, 1 with the right arm up in a flex; a tap raises it for a moment.
    var figureFlex = SpringState(position: 0, target: 0)
    /// Head turn: now and then the figure glances to its right.
    var figureLook = SpringState(position: 0, target: 0)
    /// Seconds of idle life on BODY (breathing, weight shift); frozen in fixtures.
    var bodyClock: Double = 0
    @ObservationIgnored private var flexHold: Double = 0
    /// Training tilt for the scrubbed day, recomputed when the day or the sets change.
    private(set) var figureTilt = MuscleTilt.none
    @ObservationIgnored private var tiltKey: (day: Int, sets: Int)?

    // Shared camera shake (points), applied to the whole machine.
    var shake = SpringState(position: 0, target: 0)

    // Juice: hit rays, the hero number's punch and the windup before contact.
    var bursts: [ImpactBurst] = []
    var heroPunch = SpringState(position: 0, target: 0)
    /// The DIET number counts to its new value instead of jumping.
    var heroKcal = SpringState(position: 0, target: 0)
    /// 0...1: how strongly a held block over the jar is winding it up.
    var charge = SpringState(position: 0, target: 0)
    @ObservationIgnored private var burstSeed: UInt64 = 0x2545_F491_4F6C_DD1D
    /// Hero numbers are drawn as lit 3D glyphs; the SwiftUI text stays for
    /// layout, taps and VoiceOver and reports where it sits.
    var heroIn3D = true
    /// Where each face's invisible hero text sits, so its 3D glyphs can stand there.
    var heroGlyphs: [PrismFace: HeroGlyphs] = [:]
    /// Keys and gauges built as clay and glass objects on the faces (clay skins),
    /// by id; SwiftUI reports them and the scene reads them every frame.
    @ObservationIgnored var clayParts: [String: ClayPart] = [:]
    /// How far each clay key is pushed in, 0...1, on the piston spring.
    @ObservationIgnored var keyPress: [String: SpringState] = [:]

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkProxy: DisplayLinkProxy?
    @ObservationIgnored private var lastTick: CFTimeInterval?

    init(store: LogStore, now: @escaping () -> Date = Date.init, isFixture: Bool = false) {
        self.store = store
        self.now = now
        self.isFixture = isFixture
        // Rests are kept per body part (TRAIN is a rest timer, Wei 15 Oct 2026).
        let ex = Exercise.rest(for: (Exercise.named(store.data.currentExercise) ?? Exercise.library[0]).bodyPart)
        self.exercise = ex
        let memory = store.memory(for: ex.name)
        self.loadKg = memory?.loadKg ?? 60
        self.reps = memory?.reps ?? 8
        let restNumber = store.restsToday(bodyPart: ex.bodyPart, now: now()).count + 1
        self.advice = RestCoach.recommend(for: ex, setNumber: restNumber, history: store.data.rests, readiness: .unknown, now: now())
        self.plannedRest = memory?.restSeconds ?? advice.seconds
        let left = totals.remainingKcal(target: targets)
        heroKcal = SpringState(position: left, target: left)
        scrubSpring = SpringState(position: Double(bodyHistory.count - 1), target: Double(bodyHistory.count - 1))
        bodyNumbers = scrubSpring
        syncFigureImmediately()
        if RenderedArt.on(.train), let glass = RenderedArt.trainLayout?.glass { sand = SandGlass(glass: glass) }
        syncGlassImmediately()
        syncPiecesImmediately()
    }

    // MARK: Derived

    var targets: NutritionTargets { store.data.targets }
    var today: [FoodEntry] { store.foods(on: now()) }
    var totals: DayTotals { DayTotals(entries: today) }
    var jarGeometry: JarGeometry { JarGeometry(layout: layout, targetKcal: targets.kcal) }
    var rail: RailGeometry { RailGeometry(layout: layout) }
    var glassGeometry: HourglassGeometry { HourglassGeometry(layout: layout) }
    var activeRest: RestPeriod? { store.activeRest }

    func jarItems(_ entries: [FoodEntry]) -> [JarItem] {
        entries.map { (entry: FoodEntry) -> JarItem in
            let drop = dropInfo[entry.id]
            return JarItem(kcal: entry.nutrients.kcal, seed: drop?.seed ?? JarGeometry.seed(for: entry), dropX: drop?.x)
        }
    }

    /// Today's pile, laid out once per change.
    var pile: JarPile { pile(for: jarItems(today)) }

    func pile(for items: [JarItem]) -> JarPile {
        let key = JarGeometryKey(layout: layout, targetKcal: targets.kcal)
        if let cache = pileCache, cache.items == items, cache.geometry == key { return cache.pile }
        let result = jarGeometry.pile(items)
        pileCache = (items, key, result)
        return result
    }

    var isPileScaled: Bool { pile.scaled }

    var landingRect: CGRect { jarGeometry.landingRect(pileTop: pile.top) }

    /// Every logged block as drawn now: its spring position (or its place in
    /// the pile when it has none yet), carried up and down by the jar's bob.
    func jarPieces() -> [JarPiece] {
        let entries = today
        let poses = pile.poses
        let useMotion = piecesLayout == layout
        let bob = CGFloat(jarBob.position)
        var out: [JarPiece] = []
        for (entry, pose) in zip(entries, poses) {
            var center = pose.center
            var angle = pose.angle
            var size = pose.size
            if useMotion, let body = jar.body(entry.id) {
                center = body.center
                // A box turned half over is the same box: draw it the way up
                // that keeps its label readable.
                angle = body.angle - .pi * (body.angle / .pi).rounded()
                size = body.size
            }
            center.y += bob
            out.append(JarPiece(entry: entry, center: center, angle: angle, size: size, tint: FoodTint.of(entry.nutrients)))
        }
        return out
    }

    /// Puts every block straight in its place (launch, fixtures, layout
    /// changes): each starts where the laid-out pile has it and the physics
    /// lets the pile come to rest before anything is drawn.
    func syncPiecesImmediately() {
        let g = jarGeometry
        var world = JarWorld()
        world.setGlass(interior: g.interior, ceiling: g.ceilingY)
        for (entry, pose) in zip(today, pile.poses) {
            world.add(entry.id, center: pose.center, size: bodySize(pose), angle: pose.angle)
        }
        world.settle()
        jar = world
        piecesLayout = layout
        jarVersion = jar.version
    }

    /// A tipped, loose pile takes more room than the laid-out one: when the
    /// blocks were already shrunk to fit, they shrink a little more.
    private func bodySize(_ pose: JarPose) -> CGSize {
        let k: CGFloat = pile.scaled ? 0.9 : 1
        return CGSize(width: pose.size.width * k, height: pose.size.height * k)
    }

    var isAnyBlockOverLanding: Bool {
        blocks.contains { $0.phase == .held && landingRect.contains($0.position) }
    }

    var isDragging: Bool { blocks.contains { $0.phase == .held } }

    // MARK: Frame loop

    func wake() {
        guard !isFixture else { return }
        if link == nil {
            let proxy = DisplayLinkProxy { [weak self] link in self?.tick(link) }
            let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
            linkProxy = proxy
            lastTick = nil
        }
        link?.isPaused = false
    }

    private func tick(_ link: CADisplayLink) {
        let t = link.timestamp
        let dt = lastTick.map { t - $0 } ?? 1.0 / 120
        lastTick = t
        step(dt)
        if !needsFrames {
            link.isPaused = true
            lastTick = nil
        } else {
            // Only sand moving: a slower cadence is plenty and saves energy.
            let calm = !isRotating && yaw.isSettled(tolerance: 0.01) && blocks.allSatisfy { $0.phase == .resting }
                && jarBob.isSettled(tolerance: 0.05) && glassAngle.isSettled(tolerance: 0.001) && shake.isSettled(tolerance: 0.05)
                && figureFlex.isSettled(tolerance: 0.01) && figureSpin.isSettled(tolerance: 0.01)
            link.preferredFrameRateRange = calm ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                                                : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
    }

    var needsFrames: Bool {
        isRotating || !yaw.isSettled(tolerance: 0.005) || !jarBob.isSettled(tolerance: 0.02)
            || blocks.contains { $0.phase != .resting || !$0.lift.isSettled(tolerance: 0.002) || !$0.tilt.isSettled(tolerance: 0.001) }
            || !jar.isAtRest || !glassAngle.isSettled(tolerance: 0.0005) || !glassHeight.isSettled(tolerance: 0.1)
            || !sandA.isSettled(tolerance: 0.0005) || !sandB.isSettled(tolerance: 0.0005) || activeRest != nil
            || !(sand?.isStill ?? true)
            || !scrubSpring.isSettled(tolerance: 0.001) || !bodyNumbers.isSettled(tolerance: 0.001) || !shake.isSettled(tolerance: 0.02)
            || !figureFat.isSettled(tolerance: 0.005) || !figureLean.isSettled(tolerance: 0.005) || !figureSpin.isSettled(tolerance: 0.001)
            || !figureFlex.isSettled(tolerance: 0.001) || !figureLook.isSettled(tolerance: 0.001) || figureIsAlive
            || !bursts.isEmpty || !heroPunch.isSettled(tolerance: 0.001) || !heroKcal.isSettled(tolerance: 0.5)
            || !charge.isSettled(tolerance: 0.002) || keyPress.values.contains { !$0.isSettled(tolerance: 0.002) }
    }

    /// Advances every spring and body by `dt` seconds. Public so tests and
    /// fixtures can run the physics deterministically.
    func step(_ dt: Double) {
        stepPrism(dt)
        stepDiet(dt)
        stepTrain(dt)
        let bodyCfg = reduceMotion ? SpringConfig.calm : .bodyNumbers
        scrubSpring.advance(dt, config: .follow)
        bodyNumbers.target = scrubSpring.position.rounded()
        bodyNumbers.advance(dt, config: bodyCfg)
        stepFigure(dt)
        shake.advance(dt, config: .piston)
        stepJuice(dt)
    }

    /// A clay key goes down under the finger and springs back on release.
    func pressKey(_ id: String, down: Bool) {
        var spring = keyPress[id] ?? SpringState(position: 0, target: 0)
        spring.target = down ? 1 : 0
        keyPress[id] = spring
        wake()
    }

    private func stepJuice(_ dt: Double) {
        for id in keyPress.keys { keyPress[id]?.advance(dt, config: reduceMotion ? .calm : .piston) }
        heroPunch.advance(dt, config: reduceMotion ? .calm : .punch)
        heroKcal.target = totals.remainingKcal(target: targets)
        heroKcal.advance(dt, config: reduceMotion ? .calm : .bodyNumbers)
        for i in bursts.indices { bursts[i].progress.advance(dt, config: .burst) }
        bursts.removeAll { $0.progress.isSettled(tolerance: 0.004) }
        let landing = landingRect
        let over = blocks.first { $0.phase == .held && landing.contains($0.position) }
        charge.target = over == nil ? 0 : min(over!.kcal / 500, 1) * 0.6 + 0.4
        // Over the jar a block swells to the size it will take inside.
        for i in blocks.indices where blocks[i].phase == .held {
            blocks[i].sizeMix.target = landing.contains(blocks[i].position) ? 1 : 0
        }
        charge.advance(dt, config: .follow)
        SoundEngine.shared.setCharge(Float(charge.position))
    }

    /// The juice on a contact: hit rays, a camera kick and the number's punch.
    /// Reduce Motion keeps the sound and haptic but drops the motion.
    func fireImpact(at origin: CGPoint, strength: Double, face: PrismFace) {
        guard !reduceMotion else { return }
        burstSeed = burstSeed &* 6364136223846793005 &+ 1442695040888963407
        bursts.append(ImpactBurst(origin: origin, strength: strength, seed: burstSeed, face: face))
        if bursts.count > 4 { bursts.removeFirst(bursts.count - 4) }
        shake.velocity += 90 + 170 * strength
        heroPunch.velocity += 1.6 + 2.4 * strength
    }

    // MARK: Prism

    var prismConfig: SpringConfig { reduceMotion ? .calm : .prism }

    func beginRotate(screenX: CGFloat, time: CFTimeInterval) {
        guard inset == .closed else { return }
        isRotating = true
        rotateStart = (screenX, yaw.position)
        rotateSamples = [(screenX, time)]
        yaw.velocity = 0
        showSwipeHint = false
        wake()
    }

    func updateRotate(screenX: CGFloat, time: CFTimeInterval) {
        guard isRotating, let start = rotateStart else { return }
        // Finger left turns the next face in from the right. The front face's
        // centre tracks the finger: dφ = dx / apothem.
        let degreesPerPoint = 180 / (.pi * Double(layout.apothem))
        let previous = yaw.position
        yaw.position = start.yaw + Double(start.x - screenX) * degreesPerPoint
        yaw.target = yaw.position
        rotateSamples.append((screenX, time))
        if rotateSamples.count > 6 { rotateSamples.removeFirst(rotateSamples.count - 6) }
        // A detent every 12° while dragging.
        if Int((previous / 12).rounded(.down)) != Int((yaw.position / 12).rounded(.down)) {
            HapticEngine.shared.tick(intensity: 0.18, sharpness: 0.7)
        }
        SoundEngine.shared.setGrind(Float(min(abs(yaw.position - previous) / 3, 1)))
    }

    func endRotate(time: CFTimeInterval) {
        guard isRotating else { return }
        isRotating = false
        var velocity = 0.0
        if let first = rotateSamples.first, let last = rotateSamples.last, last.t > first.t {
            let degreesPerPoint = 180 / (.pi * Double(layout.apothem))
            velocity = Double(first.x - last.x) / (last.t - first.t) * degreesPerPoint
        }
        // Throws are bounded so a flick can turn at most one face.
        velocity = min(max(velocity, -900), 900)
        let moved = yaw.position - (rotateStart?.yaw ?? yaw.position)
        var index = (yaw.position / 120).rounded()
        let startIndex = ((rotateStart?.yaw ?? 0) / 120).rounded()
        if index == startIndex && (abs(moved) > 18 || abs(velocity) > 250) {
            index += (abs(velocity) > 250 ? (velocity > 0 ? 1 : -1) : (moved > 0 ? 1 : -1))
        }
        index = min(max(index, startIndex - 1), startIndex + 1)
        settle(toIndex: Int(index), velocity: velocity)
        rotateStart = nil
    }

    func cancelRotate() {
        guard isRotating else { return }
        isRotating = false
        settle(toIndex: Int((yaw.position / 120).rounded()), velocity: 0)
    }

    /// Accessible face switching: the same spring as a swipe.
    func rotate(by step: Int) {
        guard inset == .closed else { return }
        // A swipe the system cancelled without an end event must not lock the prism.
        if isRotating { isRotating = false; rotateStart = nil }
        showSwipeHint = false
        settle(toIndex: faceIndex + step, velocity: 0)
    }

    private func settle(toIndex index: Int, velocity: Double) {
        yaw.target = Double(index) * 120
        yaw.velocity = velocity
        seatPending = abs(yaw.target - yaw.position) > 0.5
        midpointPending = abs(yaw.target - yaw.position) > 60
        if isFixture { yaw.position = yaw.target; yaw.velocity = 0 }
        wake()
    }

    private func stepPrism(_ dt: Double) {
        guard !isRotating else { return }
        let before = yaw.position
        yaw.advance(dt, config: prismConfig)
        let target = yaw.target
        if midpointPending, abs(yaw.position - target) <= 60, abs(before - target) > 60 {
            midpointPending = false
            HapticEngine.shared.tick(intensity: 0.55, sharpness: 0.35)
        }
        // Seating fires on the first crossing of the face, not at peak overshoot.
        if seatPending, (before - target) * (yaw.position - target) <= 0, before != target {
            seatPending = false
            let speed = min(abs(yaw.velocity) / 600, 1)
            HapticEngine.shared.tick(intensity: 0.7 + 0.3 * Float(speed), sharpness: 0.9)
            SoundEngine.shared.play(.seat, intensity: 0.5 + 0.5 * Float(speed))
        }
        SoundEngine.shared.setGrind(yaw.isSettled(tolerance: 0.05) ? 0 : Float(min(abs(yaw.velocity) / 500, 1)))
    }

    // MARK: DIET blocks

    /// Touch-down on a rail block: it lifts immediately and follows the finger.
    @discardableResult
    func grabQuick(kcal: Int, at point: CGPoint, time: CFTimeInterval) -> UUID? {
        guard inset == .closed else { return nil }
        let isThisSlot: (FlyingBlock) -> Bool = { if case .quick(kcal) = $0.kind { return true }; return false }
        if blocks.contains(where: isThisSlot) { return regrab(matching: isThisSlot, at: point, time: time) }
        var b = makeBlock(.quick(kcal), at: nil)
        startHold(&b, at: point, time: time)
        blocks.append(b)
        wake()
        return b.id
    }

    @discardableResult
    func grabPending(at point: CGPoint, time: CFTimeInterval) -> UUID? {
        guard let pending else { return nil }
        if let id = regrab(matching: { $0.entryID == pending.entryID }, at: point, time: time) { return id }
        var b = makeBlock(.food(pending), at: nil)
        startHold(&b, at: point, time: time)
        blocks.append(b)
        wake()
        return b.id
    }

    /// A block at its rail home (or `position`), with its jar size and shape seed.
    func makeBlock(_ kind: FlyingBlock.Kind, at position: CGPoint?) -> FlyingBlock {
        blockSeed = JarGeometry.mix(blockSeed &+ 0x9E37_79B9_7F4A_7C15)
        let size: CGSize, home: CGPoint, kcal: Double
        switch kind {
        case .quick(let k):
            size = rail.quickBlockSize(kcal: k); home = rail.quickBlockHome(kcal: k); kcal = Double(k)
        case .food(let f):
            kcal = f.nutrients.kcal
            size = rail.foodBlockSize(kcal: kcal); home = rail.foodBlockHome(kcal: kcal)
        }
        let jarSize = jarGeometry.blockSize(kcal: kcal, seed: blockSeed, scale: pile.scale)
        return FlyingBlock(id: UUID(), kind: kind, size: size, jarSize: jarSize, seed: blockSeed, home: home, position: position ?? home)
    }

    /// Re-grab a block that is falling or springing home, from where it is now.
    private func regrab(matching: (FlyingBlock) -> Bool, at point: CGPoint, time: CFTimeInterval) -> UUID? {
        guard let i = blocks.firstIndex(where: matching) else { return nil }
        startHold(&blocks[i], at: point, time: time)
        wake()
        return blocks[i].id
    }

    private func startHold(_ b: inout FlyingBlock, at point: CGPoint, time: CFTimeInterval) {
        b.phase = .held
        b.grabOffset = CGSize(width: b.position.x - point.x, height: b.position.y - point.y)
        b.velocity = .zero
        b.lift.target = 1
        b.lastSample = (point, time)
        HapticEngine.shared.tick(intensity: 0.35, sharpness: 0.3)
    }

    func dragBlock(_ id: UUID, to point: CGPoint, time: CFTimeInterval) {
        guard let i = blocks.firstIndex(where: { $0.id == id }), blocks[i].phase == .held else { return }
        let p = CGPoint(x: point.x + blocks[i].grabOffset.width, y: point.y + blocks[i].grabOffset.height)
        if let last = blocks[i].lastSample, time > last.time {
            let dt = time - last.time
            let v = CGVector(dx: (point.x - last.point.x) / dt, dy: (point.y - last.point.y) / dt)
            // Light smoothing so one noisy sample doesn't spike the tilt.
            blocks[i].velocity = CGVector(dx: blocks[i].velocity.dx * 0.5 + v.dx * 0.5, dy: blocks[i].velocity.dy * 0.5 + v.dy * 0.5)
        }
        blocks[i].lastSample = (point, time)
        blocks[i].position = clampToFace(p, size: blocks[i].size)
        // Secondary tilt suggests mass: the block trails its direction of travel.
        blocks[i].tilt.target = Double(min(max(-blocks[i].velocity.dx * 0.00035, -0.22), 0.22))
        wake()
    }

    func releaseBlock(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }), blocks[i].phase == .held else { return }
        blocks[i].lift.target = 0
        blocks[i].tilt.target = 0
        let maxV: CGFloat = 2400
        blocks[i].velocity = CGVector(dx: min(max(blocks[i].velocity.dx, -maxV), maxV), dy: min(max(blocks[i].velocity.dy, -maxV), maxV))
        if landingRect.contains(blocks[i].position) {
            startFall(i, velocity: blocks[i].velocity)
        } else {
            beginReturn(i)
        }
        wake()
    }

    func cancelBlock(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[i].lift.target = 0
        blocks[i].tilt.target = 0
        beginReturn(i)
        wake()
    }

    /// Into the jar: it takes its jar size, keeps some of the throw and spins.
    private func startFall(_ i: Int, velocity: CGVector) {
        let g = jarGeometry
        let half = blocks[i].jarSize.width / 2
        let x = min(max(blocks[i].position.x, g.interior.minX + half), g.interior.maxX - half)
        blocks[i].phase = .falling
        blocks[i].dropX = x
        blocks[i].sizeMix.target = 1
        blocks[i].velocity = velocity
        let wobble = (JarGeometry.unit(blocks[i].seed >> 24) - 0.5) * 3
        blocks[i].spin = min(max(Double(velocity.dx) * 0.004, -4), 4) + wobble
        if reduceMotion {
            blocks[i].velocity = CGVector(dx: 0, dy: 900)
            blocks[i].spin = 0
        }
    }

    private func beginReturn(_ i: Int) {
        blocks[i].phase = .returning
        blocks[i].sizeMix.target = 0
        blocks[i].returnX = SpringState(position: Double(blocks[i].position.x), velocity: Double(blocks[i].velocity.dx), target: Double(blocks[i].home.x))
        blocks[i].returnY = SpringState(position: Double(blocks[i].position.y), velocity: Double(blocks[i].velocity.dy), target: Double(blocks[i].home.y))
    }

    /// VoiceOver and the LOAD button: the same drop, starting above the jar.
    func loadPending() {
        guard let pending else { return }
        if let i = blocks.firstIndex(where: { $0.entryID == pending.entryID }) {
            blocks[i].position.y = min(blocks[i].position.y, dropStartY(height: blocks[i].jarSize.height))
            blocks[i].position.x = jarGeometry.outer.midX
            startFall(i, velocity: CGVector(dx: 0, dy: 400))
        } else {
            dropIn(.food(pending))
        }
        if isFixture { finishFallsImmediately() }
        wake()
    }

    func loadQuick(kcal: Int) {
        dropIn(.quick(kcal))
        if isFixture { finishFallsImmediately() }
        wake()
    }

    private func dropIn(_ kind: FlyingBlock.Kind) {
        var b = makeBlock(kind, at: nil)
        b.position = CGPoint(x: jarGeometry.outer.midX, y: dropStartY(height: b.jarSize.height))
        b.sizeMix = SpringState(position: 1, target: 1)
        blocks.append(b)
        startFall(blocks.count - 1, velocity: CGVector(dx: 0, dy: 300))
    }

    /// Just above the jar mouth, or above the pile if it has risen out.
    private func dropStartY(height: CGFloat) -> CGFloat {
        max(min(jarGeometry.outer.minY, pile.top) - height * 1.5, layout.mechanismRect.minY - 40)
    }

    private func clampToFace(_ p: CGPoint, size: CGSize) -> CGPoint {
        let minX = size.width / 2 + 4, maxX = layout.faceWidth - size.width / 2 - 4
        let minY = size.height / 2 + 4, maxY = layout.faceHeight - size.height / 2 - 4
        return CGPoint(x: min(max(p.x, minX), maxX), y: min(max(p.y, minY), maxY))
    }

    private func stepDiet(_ dt: Double) {
        let g = jarGeometry
        // Windup: a block held over the jar sinks it a little before contact.
        jarBob.target = charge.position * 4
        jarBob.advance(dt, config: reduceMotion ? .calm : .jar)

        let gravity: CGFloat = 2600
        var landed: [Int] = []
        for i in blocks.indices {
            blocks[i].lift.advance(dt, config: .piston)
            blocks[i].sizeMix.advance(dt, config: .follow)
            switch blocks[i].phase {
            case .resting, .held:
                blocks[i].tilt.advance(dt, config: .piston)
            case .falling:
                blocks[i].velocity.dy += gravity * CGFloat(dt)
                blocks[i].velocity.dx *= CGFloat(max(0, 1 - 6 * dt))
                blocks[i].position.x += blocks[i].velocity.dx * CGFloat(dt)
                blocks[i].position.y += blocks[i].velocity.dy * CGFloat(dt)
                blocks[i].tilt.position += blocks[i].spin * dt
                blocks[i].tilt.target = blocks[i].tilt.position
                // The glass walls keep it inside.
                let half = blocks[i].drawnSize.width / 2
                blocks[i].position.x = min(max(blocks[i].position.x, g.interior.minX + half), max(g.interior.maxX - half, g.interior.minX + half))
                // Contact with the floor or a block in the jar (the jar's bodies don't bob).
                let inJar = CGPoint(x: blocks[i].position.x, y: blocks[i].position.y - CGFloat(jarBob.position))
                if blocks[i].velocity.dy > 0, jar.touches(center: inJar, size: blocks[i].drawnSize, angle: blocks[i].tilt.position) {
                    landed.append(i)
                }
            case .returning:
                blocks[i].tilt.advance(dt, config: .piston)
                blocks[i].returnX.advance(dt, config: prismConfig)
                blocks[i].returnY.advance(dt, config: prismConfig)
                blocks[i].position = CGPoint(x: blocks[i].returnX.position, y: blocks[i].returnY.position)
                if blocks[i].returnX.isSettled(tolerance: 0.3) && blocks[i].returnY.isSettled(tolerance: 0.3) {
                    blocks[i].position = blocks[i].home
                    blocks[i].phase = .resting
                }
            }
        }
        for i in landed.reversed() { land(i) }
        // Quick blocks back on the rail dissolve into the rail's own block.
        blocks.removeAll { b in
            if case .quick = b.kind { return b.phase == .resting && b.lift.isSettled(tolerance: 0.002) }
            return false
        }
        stepPieces(dt)
    }

    /// The jar's bodies follow today's log: a new or returning food drops in
    /// from the mouth, a deleted one leaves (the blocks above fall into its
    /// place), a changed one takes its new size; then the physics steps.
    private func stepPieces(_ dt: Double) {
        if piecesLayout != layout { syncPiecesImmediately(); return }
        let entries = today
        let poses = pile.poses
        var live = Set<UUID>()
        for (entry, pose) in zip(entries, poses) {
            live.insert(entry.id)
            let size = bodySize(pose)
            if let body = jar.body(entry.id) {
                if abs(body.size.width - size.width) > 1 || abs(body.size.height - size.height) > 1 { jar.resize(entry.id, to: size) }
            } else {
                jar.add(entry.id, center: CGPoint(x: pose.center.x, y: jarGeometry.outer.minY - size.height), size: size, angle: 0,
                        velocity: CGVector(dx: 0, dy: 300))
            }
        }
        for id in jar.blockIDs where !live.contains(id) { jar.remove(id) }
        // Reduce Motion: the pile comes to rest at once.
        if reduceMotion { jar.settle() } else { jar.step(dt) }
        if jar.version != jarVersion { jarVersion = jar.version }
    }

    /// Contact: commit once, hand the block to the pile, fire the impact.
    private func land(_ i: Int) {
        let block = blocks[i]
        let impact = Double(block.velocity.dy)
        let entry: FoodEntry
        let at = now()
        switch block.kind {
        case .quick(let kcal):
            entry = .quickAdd(kcal: kcal, at: at)
        case .food(let food):
            entry = .food(food.item, grams: food.grams, id: food.entryID, at: at)
        }
        let center = block.position
        let size = block.drawnSize
        blocks.remove(at: i)
        guard store.commitFood(entry) else { return }
        if case .food = block.kind { pending = nil }
        dropInfo[entry.id] = DropInfo(x: block.dropX ?? center.x, seed: block.seed)
        lastLanded = entry.id
        let strength = Float(min(max(impact / 1600, 0.25), 1))
        // The block carries on as a body in the jar with its speed and spin:
        // it bounces a little, knocks the blocks it hits and settles among them.
        jar.add(entry.id, center: CGPoint(x: center.x, y: center.y - CGFloat(jarBob.position)), size: size,
                angle: block.tilt.position, velocity: block.velocity, spin: block.spin)
        // Heavier food and faster drops sink the jar further.
        let share = min(max(block.kcal / 700, 0.05), 0.75)
        jarBob.velocity += impact * share * 0.1
        let weight = Float(min(block.kcal / 600, 1))
        HapticEngine.shared.play(.dropWeight, weight: weight, scale: strength)
        SoundEngine.shared.play(.mallet, intensity: 0.45 + 0.55 * strength, pitch: 1.08 - 0.12 * weight)
        SoundEngine.shared.play(.glassTap, intensity: 0.25 + 0.35 * strength, pitch: 1.1 - 0.2 * weight)
        // Each food logged today climbs one step up a pentatonic scale.
        SoundEngine.shared.chime(step: today.count - 1, intensity: 0.35 + 0.3 * strength)
        fireImpact(at: CGPoint(x: center.x, y: center.y - size.height / 2), strength: Double(strength), face: .diet)
        let after = totals.kcal
        if after >= targets.kcal, after - block.kcal < targets.kcal {
            // Crossing the day's target: a second, bigger burst at the number.
            SoundEngine.shared.chime(step: 7, intensity: 0.7)
            HapticEngine.shared.play(.setDone)
            fireImpact(at: CGPoint(x: layout.heroRect.minX + 90, y: layout.heroRect.minY + 58 + layout.heroRect.height * 0.2), strength: 1, face: .diet)
        }
        publishSnapshot()
    }

    private func finishFallsImmediately() {
        for _ in 0..<600 where blocks.contains(where: { $0.phase == .falling }) { stepDiet(1.0 / 240) }
        syncPiecesImmediately()
    }

    func undoFood() {
        guard let undone = store.undoFood() else { return }
        if case .added(let id) = undone { jar.remove(id) }
        HapticEngine.shared.tick(intensity: 0.5, sharpness: 0.5)
        publishSnapshot()
        wake()
    }

    func deleteFood(_ id: UUID) {
        store.deleteFood(id: id)
        publishSnapshot()
        wake()
    }

    func updateFood(_ id: UUID, grams: Double) {
        store.updateFood(id: id, grams: grams)
        publishSnapshot()
        wake()
    }

    // MARK: Intake

    func openInset(_ newInset: Inset) {
        guard !isRotating, yaw.isSettled(tolerance: 1) else { return }
        inset = newInset
    }

    func closeInset() { inset = .closed }

    /// Confirming a serving forms the block on the rail.
    func formBlock(item: FoodItem, grams: Double) {
        guard grams > 0 else { return }
        pending = PendingFood(item: item, grams: grams)
        blocks.removeAll { $0.entryID != nil }
        inset = .closed
        HapticEngine.shared.tick(intensity: 0.6, sharpness: 0.4)
        SoundEngine.shared.play(.detent, intensity: 0.8, pitch: 0.85)
        wake()
    }

    func discardPending() {
        blocks.removeAll { $0.entryID != nil }
        pending = nil
    }

    // MARK: TRAIN

    var setsToday: [SetRecord] { store.setsToday(exercise: exercise.name, now: now()) }
    var nextSetNumber: Int { setsToday.count + 1 }

    /// Which of today's rests for this body part comes next.
    var nextRestNumber: Int { store.restsToday(bodyPart: exercise.bodyPart, now: now()).count + 1 }

    func refreshAdvice() {
        advice = RestCoach.recommend(for: exercise, setNumber: nextRestNumber, history: store.data.rests, readiness: readiness, now: now())
    }

    /// Picks the body part the next rest is for; the coach advises for it.
    func selectBodyPart(_ part: BodyPart) {
        selectExercise(Exercise.rest(for: part))
    }

    func selectExercise(_ ex: Exercise) {
        exercise = ex
        store.selectExercise(ex.name)
        let memory = store.memory(for: ex.name)
        loadKg = memory?.loadKg ?? loadKg
        reps = memory?.reps ?? reps
        refreshAdvice()
        plannedRest = memory?.restSeconds ?? advice.seconds
        wake()
    }

    func adjustLoad(_ delta: Double) {
        loadKg = max(0, (loadKg + delta) * 2).rounded() / 2
        HapticEngine.shared.tick(intensity: 0.25, sharpness: 0.8)
        SoundEngine.shared.play(.detent, intensity: 0.5)
    }

    func adjustReps(_ delta: Int) {
        reps = max(1, reps + delta)
        HapticEngine.shared.tick(intensity: 0.25, sharpness: 0.8)
        SoundEngine.shared.play(.detent, intensity: 0.5)
    }

    /// Before the set: choose the rest. The glass grows or shrinks with it.
    func adjustPlannedRest(by seconds: Int) {
        plannedRest = RestLimits.clamp(plannedRest + seconds)
        HapticEngine.shared.tick(intensity: 0.25, sharpness: 0.8)
        SoundEngine.shared.play(.detent, intensity: 0.5, pitch: 0.9 + Float(plannedRest) / 600)
        wake()
    }

    func useAdvice() {
        plannedRest = advice.seconds
        HapticEngine.shared.tick(intensity: 0.4, sharpness: 0.6)
        wake()
    }

    /// START REST: flip the glass and start the rest (TRAIN logs rests only,
    /// no sets: Wei, 15 Oct 2026).
    func startRest() {
        let at = now()
        let rest = store.startRest(exercise: exercise, restSeconds: plannedRest, recommendedSeconds: advice.seconds, at: at)
        announcedRestDone = nil
        restJustEnded = nil
        glassParity += 1
        glassAngle.target = Double(glassParity) * .pi
        flipSeatPending = true
        if reduceMotion || isFixture {
            glassAngle.position = glassAngle.target
            glassAngle.velocity = 0
        }
        refreshAdvice()
        RestActivity.start(rest, setNumber: rest.afterSet)
        if isFixture { syncGlassImmediately() }
        wake()
    }

    /// Adds time mid-rest; logged as its own addition.
    func addRestTime(_ seconds: Int = RestLimits.addStep) {
        guard activeRest != nil else { return }
        store.addRestTime(seconds, at: now())
        HapticEngine.shared.tick(intensity: 0.4, sharpness: 0.5)
        SoundEngine.shared.play(.detent, intensity: 0.7, pitch: 0.85)
        if let rest = activeRest { RestActivity.update(rest) }
        if isFixture { syncGlassImmediately() }
        wake()
    }

    func endRest() {
        store.cancelRest(at: now())
        Task { await RestActivity.endAll() }
        wake()
    }

    /// Which container (A = glass-local top, B = glass-local bottom) is up in the world.
    var aIsUp: Bool { glassParity % 2 == 0 }

    /// Sand fraction in the world-top bulb right now.
    var topSandTarget: Double {
        guard let rest = activeRest else { return 0 }
        return rest.remainingFraction(at: now())
    }

    var glassSeconds: Double { Double(activeRest?.totalSeconds ?? plannedRest) }

    func syncGlassImmediately() {
        let top = topSandTarget
        sandA = SpringState(position: aIsUp ? top : 1 - top, target: aIsUp ? top : 1 - top)
        sandB = SpringState(position: aIsUp ? 1 - top : top, target: aIsUp ? 1 - top : top)
        let h = Double(glassGeometry.height(forSeconds: glassSeconds))
        glassHeight = SpringState(position: h, target: h)
        glassAngle = SpringState(position: Double(glassParity) * .pi, target: Double(glassParity) * .pi)
        settleSand()
    }

    /// Puts the grains where the clock says, at rest; while a rest runs, a few
    /// are let through first so the stream is falling.
    private func settleSand() {
        guard let sand else { return }
        guard let target = sandTarget(sand) else {
            sand.settle(top: 0, aIsUp: aIsUp)
            sandVersion = sand.version
            return
        }
        sand.settle(top: min(target + 24, sand.total), aIsUp: aIsUp)
        for _ in 0..<90 { sand.step(1.0 / 60, angle: glassAngle.position, upperTarget: target) }
        sandVersion = sand.version
    }

    /// Grains the upper bulb must still hold while a rest runs.
    private func sandTarget(_ sand: SandGlass) -> Int? {
        activeRest.map { Int((Double(sand.total) * $0.remainingFraction(at: now())).rounded()) }
    }

    private func stepSand(_ dt: Double) {
        guard let sand else { return }
        let target = sandTarget(sand)
        // After a jump in time (the app was away) the grains go where the clock says.
        if let target, glassAngle.isSettled(tolerance: 0.01), abs(sand.upperCount(angle: glassAngle.position) - target) > sand.total / 6 {
            sand.settle(top: target, aIsUp: aIsUp)
        }
        sand.step(dt, angle: glassAngle.position, upperTarget: target)
        if sand.version != sandVersion { sandVersion = sand.version }
    }

    private func stepTrain(_ dt: Double) {
        let t = now()
        if let rest = activeRest, rest.endsAt <= t {
            store.settleElapsedRests(now: t)
            if announcedRestDone != rest.id {
                announcedRestDone = rest.id
                restJustEnded = store.data.rests.first { $0.id == rest.id }
                HapticEngine.shared.play(.restDone)
                SoundEngine.shared.play(.glassTap, intensity: 0.8)
                Task { await RestActivity.endAll() }
            }
        }
        let before = glassAngle.position
        glassAngle.advance(dt, config: reduceMotion ? .calm : .piston)
        if flipSeatPending, (before - glassAngle.target) * (glassAngle.position - glassAngle.target) <= 0, before != glassAngle.target {
            flipSeatPending = false
            HapticEngine.shared.play(.setDone)
            SoundEngine.shared.play(.rack, intensity: 1)
            if !reduceMotion { shake.velocity = 260 }
            let glass = glassGeometry
            fireImpact(at: glass.center(forHeight: CGFloat(glassHeight.position)), strength: 0.8, face: .train)
        }
        let top = topSandTarget
        sandA.target = aIsUp ? top : 1 - top
        sandB.target = aIsUp ? 1 - top : top
        sandA.advance(dt, config: .follow)
        sandB.advance(dt, config: .follow)
        glassHeight.target = Double(glassGeometry.height(forSeconds: glassSeconds))
        glassHeight.advance(dt, config: reduceMotion ? .calm : .bodyNumbers)
        stepSand(dt)
    }

    // MARK: BODY

    func scrubBody(toFraction f: Double) {
        let maxIndex = Double(max(bodyHistory.count - 1, 0))
        let target = min(max(f, 0), 1) * maxIndex
        let before = Int(scrubSpring.target.rounded())
        scrubSpring.target = target
        let after = Int(target.rounded())
        if before != after, bodyHistory.indices.contains(after) {
            let scan = bodyHistory[after].isScan
            HapticEngine.shared.play(scan ? .scrubInBodyDay : .scrubTick)
            SoundEngine.shared.play(.detent, intensity: scan ? 1 : 0.45, pitch: scan ? 0.8 : 1)
        }
        wake()
    }

    /// Replaces the sample history with real Health readings when there are any.
    func setBodyHistory(_ history: [BodyObservation]) {
        guard !history.isEmpty else { return }
        bodyHistory = history
        bodyUsesSample = false
        scrubSpring = SpringState(position: Double(history.count - 1), target: Double(history.count - 1))
        bodyNumbers = scrubSpring
        syncFigureImmediately()
    }

    /// The figurine as it is drawn this frame.
    var figure: FigureShape {
        FigureShape.from(fatPercent: figureFat.position, leanKg: figureLean.position, tilt: figureTilt)
    }

    /// Breathing and weight shift run whenever BODY is the face showing, unless
    /// Reduce Motion is on. Fixtures hold still so every capture is identical.
    var figureIsAlive: Bool { face == .body && !reduceMotion && !isFixture && !isRotating }

    /// What the mannequin is doing this frame.
    var figurePose: Mannequin.Pose {
        let t = bodyClock
        let alive: Float = reduceMotion ? 0 : 1
        return Mannequin.Pose(breathe: alive * Float(sin(2 * .pi * t / 4.2)),
                              shift: alive * Float(sin(2 * .pi * t / 9.0)),
                              look: Float(figureLook.position),
                              flex: Float(figureFlex.position),
                              swing: figure.armSwing)
    }

    /// A tap on the figure: it flexes its right arm and the turntable gives a
    /// little swing, then both settle back on their springs.
    func pokeFigure() {
        figureFlex.target = 1
        flexHold = 1.3
        if !reduceMotion { figureSpin.velocity += 0.9 }
        HapticEngine.shared.tick(intensity: 0.7, sharpness: 0.55)
        SoundEngine.shared.play(.seat, intensity: 0.7, pitch: 1.35)
        wake()
    }
    /// Turn about the vertical axis this frame: the resting three-quarter view plus the swing.
    var figureYaw: Float { FigureGeometry.restYaw + Float(figureSpin.position) }

    /// The comparison outline: 8 weeks before the scrubbed day, or the earliest
    /// day there is. Nil when that is less than a week back or nothing changed.
    var ghostFigure: (shape: FigureShape, daysBack: Int)? {
        let index = min(Int(bodyNumbers.target.rounded()), bodyHistory.count - 1)
        let back = max(index - 56, 0)
        guard index - back >= 7 else { return nil }
        let then = BodyComposition.on(bodyHistory, upTo: back)
        guard then.fatPercent != nil || then.leanKg != nil else { return nil }
        let shape = FigureShape.from(fatPercent: then.fatPercent, leanKg: then.leanKg, tilt: tilt(forDay: back))
        let now = BodyComposition.on(bodyHistory, upTo: index)
        guard shape != FigureShape.from(fatPercent: now.fatPercent, leanKg: now.leanKg, tilt: tilt(forDay: index)) else { return nil }
        return (shape, index - back)
    }

    private func figureTargets() -> (fat: Double, lean: Double) {
        let c = BodyComposition.on(bodyHistory, upTo: Int(bodyNumbers.target.rounded()))
        return (c.fatPercent ?? 16, c.leanKg ?? 66)
    }

    /// The scrubbed day's composition: scans, with the scale trend in between.
    var bodyComposition: BodyComposition {
        BodyComposition.on(bodyHistory, upTo: Int(bodyNumbers.target.rounded()))
    }

    /// Training tilt from the 28 days of logged sets up to the end of a ruler day.
    func tilt(forDay index: Int) -> MuscleTilt {
        guard bodyHistory.indices.contains(index) else { return .none }
        let end = Calendar.current.startOfDay(for: bodyHistory[index].date).addingTimeInterval(86_400)
        return MuscleTilt.from(store.data.sets, endingAt: end)
    }

    func syncFigureImmediately() {
        let t = figureTargets()
        figureFat = SpringState(position: t.fat, target: t.fat)
        figureLean = SpringState(position: t.lean, target: t.lean)
        figureSpin = SpringState(position: 0, target: 0)
        figureFlex = SpringState(position: 0, target: 0)
        figureLook = SpringState(position: 0, target: 0)
        updateTilt()
    }

    private func updateTilt() {
        let day = min(max(Int(bodyNumbers.target.rounded()), 0), max(bodyHistory.count - 1, 0))
        let key = (day: day, sets: store.data.sets.count)
        if let tiltKey, tiltKey == key { return }
        tiltKey = key
        figureTilt = tilt(forDay: day)
    }

    private func stepFigure(_ dt: Double) {
        let t = figureTargets()
        figureFat.target = t.fat
        figureLean.target = t.lean
        let cfg = reduceMotion ? SpringConfig.calm : .bodyNumbers
        figureFat.advance(dt, config: cfg)
        figureLean.advance(dt, config: cfg)
        // Dragging the ruler drags the turntable round; letting go, it swings back
        // to its resting turn with one soft overshoot.
        let swing = reduceMotion ? 0 : min(max(-scrubSpring.velocity * 0.015, -FigureGeometry.maxSwing), FigureGeometry.maxSwing)
        figureSpin.target = swing
        figureSpin.advance(dt, config: reduceMotion ? .calm : .tumble)
        updateTilt()
        // Idle life: a slow clock drives breathing and weight shift; a glance to
        // the right every so often; the flex holds a moment, then lets go.
        if figureIsAlive { bodyClock += dt }
        let glance = bodyClock.truncatingRemainder(dividingBy: 11)
        figureLook.target = (!reduceMotion && glance > 6.5 && glance < 8.2) ? -0.5 : 0
        figureLook.advance(dt, config: reduceMotion ? .calm : .glance)
        if flexHold > 0 {
            flexHold -= dt
            if flexHold <= 0 { figureFlex.target = 0 }
        }
        figureFlex.advance(dt, config: reduceMotion ? .calm : .flex)
    }

    var bodyObservation: BodyObservation? {
        let i = Int(bodyNumbers.target.rounded())
        return bodyHistory.indices.contains(i) ? bodyHistory[i] : bodyHistory.last
    }

    // MARK: Widgets

    func publishSnapshot() {
        guard !isFixture else { return }
        let totals = self.totals
        var snapshot = SnapshotStore.load() ?? DailySnapshot.placeholder
        snapshot.date = now()
        snapshot.caloriesEaten = Int(totals.kcal.rounded())
        snapshot.caloriesTarget = Int(targets.kcal)
        snapshot.proteinEaten = Int(totals.protein.rounded())
        snapshot.proteinTarget = Int(targets.protein)
        SnapshotStore.save(snapshot)
        WidgetReload.request()
    }
}

/// CADisplayLink needs an Objective-C target.
final class DisplayLinkProxy: NSObject {
    let handler: (CADisplayLink) -> Void
    init(_ handler: @escaping (CADisplayLink) -> Void) { self.handler = handler }
    @objc func step(_ link: CADisplayLink) { handler(link) }
}
