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
}
