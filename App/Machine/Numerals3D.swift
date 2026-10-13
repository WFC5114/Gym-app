import RealityKit
import UIKit

/// Hero numerals as real extruded, lit glyphs standing on the face, instead of
/// flat text drawn over the scene. Glyph meshes are generated once per size and
/// reused; changing a digit swaps a mesh, never regenerates one. The SwiftUI
/// text stays in place, invisible, for layout, hit testing and VoiceOver; it
/// reports its frame so the glyphs sit exactly where the text would be.
@MainActor
final class Numerals3D {
    let root = Entity()
    private let tilt = Entity()
    private var glyphs: [ModelEntity] = []
    private var cache: [Character: MeshResource] = [:]
    private var cachedSize: CGFloat = 0
    /// Moves glyph meshes so the digit "0" rests on the baseline.
    private var baselineOffset: Float = 0
    private let material: PhysicallyBasedMaterial

    /// Depth of the extrusion as a fraction of the font size.
    static let depth: CGFloat = 0.22
    /// Resting tilt (about x, then y) so the extrusion shows under the straight-on
    /// orthographic camera. Negative y brings the right end forward, never into the face.
    static let restTilt = SIMD2<Float>(-0.10, -0.12)

    init(material: PhysicallyBasedMaterial) {
        self.material = material
        root.addChild(tilt)
    }

    /// - Parameters:
    ///   - frame: the invisible text's frame in face-local points.
    ///   - punch: the hero punch spring; scales the number and kicks the tilt.
    func update(text: String, size: CGFloat, frame: CGRect, punch: Double, layout: MachineLayout) {
        if size != cachedSize { resetCache(size: size) }
        let font = TypeKit.displayUIFont(size)
        let tracking = TypeKit.heroTracking * size
        let baseline = frame.maxY + font.descender
        // Stand clear of the face whichever way the extrusion runs, so the
        // glyphs cast a contact shadow instead of sinking into the chassis.
        root.position = World.point(CGPoint(x: frame.minX, y: baseline), z: 10 + size * Self.depth, in: layout)
        let p = Float(punch)
        root.scale = SIMD3(repeating: 1 + 0.07 * p)
        tilt.orientation = simd_quatf(angle: Self.restTilt.x - 0.12 * p, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: Self.restTilt.y - 0.06 * p, axis: SIMD3(0, 1, 0))

        let characters = Array(text)
        while glyphs.count < characters.count {
            let entity = ModelEntity()
            tilt.addChild(entity)
            glyphs.append(entity)
        }
        var pen: CGFloat = 0
        for (i, entity) in glyphs.enumerated() {
            guard i < characters.count, let mesh = mesh(for: characters[i], size: size) else {
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            if entity.model?.mesh !== mesh {
                entity.model = ModelComponent(mesh: mesh, materials: [material])
            }
            entity.position = SIMD3(World.len(pen), baselineOffset, 0)
            let advance = NSAttributedString(string: String(characters[i]), attributes: [.font: font]).size().width
            pen += advance + tracking
        }
    }

    private func resetCache(size: CGFloat) {
        cache = [:]
        cachedSize = size
        for g in glyphs { g.model = nil }
        if let zero = mesh(for: "0", size: size) {
            baselineOffset = -zero.bounds.min.y
        }
    }

    private func mesh(for character: Character, size: CGFloat) -> MeshResource? {
        if let m = cache[character] { return m }
        guard character != " " else { return nil }
        let worldFont = TypeKit.displayUIFont(CGFloat(World.len(size)))
        let mesh = MeshResource.generateText(String(character), extrusionDepth: World.len(size * Self.depth), font: worldFont)
        cache[character] = mesh
        return mesh
    }
}
