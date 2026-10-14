import SwiftUI
import UIKit

/// DIET drawn from Blender (see `RenderedArt`): every object on the face is a
/// rendered picture where the Blender layout put it. Code sets the changing
/// text at the layout's anchors and keeps the behaviour: taps, drags, springs,
/// sound, haptics and data.
struct RenderedDietFace: View {
    let model: MachineModel
    let layout: MachineLayout

    private static let ink = Color(hex: 0xF1ECE4)
    private static let muted = Color(hex: 0x8E8892)

    /// The render's own faces (Inter Display, bundled), at the layout's em sizes.
    static func font(_ weight: String, _ size: CGFloat) -> Font {
        .custom(weight == "bold" ? "InterDisplay-Bold" : "InterDisplay-Medium", fixedSize: size)
    }

    var body: some View {
        if let art = RenderedArt.layout {
            face(art)
        }
    }

    private func face(_ art: RenderedArt.Layout) -> some View {
        let totals = model.totals
        let targets = model.targets
        let remaining = totals.remainingKcal(target: targets)
        let rail = model.rail
        let g = model.jarGeometry
        let bob = CGSize(width: 0, height: CGFloat(model.jarBob.position))
        return ZStack(alignment: .topLeading) {
            PlacedSprite(name: "night-diet-backdrop", layout: layout)

            // Empty face area: horizontal swipes turn the prism.
            Color.clear.contentShape(Rectangle()).modifier(FaceSwipe(model: model))

            header(art)
            hero(art, remaining: remaining, totals: totals, targets: targets)

            // The jar: back layer, the pile, front layer, bobbing together.
            PlacedSprite(name: "night-jar-back", layout: layout, offset: bob)
            if model.isDragging {
                LandingGuide(rect: model.landingRect, active: model.isAnyBlockOverLanding)
            }
            Color.clear
                .frame(width: model.landingRect.width, height: model.landingRect.height)
                .position(x: model.landingRect.midX, y: model.landingRect.midY)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("Jar, \(Readout.kcal(totals.kcal)) of \(Readout.kcal(targets.kcal)) kilocalories in it")
                .accessibilityIdentifier("jar.landing")
            PieceLabels(model: model, rendered: true)
            PlacedSprite(name: "night-jar-front", layout: layout, offset: bob)
            label(art, "target.name", "TARGET", Self.muted, tracking: 0.13)
            label(art, "target.value", Readout.kcal(targets.kcal), Self.ink)
                .accessibilityHidden(true)
            if model.isPileScaled {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(["BLOCKS", "SHRUNK", "TO FIT"], id: \.self) { line in
                        Text(line).font(Self.font("bold", 7)).tracking(0.7).foregroundStyle(Self.muted)
                    }
                }
                .position(x: g.outer.maxX + 30, y: g.targetLineY)
                .accessibilityElement(children: .combine)
            }

            // Rail: quick-add blocks, or the formed food block.
            if let pending = model.pending {
                PendingBlockHandle(model: model, pending: pending, rail: rail)
            } else {
                ForEach(QuickAdd.weights, id: \.self) { kcal in
                    QuickBlockHandle(model: model, kcal: kcal, rail: rail)
                }
            }
            FlyingBlockLabels(model: model)
            ImpactRays(model: model, face: .diet)

            keys(art)
        }
        .coordinateSpace(name: PrismFace.diet.space)
    }

    // MARK: Text at the layout's anchors

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let s = RenderedArt.scale(layout)
        return CGPoint(x: x * s.width, y: y * s.height)
    }

    /// A line of text with its left (or right) edge and vertical centre on the anchor.
    private func label(_ art: RenderedArt.Layout, _ key: String, _ text: String, _ color: Color,
                       tracking: CGFloat = 0) -> some View {
        let a = art.labels[key] ?? RenderedArt.Label(x: 0, y: 0, size: 10, align: "left", weight: "bold")
        let p = point(a.x, a.y)
        let right = a.align == "right"
        return Text(text)
            .font(Self.font(a.weight, a.size))
            .tracking(tracking * a.size)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(width: 300, alignment: right ? .trailing : .leading)
            .position(x: right ? p.x - 150 : p.x + 150, y: p.y)
    }

    private func header(_ art: RenderedArt.Layout) -> some View {
        let nav = art.labels["nav"] ?? RenderedArt.Label(x: 392, y: 40, size: 11, align: "right", weight: "bold")
        let p = point(nav.x, nav.y)
        let face = PrismFace.diet
        return ZStack(alignment: .topLeading) {
            label(art, "title", face.title, Self.ink, tracking: 0.1)
                .accessibilityAddTraits(.isHeader)
            label(art, "caption", model.dataCaption, Self.muted, tracking: 0.07)
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

    // MARK: Hero

    private func hero(_ art: RenderedArt.Layout, remaining: Double, totals: DayTotals, targets: NutritionTargets) -> some View {
        let s = RenderedArt.scale(layout)
        let text = Readout.kcal(model.heroKcal.position.rounded())
        // The mockup's size, smaller only when a long number would run off the face.
        let widest = RenderedHero.width(Readout.kcal(remaining), size: art.hero.fontSize)
        let room = (layout.faceWidth - 2 * art.hero.x * s.width) / s.width
        let size = art.hero.fontSize * min(1, room / max(widest, 1)) * s.width
        let capHeight = TypeKit.displayUIFont(size).capHeight
        let origin = CGPoint(x: art.hero.x * s.width, y: art.hero.centerY * s.height + capHeight / 2)
        let punch = 1 + 0.07 * model.heroPunch.position
        return ZStack(alignment: .topLeading) {
            RenderedHero(text: text, size: size, origin: origin)
                .scaleEffect(punch, anchor: UnitPoint(x: origin.x / max(layout.faceWidth, 1), y: origin.y / max(layout.faceHeight, 1)))

            label(art, "heroLabel", remaining >= 0 ? "KCAL LEFT" : "KCAL OVER TARGET", Self.ink, tracking: 0.13)
            label(art, "eaten", "\(Readout.kcal(totals.kcal)) of \(Readout.kcal(targets.kcal)) eaten", Self.muted)
            macro(art, "protein", "PROTEIN", totals.protein, targets.protein)
            macro(art, "carbs", "CARBS", totals.carbs, targets.carbs)
            macro(art, "fat", "FAT", totals.fat, targets.fat)
            if totals.entriesWithUnknownMacros > 0 {
                let n = totals.entriesWithUnknownMacros
                label(art, "unknownMacros", "+\(n) QUICK-ADD\(n == 1 ? "" : "S") WITHOUT MACROS", Self.muted, tracking: 0.07)
            }

            // The hero, its lines and the gauges open today's food log.
            Button { model.openInset(.ledger) } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: layout.faceWidth - 2 * layout.side, height: (art.gauges["protein"].map { $0[1] + $0[3] } ?? 280) * s.height - origin.y + size * 0.9)
            .position(x: layout.faceWidth / 2,
                      y: (origin.y - size * 0.9 + (art.gauges["protein"].map { $0[1] + $0[3] } ?? 280) * s.height) / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Readout.kcal(abs(remaining))) kilocalories \(remaining >= 0 ? "left" : "over target"). Protein \(Int(totals.protein)) of \(Int(targets.protein)) grams.")
            .accessibilityHint("Opens today's food log")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("diet.hero")
        }
    }

    /// "PROTEIN", "92 / 180 g" and the glass tube filled with clay to the share eaten (one of 21 renders).
    private func macro(_ art: RenderedArt.Layout, _ key: String, _ name: String, _ eaten: Double, _ target: Double) -> some View {
        let share = target > 0 ? min(max(eaten / target, 0), 1) : 0
        let step = Int((share * 20).rounded())
        return ZStack(alignment: .topLeading) {
            label(art, "macro.\(key).name", name, Self.muted, tracking: 0.1)
            label(art, "macro.\(key).value", "\(Int(eaten.rounded())) / \(Int(target)) g", Self.ink)
            PlacedSprite(name: String(format: "night-gauge-%@-%02d", key, step), layout: layout)
        }
        .accessibilityHidden(true)
    }

    // MARK: Keys

    @ViewBuilder
    private func keys(_ art: RenderedArt.Layout) -> some View {
        if model.pending != nil {
            key(art, "load", label: "Load") { model.loadPending() }
                .accessibilityIdentifier("intake.load")
            key(art, "discard", label: "Discard") { model.discardPending() }
        } else {
            key(art, "log", label: "Log food") { model.openInset(.search) }
                .accessibilityIdentifier("intake.open")
            key(art, "undo", label: "Undo") { model.undoFood() }
                .disabled(!model.store.canUndoFood)
                .accessibilityIdentifier("diet.undo")
        }
    }

    /// A rendered key at its Blender rect: the up and pressed renders, with the label baked in.
    private func key(_ art: RenderedArt.Layout, _ id: String, label: String, action: @escaping () -> Void) -> some View {
        let r = RenderedArt.rect(art.keys[id] ?? [], layout)
        return Button(action: action) { EmptyView() }
            .buttonStyle(RenderedKeyStyle(name: "night-key-" + id, object: art.keys[id] ?? [], size: r.size))
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
        RenderedKey(name: name, object: object, size: size, pressed: configuration.isPressed)
    }
}

private struct RenderedKey: View {
    let name: String
    let object: [CGFloat]
    let size: CGSize
    let pressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            ObjectSprite(name: name, object: object, size: size)
            ObjectSprite(name: name + "-down", object: object, size: size)
                .opacity(pressed ? 1 : 0)
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
