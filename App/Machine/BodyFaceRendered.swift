import SwiftUI

/// BODY drawn from Blender (see `RenderedArt`, design/render/night_body.py):
/// the tray and the ruler's plate are one rendered picture that `MachineScene`
/// shows on the face, behind the live 3D mannequin and turntable (they move too
/// much to pre-render), with their soft shadows baked in. The ruler's ticks and
/// slider are rendered pieces laid out from the history. Code sets the text and
/// keeps the behaviour: scrubbing, the poke, springs, sound, haptics and data.
struct RenderedBodyFace: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        if let art = RenderedArt.bodyLayout {
            face(art, ArtPlacer(model: model, layout: layout, labels: art.labels))
        }
    }

    private func face(_ art: RenderedArt.BodyLayout, _ place: ArtPlacer) -> some View {
        let index = Int(model.bodyNumbers.target.rounded())
        let obs = model.bodyObservation
        let composition = model.bodyComposition
        let text = BodyFace(model: model, layout: layout)
        return ZStack(alignment: .topLeading) {
            // Empty face area: horizontal swipes turn the prism.
            Color.clear.contentShape(Rectangle()).modifier(FaceSwipe(model: model))

            place.header(.body, caption: model.bodyCaption)
            hero(art, place, obs: obs)
            ZStack(alignment: .topLeading) {
                place.label("line1", text.weeklyDelta(index: index), ArtPlacer.ink, tracking: 0.13)
                place.label("line2", text.dateLine(obs), ArtPlacer.muted)
            }
            .accessibilityElement(children: .combine)

            place.label("schematic", "SCHEMATIC · NOT A BODY SCAN", ArtPlacer.muted, tracking: 0.12)
            place.label("sources", text.shapeSources(composition), ArtPlacer.muted, tracking: 0.08)

            // Tap the mannequin: it flexes and the turntable gives a little swing.
            let figure = FigureGeometry(layout: layout)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: figure.unit * 0.5, height: figure.unit * 1.0)
                .position(figure.point(x: 0, y: 0.5))
                .onTapGesture { model.pokeFigure() }
                .accessibilityElement()
                .accessibilityLabel("Mannequin, shaped from your body readings")
                .accessibilityHint("Double-tap to make it flex")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("body.figure")

            if let ghost = model.ghostFigure {
                GhostOutline(shape: ghost.shape, daysBack: ghost.daysBack, yaw: model.figureYaw, geometry: figure)
            }

            reading(place, "fat", composition.fatIsEstimate ? "FAT · EST" : "FAT",
                    composition.fatPercent.map { String(format: composition.fatIsEstimate ? "≈ %.1f %%" : "%.1f %%", $0) })
            reading(place, "lean", "LEAN", composition.leanKg.map { String(format: "%.1f KG", $0) })
            reading(place, "source", "SOURCE", obs.map { $0.isScan ? "INBODY" : "SCALE" })

            ruler(art.ruler)
        }
        .coordinateSpace(name: PrismFace.body.space)
    }

    // MARK: Hero

    private func hero(_ art: RenderedArt.BodyLayout, _ place: ArtPlacer, obs: BodyObservation?) -> some View {
        let text = obs?.weightKg.map { String(format: "%.1f", $0) } ?? "—"
        let (size, origin) = place.hero(art.hero, widest: "88.8")
        let unit = place.anchor("unit")
        let end = origin.x + RenderedHero.width(text, size: size)
        return ZStack(alignment: .topLeading) {
            if RenderedArt.covers(text) {
                place.heroGlyphs(text, size: size, origin: origin)
            } else {
                Text(text)
                    .font(TypeKit.display(size))
                    .foregroundStyle(ArtPlacer.ink)
                    .fixedSize()
                    .position(x: origin.x + RenderedHero.width(text, size: size) / 2, y: origin.y - size * 0.36)
            }
            // KG sits on the hero's baseline, just after it.
            Text("KG")
                .font(ArtPlacer.font(unit.weight, unit.size))
                .tracking(0.1 * unit.size)
                .foregroundStyle(ArtPlacer.ink)
                .fixedSize()
                .frame(width: 100, alignment: .leading)
                .position(x: end + 8 + 50, y: origin.y - unit.size * 0.36)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(obs?.weightKg == nil ? "No weight this day" : "\(text) kilograms")
    }

    private func reading(_ place: ArtPlacer, _ key: String, _ title: String, _ value: String?) -> some View {
        ZStack(alignment: .topLeading) {
            place.label("reading.\(key).name", title, ArtPlacer.muted, tracking: 0.12)
            place.label("reading.\(key).value", value ?? "NO DATA", value == nil ? ArtPlacer.muted : ArtPlacer.ink, tracking: 0.05)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Ruler

    /// Ticks for every day (taller for week starts, tallest and brass on scan
    /// days), standing on the plate's groove; the slider rides the scrub spring
    /// with a vernier of fine ticks under it. Drag anywhere on the plate to scrub.
    private func ruler(_ r: RenderedArt.Ruler) -> some View {
        let s = RenderedArt.scale(layout)
        let history = model.bodyHistory
        let count = max(history.count - 1, 1)
        let x0 = (r.track.first ?? 46) * s.width, x1 = (r.track.last ?? 374) * s.width
        let base = r.baseY * s.height
        let x = { (i: Double) in x0 + (x1 - x0) * CGFloat(i) / CGFloat(count) }
        let cursor = model.scrubSpring.position
        let fineFoot = (r.cursorTop + 24) * s.height
        let plate = RenderedArt.rect(r.rect, layout)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(history.enumerated()), id: \.offset) { i, obs in
                StandingSprite(name: "night-body-tick-" + (obs.isScan ? "scan" : i % 7 == 0 ? "week" : "day"),
                               foot: CGPoint(x: x(Double(i)), y: base), scale: s)
            }
            ForEach([-5, -4, -3, -2, -1, 1, 2, 3, 4, 5], id: \.self) { k in
                StandingSprite(name: "night-body-fine", foot: CGPoint(x: x(cursor + Double(k) * 0.9), y: fineFoot), scale: s)
            }
            StandingSprite(name: "night-body-cursor", foot: CGPoint(x: x(cursor), y: base), scale: s)

            Color.clear
                .contentShape(Rectangle())
                .frame(width: plate.width, height: plate.height)
                .position(x: plate.midX, y: plate.midY)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(PrismFace.body.space))
                        .onChanged { value in model.scrubBody(toFraction: Double((value.location.x - x0) / max(x1 - x0, 1))) }
                )
                .accessibilityElement()
                .accessibilityLabel("History ruler")
                .accessibilityValue(model.bodyObservation.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "")
                .accessibilityAdjustableAction { direction in
                    let step = 1.0 / Double(count)
                    let f = model.scrubSpring.target / Double(count) + (direction == .increment ? step : -step)
                    model.scrubBody(toFraction: f)
                }
                .accessibilityIdentifier("body.ruler")
        }
    }
}

/// A rendered piece stood with the middle of its object's foot on `foot` (face points).
struct StandingSprite: View {
    let name: String
    let foot: CGPoint
    let scale: CGSize

    var body: some View {
        if let sprite = RenderedArt.sprite(name), let o = sprite.object, o.count == 4, sprite.rect.count == 4,
           let image = RenderedArt.image(name) {
            let w = sprite.rect[2] * scale.width, h = sprite.rect[3] * scale.height
            let left = foot.x - (o[0] + o[2] / 2) * scale.width
            let top = foot.y - (o[1] + o[3]) * scale.height
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
                .position(x: left + w / 2, y: top + h / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
