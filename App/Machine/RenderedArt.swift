import SwiftUI
import UIKit

/// DIET straight from Blender (Wei, 14 Oct 2026: "none of the objects should
/// be created from code, all straight from blender; coding controls the
/// reactions, feel and functionalities"). design/render/night_diet.py renders
/// the Night mockup scene, fitted to the face, in pieces: a backdrop, the jar
/// in two layers, quick-add blocks, keys up and pressed, gauges at 21 fills,
/// food blocks and hero glyphs, each 3 px per point with its soft shadow.
/// night-diet.json gives every picture's rect on the reference face (420 × 852
/// pt) and the layout the behaviour needs. On a rendered face the app lays
/// these pictures out and moves them; it draws no objects of its own, and the
/// face's RealityKit content is hidden.
enum RenderedArt {
    struct Sprite: Decodable {
        /// The picture's rect on the reference face, in points.
        var rect: [CGFloat]
        /// Food blocks: the block's own rect inside the picture's.
        var object: [CGFloat]?
        /// Glyphs: the character, its font size and its origin on the baseline.
        var character: String?
        var fontSize: CGFloat?
        var origin: [CGFloat]?
    }

    struct Label: Decodable {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var align: String
        var weight: String
    }

    struct Hero: Decodable {
        var x: CGFloat
        var centerY: CGFloat
        var fontSize: CGFloat
    }

    struct Jar: Decodable {
        var outer: [CGFloat]
        var interior: [CGFloat]
        var targetY: CGFloat
    }

    struct Layout: Decodable {
        var face: [CGFloat]
        var labels: [String: Label]
        var hero: Hero
        var jar: Jar
        var railY: CGFloat
        var quick: [String: [CGFloat]]
        var keys: [String: [CGFloat]]
        var gauges: [String: [CGFloat]]
    }

    private struct Meta: Decodable {
        var layout: Layout
        var sprites: [String: Sprite]
    }

    private static let meta: Meta? = {
        guard let url = Bundle.main.url(forResource: "night-diet", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }()

    @MainActor private static var images: [String: UIImage] = [:]

    /// Faces drawn from Blender. TRAIN follows; BODY's mannequin stays live 3D.
    static let faces: Set<PrismFace> = [.diet]

    /// The Night skin with its pictures bundled.
    static var isOn: Bool { Brutal.skin.clayUI && meta != nil }

    static func on(_ face: PrismFace) -> Bool { isOn && faces.contains(face) }

    static var layout: Layout? { meta?.layout }

    static func sprite(_ name: String) -> Sprite? { meta?.sprites[name] }

    @MainActor
    static func image(_ name: String) -> UIImage? {
        if let image = images[name] { return image }
        let image = UIImage(named: name)
        images[name] = image
        return image
    }

    /// Reference-face points to this device's face: the pictures were rendered
    /// for the iPhone 18 Pro Max face and stretch a little on other phones.
    static func scale(_ layout: MachineLayout) -> CGSize {
        let face = meta?.layout.face ?? [420, 852]
        return CGSize(width: layout.faceWidth / face[0], height: layout.faceHeight / face[1])
    }

    static func rect(_ r: [CGFloat], _ layout: MachineLayout) -> CGRect {
        guard r.count == 4 else { return .zero }
        let s = scale(layout)
        return CGRect(x: r[0] * s.width, y: r[1] * s.height, width: r[2] * s.width, height: r[3] * s.height)
    }

    static func glyphName(_ c: Character) -> String? {
        let names: [Character: String] = ["0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
                                          "6": "six", "7": "seven", "8": "eight", "9": "nine", ",": "comma", ".": "period",
                                          ":": "colon", "×": "times", "−": "minus", "-": "hyphen", "—": "emdash", "G": "G", "O": "O"]
        return names[c].map { "night-glyph-" + $0 }
    }

    /// Whether every character of a hero readout has a rendered glyph (spaces are just advance).
    static func covers(_ text: String) -> Bool {
        isOn && text.allSatisfy { $0 == " " || glyphName($0).flatMap(sprite) != nil }
    }

    static func foodName(_ tint: FoodTint, aspect: CGFloat) -> String {
        let kind: String
        switch tint {
        case .carbs: kind = "carbs"
        case .protein: kind = "protein"
        case .fat: kind = "fat"
        case .mixed: kind = "mixed"
        case .quick: kind = "quick"
        }
        let variant = [12, 16, 20].min { abs(CGFloat($0) / 10 - aspect) < abs(CGFloat($1) / 10 - aspect) } ?? 16
        return "night-food-\(kind)-\(variant)"
    }
}

/// A picture where Blender put it, optionally moved by `offset`.
struct PlacedSprite: View {
    let name: String
    let layout: MachineLayout
    var offset: CGSize = .zero

    var body: some View {
        if let s = RenderedArt.sprite(name), let image = RenderedArt.image(name) {
            let r = RenderedArt.rect(s.rect, layout)
            Image(uiImage: image)
                .resizable()
                .frame(width: r.width, height: r.height)
                .position(x: r.midX + offset.width, y: r.midY + offset.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A picture whose object (`object`, reference points) is drawn to fill
/// `size`, centred in the view; its shadow spills round it.
struct ObjectSprite: View {
    let name: String
    let object: [CGFloat]
    let size: CGSize

    var body: some View {
        if let s = RenderedArt.sprite(name), let image = RenderedArt.image(name), object.count == 4, s.rect.count == 4 {
            let kx = size.width / max(object[2], 1), ky = size.height / max(object[3], 1)
            let dx = (s.rect[0] + s.rect[2] / 2 - (object[0] + object[2] / 2)) * kx
            let dy = (s.rect[1] + s.rect[3] / 2 - (object[1] + object[3] / 2)) * ky
            Image(uiImage: image)
                .resizable()
                .frame(width: s.rect[2] * kx, height: s.rect[3] * ky)
                .offset(x: dx, y: dy)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A food block in rendered clay: the nearest of three proportions, scaled to fit.
struct FoodSprite: View {
    let tint: FoodTint
    let size: CGSize

    var body: some View {
        let name = RenderedArt.foodName(tint, aspect: size.width / max(size.height, 1))
        ObjectSprite(name: name, object: RenderedArt.sprite(name)?.object ?? [], size: size)
    }
}

/// A quick-add block as rendered, scaled to `size`.
struct QuickSprite: View {
    let kcal: Int
    let size: CGSize

    var body: some View {
        ObjectSprite(name: "night-quick-\(kcal)", object: RenderedArt.layout?.quick["\(kcal)"] ?? [], size: size)
    }
}

/// A hero readout set from rendered clay glyphs with the display font's own
/// advances, its baseline starting at `origin` (face points).
struct RenderedHero: View {
    let text: String
    let size: CGFloat
    let origin: CGPoint

    var body: some View {
        let font = TypeKit.displayUIFont(size)
        // Blender set the mockup's numeral with the font's own spacing.
        let tracking: CGFloat = 0
        ZStack(alignment: .topLeading) {
            ForEach(Array(placed(font: font, tracking: tracking).enumerated()), id: \.offset) { _, g in
                if let s = RenderedArt.sprite(g.name), let image = RenderedArt.image(g.name),
                   let o = s.origin, o.count == 2, s.rect.count == 4 {
                    let k = size / (s.fontSize ?? size)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: s.rect[2] * k, height: s.rect[3] * k)
                        .position(x: origin.x + g.x + (s.rect[0] + s.rect[2] / 2 - o[0]) * k,
                                  y: origin.y + (s.rect[1] + s.rect[3] / 2 - o[1]) * k)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placed(font: UIFont, tracking: CGFloat) -> [(name: String, x: CGFloat)] {
        var pen: CGFloat = 0
        var out: [(String, CGFloat)] = []
        for c in text {
            if let name = RenderedArt.glyphName(c) { out.append((name, pen)) }
            pen += NSAttributedString(string: String(c), attributes: [.font: font]).size().width + tracking
        }
        return out
    }
}
