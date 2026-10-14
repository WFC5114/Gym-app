import RealityKit
import UIKit

/// The BODY mannequin in RealityKit: a jointed clay artist's mannequin on a dial
/// turntable, built once from procedural meshes (no model files) and posed every
/// frame from `FigureShape` and `Mannequin.Pose`. Mirrors the clay look of
/// design/mockups/body/mannequin.py: hinge forks with screws at elbows and
/// knees, socket cups and rings, panel seams, jointed fingers, hinged toes, and
/// a dial with a knurled rim, raised week numbers, a crank and a BODY plaque.
@MainActor
final class MannequinRig {
    /// Leans with the stand; holds the plinth and everything else.
    let root = Entity()
    /// Turns with the figure: the dial, its rod and the mannequin.
    private let turn = Entity()
    private var joints: [Mannequin.Joint: Entity] = [:]
    /// Pieces whose width and depth follow the body, with how to scale them.
    private var scaled: [(entity: Entity, scale: (FigureShape) -> SIMD3<Float>)] = []
    private var chestGroup = Entity()
    private let clay: ClayKit
    private let sphere: MeshResource

    init(clay: ClayKit) {
        self.clay = clay
        sphere = MeshResource.generateSphere(radius: 1)
        root.addChild(turn)
        buildStand()
        buildDial()
        buildFigure()
    }

    // MARK: Per frame

    func apply(shape: FigureShape, pose: Mannequin.Pose, yaw: Float) {
        root.orientation = simd_quatf(angle: FigureGeometry.lean, axis: [1, 0, 0])
        turn.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        for (joint, entity) in joints {
            entity.position = Mannequin.offset(joint, shape: shape)
            entity.orientation = Mannequin.rotation(joint, pose: pose)
        }
        for item in scaled { item.entity.scale = item.scale(shape) }
        // The chest swells a touch with each breath.
        let breath = 1 + 0.012 * max(pose.breathe, 0)
        chestGroup.scale = SIMD3(shape.chestScale.x * breath, 1, shape.chestScale.y * breath)
    }

    // MARK: Building blocks

    @discardableResult
    private func add(_ mesh: MeshResource, _ material: PhysicallyBasedMaterial, to parent: Entity,
                     at position: SIMD3<Float> = .zero, scale: SIMD3<Float> = .one,
                     orientation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = position
        e.scale = scale
        e.orientation = orientation
        parent.addChild(e)
        return e
    }

    private func ball(_ radii: SIMD3<Float>, _ material: PhysicallyBasedMaterial, to parent: Entity, at position: SIMD3<Float>) {
        add(sphere, material, to: parent, at: position, scale: radii)
    }

    private func group(_ parent: Entity, at position: SIMD3<Float> = .zero, scale: ((FigureShape) -> SIMD3<Float>)? = nil) -> Entity {
        let g = Entity()
        g.position = position
        parent.addChild(g)
        if let scale { scaled.append((g, scale)) }
        return g
    }

    private func lathe(_ profile: [SIMD2<Float>], segments: Int = 48, _ name: String) -> MeshResource {
        (try? Geometry.lathe(profile, segments: segments, name: name)) ?? sphere
    }

    private func block(bottom: Float, top: Float, depth: Float, height: Float, front: Float = 0, round: Float, _ name: String) -> MeshResource {
        (try? Geometry.clayBlock(bottom: bottom, top: top, depth: depth, height: height, front: front, round: round, name: name)) ?? sphere
    }

    /// A thin socket ring of inner radius `r` round a limb at height `y`.
    private func socketRing(_ r: Float, at y: Float, to parent: Entity, width: Float = 0.004, depth: Float = 0.003) {
        let loop: [SIMD2<Float>] = [SIMD2(-width / 2, r), SIMD2(-width / 2, r + depth), SIMD2(width / 2, r + depth), SIMD2(width / 2, r)]
        let mesh = (try? Geometry.ring(loop, name: "socketRing")) ?? sphere
        add(mesh, clay.socket, to: parent, at: [0, y, 0])
    }

    /// A clay cup or collar from a closed (y, radius) cross-section.
    private func cup(_ loop: [SIMD2<Float>], at y: Float, to parent: Entity, _ material: PhysicallyBasedMaterial) {
        let mesh = (try? Geometry.ring(loop, name: "cup")) ?? sphere
        add(mesh, material, to: parent, at: [0, y, 0])
    }

    /// A turned limb hanging from `y` down by `length`.
    private func spindle(length: Float, top: Float, bottom: Float, bulge: Float = 0, peak: Float = 0.3,
                         at position: SIMD3<Float>, to parent: Entity, _ material: PhysicallyBasedMaterial? = nil,
                         orientation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        let profile = Geometry.spindleProfile(length: length, top: top, bottom: bottom, bulge: bulge, peak: peak)
        add(lathe(profile, segments: 40, "spindle"), material ?? clay.body, to: parent, at: position, orientation: orientation)
    }

    /// A domed screw head with a cross slot, its axis turned from +y to `axis`.
    private func screw(radius r: Float, at position: SIMD3<Float>, axis: SIMD3<Float>, to parent: Entity) {
        let holder = Entity()
        holder.position = position
        holder.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(axis))
        parent.addChild(holder)
        let dome: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0, r), SIMD2(r * 0.25, r * 0.92), SIMD2(r * 0.45, r * 0.6), SIMD2(r * 0.52, 0)]
        add(lathe(dome, segments: 24, "screw"), clay.hardware, to: holder)
        let slot = MeshResource.generateBox(width: r * 1.6, height: r * 0.4, depth: r * 0.26)
        for a in [Float(0), .pi / 2] {
            add(slot, clay.socket, to: holder, at: [0, r * 0.5, 0], orientation: simd_quatf(angle: a, axis: [0, 1, 0]))
        }
    }

    /// A hinge: two cheek plates from the upper limb hug the joint ball at `y`,
    /// each pinned through with a screw.
    private func fork(ballRadius: Float, at y: Float, to parent: Entity) {
        let r = ballRadius
        let cheek = lathe([SIMD2(-0.002, 0), SIMD2(-0.002, r * 0.95), SIMD2(0, r * 1.02), SIMD2(0.002, r * 0.95), SIMD2(0.002, 0)], segments: 32, "cheek")
        let tongue = block(bottom: 0.0022, top: 0.0022, depth: r * 0.7, height: r * 0.6, round: 0.0015, "tongue")
        for side in [Float(-1), 1] {
            add(cheek, clay.joint, to: parent, at: [side * (r + 0.002), y, 0],
                orientation: simd_quatf(from: [0, 1, 0], to: [1, 0, 0]))
            add(tongue, clay.joint, to: parent, at: [side * (r + 0.002), y + r * 0.75, 0])
            screw(radius: r * 0.42, at: [side * (r + 0.004), y, 0], axis: [side, 0, 0], to: parent)
        }
    }

    /// A tapered clay block cut through by a panel seam at `seam` (block-local y):
    /// two rounded pieces with a dark core showing in the gap.
    private func seamedBlock(bottom: Float, top: Float, depth: Float, height: Float, front: Float, round: Float,
                             seam: Float, at position: SIMD3<Float>, to parent: Entity) {
        let gap: Float = 0.0028
        func width(_ y: Float) -> Float { bottom + (top - bottom) * (y + height) / (2 * height) }
        let lowTop = seam - gap / 2, highBottom = seam + gap / 2
        let lowHalf = (lowTop + height) / 2, highHalf = (height - highBottom) / 2
        add(block(bottom: bottom, top: width(lowTop), depth: depth, height: lowHalf, front: front, round: round, "panelLow"),
            clay.body, to: parent, at: position + [0, -height + lowHalf, 0])
        add(block(bottom: width(highBottom), top: top, depth: depth, height: highHalf, front: front * 0.5, round: min(round, highHalf * 0.9), "panelHigh"),
            clay.body, to: parent, at: position + [0, height - highHalf, 0])
        ball([width(seam) * 0.86, gap * 1.6, depth * 0.86], clay.socket, to: parent, at: position + [0, seam, 0])
    }

    /// Raised lettering lying flat (or standing, if `upright`), centred on its holder.
    private func lettering(_ text: String, size: CGFloat, depth: Float, _ material: PhysicallyBasedMaterial, to holder: Entity) {
        let mesh = MeshResource.generateText(text, extrusionDepth: depth, font: .systemFont(ofSize: size, weight: .heavy))
        let b = mesh.bounds
        add(mesh, material, to: holder, at: [-b.center.x, -b.center.y, 0])
    }

    // MARK: Stand (does not turn)

    private func buildStand() {
        add(lathe([SIMD2(-0.075, 0), SIMD2(-0.075, 0.225), SIMD2(-0.072, 0.23), SIMD2(-0.044, 0.23), SIMD2(-0.04, 0.225), SIMD2(-0.04, 0)],
                  segments: 96, "plinth"), clay.plinth, to: root)
        // Three bun feet.
        for k in 0..<3 {
            let a = Float.pi / 3 + 2 * Float.pi * Float(k) / 3
            ball([0.03, 0.012, 0.03], clay.hardware, to: root, at: [0.17 * sin(a), -0.072, 0.17 * cos(a)])
        }
        // Index pointer at the front, reading the dial.
        add(block(bottom: 0.012, top: 0.005, depth: 0.006, height: 0.02, round: 0.005, "index"), clay.hardware, to: root, at: [0, -0.036, 0.27])
        // A crank on the right side: hub, arm and a spinning knob.
        let toX = simd_quatf(from: [0, 1, 0], to: [1, 0, 0])
        add(lathe([SIMD2(0, 0), SIMD2(0, 0.011), SIMD2(0.012, 0.011), SIMD2(0.016, 0.006), SIMD2(0.016, 0)], segments: 24, "crankHub"),
            clay.hardware, to: root, at: [0.226, -0.058, 0.02], orientation: toX)
        add(block(bottom: 0.004, top: 0.004, depth: 0.03, height: 0.007, round: 0.003, "crankArm"), clay.hardware, to: root,
            at: [0.246, -0.058, 0.045], orientation: simd_quatf(angle: 0.3, axis: [1, 0, 0]))
        add(lathe([SIMD2(0, 0), SIMD2(0, 0.004), SIMD2(0.004, 0.009), SIMD2(0.022, 0.009), SIMD2(0.028, 0.006), SIMD2(0.03, 0)], segments: 24, "crankKnob"),
            clay.tick, to: root, at: [0.248, -0.058, 0.07], orientation: toX)
        // Name plaque with two screws, off to one side of the pointer.
        let pa = -32 * Float.pi / 180
        let plaque = Entity()
        plaque.position = [0.232 * sin(pa), -0.058, 0.232 * cos(pa)]
        plaque.orientation = simd_quatf(angle: pa, axis: [0, 1, 0])
        root.addChild(plaque)
        add(block(bottom: 0.05, top: 0.05, depth: 0.003, height: 0.012, round: 0.003, "plaque"), clay.hardware, to: plaque)
        let label = Entity()
        label.position = [0, 0, 0.0028]
        plaque.addChild(label)
        lettering("BODY", size: 0.014, depth: 0.0012, clay.plinth, to: label)
        for x in [Float(-0.042), 0.042] { screw(radius: 0.003, at: [x, 0, 0.0028], axis: [0, 0, 1], to: plaque) }
    }

    // MARK: Dial (turns with the figure)

    private func buildDial() {
        add(lathe([SIMD2(-0.04, 0), SIMD2(-0.04, 0.24), SIMD2(-0.037, 0.245), SIMD2(-0.004, 0.245), SIMD2(0, 0.24), SIMD2(0, 0)],
                  segments: 96, "dial"), clay.dial, to: turn)
        // Knurled grip rim: the bit your thumb wants to turn.
        let rimLoop: [SIMD2<Float>] = [
            SIMD2(-0.034, 0.246), SIMD2(-0.034, 0.256), SIMD2(-0.026, 0.264), SIMD2(-0.02, 0.264), SIMD2(-0.015, 0.264),
            SIMD2(-0.01, 0.264), SIMD2(-0.006, 0.264), SIMD2(0.004, 0.256), SIMD2(0.004, 0.246),
        ]
        if let rim = try? Geometry.knurledRim(loop: rimLoop, ridges: 120, rib: 0.0025, name: "rim") {
            add(rim, clay.hardware, to: turn)
        }
        for k in 0..<24 {
            let a = 2 * Float.pi * Float(k) / 24
            let big: Float = k % 6 == 0 ? 0.009 : 0.006
            ball([big, 0.004, big], clay.tick, to: turn, at: [0.222 * sin(a), 0.001, 0.222 * cos(a)])
        }
        // Raised week numbers, a quarter turn apart: the ruler's eight weeks.
        for (i, week) in ["0", "2", "4", "6", "8"].enumerated() {
            let a = -Float.pi / 2 + Float(i) * Float.pi / 4
            let holder = Entity()
            holder.position = [0.19 * sin(a), 0, 0.19 * cos(a)]
            holder.orientation = simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            turn.addChild(holder)
            lettering(week, size: 0.045, depth: 0.004, clay.hardware, to: holder)
        }
        let label = Entity()
        label.position = [0, 0, 0.15]
        label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        turn.addChild(label)
        lettering("WEEKS", size: 0.022, depth: 0.003, clay.tick, to: label)
        // The stand rod rises from the back of the dial into the hips.
        let lean = atan2(Float(0.05), 0.445)
        let base = SIMD3<Float>(0, 0, -0.075)
        let dir = SIMD3<Float>(0, cos(lean), sin(lean))
        add(.generateCylinder(height: 0.445, radius: 0.008), clay.rod, to: turn, at: base + dir * 0.2225,
            orientation: simd_quatf(angle: lean, axis: [1, 0, 0]))
        add(lathe([SIMD2(0, 0), SIMD2(0, 0.016), SIMD2(0.005, 0.016), SIMD2(0.012, 0.008), SIMD2(0.03, 0.007), SIMD2(0.03, 0)], segments: 32, "collar"),
            clay.hardware, to: turn, at: base)
    }

    // MARK: Figure

    private func joint(_ j: Mannequin.Joint) -> Entity {
        if let e = joints[j] { return e }
        let e = Entity()
        joints[j] = e
        let parent = j.parent.map { joint($0) } ?? turn
        parent.addChild(e)
        return e
    }

    private func buildFigure() {
        let M = Mannequin.self
        // Pelvis: a seamed hip block.
        let pelvis = joint(.pelvis)
        let hips = group(pelvis) { s in SIMD3(s.pelvisScale.x, 1, s.pelvisScale.y) }
        seamedBlock(bottom: M.pelvisBottom, top: M.pelvisTop, depth: M.pelvisDepth, height: M.pelvisHalfHeight, front: 0.12, round: 0.028,
                    seam: 0.022, at: .zero, to: hips)

        // Waist: the belly ball between socket cups.
        let abdomen = joint(.abdomen)
        let belly = group(abdomen) { s in s.bellyScale }
        ball(SIMD3(repeating: M.bellyRadius), clay.body, to: belly, at: .zero)
        let hipCup = group(abdomen) { s in SIMD3(s.pelvisScale.x, 1, s.pelvisScale.y) }
        cup([SIMD2(-0.008, 0.026), SIMD2(-0.008, 0.045), SIMD2(0, 0.043), SIMD2(0.006, 0.036), SIMD2(0.006, 0.026)], at: -0.03, to: hipCup, clay.joint)
        socketRing(0.03, at: 0.035, to: belly)

        // Chest: seamed block, waist cup, neck collar, shoulder blades and spine.
        let chest = joint(.chest)
        chestGroup = Entity()
        chest.addChild(chestGroup)
        seamedBlock(bottom: M.chestBottom, top: M.chestTop, depth: M.chestDepth, height: M.chestHalfHeight, front: 0.5, round: 0.034,
                    seam: 0.045, at: [0, M.chestBlockY, 0], to: chestGroup)
        cup([SIMD2(-0.006, 0.026), SIMD2(-0.006, 0.036), SIMD2(0, 0.043), SIMD2(0.008, 0.045), SIMD2(0.008, 0.026)], at: 0.004, to: chestGroup, clay.joint)
        cup([SIMD2(-0.004, 0.012), SIMD2(-0.004, 0.026), SIMD2(0.004, 0.028), SIMD2(0.009, 0.024), SIMD2(0.009, 0.012)], at: 0.2, to: chestGroup, clay.joint)
        for side in [Float(-1), 1] { ball([0.032, 0.042, 0.012], clay.body, to: chestGroup, at: [side * 0.04, 0.15, -0.058]) }
        for i in 0..<6 {
            ball([0.009, 0.0075, 0.006], clay.joint, to: chestGroup, at: [0, 0.06 + Float(i) * 0.024, -(0.06 - 0.004 * abs(Float(i) - 2.5) / 2.5)])
        }

        // Neck and head: an egg with a small nose ridge and ears, no face.
        let neck = joint(.neck)
        ball(SIMD3(repeating: 0.0242), clay.joint, to: neck, at: .zero)
        spindle(length: 0.035, top: 0.02, bottom: 0.02375, at: [0, 0.04, 0], to: neck)
        for y in [Float(0.052), 0.064] { socketRing(0.02, at: y, to: neck, width: 0.003, depth: 0.002) }
        let head = joint(.head)
        let egg = Geometry.eggProfile(radius: M.skull.x, height: M.skull.y, taper: 0.32)
        add(lathe(egg, segments: 48, "skull"), clay.body, to: head, at: [0, M.skullUp, 0.006], scale: [1, 1, M.skull.z / M.skull.x])
        add(sphere, clay.body, to: head, at: [0, 0.06, 0.054], scale: [0.005, 0.017, 0.007],
            orientation: simd_quatf(angle: -0.2, axis: [1, 0, 0]))
        for side in [Float(-1), 1] { ball([0.005, 0.016, 0.011], clay.body, to: head, at: [side * 0.046, 0.07, 0]) }

        for side in [Float(1), -1] { buildArm(side: side) }
        for side in [Float(1), -1] { buildLeg(side: side) }
    }

    private func buildArm(side: Float) {
        let left = side > 0
        let shoulder = joint(left ? .shoulderL : .shoulderR)
        let ballGroup = group(shoulder) { s in SIMD3(repeating: s.shoulderBallScale) }
        ball(SIMD3(repeating: Mannequin.shoulderBall), clay.joint, to: ballGroup, at: .zero)
        screw(radius: 0.005, at: [side * 0.031, 0, 0], axis: [side, 0, 0], to: ballGroup)
        let upper = group(shoulder) { s in SIMD3(s.armScale, 1, s.armScale) }
        spindle(length: 0.15, top: 0.0275, bottom: 0.02125, bulge: 0.005, at: [0, -0.02, 0], to: upper)
        socketRing(0.03, at: -0.02, to: upper)
        fork(ballRadius: 0.0209, at: -Mannequin.elbowDrop, to: upper)

        let elbow = joint(left ? .elbowL : .elbowR)
        let fore = group(elbow) { s in SIMD3(s.armScale, 1, s.armScale) }
        ball(SIMD3(repeating: 0.0209), clay.joint, to: fore, at: .zero)
        spindle(length: 0.145, top: 0.0225, bottom: 0.01625, bulge: 0.00375, at: [0, -0.016, 0], to: fore)
        socketRing(0.02375, at: -0.016, to: fore)

        // Hand: palm, thumb, four two-jointed fingers on a knuckle bar.
        let wrist = joint(left ? .wristL : .wristR)
        ball(SIMD3(repeating: 0.0132), clay.joint, to: wrist, at: .zero)
        add(block(bottom: 0.0109, top: 0.0093, depth: 0.0247, height: 0.032, round: 0.0087, "palm"), clay.body, to: wrist, at: [0, -0.04, 0])
        spindle(length: 0.03, top: 0.0075, bottom: 0.00625, at: [side * -0.0087, -0.018, 0.0174], to: wrist,
                orientation: simd_quatf(angle: 0.5, axis: [1, 0, 0]))
        add(.generateCylinder(height: 0.0288, radius: 0.0055), clay.joint, to: wrist, at: [0, -0.07, 0],
            orientation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        for i in 0..<4 {
            let length = 0.016 - abs(Float(i) - 1.5) * 0.0018
            let base = Entity()
            base.position = [0, -0.07, 0.018 - Float(i) * 0.012]
            base.orientation = simd_quatf(angle: side * 0.12, axis: [0, 0, 1]) * simd_quatf(angle: 0.1, axis: [1, 0, 0])
            wrist.addChild(base)
            spindle(length: length, top: 0.00525, bottom: 0.004875, at: .zero, to: base)
            let knuckle = Entity()
            knuckle.position = [0, -length - 0.002, 0]
            knuckle.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
            base.addChild(knuckle)
            ball(SIMD3(repeating: 0.0045), clay.joint, to: knuckle, at: [0, 0.001, 0])
            spindle(length: length * 0.85, top: 0.00475, bottom: 0.004125, at: [0, -0.002, 0], to: knuckle)
        }
    }

    private func buildLeg(side: Float) {
        let left = side > 0
        let hip = joint(left ? .hipL : .hipR)
        ball(SIMD3(repeating: 0.033), clay.joint, to: hip, at: .zero)
        let thigh = group(hip) { s in SIMD3(s.legScale, 1, s.legScale) }
        spindle(length: 0.205, top: 0.0375, bottom: 0.02625, bulge: 0.00625, at: [0, -0.022, 0], to: thigh)
        socketRing(0.0375, at: -0.022, to: thigh)
        fork(ballRadius: 0.0242, at: -Mannequin.kneeDrop, to: thigh)

        let knee = joint(left ? .kneeL : .kneeR)
        let shin = group(knee) { s in SIMD3(s.legScale, 1, s.legScale) }
        ball(SIMD3(repeating: 0.0242), clay.joint, to: shin, at: .zero)
        spindle(length: 0.19, top: 0.0275, bottom: 0.01875, bulge: 0.005, peak: 0.25, at: [0, -0.018, 0], to: shin)
        socketRing(0.02875, at: -0.018, to: shin)
        ball([0.014, 0.017, 0.008], clay.body, to: shin, at: [0, -0.004, 0.024])

        // Foot: sole block, heel, a hinge pin and a separate toe.
        let ankle = joint(left ? .ankleL : .ankleR)
        ball(SIMD3(repeating: 0.0154), clay.joint, to: ankle, at: .zero)
        add(block(bottom: 0.02, top: 0.016, depth: 0.035, height: 0.011, round: 0.008, "foot"), clay.body, to: ankle, at: [0, -0.012, 0.026])
        ball([0.017, 0.012, 0.015], clay.body, to: ankle, at: [0, -0.012, -0.012])
        add(.generateCylinder(height: 0.034, radius: 0.0035), clay.rod, to: ankle, at: [0, -0.016, 0.066],
            orientation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        add(block(bottom: 0.017, top: 0.0128, depth: 0.011, height: 0.008, round: 0.006, "toe"), clay.body, to: ankle, at: [0, -0.016, 0.079])
    }
}
