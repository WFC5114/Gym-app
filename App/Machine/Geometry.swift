import RealityKit
import simd

/// Procedural meshes for the machine. Every shape is generated here from
/// numbers; there are no model files. Front faces wind counter-clockwise.
enum Geometry {
    /// Collects triangles with flat or smooth normals.
    struct Builder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        /// Adds a flat quad a-b-c-d, oriented so its normal points away from `inside`.
        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, inside: SIMD3<Float>, uvScale: Float = 1) {
            var n = simd_normalize(simd_cross(b - a, d - a))
            let center = (a + b + c + d) / 4
            var verts = [a, b, c, d]
            if simd_dot(n, center - inside) < 0 {
                n = -n
                verts = [a, d, c, b]
            }
            let base = UInt32(positions.count)
            for v in verts {
                positions.append(v)
                normals.append(n)
                uvs.append(planarUV(v, n) * uvScale)
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, inside: SIMD3<Float>) {
            var n = simd_normalize(simd_cross(b - a, c - a))
            var verts = [a, b, c]
            if simd_dot(n, (a + b + c) / 3 - inside) < 0 {
                n = -n
                verts = [a, c, b]
            }
            let base = UInt32(positions.count)
            for v in verts {
                positions.append(v)
                normals.append(n)
                uvs.append(planarUV(v, n))
            }
            indices += [base, base + 1, base + 2]
        }

        /// Projects onto the plane most facing the normal so grain stays even.
        func planarUV(_ v: SIMD3<Float>, _ n: SIMD3<Float>) -> SIMD2<Float> {
            let a = simd_abs(n)
            if a.y >= a.x && a.y >= a.z { return SIMD2(v.x, v.z) }
            if a.x >= a.z { return SIMD2(v.z, v.y) }
            return SIMD2(v.x, v.y)
        }

        func mesh(named name: String) throws -> MeshResource {
            var d = MeshDescriptor(name: name)
            d.positions = MeshBuffers.Positions(positions)
            d.normals = MeshBuffers.Normals(normals)
            d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
            d.primitives = .triangles(indices)
            return try MeshResource.generate(from: [d])
        }
    }

    // MARK: Prism

    /// The chassis: an equilateral triangular prism, axis on Y, with a face
    /// square to +Z at distance `apothem`. Vertical edges are chamfered and the
    /// top and bottom edges bevelled so light catches them.
    static func prism(side s: Float, height h: Float, chamfer c: Float, bevel b: Float) throws -> MeshResource {
        let a = s / (2 * Float(3).squareRoot())
        let corners: [SIMD2<Float>] = [SIMD2(-s / 2, a), SIMD2(s / 2, a), SIMD2(0, -2 * a)]
        var outline: [SIMD2<Float>] = []
        for i in 0..<3 {
            let p = corners[i], prev = corners[(i + 2) % 3], next = corners[(i + 1) % 3]
            outline.append(p + simd_normalize(prev - p) * c)
            outline.append(p + simd_normalize(next - p) * c)
        }
        let inset = offset(outline, by: b)
        var builder = Builder()
        let y0 = -h / 2, y1 = -h / 2 + b, y2 = h / 2 - b, y3 = h / 2
        let center = SIMD3<Float>(0, 0, 0)
        func v(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }
        let n = outline.count
        for i in 0..<n {
            let j = (i + 1) % n
            builder.quad(v(outline[i], y1), v(outline[j], y1), v(outline[j], y2), v(outline[i], y2), inside: center)
            builder.quad(v(inset[i], y0), v(inset[j], y0), v(outline[j], y1), v(outline[i], y1), inside: center)
            builder.quad(v(outline[i], y2), v(outline[j], y2), v(inset[j], y3), v(inset[i], y3), inside: center)
        }
        for i in 1..<(n - 1) {
            builder.triangle(v(inset[0], y3), v(inset[i], y3), v(inset[i + 1], y3), inside: center)
            builder.triangle(v(inset[0], y0), v(inset[i], y0), v(inset[i + 1], y0), inside: center)
        }
        return try builder.mesh(named: "prism")
    }

    /// Insets a convex polygon by moving each edge inward by `d`.
    static func offset(_ poly: [SIMD2<Float>], by d: Float) -> [SIMD2<Float>] {
        let n = poly.count
        let centroid = poly.reduce(SIMD2<Float>(0, 0), +) / Float(n)
        var lines: [(SIMD2<Float>, SIMD2<Float>)] = []
        for i in 0..<n {
            let p = poly[i], q = poly[(i + 1) % n]
            let dir = simd_normalize(q - p)
            var normal = SIMD2<Float>(-dir.y, dir.x)
            if simd_dot(normal, centroid - p) < 0 { normal = -normal }
            lines.append((p + normal * d, dir))
        }
        return (0..<n).map { i in
            let (p1, d1) = lines[(i + n - 1) % n]
            let (p2, d2) = lines[i]
            let denom = d1.x * d2.y - d1.y * d2.x
            guard abs(denom) > 1e-6 else { return p2 }
            let t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / denom
            return p1 + d1 * t
        }
    }

    // MARK: Spring

    /// A coil spring of height 1 centred on the origin, axis on Y. Scale Y to compress.
    static func coil(radius r: Float, wire w: Float, turns: Float, segments: Int = 160, sides: Int = 10) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let u = Float(i) / Float(segments)
            let angle = u * turns * 2 * .pi
            let center = SIMD3<Float>(r * cos(angle), u - 0.5, r * sin(angle))
            let tangent = simd_normalize(SIMD3<Float>(-r * sin(angle) * turns * 2 * .pi, 1, r * cos(angle) * turns * 2 * .pi))
            let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
            let binormal = simd_normalize(simd_cross(tangent, radial))
            let normal0 = simd_normalize(simd_cross(binormal, tangent))
            for k in 0..<sides {
                let phi = Float(k) / Float(sides) * 2 * .pi
                let nrm = normal0 * cos(phi) + binormal * sin(phi)
                positions.append(center + nrm * w)
                normals.append(nrm)
                uvs.append(SIMD2(u * 8, Float(k) / Float(sides)))
            }
        }
        for i in 0..<segments {
            for k in 0..<sides {
                let a = UInt32(i * sides + k)
                let b = UInt32(i * sides + (k + 1) % sides)
                let c = UInt32((i + 1) * sides + (k + 1) % sides)
                let d = UInt32((i + 1) * sides + k)
                indices += [a, d, c, a, c, b]
            }
        }
        var desc = MeshDescriptor(name: "coil")
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        desc.primitives = .triangles(indices)
        return try MeshResource.generate(from: [desc])
    }

    // MARK: Hourglass

    /// A smooth surface of revolution about y. `profile` is (y, radius) pairs in
    /// order: a profile running up the axis faces away from it, the same profile
    /// reversed faces in toward it. Points with radius 0 close the surface on the axis.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int = 64, name: String) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let n = profile.count
        for (i, p) in profile.enumerated() {
            // Outward normal of the profile polyline, averaged across the vertex.
            let prev = profile[max(i - 1, 0)], next = profile[min(i + 1, n - 1)]
            let t = next - prev
            var n2 = SIMD2<Float>(t.x, -t.y)  // (dy, -dr) as (radial, vertical)
            if simd_length(n2) < 1e-6 { n2 = SIMD2(1, 0) }
            n2 = simd_normalize(n2)
            for k in 0...segments {
                let phi = Float(k) / Float(segments) * 2 * .pi
                positions.append(SIMD3(p.y * cos(phi), p.x, p.y * sin(phi)))
                normals.append(simd_normalize(SIMD3(n2.x * cos(phi), n2.y, n2.x * sin(phi))))
                uvs.append(SIMD2(Float(k) / Float(segments), Float(i) / Float(max(n - 1, 1))))
            }
        }
        let row = segments + 1
        for i in 0..<(n - 1) {
            for k in 0..<segments {
                let a = UInt32(i * row + k), b = UInt32(i * row + k + 1)
                let c = UInt32((i + 1) * row + k + 1), d = UInt32((i + 1) * row + k)
                indices += [a, d, c, a, c, b]
            }
        }
        var desc = MeshDescriptor(name: name)
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        desc.primitives = .triangles(indices)
        return try MeshResource.generate(from: [desc])
    }

    // MARK: Clay (BODY mannequin and its turntable)

    /// A smooth closed surface from rings stacked bottom to top. Each ring is a
    /// loop of `segments + 1` points (the last repeats the first) laid out
    /// with increasing angle the way `lathe` lays its rings out, so the outside
    /// faces out. Normals come from the neighbouring points; at a collapsed pole
    /// they point away from the surface's centre.
    static func surface(_ rings: [[SIMD3<Float>]], name: String,
                        uv planar: ((SIMD3<Float>) -> SIMD2<Float>)? = nil) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let n = rings.count
        let row = rings[0].count
        let segments = row - 1
        var centre = SIMD3<Float>(repeating: 0)
        for ring in rings { for p in ring.dropLast() { centre += p } }
        centre /= Float(max(n * segments, 1))
        for i in 0..<n {
            let ring = rings[i]
            for k in 0...segments {
                let p = ring[k]
                let du = ring[k == segments ? 1 : k + 1] - ring[k == 0 ? segments - 1 : k - 1]
                let dv = rings[min(i + 1, n - 1)][k] - rings[max(i - 1, 0)][k]
                // With rings laid out like `lathe`'s, dv × du points out of the surface.
                var nrm = simd_cross(dv, du)
                if simd_length(nrm) < 1e-9 { nrm = p - centre }
                normals.append(simd_length(nrm) < 1e-9 ? SIMD3(0, 1, 0) : simd_normalize(nrm))
                positions.append(p)
                uvs.append(planar?(p) ?? SIMD2(Float(k) / Float(max(segments, 1)), Float(i) / Float(max(n - 1, 1))))
            }
        }
        for i in 0..<(n - 1) {
            for k in 0..<segments {
                let a = UInt32(i * row + k), b = UInt32(i * row + k + 1)
                let c = UInt32((i + 1) * row + k + 1), d = UInt32((i + 1) * row + k)
                indices += [a, d, c, a, c, b]
            }
        }
        var desc = MeshDescriptor(name: name)
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        desc.primitives = .triangles(indices)
        return try MeshResource.generate(from: [desc])
    }

    /// A sculpted clay block centred on the origin: squircle cross-sections whose
    /// half-width runs from `bottom` to `top`, `depth` half-deep, `height` half-tall,
    /// with every edge rounded by `round` and an optional swell on its front (+z).
    /// Mirrors `shaped()` in design/mockups/body/mannequin.py.
    static func clayBlockRings(bottom: Float, top: Float, depth: Float, height: Float, front: Float = 0,
                               round: Float, segments: Int = 48) -> [[SIMD3<Float>]] {
        let r = min(round, height * 0.95, min(bottom, top, depth) * 0.95)
        let e: Float = 2.6
        var levels: [(y: Float, inset: Float)] = []
        let capRows = 7
        for j in 0...capRows {
            let t = -Float.pi / 2 + Float(j) / Float(capRows) * Float.pi / 2
            levels.append((-height + r * (1 + sin(t)), r * (1 - cos(t))))
        }
        let middleRows = 6
        for j in 1..<middleRows {
            levels.append((-height + r + (2 * height - 2 * r) * Float(j) / Float(middleRows), 0))
        }
        for j in 0...capRows {
            let t = Float(j) / Float(capRows) * Float.pi / 2
            levels.append((height - r + r * sin(t), r * (1 - cos(t))))
        }
        func power(_ v: Float) -> Float { (v < 0 ? -1 : 1) * pow(abs(v), 2 / e) }
        var rings: [[SIMD3<Float>]] = [Array(repeating: SIMD3(0, -height, 0), count: segments + 1)]
        for level in levels {
            let u = (level.y + height) / (2 * height)
            let a = max(bottom + (top - bottom) * u - level.inset, 0.0004)
            let b = max(depth - level.inset, 0.0004)
            let swell = front * depth * sin(Float.pi * u) * (1 - level.inset / max(r, 1e-6))
            rings.append((0...segments).map { k in
                let phi = Float(k % segments) / Float(segments) * 2 * Float.pi
                let c = cos(phi), s = sin(phi)
                let z = b * power(s) + (s > 0 ? swell * s * s : 0)
                return SIMD3(a * power(c), level.y, z)
            })
        }
        rings.append(Array(repeating: SIMD3(0, height, 0), count: segments + 1))
        return rings
    }

    static func clayBlock(bottom: Float, top: Float, depth: Float, height: Float, front: Float = 0,
                          round: Float, name: String) throws -> MeshResource {
        try surface(clayBlockRings(bottom: bottom, top: top, depth: depth, height: height, front: front, round: round), name: name)
    }

    /// A pillowy clay slab facing +z, for the face trays, keys and gauges: a
    /// rounded-rectangle outline of half sizes `halfWidth` × `halfHeight` and
    /// corner radius `corner`, `depth` thick from its flat back at z 0, every
    /// edge rolled by `bevel`, and its front swelling `puff` further at the middle.
    static func slabRings(halfWidth w: Float, halfHeight h: Float, depth d: Float, corner: Float, bevel: Float,
                          puff p: Float = 0, arc m: Int = 10) -> [[SIMD3<Float>]] {
        let c = min(corner, w, h)
        // A bevel as round as the corner would collapse the front outline to a line.
        let b = max(min(bevel, 0.85 * c, d / 2), 0)
        func outline(_ inset: Float, scale s: Float, z: Float) -> [SIMD3<Float>] {
            let r = max(c - inset, 0)
            let x = w - inset - r, y = h - inset - r
            var points: [SIMD3<Float>] = []
            // Counter-clockwise seen from the front, one quarter arc per corner.
            for (q, centre) in [SIMD2(x, y), SIMD2(-x, y), SIMD2(-x, -y), SIMD2(x, -y)].enumerated() {
                for j in 0...m {
                    let a = (Float(q) + Float(j) / Float(m)) * .pi / 2
                    let p2 = (centre + r * SIMD2(cos(a), sin(a))) * s
                    points.append(SIMD3(p2.x, p2.y, z))
                }
            }
            return points + [points[0]]
        }
        // Rings run front to back so, laid out counter-clockwise, they face out like `lathe`'s.
        var rings: [[SIMD3<Float>]] = []
        let capRows = 6
        for j in 0..<capRows {
            let s = Float(j) / Float(capRows)
            rings.append(outline(b, scale: s, z: d + p * pow(1 - s * s, 2)))
        }
        let bevelRows = 7
        for j in 0...bevelRows {
            let t = Float.pi / 2 * (1 - Float(j) / Float(bevelRows))
            rings.append(outline(b * (1 - cos(t)), scale: 1, z: d - b + b * sin(t)))
        }
        rings.append(outline(0, scale: 1, z: d / 2))
        for j in 0...bevelRows {
            let t = Float.pi / 2 * Float(j) / Float(bevelRows)
            rings.append(outline(b * (1 - cos(t)), scale: 1, z: b - b * sin(t)))
        }
        rings.append(outline(b, scale: 0.5, z: 0))
        rings.append(outline(b, scale: 0, z: 0))
        return rings
    }

    /// `centred` moves the slab so its walls straddle z 0, like a generated box.
    static func slab(halfWidth w: Float, halfHeight h: Float, depth d: Float, corner: Float, bevel: Float,
                     puff p: Float = 0, centred: Bool = false, name: String) throws -> MeshResource {
        var rings = slabRings(halfWidth: w, halfHeight: h, depth: d, corner: corner, bevel: bevel, puff: p)
        if centred { rings = rings.map { $0.map { $0 - SIMD3(0, 0, d / 2) } } }
        // Texture laid flat across the front, one tile per 50 pt, so grain never
        // streaks round the outline or swirls in to the middle.
        return try surface(rings, name: name, uv: { SIMD2($0.x * 2, $0.y * 2) })
    }

    /// A turned limb hanging from y 0 to −length: rounded ends, a swell near the
    /// top and two lathe-cut grooves just inside its ends, as (y, radius) for `lathe`.
    static func spindleProfile(length: Float, top: Float, bottom: Float, bulge: Float = 0, peak: Float = 0.3,
                               grooves: Bool = true) -> [SIMD2<Float>] {
        let n = 72
        return (0...n).map { i in
            let t = Float(i) / Float(n)  // 0 at the bottom, 1 at the top
            let base = bottom + (top - bottom) * t
            let swell = bulge * exp(-pow((t - (1 - peak)) / 0.28, 2))
            let end = min(t, 1 - t) / 0.08
            let cap = (max(0, 1 - pow(1 - min(end, 1), 2))).squareRoot()
            var groove: Float = 0
            if grooves && length > 0.06 {
                for g in [Float(0.13), 0.87] { groove += 0.09 * base * exp(-pow((t - g) * length / 0.0022, 2)) }
            }
            return SIMD2(-length + length * t, (base + swell - groove) * cap)
        }
    }

    /// An egg: an ellipsoid narrowing toward its lower end, like a mannequin head,
    /// as (y, radius) for `lathe` (round in plan; scale x and z on the entity).
    static func eggProfile(radius: Float, height: Float, taper: Float, steps: Int = 40) -> [SIMD2<Float>] {
        (0...steps).map { i in
            let t = -Float.pi / 2 + Float(i) / Float(steps) * Float.pi
            let y = height * sin(t)
            var r = radius * cos(t)
            if y < 0 { r *= 1 - taper * pow(-y / height, 1.5) }
            return SIMD2(y, max(r, 0))
        }
    }

    /// A ring of revolution from a closed cross-section loop of (y, radius)
    /// points listed counter-clockwise (outward, up, inward, down).
    static func ring(_ loop: [SIMD2<Float>], segments: Int = 64, name: String) throws -> MeshResource {
        try lathe(loop + [loop[0]], segments: segments, name: name)
    }

    /// The turntable's rim with a knurled grip round its outer wall: `ridges`
    /// raised ribs, each `rib` proud, over the middle of the wall.
    static func knurledRim(loop: [SIMD2<Float>], ridges: Int, rib: Float, name: String) throws -> MeshResource {
        let outer = loop.map(\.y).max() ?? 0
        let ys = loop.map(\.x)
        let low = ys.min() ?? 0, high = ys.max() ?? 0
        let segments = ridges * 6
        let closed = loop + [loop[0]]
        let rings: [[SIMD3<Float>]] = closed.map { p in
            // Only points on the outer wall, away from its rounded edges, carry ribs.
            let onWall = p.y >= outer - 1e-5 && p.x > low + (high - low) * 0.2 && p.x < high - (high - low) * 0.2
            return (0...segments).map { k in
                let phi = Float(k % segments) / Float(segments) * 2 * Float.pi
                let ribShape = max(0, cos(phi * Float(ridges)))
                let r = p.y + (onWall ? rib * ribShape * ribShape : 0)
                return SIMD3(r * cos(phi), p.x, r * sin(phi))
            }
        }
        return try surface(rings, name: name)
    }
}

