import CoreGraphics
import simd

/// BODY's figure: a jointed artist's mannequin in clay (Wei, 14 Oct 2026:
/// claymorphism, "complex with tactile 3d object", hard joints, tall). Figure
/// units: feet at y 0, the top of the head near 1, x across, z toward the
/// viewer. A schematic, not a body scan: fat fills out the waist, belly and
/// limbs, lean mass broadens the shoulders and limbs, and a gentle training
/// tilt (an estimate from logged sets) leans muscle toward the parts trained most.
struct FigureShape: Equatable {
    var shoulders: Float
    var waist: Float
    var depth: Float
    var limb: Float
    var tilt: MuscleTilt = .none

    static let neutral = FigureShape.from(fatPercent: nil, leanKg: nil)
    static let range: ClosedRange<Float> = 0.55...2.0

    static func from(fatPercent: Double?, leanKg: Double?, tilt: MuscleTilt = .none) -> FigureShape {
        let fat = Float(min(max(fatPercent ?? 16, 5), 45))
        let lean = Float(min(max(leanKg ?? 66, 35), 100))
        let soft = (fat - 16) * 0.045
        let muscle = (lean - 66) * 0.015
        func clamp(_ v: Float) -> Float { min(max(v, range.lowerBound), range.upperBound) }
        return FigureShape(shoulders: clamp((1 + muscle) * (1 + soft * 0.4)),
                           waist: clamp((1 + soft) * (1 + muscle * 0.3)),
                           depth: clamp(1 + soft * 0.9 + muscle * 0.3),
                           limb: clamp((1 + soft * 0.5) * (1 + muscle * 1.4)),
                           tilt: tilt)
    }

    // MARK: How each piece is scaled across (x) and deep (z); lengths never change.

    /// The chest: mostly shoulders, some waist; chest and back training broaden it.
    var chestScale: SIMD2<Float> {
        SIMD2((shoulders * 0.6 + waist * 0.4) * (1 + tilt.torso), (1 + (depth - 1) * 0.4) * (1 + tilt.torso))
    }
    /// The hip block widens with the waist, a little less than the belly does.
    var pelvisScale: SIMD2<Float> { SIMD2(0.3 + 0.7 * waist, 0.3 + 0.7 * depth) }
    /// The waist ball is the belly: hidden between chest and hips when lean,
    /// pushing out past both as body fat rises.
    var bellyScale: SIMD3<Float> { SIMD3(waist, 0.85 + 0.15 * waist, depth) }
    var armScale: Float { limb * (1 + tilt.arms) }
    var legScale: Float { limb * (1 + tilt.legs) }
    var shoulderBallScale: Float { (0.5 + 0.5 * shoulders) * (1 + tilt.shoulders) }

    /// Shoulder joints sit on the chest's top corners, wherever those are.
    var shoulderX: Float {
        Mannequin.shoulder.x * chestScale.x + Mannequin.shoulderBall * (shoulderBallScale - 1)
    }
    /// Hip joints spread with the hips but always keep the thighs apart.
    var hipX: Float {
        max(Mannequin.hip.x * (0.6 + 0.4 * waist), Mannequin.thighTop * legScale + 0.003)
    }

    /// How far (radians) the arms swing out from straight down so their inner
    /// edges clear the chest, belly and hips at every body composition.
    var armSwing: Float {
        let shoulderY = Mannequin.shoulderY
        let radius = Mannequin.upperArmTop * armScale
        let checks: [(half: Float, y: Float)] = [
            (Mannequin.chestHalfWidth(atFigureY: 0.66) * chestScale.x, 0.66),
            (Mannequin.bellyRadius * bellyScale.x, Mannequin.abdomenY),
            (Mannequin.pelvisTop * pelvisScale.x, Mannequin.pelvisY + 0.03),
            (Mannequin.cupRadius * pelvisScale.x, Mannequin.pelvisY + 0.035),
        ]
        return checks.reduce(Mannequin.minimumSwing) { a, c in
            max(a, atan((c.half + radius + 0.008 - shoulderX) / (shoulderY - c.y)))
        }
    }

    var height: Float { Mannequin.headTop }

    // MARK: Ghost outline

    /// An axis-aligned piece, for the dashed outline drawn by the type layer.
    struct Part: Equatable {
        var center: SIMD3<Float>
        var size: SIMD3<Float>
    }

    /// The chest block.
    var torso: Part {
        Part(center: [0, Mannequin.chestY + Mannequin.chestBlockY, 0],
             size: [2 * Mannequin.chestTop * chestScale.x, 2 * Mannequin.chestHalfHeight, 2 * Mannequin.chestDepth * chestScale.y])
    }

    /// Hips and belly together.
    var belly: Part {
        let x = max(2 * Mannequin.pelvisTop * pelvisScale.x, 2 * Mannequin.bellyRadius * bellyScale.x)
        let z = max(2 * Mannequin.pelvisDepth * pelvisScale.y, 2 * Mannequin.bellyRadius * bellyScale.z)
        return Part(center: [0, 0.53, 0], size: [x, 0.17, z])
    }

    /// Torso (rounded rect) and belly (ellipse bounds) as the orthographic
    /// camera sees them with the figure turned by `yaw`, in figure units (y up),
    /// for the type layer's ghost outline.
    func torsoOutline(yaw: Float) -> (torso: CGRect, belly: CGRect) {
        let c = abs(cos(yaw)), s = abs(sin(yaw))
        let t = torso, b = belly
        // A box's silhouette adds its depth; an ellipse's grows as an ellipse does.
        let tHalf = t.size.x / 2 * c + t.size.z / 2 * s
        let bHalf = ((b.size.x / 2 * c) * (b.size.x / 2 * c) + (b.size.z / 2 * s) * (b.size.z / 2 * s)).squareRoot()
        func rect(_ half: Float, _ p: Part) -> CGRect {
            CGRect(x: CGFloat(-half), y: CGFloat(p.center.y - p.size.y / 2), width: CGFloat(half * 2), height: CGFloat(p.size.y))
        }
        return (rect(tHalf, t), rect(bHalf, b))
    }
}

/// The mannequin's skeleton and proportions, in figure units. It mirrors the
/// clay look of design/mockups/body/mannequin.py (Blender z up becomes y up,
/// Blender −y, the front, becomes +z). Tall artist's proportions.
enum Mannequin {
    enum Joint: Int, CaseIterable {
        case pelvis, abdomen, chest, neck, head
        case shoulderL, elbowL, wristL, shoulderR, elbowR, wristR
        case hipL, kneeL, ankleL, hipR, kneeR, ankleR

        var parent: Joint? {
            switch self {
            case .pelvis: return nil
            case .abdomen: return .pelvis
            case .chest: return .abdomen
            case .neck: return .chest
            case .head: return .neck
            case .shoulderL, .shoulderR: return .chest
            case .elbowL: return .shoulderL
            case .elbowR: return .shoulderR
            case .wristL: return .elbowL
            case .wristR: return .elbowR
            case .hipL, .hipR: return .pelvis
            case .kneeL: return .hipL
            case .kneeR: return .hipR
            case .ankleL: return .kneeL
            case .ankleR: return .kneeR
            }
        }

        /// +1 for the figure's left (+x), −1 for its right, 0 on the centre line.
        var side: Float {
            switch self {
            case .shoulderL, .elbowL, .wristL, .hipL, .kneeL, .ankleL: return 1
            case .shoulderR, .elbowR, .wristR, .hipR, .kneeR, .ankleR: return -1
            default: return 0
            }
        }
    }

    // Skeleton: each joint's rest offset from its parent.
    static let pelvisY: Float = 0.5
    static let abdomenUp: Float = 0.065
    static let chestUp: Float = 0.035
    static let neckUp: Float = 0.215
    static let headUp: Float = 0.03
    static let shoulder = SIMD2<Float>(0.1, 0.17)
    static let elbowDrop: Float = 0.17
    static let wristDrop: Float = 0.165
    static let hip = SIMD2<Float>(0.045, -0.04)
    static let kneeDrop: Float = 0.228
    static let ankleDrop: Float = 0.21

    static var abdomenY: Float { pelvisY + abdomenUp }
    static var chestY: Float { abdomenY + chestUp }
    static var shoulderY: Float { chestY + shoulder.y }
    static var headY: Float { chestY + neckUp + headUp }

    // Pieces (half sizes unless named otherwise), at the neutral body.
    static let pelvisTop: Float = 0.08
    static let pelvisBottom: Float = 0.048
    static let pelvisDepth: Float = 0.052
    static let pelvisHalfHeight: Float = 0.044
    static let bellyRadius: Float = 0.0396
    static let cupRadius: Float = 0.045
    static let chestTop: Float = 0.0952
    static let chestBottom: Float = 0.0476
    static let chestDepth: Float = 0.054
    static let chestHalfHeight: Float = 0.092
    /// The chest block's centre above the chest joint.
    static let chestBlockY: Float = 0.105
    static let shoulderBall: Float = 0.0308
    static let upperArmTop: Float = 0.0275
    static let thighTop: Float = 0.0375
    static let skull = SIMD3<Float>(0.046, 0.072, 0.054)
    static let skullUp: Float = 0.066
    static var headTop: Float { headY + skullUp + skull.y }
    static let minimumSwing: Float = 0.1

    /// The chest block's half-width at a height in figure units (it tapers to the waist).
    static func chestHalfWidth(atFigureY y: Float) -> Float {
        let bottom = chestY + chestBlockY - chestHalfHeight
        let u = min(max((y - bottom) / (2 * chestHalfHeight), 0), 1)
        return chestBottom + (chestTop - chestBottom) * u
    }

    /// Each joint's offset from its parent for this body.
    static func offset(_ joint: Joint, shape: FigureShape) -> SIMD3<Float> {
        let s = joint.side
        switch joint {
        case .pelvis: return [0, pelvisY, 0]
        case .abdomen: return [0, abdomenUp, 0]
        case .chest: return [0, chestUp, 0]
        case .neck: return [0, neckUp, 0]
        case .head: return [0, headUp, 0]
        case .shoulderL, .shoulderR: return [s * shape.shoulderX, shoulder.y, 0]
        case .elbowL, .elbowR: return [0, -elbowDrop, 0]
        case .wristL, .wristR: return [0, -wristDrop, 0]
        case .hipL, .hipR: return [s * shape.hipX, hip.y, 0]
        case .kneeL, .kneeR: return [0, -kneeDrop, 0]
        case .ankleL, .ankleR: return [0, -ankleDrop, 0]
        }
    }

    /// What the figure is doing this frame. All of it comes from springs and a
    /// slow clock in `MachineModel`; nothing here is an easing curve.
    struct Pose: Equatable {
        /// −1...1 through a breath.
        var breathe: Float = 0
        /// −1...1 as the weight settles from one hip to the other.
        var shift: Float = 0
        /// Head turn, radians-ish (−0.5 is a glance to its right).
        var look: Float = 0
        /// 0 at rest, 1 with the right arm up in a flex after a tap.
        var flex: Float = 0
        /// Extra outward swing of both arms at rest (from the body's width).
        var swing: Float = Mannequin.minimumSwing

        static let rest = Pose()
    }

    /// Rotation of one joint relative to its parent: a twist about the limb's own
    /// axis, then about x (forward bend), then z (sideways), then y (turn). Values
    /// are the mockup's contrapposto pose.
    ///
    /// The flex is a real biceps pose, not a wave: the right upper arm rolls out a
    /// quarter turn as it rises, so the elbow hinge (pinned along x, like the
    /// mockup's forks) faces forward and bends the forearm straight up beside the
    /// head, palm to the front; the rig curls that hand into a fist.
    static func rotation(_ joint: Joint, pose p: Pose) -> simd_quatf {
        let b = p.breathe, sh = p.shift, fl = p.flex
        let angles: SIMD3<Float>  // (x, y, z)
        switch joint {
        case .pelvis: angles = [0, 0.05, -(0.03 + 0.02 * sh)]
        case .abdomen: angles = [0.012 * b, -0.03, 0.05 + 0.02 * sh]
        case .chest: angles = [-0.02 * b, -0.03, 0.03 + 0.015 * sh]
        case .neck: angles = [0.04, 0.5 * p.look, -0.02]
        case .head: angles = [-0.05 + 0.01 * b, 0.5 * p.look, -0.03]
        case .shoulderL: angles = [0.08, 0, p.swing]
        case .elbowL: angles = [-0.25, 0, 0]
        case .wristL: angles = [0, 0, -0.1]
        case .shoulderR: angles = [0.05 - 0.15 * fl, 0, -(p.swing + 1.5 * fl)]
        case .elbowR: angles = [-0.3 - 1.75 * fl, 0, 0]
        case .wristR: angles = [0, 0, 0.25 * fl]
        case .hipL: angles = [-0.02, 0, 0.06 + 0.02 * sh]
        case .kneeL: angles = [0.03, 0, 0]
        case .ankleL: angles = [0, 0, -0.04]
        case .hipR: angles = [-0.12, 0, -(0.1 - 0.02 * sh)]
        case .kneeR: angles = [0.24, 0, 0]
        case .ankleR: angles = [-0.12, 0, 0.06]
        }
        let qx = simd_quatf(angle: angles.x, axis: [1, 0, 0])
        let qy = simd_quatf(angle: angles.y, axis: [0, 1, 0])
        let qz = simd_quatf(angle: angles.z, axis: [0, 0, 1])
        let twist = joint == .shoulderR ? -Float.pi / 2 * fl : 0
        return qy * qz * qx * simd_quatf(angle: twist, axis: [0, 1, 0])
    }

    /// Where every joint is in figure units for a body and pose (forward
    /// kinematics), for tests and anything the type layer needs to point at.
    static func positions(shape: FigureShape, pose: Pose) -> [Joint: SIMD3<Float>] {
        var world: [Joint: (p: SIMD3<Float>, q: simd_quatf)] = [:]
        for joint in Joint.allCases {  // parents come before children in this order
            let local = offset(joint, shape: shape)
            let q = rotation(joint, pose: pose)
            if let parent = joint.parent, let pw = world[parent] {
                world[joint] = (pw.p + pw.q.act(local), pw.q * q)
            } else {
                world[joint] = (local, q)
            }
        }
        return world.mapValues { $0.p }
    }
}
