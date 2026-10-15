import CoreGraphics
import Foundation
import simd

/// The jar's food blocks as real rigid bodies (Wei, 15 Oct 2026: "make sure
/// the physics are all real for jar logging foods"). A small 2D rigid-body
/// world after Erin Catto's Box2D Lite (MIT licence): oriented boxes with
/// mass and inertia from their size, gravity, box-box contact manifolds,
/// sequential impulses with accumulated, warm-started normal and friction
/// impulses, a little restitution and soft position correction. Blocks fall,
/// hit, bounce a little, tip over edges, slide and come to rest on each other
/// against the glass walls and floor.
///
/// Face points with y down, so gravity is +y and a positive angle turns a
/// block clockwise on screen, as SwiftUI's `rotationEffect` does.
struct JarWorld {
    struct Body {
        var id: UUID?
        var serial: Int
        var position: SIMD2<Double>
        var angle: Double
        var velocity = SIMD2<Double>(0, 0)
        var spin: Double = 0
        var half: SIMD2<Double>
        var invMass: Double
        var invInertia: Double
        var friction: Double
        var role: Role

        enum Role { case block, floor, wall }

        var size: CGSize { CGSize(width: half.x * 2, height: half.y * 2) }
        var center: CGPoint { CGPoint(x: position.x, y: position.y) }

        init(id: UUID?, serial: Int, center: CGPoint, size: CGSize, angle: Double, role: Role) {
            self.id = id
            self.serial = serial
            position = SIMD2(Double(center.x), Double(center.y))
            self.angle = angle
            half = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
            self.role = role
            if role == .block {
                let mass = 4 * half.x * half.y * JarWorld.density
                invMass = 1 / mass
                invInertia = 12 / (mass * (4 * half.x * half.x + 4 * half.y * half.y))
                friction = JarWorld.blockFriction
            } else {
                invMass = 0
                invInertia = 0
                friction = JarWorld.glassFriction
            }
        }

        mutating func resize(_ size: CGSize) {
            half = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
            let mass = 4 * half.x * half.y * JarWorld.density
            invMass = 1 / mass
            invInertia = 12 / (mass * (4 * half.x * half.x + 4 * half.y * half.y))
        }
    }

    // Tuned on the face's points: a 300 pt drop takes about half a second.
    static let gravity = SIMD2<Double>(0, 2600)
    static let density = 0.001
    static let blockFriction = 0.6
    static let glassFriction = 0.25
    /// Clay barely bounces: a tenth of a hard hit comes back.
    static let restitution = 0.12
    static let bounceThreshold = 240.0
    static let allowedPenetration = 0.5
    static let biasFactor = 0.2
    static let iterations = 10
    static let substep = 1.0 / 240

    private(set) var bodies: [Body] = []
    private var arbiters: [ArbiterKey: Arbiter] = [:]
    private var nextSerial = 0
    private var restTime = 0.0
    /// Every block has been still for a moment: stepping stops until something changes.
    private(set) var isAtRest = true
    /// Bumped whenever a block moves.
    private(set) var version = 0

    // MARK: Building

    /// The glass: floor and walls at the interior's edges, rising well above the
    /// mouth so an overfull pile stays in its column, and a lid at `ceiling`.
    mutating func setGlass(interior: CGRect, ceiling: CGFloat) {
        bodies.removeAll { $0.role != .block }
        arbiters.removeAll()
        let thick: CGFloat = 400
        let top = ceiling - thick
        let height = interior.maxY - top + thick
        addStatic(CGRect(x: interior.minX - thick, y: interior.maxY, width: interior.width + 2 * thick, height: thick), role: .floor)
        addStatic(CGRect(x: interior.minX - thick, y: top, width: thick, height: height), role: .wall)
        addStatic(CGRect(x: interior.maxX, y: top, width: thick, height: height), role: .wall)
        addStatic(CGRect(x: interior.minX - thick, y: top, width: interior.width + 2 * thick, height: thick), role: .wall)
        wake()
    }

    private mutating func addStatic(_ r: CGRect, role: Body.Role) {
        bodies.append(Body(id: nil, serial: nextSerial, center: CGPoint(x: r.midX, y: r.midY), size: r.size, angle: 0, role: role))
        nextSerial += 1
    }

    mutating func add(_ id: UUID, center: CGPoint, size: CGSize, angle: Double, velocity: CGVector = .zero, spin: Double = 0) {
        remove(id)
        var b = Body(id: id, serial: nextSerial, center: center, size: size, angle: angle, role: .block)
        b.velocity = SIMD2(Double(velocity.dx), Double(velocity.dy))
        b.spin = spin
        nextSerial += 1
        bodies.append(b)
        wake()
    }

    mutating func remove(_ id: UUID) {
        guard let i = bodies.firstIndex(where: { $0.id == id }) else { return }
        let serial = bodies[i].serial
        bodies.remove(at: i)
        arbiters = arbiters.filter { $0.key.a != serial && $0.key.b != serial }
        wake()
    }

    mutating func removeAllBlocks() {
        bodies.removeAll { $0.role == .block }
        arbiters.removeAll()
        wake()
    }

    mutating func resize(_ id: UUID, to size: CGSize) {
        guard let i = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[i].resize(size)
        wake()
    }

    /// Puts a block exactly here (fixtures: a frame mid-tumble).
    mutating func place(_ id: UUID, center: CGPoint, angle: Double, velocity: CGVector = .zero, spin: Double = 0) {
        guard let i = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[i].position = SIMD2(Double(center.x), Double(center.y))
        bodies[i].angle = angle
        bodies[i].velocity = SIMD2(Double(velocity.dx), Double(velocity.dy))
        bodies[i].spin = spin
        version &+= 1
    }

    mutating func wake() {
        isAtRest = false
        restTime = 0
    }

    func body(_ id: UUID) -> Body? { bodies.first { $0.id == id } }
    var blockIDs: [UUID] { bodies.compactMap { $0.role == .block ? $0.id : nil } }

    /// Whether a box (a block still in the air) touches the floor or a block.
    func touches(center: CGPoint, size: CGSize, angle: Double) -> Bool {
        let probe = Body(id: nil, serial: -1, center: center, size: size, angle: angle, role: .block)
        return bodies.contains { $0.role != .wall && !Self.collide(probe, $0).isEmpty }
    }

    // MARK: Stepping

    /// Advances by `dt` in fixed substeps.
    mutating func step(_ dt: Double) {
        guard !isAtRest else { return }
        var left = min(dt, 0.05)
        while left > 1e-9 {
            let h = min(Self.substep, left)
            substep(h)
            left -= h
        }
        version &+= 1
        let still = bodies.allSatisfy { $0.role != .block || (simd_length($0.velocity) < 8 && abs($0.spin) < 0.1) }
        restTime = still ? restTime + dt : 0
        if restTime > 0.4 {
            isAtRest = true
            for i in bodies.indices { bodies[i].velocity = .zero; bodies[i].spin = 0 }
        }
    }

    /// Runs until everything is still, up to `limit` seconds (launch, fixtures).
    mutating func settle(limit: Double = 4) {
        wake()
        var t = 0.0
        while !isAtRest && t < limit {
            step(1.0 / 60)
            t += 1.0 / 60
        }
    }

    private mutating func substep(_ dt: Double) {
        let invDt = 1 / dt
        // Contacts for every overlapping pair, keeping last step's impulses for warm starting.
        for i in bodies.indices {
            for j in (i + 1)..<bodies.count {
                let a = bodies[i], b = bodies[j]
                if a.invMass == 0 && b.invMass == 0 { continue }
                let key = ArbiterKey(a: a.serial, b: b.serial)
                let contacts = Self.collide(a, b)
                if contacts.isEmpty {
                    arbiters[key] = nil
                } else if var old = arbiters[key] {
                    old.update(contacts)
                    arbiters[key] = old
                } else {
                    arbiters[key] = Arbiter(first: i, second: j, contacts: contacts, friction: (a.friction * b.friction).squareRoot())
                }
            }
        }
        var index: [Int: Int] = [:]
        for (i, b) in bodies.enumerated() { index[b.serial] = i }
        for i in bodies.indices where bodies[i].invMass > 0 {
            bodies[i].velocity += dt * Self.gravity
            bodies[i].velocity *= 1 / (1 + dt * 0.05)
            bodies[i].spin *= 1 / (1 + dt * 0.4)
        }
        var active: [(ArbiterKey, Arbiter)] = []
        for (key, var arb) in arbiters {
            guard let i = index[key.a], let j = index[key.b] else { continue }
            arb.first = i
            arb.second = j
            arb.preStep(&bodies, invDt: invDt)
            active.append((key, arb))
        }
        active.sort { ($0.0.a, $0.0.b) < ($1.0.a, $1.0.b) }   // a fixed order keeps it deterministic
        for _ in 0..<Self.iterations {
            for k in active.indices { active[k].1.applyImpulse(&bodies) }
        }
        for (key, arb) in active { arbiters[key] = arb }
        for i in bodies.indices where bodies[i].invMass > 0 {
            bodies[i].position += dt * bodies[i].velocity
            bodies[i].angle += dt * bodies[i].spin
        }
    }

    // MARK: Contacts

    struct ArbiterKey: Hashable {
        var a: Int
        var b: Int
    }

    /// Which edges a contact point came from, so it can be recognised next step.
    struct Feature: Equatable {
        var inEdge1: UInt8 = 0, outEdge1: UInt8 = 0, inEdge2: UInt8 = 0, outEdge2: UInt8 = 0
        mutating func flip() {
            swap(&inEdge1, &inEdge2)
            swap(&outEdge1, &outEdge2)
        }
    }

    struct Contact {
        var position: SIMD2<Double>
        var normal: SIMD2<Double>
        var separation: Double
        var feature: Feature
        var r1 = SIMD2<Double>(0, 0), r2 = SIMD2<Double>(0, 0)
        var pn = 0.0, pt = 0.0
        var massNormal = 0.0, massTangent = 0.0
        var bias = 0.0
        var bounce = 0.0
    }

    struct Arbiter {
        var first: Int
        var second: Int
        var contacts: [Contact]
        var friction: Double

        mutating func update(_ fresh: [Contact]) {
            contacts = fresh.map { c in
                var c = c
                if let old = contacts.first(where: { $0.feature == c.feature }) {
                    c.pn = old.pn
                    c.pt = old.pt
                }
                return c
            }
        }

        mutating func preStep(_ bodies: inout [Body], invDt: Double) {
            let b1 = bodies[first], b2 = bodies[second]
            for k in contacts.indices {
                var c = contacts[k]
                c.r1 = c.position - b1.position
                c.r2 = c.position - b2.position
                let rn1 = simd_dot(c.r1, c.normal), rn2 = simd_dot(c.r2, c.normal)
                let kNormal = b1.invMass + b2.invMass
                    + b1.invInertia * (simd_dot(c.r1, c.r1) - rn1 * rn1) + b2.invInertia * (simd_dot(c.r2, c.r2) - rn2 * rn2)
                c.massNormal = 1 / kNormal
                let tangent = JarWorld.cross(c.normal, 1)
                let rt1 = simd_dot(c.r1, tangent), rt2 = simd_dot(c.r2, tangent)
                let kTangent = b1.invMass + b2.invMass
                    + b1.invInertia * (simd_dot(c.r1, c.r1) - rt1 * rt1) + b2.invInertia * (simd_dot(c.r2, c.r2) - rt2 * rt2)
                c.massTangent = 1 / kTangent
                c.bias = -JarWorld.biasFactor * invDt * min(0, c.separation + JarWorld.allowedPenetration)
                // A hard hit comes back a little.
                let dv = b2.velocity + JarWorld.cross(b2.spin, c.r2) - b1.velocity - JarWorld.cross(b1.spin, c.r1)
                let vn = simd_dot(dv, c.normal)
                c.bounce = vn < -JarWorld.bounceThreshold ? -JarWorld.restitution * vn : 0
                // Warm start with last step's impulses.
                let p = c.pn * c.normal + c.pt * tangent
                bodies[first].velocity -= b1.invMass * p
                bodies[first].spin -= b1.invInertia * JarWorld.cross(c.r1, p)
                bodies[second].velocity += b2.invMass * p
                bodies[second].spin += b2.invInertia * JarWorld.cross(c.r2, p)
                contacts[k] = c
            }
        }

        mutating func applyImpulse(_ bodies: inout [Body]) {
            for k in contacts.indices {
                var c = contacts[k]
                let b1 = bodies[first], b2 = bodies[second]
                var dv = b2.velocity + JarWorld.cross(b2.spin, c.r2) - b1.velocity - JarWorld.cross(b1.spin, c.r1)
                let vn = simd_dot(dv, c.normal)
                var dPn = c.massNormal * (-vn + max(c.bias, c.bounce))
                let pn0 = c.pn
                c.pn = max(pn0 + dPn, 0)
                dPn = c.pn - pn0
                let pn = dPn * c.normal
                bodies[first].velocity -= b1.invMass * pn
                bodies[first].spin -= b1.invInertia * JarWorld.cross(c.r1, pn)
                bodies[second].velocity += b2.invMass * pn
                bodies[second].spin += b2.invInertia * JarWorld.cross(c.r2, pn)

                let n1 = bodies[first], n2 = bodies[second]
                dv = n2.velocity + JarWorld.cross(n2.spin, c.r2) - n1.velocity - JarWorld.cross(n1.spin, c.r1)
                let tangent = JarWorld.cross(c.normal, 1)
                let vt = simd_dot(dv, tangent)
                var dPt = c.massTangent * -vt
                let maxPt = friction * c.pn
                let pt0 = c.pt
                c.pt = min(max(pt0 + dPt, -maxPt), maxPt)
                dPt = c.pt - pt0
                let pt = dPt * tangent
                bodies[first].velocity -= n1.invMass * pt
                bodies[first].spin -= n1.invInertia * JarWorld.cross(c.r1, pt)
                bodies[second].velocity += n2.invMass * pt
                bodies[second].spin += n2.invInertia * JarWorld.cross(c.r2, pt)
                contacts[k] = c
            }
        }
    }

    static func cross(_ v: SIMD2<Double>, _ s: Double) -> SIMD2<Double> { SIMD2(s * v.y, -s * v.x) }
    static func cross(_ s: Double, _ v: SIMD2<Double>) -> SIMD2<Double> { SIMD2(-s * v.y, s * v.x) }
    static func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }

    /// A 2x2 rotation as its two columns.
    private struct Rot {
        var c1: SIMD2<Double>, c2: SIMD2<Double>
        init(_ angle: Double) {
            let c = cos(angle), s = sin(angle)
            c1 = SIMD2(c, s)
            c2 = SIMD2(-s, c)
        }
        init(c1: SIMD2<Double>, c2: SIMD2<Double>) { self.c1 = c1; self.c2 = c2 }
        func apply(_ v: SIMD2<Double>) -> SIMD2<Double> { c1 * v.x + c2 * v.y }
        var transposed: Rot { Rot(c1: SIMD2(c1.x, c2.x), c2: SIMD2(c1.y, c2.y)) }
        var abs: Rot { Rot(c1: simd_abs(c1), c2: simd_abs(c2)) }
        func times(_ o: Rot) -> Rot { Rot(c1: apply(o.c1), c2: apply(o.c2)) }
    }

    private struct ClipVertex {
        var v: SIMD2<Double>
        var fp = Feature()
    }

    private static func clip(_ input: [ClipVertex], normal: SIMD2<Double>, offset: Double, edge: UInt8) -> [ClipVertex] {
        var out: [ClipVertex] = []
        let d0 = simd_dot(normal, input[0].v) - offset
        let d1 = simd_dot(normal, input[1].v) - offset
        if d0 <= 0 { out.append(input[0]) }
        if d1 <= 0 { out.append(input[1]) }
        if d0 * d1 < 0 {
            let t = d0 / (d0 - d1)
            var v = ClipVertex(v: input[0].v + t * (input[1].v - input[0].v))
            if d0 > 0 {
                v.fp = input[0].fp
                v.fp.inEdge1 = edge
                v.fp.inEdge2 = 0
            } else {
                v.fp = input[1].fp
                v.fp.outEdge1 = edge
                v.fp.outEdge2 = 0
            }
            out.append(v)
        }
        return out
    }

    private static func incidentEdge(half h: SIMD2<Double>, position: SIMD2<Double>, rot: Rot, normal: SIMD2<Double>) -> [ClipVertex] {
        // The reference face's normal in the incident box's frame, turned round.
        let n = -rot.transposed.apply(normal)
        var c = [ClipVertex(v: .zero), ClipVertex(v: .zero)]
        if Swift.abs(n.x) > Swift.abs(n.y) {
            if n.x > 0 {
                c[0].v = SIMD2(h.x, -h.y); c[0].fp.inEdge2 = 3; c[0].fp.outEdge2 = 4
                c[1].v = SIMD2(h.x, h.y); c[1].fp.inEdge2 = 4; c[1].fp.outEdge2 = 1
            } else {
                c[0].v = SIMD2(-h.x, h.y); c[0].fp.inEdge2 = 1; c[0].fp.outEdge2 = 2
                c[1].v = SIMD2(-h.x, -h.y); c[1].fp.inEdge2 = 2; c[1].fp.outEdge2 = 3
            }
        } else {
            if n.y > 0 {
                c[0].v = SIMD2(h.x, h.y); c[0].fp.inEdge2 = 4; c[0].fp.outEdge2 = 1
                c[1].v = SIMD2(-h.x, h.y); c[1].fp.inEdge2 = 1; c[1].fp.outEdge2 = 2
            } else {
                c[0].v = SIMD2(-h.x, -h.y); c[0].fp.inEdge2 = 2; c[0].fp.outEdge2 = 3
                c[1].v = SIMD2(h.x, -h.y); c[1].fp.inEdge2 = 3; c[1].fp.outEdge2 = 4
            }
        }
        c[0].v = position + rot.apply(c[0].v)
        c[1].v = position + rot.apply(c[1].v)
        return c
    }

    /// Box-box contact points (none, one or two), normal from `a` to `b`.
    static func collide(_ a: Body, _ b: Body) -> [Contact] {
        let hA = a.half, hB = b.half
        let posA = a.position, posB = b.position
        let rotA = Rot(a.angle), rotB = Rot(b.angle)
        let rotAT = rotA.transposed, rotBT = rotB.transposed
        let dp = posB - posA
        let dA = rotAT.apply(dp), dB = rotBT.apply(dp)
        let c = rotAT.times(rotB)
        let absC = c.abs
        let absCT = absC.transposed

        let faceA = simd_abs(dA) - hA - absC.apply(hB)
        if faceA.x > 0 || faceA.y > 0 { return [] }
        let faceB = simd_abs(dB) - absCT.apply(hA) - hB
        if faceB.x > 0 || faceB.y > 0 { return [] }

        enum Axis { case ax, ay, bx, by }
        let relativeTol = 0.95, absoluteTol = 0.01
        var axis = Axis.ax
        var separation = faceA.x
        var normal = dA.x > 0 ? rotA.c1 : -rotA.c1
        if faceA.y > relativeTol * separation + absoluteTol * hA.y {
            axis = .ay; separation = faceA.y; normal = dA.y > 0 ? rotA.c2 : -rotA.c2
        }
        if faceB.x > relativeTol * separation + absoluteTol * hB.x {
            axis = .bx; separation = faceB.x; normal = dB.x > 0 ? rotB.c1 : -rotB.c1
        }
        if faceB.y > relativeTol * separation + absoluteTol * hB.y {
            axis = .by; separation = faceB.y; normal = dB.y > 0 ? rotB.c2 : -rotB.c2
        }

        let frontNormal: SIMD2<Double>, sideNormal: SIMD2<Double>
        let front: Double, negSide: Double, posSide: Double
        let negEdge: UInt8, posEdge: UInt8
        let incident: [ClipVertex]
        switch axis {
        case .ax:
            frontNormal = normal; front = simd_dot(posA, frontNormal) + hA.x
            sideNormal = rotA.c2; let side = simd_dot(posA, sideNormal)
            negSide = -side + hA.y; posSide = side + hA.y; negEdge = 3; posEdge = 1
            incident = incidentEdge(half: hB, position: posB, rot: rotB, normal: frontNormal)
        case .ay:
            frontNormal = normal; front = simd_dot(posA, frontNormal) + hA.y
            sideNormal = rotA.c1; let side = simd_dot(posA, sideNormal)
            negSide = -side + hA.x; posSide = side + hA.x; negEdge = 2; posEdge = 4
            incident = incidentEdge(half: hB, position: posB, rot: rotB, normal: frontNormal)
        case .bx:
            frontNormal = -normal; front = simd_dot(posB, frontNormal) + hB.x
            sideNormal = rotB.c2; let side = simd_dot(posB, sideNormal)
            negSide = -side + hB.y; posSide = side + hB.y; negEdge = 3; posEdge = 1
            incident = incidentEdge(half: hA, position: posA, rot: rotA, normal: frontNormal)
        case .by:
            frontNormal = -normal; front = simd_dot(posB, frontNormal) + hB.y
            sideNormal = rotB.c1; let side = simd_dot(posB, sideNormal)
            negSide = -side + hB.x; posSide = side + hB.x; negEdge = 2; posEdge = 4
            incident = incidentEdge(half: hA, position: posA, rot: rotA, normal: frontNormal)
        }

        let clip1 = clip(incident, normal: -sideNormal, offset: negSide, edge: negEdge)
        guard clip1.count >= 2 else { return [] }
        let clip2 = clip(clip1, normal: sideNormal, offset: posSide, edge: posEdge)
        guard clip2.count >= 2 else { return [] }

        var contacts: [Contact] = []
        for v in clip2.prefix(2) {
            let s = simd_dot(frontNormal, v.v) - front
            guard s <= 0 else { continue }
            var feature = v.fp
            if axis == .bx || axis == .by { feature.flip() }
            contacts.append(Contact(position: v.v - s * frontNormal, normal: normal, separation: s, feature: feature))
        }
        return contacts
    }
}
