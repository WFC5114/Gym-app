import RealityKit
import UIKit

/// The TRAIN desk hourglass in clay, built once from procedural meshes into the
/// entity SET DONE flips. Mirrors the approved round 2 of
/// design/mockups/clay/objects.py (hourglass): layered indigo and cream plates,
/// turned cups at the bulb ends, four grooved orange posts in butter sleeves,
/// dome nuts, round thick glass with a butter neck ring, and on each base slab
/// raised minute ticks, a knurled knob for the rest and raised REST lettering.
/// The frame is point-symmetric through the neck, so it looks the same after
/// every flip; only the lettering on the lower slab shows.
@MainActor
final class HourglassRig {
    private let clay: ClayKit
    private let sphere: MeshResource
    /// REST lettering on the bottom (index 0) and top (index 1) slabs.
    private var labels: [Entity] = []

    init(clay: ClayKit, into spin: Entity) {
        self.clay = clay
        sphere = MeshResource.generateSphere(radius: 1)
        build(into: spin)
    }

    /// Shows the lettering on whichever slab is lower; it fades out edge-on
    /// mid-flip. `angle` is the glass's flip angle in radians.
    func apply(angle: Float) {
        let down = cos(angle)
        for (i, label) in labels.enumerated() {
            let facing = i == 0 ? down : -down
            label.components.set(OpacityComponent(opacity: min(max(facing * 4, 0), 1)))
        }
    }

    private func build(into spin: Entity) {
        typealias H = DeskHourglass
        let u = H.unit

        // Glass: one closed shell (outside, both open ends and inside), so with
        // back faces culled the near outside and the far inside wall show.
        if let glass = try? Geometry.ring(H.glassLoop, segments: 128, name: "glass") {
            spin.addChild(ModelEntity(mesh: glass, materials: [clay.glass]))
        }
        if let neck = try? Geometry.ring([SIMD2(-0.012 * u, 0.034 * u), SIMD2(-0.012 * u, 0.04 * u),
                                          SIMD2(0.012 * u, 0.04 * u), SIMD2(0.012 * u, 0.034 * u)], segments: 64, name: "neckRing") {
            add(neck, clay.hardware, to: spin)
        }

        // Plates, cups and the dressing on each end: the bottom set as built, the
        // top set the same turned half a turn about the face normal.
        for end in 0..<2 {
            let holder = Entity()
            holder.orientation = simd_quatf(angle: end == 0 ? 0 : .pi, axis: [0, 0, 1])
            spin.addChild(holder)
            buildEnd(into: holder)
        }

        // Posts, each from one plate to the other through its sleeves.
        let post = lathe(Geometry.spindleProfile(length: H.postLength, top: H.postRadius, bottom: H.postRadius), segments: 32, "post")
        for x in [-H.postOffset, H.postOffset] {
            for z in [-H.postOffset, H.postOffset] {
                add(post, clay.joint, to: spin, at: [x, H.plateInner, z])
            }
        }
    }

    /// One end, built as the bottom: slab, panel, cup, sleeves, nuts, ticks, knob, lettering.
    private func buildEnd(into end: Entity) {
        typealias H = DeskHourglass
        let u = H.unit
        add(block(half: [H.slabHalfSide, H.slabHalfThickness, H.slabHalfSide], round: 0.03 * u, "slab"), clay.plinth,
            to: end, at: [0, -H.slabY, 0])
        add(block(half: [H.panelHalfSide, H.panelHalfThickness, H.panelHalfSide], round: 0.011 * u, "panel"), clay.body,
            to: end, at: [0, -H.panelY, 0])
        // The turned cup the bulb's open end sits in, under the plate.
        let cupLoop: [SIMD2<Float>] = [SIMD2(0, 0.075), SIMD2(0, 0.11), SIMD2(0.01, 0.114), SIMD2(0.022, 0.095), SIMD2(0.03, 0.075)].map { $0 * u }
        if let cup = try? Geometry.ring(cupLoop, segments: 64, name: "cup") {
            add(cup, clay.joint, to: end, at: [0, -H.plateInner, 0])
        }
        let sleeve = lathe([SIMD2(0, 0.0001), SIMD2(0, 0.026), SIMD2(0.006, 0.028), SIMD2(0.05, 0.024), SIMD2(0.06, 0.02), SIMD2(0.06, 0.0001)].map { $0 * u },
                           segments: 32, "sleeve")
        for x in [-H.postOffset, H.postOffset] {
            for z in [-H.postOffset, H.postOffset] {
                add(sleeve, clay.hardware, to: end, at: [x, -H.plateInner, z])
                add(sphere, clay.hardware, to: end, at: [x, -H.nutY, z], scale: [H.nutWidth, H.nutRadius, H.nutWidth])
            }
        }

        // The slab's front: raised minute ticks, a knurled knob to set the rest, REST.
        let front = H.slabHalfSide + 0.002 * u
        for i in 0..<7 {
            let tall = i % 2 == 0
            add(block(half: [0.003 * u, (tall ? 0.01 : 0.006) * u, 0.003 * u], round: 0.002 * u, "tick"), clay.hardware,
                to: end, at: [(-0.19 + Float(i) * 0.05) * u, -H.plateInner - 0.022 * u, front])
        }
        let r = 0.024 * u, length = 0.022 * u
        let knobLoop: [SIMD2<Float>] = [SIMD2(0, 0.0005 * u), SIMD2(0, r * 0.7), SIMD2(0.004 * u, r), SIMD2(length * 0.3, r), SIMD2(length * 0.5, r),
                                        SIMD2(length * 0.7, r), SIMD2(length - 0.004 * u, r), SIMD2(length, r * 0.8), SIMD2(length, 0.0005 * u)]
        let toFront = simd_quatf(from: [0, 1, 0], to: [0, 0, 1])
        if let knob = try? Geometry.knurledRim(loop: knobLoop, ridges: 24, rib: 0.003 * u, name: "knob") {
            add(knob, clay.hardware, to: end, at: [0.205 * u, -H.slabY, H.slabHalfSide - 0.002 * u], orientation: toFront)
        }
        add(sphere, clay.joint, to: end, at: [0.205 * u, -H.slabY, H.slabHalfSide + length - 0.002 * u], scale: [0.013 * u, 0.013 * u, 0.004 * u])

        let label = Entity()
        label.position = [-0.04 * u, -H.plateInner - 0.053 * u, front]
        end.addChild(label)
        let text = MeshResource.generateText("REST", extrusionDepth: 0.003 * u, font: .systemFont(ofSize: CGFloat(0.026 * u), weight: .heavy))
        let b = text.bounds
        add(text, clay.hardware, to: label, at: [-b.center.x, -b.center.y, 0])
        labels.append(label)
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

    private func lathe(_ profile: [SIMD2<Float>], segments: Int, _ name: String) -> MeshResource {
        (try? Geometry.lathe(profile, segments: segments, name: name)) ?? sphere
    }

    /// A rounded clay block of half sizes `half` (width, height, depth).
    private func block(half: SIMD3<Float>, round: Float, _ name: String) -> MeshResource {
        (try? Geometry.clayBlock(bottom: half.x, top: half.x, depth: half.z, height: half.y, round: round, name: name)) ?? sphere
    }
}
