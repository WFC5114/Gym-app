import SwiftUI

/// DIET drawn from Blender (see `RenderedArt`): every object on the face is a
/// rendered picture where the Blender layout put it. Code sets the changing
/// text at the layout's anchors and keeps the behaviour: taps, drags, springs,
/// sound, haptics and data.
struct RenderedDietFace: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        if let art = RenderedArt.layout {
            face(art, ArtPlacer(model: model, layout: layout, labels: art.labels))
        }
    }

    private func face(_ art: RenderedArt.Layout, _ place: ArtPlacer) -> some View {
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

            place.header(.diet, caption: model.dataCaption)
            hero(art, place, remaining: remaining, totals: totals, targets: targets)

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
            place.label("target.name", "TARGET", ArtPlacer.muted, tracking: 0.13)
            place.label("target.value", Readout.kcal(targets.kcal), ArtPlacer.ink)
                .accessibilityHidden(true)
            if model.isPileScaled {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(["BLOCKS", "SHRUNK", "TO FIT"], id: \.self) { line in
                        Text(line).font(ArtPlacer.font("bold", 7)).tracking(0.7).foregroundStyle(ArtPlacer.muted)
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

            keys(art, place)
        }
        .coordinateSpace(name: PrismFace.diet.space)
    }

    // MARK: Hero

    private func hero(_ art: RenderedArt.Layout, _ place: ArtPlacer, remaining: Double, totals: DayTotals,
                      targets: NutritionTargets) -> some View {
        let s = RenderedArt.scale(layout)
        let (size, origin) = place.hero(art.hero, widest: Readout.kcal(remaining))
        let gaugesBottom = (art.gauges["protein"].map { $0[1] + $0[3] } ?? 280) * s.height
        return ZStack(alignment: .topLeading) {
            place.heroGlyphs(Readout.kcal(model.heroKcal.position.rounded()), size: size, origin: origin)

            place.label("heroLabel", remaining >= 0 ? "KCAL LEFT" : "KCAL OVER TARGET", ArtPlacer.ink, tracking: 0.13)
            place.label("eaten", "\(Readout.kcal(totals.kcal)) of \(Readout.kcal(targets.kcal)) eaten", ArtPlacer.muted)
            macro(place, "protein", "PROTEIN", totals.protein, targets.protein)
            macro(place, "carbs", "CARBS", totals.carbs, targets.carbs)
            macro(place, "fat", "FAT", totals.fat, targets.fat)
            if totals.entriesWithUnknownMacros > 0 {
                let n = totals.entriesWithUnknownMacros
                place.label("unknownMacros", "+\(n) QUICK-ADD\(n == 1 ? "" : "S") WITHOUT MACROS", ArtPlacer.muted, tracking: 0.07)
            }

            // The hero, its lines and the gauges open today's food log.
            Button { model.openInset(.ledger) } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: layout.faceWidth - 2 * layout.side, height: gaugesBottom - origin.y + size * 0.9)
            .position(x: layout.faceWidth / 2, y: (origin.y - size * 0.9 + gaugesBottom) / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Readout.kcal(abs(remaining))) kilocalories \(remaining >= 0 ? "left" : "over target"). Protein \(Int(totals.protein)) of \(Int(targets.protein)) grams.")
            .accessibilityHint("Opens today's food log")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("diet.hero")
        }
    }

    /// "PROTEIN", "92 / 180 g" and the glass tube filled with clay to the share eaten (one of 21 renders).
    private func macro(_ place: ArtPlacer, _ key: String, _ name: String, _ eaten: Double, _ target: Double) -> some View {
        let share = target > 0 ? min(max(eaten / target, 0), 1) : 0
        let step = Int((share * 20).rounded())
        return ZStack(alignment: .topLeading) {
            place.label("macro.\(key).name", name, ArtPlacer.muted, tracking: 0.1)
            place.label("macro.\(key).value", "\(Int(eaten.rounded())) / \(Int(target)) g", ArtPlacer.ink)
            PlacedSprite(name: String(format: "night-gauge-%@-%02d", key, step), layout: layout)
        }
        .accessibilityHidden(true)
    }

    // MARK: Keys

    @ViewBuilder
    private func keys(_ art: RenderedArt.Layout, _ place: ArtPlacer) -> some View {
        if model.pending != nil {
            place.key("night-key-load", rect: art.keys["load"] ?? [], label: "Load") { model.loadPending() }
                .accessibilityIdentifier("intake.load")
            place.key("night-key-discard", rect: art.keys["discard"] ?? [], label: "Discard") { model.discardPending() }
        } else {
            place.key("night-key-log", rect: art.keys["log"] ?? [], label: "Log food") { model.openInset(.search) }
                .accessibilityIdentifier("intake.open")
            place.key("night-key-undo", rect: art.keys["undo"] ?? [], label: "Undo") { model.undoFood() }
                .disabled(!model.store.canUndoFood)
                .accessibilityIdentifier("diet.undo")
        }
    }
}
