import SwiftUI
import UIKit

/// Text, keys and the hero on a face drawn from Blender, at its layout's
/// anchors: the pictures are rendered, the changing words are set here in the
/// render's own Inter Display at the render's sizes.
@MainActor
struct ArtPlacer {
    let model: MachineModel
    let layout: MachineLayout
    let labels: [String: RenderedArt.Label]

    static let ink = Color(hex: 0xF1ECE4)
    static let muted = Color(hex: 0x8E8892)

    /// The render's own faces (Inter Display, bundled), at the layout's em sizes.
    static func font(_ weight: String, _ size: CGFloat) -> Font {
        .custom(weight == "bold" ? "InterDisplay-Bold" : "InterDisplay-Medium", fixedSize: size)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let s = RenderedArt.scale(layout)
        return CGPoint(x: x * s.width, y: y * s.height)
    }

    func anchor(_ key: String) -> RenderedArt.Label {
        labels[key] ?? RenderedArt.Label(x: 0, y: 0, size: 10, align: "left", weight: "bold")
    }

    /// A line of text with its left edge, right edge or centre, and its vertical centre, on the anchor.
    func label(_ key: String, _ text: String, _ color: Color, tracking: CGFloat = 0) -> some View {
        let a = anchor(key)
        let p = point(a.x, a.y)
        let alignment: Alignment = a.align == "right" ? .trailing : a.align == "center" ? .center : .leading
        let x = a.align == "right" ? p.x - 150 : a.align == "center" ? p.x : p.x + 150
        return Text(text)
            .font(Self.font(a.weight, a.size))
            .tracking(tracking * a.size)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(width: 300, alignment: alignment)
            .position(x: x, y: p.y)
    }

    /// Title, caption and the two turn buttons.
    func header(_ face: PrismFace, caption: String) -> some View {
        let nav = anchor("nav")
        let p = point(nav.x, nav.y)
        return ZStack(alignment: .topLeading) {
            label("title", face.title, Self.ink, tracking: 0.1)
                .accessibilityAddTraits(.isHeader)
            label("caption", caption, Self.muted, tracking: 0.07)
            HStack(spacing: 0) {
                navButton(face.next(), size: nav.size, step: 1, id: "face.next")
                navButton(face.previous(), size: nav.size, step: -1, id: "face.previous")
            }
            .fixedSize()
            .frame(width: 300, alignment: .trailing)
            // The 44 pt targets reach past the text; keep the text's right edge on the anchor.
            .position(x: p.x - 150 + 8, y: p.y)
        }
    }

    private func navButton(_ target: PrismFace, size: CGFloat, step: Int, id: String) -> some View {
        Button { model.rotate(by: step) } label: {
            Text(target.title)
                .font(Self.font("bold", size))
                .tracking(0.1 * size)
                .foregroundStyle(Self.muted)
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Turn to \(target.title.lowercased())")
        .accessibilityIdentifier(id)
    }

    /// Where a hero readout sits: the mockup's size, smaller only when the
    /// widest text it will show would run off the face; `origin` is the start
    /// of its baseline.
    func hero(_ hero: RenderedArt.Hero, widest: String) -> (size: CGFloat, origin: CGPoint) {
        let s = RenderedArt.scale(layout)
        let room = (layout.faceWidth - 2 * hero.x * s.width) / s.width
        let size = hero.fontSize * min(1, room / max(RenderedHero.width(widest, size: hero.fontSize), 1)) * s.width
        let capHeight = TypeKit.displayUIFont(size).capHeight
        return (size, CGPoint(x: hero.x * s.width, y: hero.centerY * s.height + capHeight / 2))
    }

    /// The hero in rendered glyphs, punched on its spring from its baseline's start.
    func heroGlyphs(_ text: String, size: CGFloat, origin: CGPoint) -> some View {
        RenderedHero(text: text, size: size, origin: origin)
            .scaleEffect(1 + 0.07 * model.heroPunch.position,
                         anchor: UnitPoint(x: origin.x / max(layout.faceWidth, 1), y: origin.y / max(layout.faceHeight, 1)))
    }

    /// A rendered key at its Blender rect: the up and pressed renders, its label
    /// baked in (or `printed` on it, for a label that changes).
    func key(_ name: String, rect: [CGFloat], label: String, printed: String? = nil,
             action: @escaping () -> Void) -> some View {
        let r = RenderedArt.rect(rect, layout)
        return Button(action: action) {
            if let printed {
                Text(printed)
                    .font(Self.font("bold", 10.5))
                    .tracking(1.2)
                    .foregroundStyle(Self.ink)
            }
        }
        .buttonStyle(RenderedKeyStyle(name: name, object: rect, size: r.size))
        .frame(width: r.width, height: max(r.height, 44))
        .position(x: r.midX, y: r.midY)
        .accessibilityLabel(label)
    }
}

/// A key drawn from its two renders, up and pressed, crossfaded on a damped spring.
struct RenderedKeyStyle: ButtonStyle {
    let name: String
    let object: [CGFloat]
    let size: CGSize

    func makeBody(configuration: Configuration) -> some View {
        RenderedKey(name: name, object: object, size: size, pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct RenderedKey<Printed: View>: View {
    let name: String
    let object: [CGFloat]
    let size: CGSize
    let pressed: Bool
    let label: Printed
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            ObjectSprite(name: name, object: object, size: size)
            ObjectSprite(name: name + "-down", object: object, size: size)
                .opacity(pressed ? 1 : 0)
            // A printed label sinks with the key.
            label.offset(y: pressed ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.interpolatingSpring(mass: 1, stiffness: 800, damping: 35), value: pressed)
    }
}

extension RenderedHero {
    /// The set width of a readout in the display font, as `RenderedHero` advances it.
    static func width(_ text: String, size: CGFloat) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: TypeKit.displayUIFont(size)]).size().width
    }
}
