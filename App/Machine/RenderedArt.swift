import SwiftUI
import UIKit

/// Faces straight from Blender (Wei, 14 Oct 2026: "none of the objects should
/// be created from code, all straight from blender; coding controls the
/// reactions, feel and functionalities"). design/render/night_diet.py and
/// night_train.py render the Night scene, fitted to the face, in pieces:
/// backdrops, the jar in two layers, quick-add blocks, keys up and pressed,
/// gauges at 21 fills, food blocks, hero glyphs, the hourglass upright and
/// turned over, empty and full of sand (the grains show the full one through),
/// with its soft shadow. night-<face>.json
/// gives every picture's rect on the reference face (420 × 852 pt) and the
/// layout the behaviour needs. On a rendered face the app lays these pictures
/// out and moves them; it draws no objects of its own, and the face's
/// RealityKit content is hidden.
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
        /// Sliced pictures (the inset's): the corners to keep, in points (top, left, bottom, right).
        var slice: [CGFloat]?
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

    struct Glass: Decodable {
        /// The largest glass's rect, its centre (the flip turns about it), the
        /// foot of its base, and its height; short rests show it scaled down
        /// about the base to `minShare` of that.
        var rect: [CGFloat]
        var centre: [CGFloat]
        var baseY: CGFloat
        var maxHeight: CGFloat
        var minShare: CGFloat
        /// For the simulated sand (SandGlass): points per glass unit of radius,
        /// the glass's axis toward its A bulb in points per unit (pose a,
        /// largest glass), its inner wall as (z, r) from the neck out, and how
        /// far up one bulb a full load of sand reaches.
        var unitPoints: CGFloat?
        var axis: [CGFloat]?
        var inner: [[CGFloat]]?
        var sandLine: CGFloat?
    }

    struct TrainLayout: Decodable {
        var face: [CGFloat]
        var labels: [String: Label]
        var hero: Hero
        var coach: [CGFloat]
        var keys: [String: [CGFloat]]
        var glass: Glass
    }

    struct Ruler: Decodable {
        /// The plate, the first and last day's x, the line the ticks stand on, and the slider's top.
        var rect: [CGFloat]
        var track: [CGFloat]
        var baseY: CGFloat
        var cursorTop: CGFloat
    }

    struct BodyLayout: Decodable {
        var face: [CGFloat]
        var labels: [String: Label]
        var hero: Hero
        var ruler: Ruler
    }

    /// The inset's pictures have no layout of their own: they are sliced to fit.
    struct InsetLayout: Decodable {
        var face: [CGFloat]
    }

    private struct Meta<L: Decodable>: Decodable {
        var layout: L
        var sprites: [String: Sprite]
    }

    private static func load<L: Decodable>(_ name: String, as type: L.Type) -> Meta<L>? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Meta<L>.self, from: data)
    }

    private static let diet = load("night-diet", as: Layout.self)
    private static let train = load("night-train", as: TrainLayout.self)
    private static let inset = load("night-inset", as: InsetLayout.self)
    private static let body = load("night-body", as: BodyLayout.self)
    /// Every picture of every face, by name (TRAIN's hero uses DIET's glyphs).
    private static let sprites: [String: Sprite] = [diet?.sprites, train?.sprites, inset?.sprites, body?.sprites]
        .compactMap { $0 }
        .reduce(into: [:]) { all, more in all.merge(more) { a, _ in a } }

    @MainActor private static var images: [String: UIImage] = [:]

    /// Faces drawn from Blender, when their pictures are bundled. BODY's
    /// mannequin and turntable move too much to pre-render and stay live 3D, in
    /// front of BODY's rendered tray (`MachineScene` shows it on the face).
    static func on(_ face: PrismFace) -> Bool {
        guard Brutal.skin.clayUI else { return false }
        switch face {
        case .diet: return diet != nil
        case .train: return train != nil && diet != nil
        case .body: return body != nil && diet != nil
        }
    }

    /// The in-face inset's well, keys and text slots from Blender (design/render/night_inset.py).
    static var insetOn: Bool { Brutal.skin.clayUI && inset != nil }

    static var layout: Layout? { diet?.layout }
    static var trainLayout: TrainLayout? { train?.layout }
    static var bodyLayout: BodyLayout? { body?.layout }

    static func sprite(_ name: String) -> Sprite? { sprites[name] }

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
        let face = diet?.layout.face ?? [420, 852]
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
        diet != nil && text.allSatisfy { $0 == " " || glyphName($0).flatMap(sprite) != nil }
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

/// A sliced picture whose object fills the view: its corners (`slice`) keep
/// their size, its middle stretches (or tiles, for textured clay), and its
/// shadow spills past the view's edges.
struct SlicedSprite: View {
    let name: String
    var tile = false

    var body: some View {
        GeometryReader { geo in
            if let s = RenderedArt.sprite(name), let o = s.object, o.count == 4, let c = s.slice, c.count == 4,
               s.rect.count == 4, let image = RenderedArt.image(name) {
                let right = s.rect[2] - o[0] - o[2], bottom = s.rect[3] - o[1] - o[3]
                Image(uiImage: image)
                    .resizable(capInsets: EdgeInsets(top: c[0], leading: c[1], bottom: c[2], trailing: c[3]),
                               resizingMode: tile ? .tile : .stretch)
                    .frame(width: geo.size.width + o[0] + right, height: geo.size.height + o[1] + bottom)
                    .offset(x: -o[0], y: -o[1])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A blank inset key from Blender, up and pressed, the nearest rendered height to the view's.
struct RenderedInsetKey: View {
    let primary: Bool
    let pressed: Bool

    var body: some View {
        GeometryReader { geo in
            let name = primary ? "night-inset-primary"
                : "night-inset-key-\([40, 44, 56].min { abs(CGFloat($0) - geo.size.height) < abs(CGFloat($1) - geo.size.height) } ?? 44)"
            ZStack {
                SlicedSprite(name: name)
                SlicedSprite(name: name + "-down").opacity(pressed ? 1 : 0)
            }
        }
    }
}

/// The slot under a text field: the rendered one in the inset, a plain well otherwise.
struct InsetFieldWell: View {
    var body: some View {
        if RenderedArt.insetOn {
            SlicedSprite(name: "night-inset-field")
        } else {
            RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.1))
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
