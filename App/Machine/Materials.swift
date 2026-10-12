import CoreGraphics
import RealityKit
import UIKit

/// Named material recipes. MONO is matte graphite (roughness 0.9, no metal):
/// planes read through broad soft light and grain, never through gloss.
@MainActor
struct MaterialKit {
    var chassis: PhysicallyBasedMaterial
    var plate: PhysicallyBasedMaterial
    var spring: PhysicallyBasedMaterial
    var weight: PhysicallyBasedMaterial
    var unknownWeight: PhysicallyBasedMaterial
    var glass: PhysicallyBasedMaterial
    var sand: PhysicallyBasedMaterial
    var body: PhysicallyBasedMaterial

    static func make(skin: Skin, grain: TextureResource?) -> MaterialKit {
        func matte(_ white: CGFloat, roughness: Float, metallic: Float = 0, grainScale: Float = 1) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(white: white, alpha: 1))
            m.roughness = .init(floatLiteral: roughness)
            m.metallic = .init(floatLiteral: metallic)
            m.specular = .init(floatLiteral: 0.25)
            if let grain {
                m.normal = .init(texture: .init(grain))
                m.textureCoordinateTransform = .init(scale: SIMD2(repeating: grainScale))
            }
            return m
        }
        let r = Float(skin.roughness)
        var glass = PhysicallyBasedMaterial()
        // Frosted, not polished: the captures showed hot specular spots on a 0.35 glass.
        glass.baseColor = .init(tint: UIColor(white: 0.7, alpha: 1))
        glass.roughness = .init(floatLiteral: 0.75)
        glass.metallic = .init(floatLiteral: 0)
        glass.specular = .init(floatLiteral: 0.08)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.1))
        glass.faceCulling = .none
        return MaterialKit(
            chassis: matte(0.05, roughness: r, grainScale: 3),
            plate: matte(0.09, roughness: r, grainScale: 4),
            spring: matte(0.16, roughness: 0.6, metallic: 0.15),
            weight: matte(0.86, roughness: 0.85, grainScale: 6),
            unknownWeight: matte(0.46, roughness: 0.9, grainScale: 6),
            glass: glass,
            sand: matte(0.66, roughness: 1.0, grainScale: 20),
            body: matte(0.12, roughness: 0.8)
        )
    }

    /// Fine surface grain as a tangent-space normal map, generated from a fixed
    /// seed so every build and every screenshot is identical.
    static func grainImage(size: Int = 256, seed: UInt32 = 0x5EED_1234, strength: Float = 0.9) -> CGImage? {
        var rng = seed
        func next() -> Float {
            rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
            return Float(rng) / Float(UInt32.max)
        }
        // Two octaves of value noise, wrapped so the texture tiles.
        var height = [Float](repeating: 0, count: size * size)
        for (cells, amp) in [(32, Float(0.6)), (128, Float(0.4))] {
            var lattice = [Float](repeating: 0, count: cells * cells)
            for i in lattice.indices { lattice[i] = next() }
            for y in 0..<size {
                for x in 0..<size {
                    let fx = Float(x) * Float(cells) / Float(size), fy = Float(y) * Float(cells) / Float(size)
                    let x0 = Int(fx) % cells, y0 = Int(fy) % cells
                    let x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells
                    let tx = fx - Float(Int(fx)), ty = fy - Float(Int(fy))
                    let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                    let a = lattice[y0 * cells + x0], b = lattice[y0 * cells + x1]
                    let c = lattice[y1 * cells + x0], d = lattice[y1 * cells + x1]
                    height[y * size + x] += amp * (a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy)
                }
            }
        }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let l = height[y * size + (x + size - 1) % size], r = height[y * size + (x + 1) % size]
                let u = height[((y + size - 1) % size) * size + x], d = height[((y + 1) % size) * size + x]
                var n = SIMD3<Float>((l - r) * strength, (u - d) * strength, 1)
                n = n / (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                let i = (y * size + x) * 4
                pixels[i] = UInt8((n.x * 0.5 + 0.5) * 255)
                pixels[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                pixels[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Environment for soft fill light: dim from above, black at the horizon and
    /// below, so the orthographic background (which looks along -Z) stays #000.
    static func environmentImage(width: Int = 256, height: Int = 128) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            // Row 0 is straight up; the horizon is the middle row.
            let elevation = 1 - Float(y) / Float(height / 2)
            let v = elevation > 0.25 ? min((elevation - 0.25) / 0.75, 1) : 0
            let level = UInt8(v * v * 70)
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = level; pixels[i + 1] = level; pixels[i + 2] = level; pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
