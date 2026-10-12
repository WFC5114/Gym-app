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
    var size: CGSize
    var home: CGPoint
    var position: CGPoint
    var phase: Phase = .resting
    var velocity = CGVector.zero
    var grabOffset = CGSize.zero
    var tilt = SpringState(position: 0, target: 0)
    var lift = SpringState(position: 0, target: 0)
    var returnX = SpringState(position: 0, target: 0)
    var returnY = SpringState(position: 0, target: 0)
    var lastSample: (point: CGPoint, time: CFTimeInterval)?

    static func == (a: FlyingBlock, b: FlyingBlock) -> Bool {
        a.id == b.id && a.position == b.position && a.phase == b.phase && a.tilt == b.tilt && a.lift == b.lift
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

struct SlabItem: Identifiable {
    var entry: FoodEntry
    var rect: CGRect
    var id: UUID { entry.id }
}

/// A slab landing on the stack morphs from the block's shape into its layer.
struct SlabMorph: Equatable {
    var from: CGRect
    var progress = SpringState(position: 0, target: 1)
}

enum Inset: Equatable {
    case closed
    case search
    case serving(FoodItem)
    case ledger
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
    /// (art direction §4 starts at 40%; `-heroFraction` compares alternatives).
    var heroFraction: CGFloat = 0.40
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
    var deck = SpringState(position: 0, target: 0)
    var blocks: [FlyingBlock] = []
    var morphs: [UUID: SlabMorph] = [:]
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
    @ObservationIgnored private var flipSeatPending = false
    @ObservationIgnored private var announcedRestDone: UUID?
    var restJustEnded: RestPeriod?

    // BODY
    var bodyHistory: [BodyObservation] = BodyObservation.sample
    var bodyUsesSample = true
    var bodyCaption: String { bodyUsesSample ? "SAMPLE DATA" : "APPLE HEALTH" }
    var scrubSpring = SpringState(position: 0, target: 0)
    var bodyNumbers = SpringState(position: 0, target: 0)

    // Shared camera shake (points), applied to the whole machine.
    var shake = SpringState(position: 0, target: 0)

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkProxy: DisplayLinkProxy?
    @ObservationIgnored private var lastTick: CFTimeInterval?

    init(store: LogStore, now: @escaping () -> Date = Date.init, isFixture: Bool = false) {
        self.store = store
        self.now = now
        self.isFixture = isFixture
        let ex = Exercise.named(store.data.currentExercise) ?? Exercise.library[0]
        self.exercise = ex
        let memory = store.memory(for: ex.name)
        self.loadKg = memory?.loadKg ?? 60
        self.reps = memory?.reps ?? 8
        self.advice = RestCoach.recommend(for: ex, setNumber: 1, history: store.data.rests, readiness: .unknown, now: now())
        self.plannedRest = memory?.restSeconds ?? advice.seconds
        let geometry = DeckGeometry(layout: layout, targetKcal: store.data.targets.kcal)
        deck = SpringState(position: geometry.restingDisplacement(eaten: totals.kcal), target: geometry.restingDisplacement(eaten: totals.kcal))
        scrubSpring = SpringState(position: Double(bodyHistory.count - 1), target: Double(bodyHistory.count - 1))
        bodyNumbers = scrubSpring
        syncGlassImmediately()
    }

    // MARK: Derived

    var targets: NutritionTargets { store.data.targets }
    var today: [FoodEntry] { store.foods(on: now()) }
    var totals: DayTotals { DayTotals(entries: today) }
    var deckGeometry: DeckGeometry { DeckGeometry(layout: layout, targetKcal: targets.kcal) }
    var rail: RailGeometry { RailGeometry(layout: layout) }
    var glassGeometry: HourglassGeometry { HourglassGeometry(layout: layout) }
    var activeRest: RestPeriod? { store.activeRest }

    /// Slab rectangles for today's entries, bottom to top, in face-local points.
    func slabRects() -> [SlabItem] {
        let g = deckGeometry
        let entries = today
        let (heights, _) = g.slabHeights(kcals: entries.map(\.nutrients.kcal))
        var y = g.plateTop(displacement: CGFloat(deck.position))
        var out: [SlabItem] = []
        for (entry, h) in zip(entries, heights) {
            let final = CGRect(x: g.centerX - g.slabWidth / 2, y: y - h, width: g.slabWidth, height: h)
            y -= h
            if let morph = morphs[entry.id] {
                out.append(SlabItem(entry: entry, rect: Self.lerp(morph.from, final, CGFloat(morph.progress.position))))
            } else {
                out.append(SlabItem(entry: entry, rect: final))
            }
        }
        return out
    }

    var stackTop: CGFloat {
        let g = deckGeometry
        let heights = g.slabHeights(kcals: today.map(\.nutrients.kcal)).heights
        return g.plateTop(displacement: CGFloat(deck.position)) - heights.reduce(0, +)
    }

    var isStackScaled: Bool { deckGeometry.slabHeights(kcals: today.map(\.nutrients.kcal)).scaled }

    var landingRect: CGRect { deckGeometry.landingRect(stackTop: stackTop) }

    var isAnyBlockOverLanding: Bool {
        blocks.contains { $0.phase == .held && landingRect.contains($0.position) }
    }

    var isDragging: Bool { blocks.contains { $0.phase == .held } }

    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

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
                && deck.isSettled(tolerance: 0.05) && glassAngle.isSettled(tolerance: 0.001) && shake.isSettled(tolerance: 0.05)
            link.preferredFrameRateRange = calm ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                                                : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
    }

    var needsFrames: Bool {
        isRotating || !yaw.isSettled(tolerance: 0.005) || !deck.isSettled(tolerance: 0.02)
            || blocks.contains { $0.phase != .resting || !$0.lift.isSettled(tolerance: 0.002) || !$0.tilt.isSettled(tolerance: 0.001) }
            || !morphs.isEmpty || !glassAngle.isSettled(tolerance: 0.0005) || !glassHeight.isSettled(tolerance: 0.1)
            || !sandA.isSettled(tolerance: 0.0005) || !sandB.isSettled(tolerance: 0.0005) || activeRest != nil
            || !scrubSpring.isSettled(tolerance: 0.001) || !bodyNumbers.isSettled(tolerance: 0.001) || !shake.isSettled(tolerance: 0.02)
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
        shake.advance(dt, config: .piston)
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
        let size = rail.quickBlockSize(kcal: kcal)
        let home = rail.quickBlockHome(kcal: kcal)
        var b = FlyingBlock(id: UUID(), kind: .quick(kcal), size: size, home: home, position: home)
        startHold(&b, at: point, time: time)
        blocks.append(b)
        wake()
        return b.id
    }

    @discardableResult
    func grabPending(at point: CGPoint, time: CFTimeInterval) -> UUID? {
        guard let pending else { return nil }
        if let id = regrab(matching: { $0.entryID == pending.entryID }, at: point, time: time) { return id }
        let kcal = pending.nutrients.kcal
        var b = FlyingBlock(id: UUID(), kind: .food(pending), size: rail.foodBlockSize(kcal: kcal),
                            home: rail.foodBlockHome(kcal: kcal), position: rail.foodBlockHome(kcal: kcal))
        startHold(&b, at: point, time: time)
        blocks.append(b)
        wake()
        return b.id
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
            blocks[i].phase = .falling
            if reduceMotion { blocks[i].velocity = CGVector(dx: 0, dy: 900) }
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

    private func beginReturn(_ i: Int) {
        blocks[i].phase = .returning
        blocks[i].returnX = SpringState(position: Double(blocks[i].position.x), velocity: Double(blocks[i].velocity.dx), target: Double(blocks[i].home.x))
        blocks[i].returnY = SpringState(position: Double(blocks[i].position.y), velocity: Double(blocks[i].velocity.dy), target: Double(blocks[i].home.y))
    }

    /// VoiceOver and the LOAD button: the same drop, starting above the deck.
    func loadPending() {
        guard let pending else { return }
        let kcal = pending.nutrients.kcal
        if let i = blocks.firstIndex(where: { $0.entryID == pending.entryID }) {
            blocks[i].phase = .falling
            blocks[i].position = CGPoint(x: deckGeometry.centerX, y: min(blocks[i].position.y, stackTop - blocks[i].size.height))
            blocks[i].velocity = CGVector(dx: 0, dy: 400)
        } else {
            let size = rail.foodBlockSize(kcal: kcal)
            var b = FlyingBlock(id: UUID(), kind: .food(pending), size: size, home: rail.foodBlockHome(kcal: kcal),
                                position: CGPoint(x: deckGeometry.centerX, y: max(layout.mechanismRect.minY, stackTop - size.height * 2.5)))
            b.phase = .falling
            b.velocity = CGVector(dx: 0, dy: 300)
            blocks.append(b)
        }
        if isFixture { finishFallsImmediately() }
        wake()
    }

    func loadQuick(kcal: Int) {
        let size = rail.quickBlockSize(kcal: kcal)
        var b = FlyingBlock(id: UUID(), kind: .quick(kcal), size: size, home: rail.quickBlockHome(kcal: kcal),
                            position: CGPoint(x: deckGeometry.centerX, y: max(layout.mechanismRect.minY, stackTop - size.height * 2.5)))
        b.phase = .falling
        b.velocity = CGVector(dx: 0, dy: 300)
        blocks.append(b)
        if isFixture { finishFallsImmediately() }
        wake()
    }

    private func clampToFace(_ p: CGPoint, size: CGSize) -> CGPoint {
        let minX = size.width / 2 + 4, maxX = layout.faceWidth - size.width / 2 - 4
        let minY = size.height / 2 + 4, maxY = layout.faceHeight - size.height / 2 - 4
        return CGPoint(x: min(max(p.x, minX), maxX), y: min(max(p.y, minY), maxY))
    }

    private func stepDiet(_ dt: Double) {
        let g = deckGeometry
        deck.target = Double(g.restingDisplacement(eaten: totals.kcal))
        deck.advance(dt, config: reduceMotion ? .calm : .deck)

        let gravity: CGFloat = 2600
        var landed: [Int] = []
        for i in blocks.indices {
            blocks[i].lift.advance(dt, config: .piston)
            blocks[i].tilt.advance(dt, config: .piston)
            switch blocks[i].phase {
            case .resting, .held:
                break
            case .falling:
                blocks[i].velocity.dy += gravity * CGFloat(dt)
                blocks[i].velocity.dx *= CGFloat(max(0, 1 - 6 * dt))
                blocks[i].position.x += blocks[i].velocity.dx * CGFloat(dt)
                blocks[i].position.y += blocks[i].velocity.dy * CGFloat(dt)
                // Stay over the deck while falling.
                let half = (g.deckWidth - blocks[i].size.width) / 2
                blocks[i].position.x = min(max(blocks[i].position.x, g.centerX - max(half, 0)), g.centerX + max(half, 0))
                if blocks[i].position.y + blocks[i].size.height / 2 >= stackTop, blocks[i].velocity.dy > 0 {
                    landed.append(i)
                }
            case .returning:
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

        for key in Array(morphs.keys) {
            morphs[key]?.progress.advance(dt, config: reduceMotion ? .calm : .deck)
            if morphs[key]?.progress.isSettled(tolerance: 0.002) == true { morphs[key] = nil }
        }
    }

    /// Contact: commit once, compress the deck, fire the impact.
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
        let rect = CGRect(x: block.position.x - block.size.width / 2, y: block.position.y - block.size.height / 2,
                          width: block.size.width, height: block.size.height)
        blocks.remove(at: i)
        guard store.commitFood(entry) else { return }
        if case .food = block.kind { pending = nil }
        morphs[entry.id] = SlabMorph(from: rect)
        lastLanded = entry.id
        // Momentum transfer: heavier food and faster drops push the deck further.
        let share = min(max(block.kcal / 700, 0.05), 0.75)
        deck.velocity += impact * share
        let strength = Float(min(max(impact / 1600, 0.25), 1))
        let weight = Float(min(block.kcal / 600, 1))
        HapticEngine.shared.play(.dropWeight, weight: weight, scale: strength)
        SoundEngine.shared.play(.mallet, intensity: 0.45 + 0.55 * strength, pitch: 1.08 - 0.12 * weight)
        publishSnapshot()
    }

    private func finishFallsImmediately() {
        for _ in 0..<600 where blocks.contains(where: { $0.phase == .falling }) { stepDiet(1.0 / 240) }
    }

    func undoFood() {
        guard let undone = store.undoFood() else { return }
        if case .added(let id) = undone { morphs[id] = nil }
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

    func refreshAdvice() {
        advice = RestCoach.recommend(for: exercise, setNumber: nextSetNumber, history: store.data.rests, readiness: readiness, now: now())
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

    /// SET DONE: log the set, flip the glass, start the rest.
    func setDone() {
        let at = now()
        let rest = store.completeSet(exercise: exercise, loadKg: loadKg, reps: reps, restSeconds: plannedRest,
                                     recommendedSeconds: advice.seconds, at: at)
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
        }
        let top = topSandTarget
        sandA.target = aIsUp ? top : 1 - top
        sandB.target = aIsUp ? 1 - top : top
        sandA.advance(dt, config: .follow)
        sandB.advance(dt, config: .follow)
        glassHeight.target = Double(glassGeometry.height(forSeconds: glassSeconds))
        glassHeight.advance(dt, config: reduceMotion ? .calm : .bodyNumbers)
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
