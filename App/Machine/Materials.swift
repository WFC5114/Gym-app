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
    /// Hero numerals: bright and satin so the extrusion's faces separate by tone.
    var numeral: PhysicallyBasedMaterial
    /// The skin's colour plate per face, or empty for the bare chassis.
    var facePlates: [PhysicallyBasedMaterial]
    /// Food blocks by `FoodTint` (carbs, protein, fat, mixed, quick-add).
    var foods: [PhysicallyBasedMaterial]
    /// Claymorphism: the BODY mannequin, the TRAIN hourglass, the DIET jar and their hardware.
    var clay: ClayKit

    func food(_ tint: FoodTint) -> PhysicallyBasedMaterial {
        tint.rawValue < foods.count ? foods[tint.rawValue] : weight
    }

    static func make(skin: Skin, grain: TextureResource?, clayGrain: TextureResource? = nil) -> MaterialKit {
        let clay = ClayKit.make(grain: clayGrain)
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
        func object(_ hex: UInt32, dim: CGFloat = 1) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            let c = UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255 * dim, green: CGFloat((hex >> 8) & 0xFF) / 255 * dim,
                            blue: CGFloat(hex & 0xFF) / 255 * dim, alpha: 1)
            m.baseColor = .init(tint: c)
            m.roughness = .init(floatLiteral: 0.38)
            m.metallic = .init(floatLiteral: 0)
            m.specular = .init(floatLiteral: 0.5)
            m.clearcoat = .init(floatLiteral: 0.6)
            m.clearcoatRoughness = .init(floatLiteral: 0.25)
            return m
        }
        func plate(_ hex: UInt32) -> PhysicallyBasedMaterial {
            var m = object(hex)
            m.roughness = .init(floatLiteral: 0.62)
            m.clearcoat = .init(floatLiteral: 0.25)
            // No grain: on saturated colour the normal map read as crumpled paper.
            return m
        }
        var glass = PhysicallyBasedMaterial()
        // Frosted, not polished: the captures showed hot specular spots on a 0.35 glass.
        glass.baseColor = .init(tint: UIColor(white: 0.7, alpha: 1))
        glass.roughness = .init(floatLiteral: 0.75)
        glass.metallic = .init(floatLiteral: 0)
        glass.specular = .init(floatLiteral: 0.08)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.1))
        glass.faceCulling = .none
        if skin.glossy {
            var spring = matte(0.75, roughness: 0.22, metallic: 1)
            spring.specular = .init(floatLiteral: 0.6)
            var numeral = object(skin.objectColor)
            numeral.roughness = .init(floatLiteral: 0.3)
            return MaterialKit(
                chassis: matte(0.07, roughness: 0.7, grainScale: 3),
                plate: object(0x2A2A2E),
                spring: spring,
                weight: object(skin.objectColor),
                unknownWeight: object(0xFFD77A),
                glass: glass,
                // Fine pale sand, as in Wei's reference hourglass.
                sand: {
                    var m = object(0xE6DED0)
                    m.roughness = .init(floatLiteral: 0.92)
                    m.clearcoat = .init(floatLiteral: 0)
                    m.specular = .init(floatLiteral: 0.2)
                    return m
                }(),
                numeral: numeral,
                facePlates: (skin.faceColors ?? []).map(plate),
                // Golden carbs, roasted protein, pale fat, the skin's cream for mixed, amber quick-adds.
                foods: [0xE9B44C, 0xC9874A, 0xF6E7C8, skin.objectColor, 0xFFD77A].map { ClayKit.material($0, grain: clayGrain) },
                clay: clay
            )
        }
        return MaterialKit(
            chassis: matte(0.05, roughness: r, grainScale: 3),
            plate: matte(0.09, roughness: r, grainScale: 4),
            spring: matte(0.16, roughness: 0.6, metallic: 0.15),
            weight: matte(0.86, roughness: 0.85, grainScale: 6),
            unknownWeight: matte(0.46, roughness: 0.9, grainScale: 6),
            glass: glass,
            sand: matte(0.66, roughness: 1.0, grainScale: 20),
            numeral: {
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: UIColor(white: 0.93, alpha: 1))
                m.roughness = .init(floatLiteral: 0.42)
                m.metallic = .init(floatLiteral: 0)
                m.specular = .init(floatLiteral: 0.45)
                m.clearcoat = .init(floatLiteral: 0.5)
                m.clearcoatRoughness = .init(floatLiteral: 0.3)
                return m
            }(),
            facePlates: [],
            foods: [matte(0.78, roughness: 0.85, grainScale: 6), matte(0.62, roughness: 0.85, grainScale: 6),
                    matte(0.94, roughness: 0.85, grainScale: 6), matte(0.86, roughness: 0.85, grainScale: 6),
                    matte(0.46, roughness: 0.9, grainScale: 6)],
            clay: clay
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
    /// The baked softbox studio (design/assets/studio_env.py), bundled as a PNG.
    static func studioImage() -> CGImage? {
        UIImage(named: "studio-env")?.cgImage
    }

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

/// Claymorphism (Wei, 14 Oct 2026): every object a solid colour with a soft
/// satin sheen and a fine pressed surface, like the clay mockup
/// (design/mockups/body/mannequin.py, look `clay`). Hard objects stay hard:
/// the look is clay, the motion is rigid.
@MainActor
struct ClayKit {
    /// Cream body pieces.
    var body: PhysicallyBasedMaterial
    /// Orange joints, cups and hinge cheeks.
    var joint: PhysicallyBasedMaterial
    /// Dark rust socket rings and seam cores.
    var socket: PhysicallyBasedMaterial
    /// Butter-yellow hardware: rims, screws, crank, plaque.
    var hardware: PhysicallyBasedMaterial
    /// Pale stand rod.
    var rod: PhysicallyBasedMaterial
    /// Violet dial.
    var dial: PhysicallyBasedMaterial
    /// Deep indigo plinth.
    var plinth: PhysicallyBasedMaterial
    /// Lilac dots and lettering on the dial.
    var tick: PhysicallyBasedMaterial
    /// Pale, dry hourglass sand.
    var sand: PhysicallyBasedMaterial
    /// Thick candy glass for the hourglass and the jar: clear, glossy, a faint
    /// white so its edges read. Back faces are culled: these are closed shells,
    /// so the near outside and the far inside of each wall show.
    var glass: PhysicallyBasedMaterial

    static func make(grain: TextureResource?) -> ClayKit {
        func clay(_ hex: UInt32, roughness: Float = 0.42, coat: Float = 0.3) -> PhysicallyBasedMaterial {
            material(hex, roughness: roughness, coat: coat, grain: grain)
        }
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(white: 0.97, alpha: 1))
        glass.roughness = .init(floatLiteral: 0.08)
        glass.metallic = .init(floatLiteral: 0)
        glass.specular = .init(floatLiteral: 0.7)
        glass.clearcoat = .init(floatLiteral: 0.6)
        glass.clearcoatRoughness = .init(floatLiteral: 0.05)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        glass.faceCulling = .back
        return ClayKit(body: clay(0xF2C38C), joint: clay(0xF0904E), socket: clay(0xB8703C, roughness: 0.55, coat: 0),
                       hardware: clay(0xFFD27A, roughness: 0.36), rod: clay(0xF4EEE6), dial: clay(0x8F5BF0, roughness: 0.5, coat: 0),
                       plinth: clay(0x2A1257, roughness: 0.5), tick: clay(0xB894FF, coat: 0.1),
                       sand: clay(0xFFF2D6, roughness: 0.8, coat: 0), glass: glass)
    }

    /// One clay colour: satin sheen and, with `grain`, a fine pressed surface.
    static func material(_ hex: UInt32, roughness: Float = 0.42, coat: Float = 0.3, grain: TextureResource?) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                                          blue: CGFloat(hex & 0xFF) / 255, alpha: 1))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        m.specular = .init(floatLiteral: 0.45)
        m.clearcoat = .init(floatLiteral: coat)
        m.clearcoatRoughness = .init(floatLiteral: 0.3)
        if let grain {
            m.normal = .init(texture: .init(grain))
            m.textureCoordinateTransform = .init(scale: SIMD2(repeating: 3))
        }
        return m
    }
}

