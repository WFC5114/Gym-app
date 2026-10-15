import SwiftUI

/// TRAIN drawn from Blender (see `RenderedArt`, design/render/night_train.py),
/// a rest timer (Wei, 15 Oct 2026: rests only, no sets): the tray and coach's
/// plate, the keys and the clay hourglass are rendered pictures where the
/// Blender layout put them. The glass is big and centred; it scales about its
/// base with the rest length and turns about its centre on the flip spring.
/// Its sand is real grains (`SandGlass`): the "full" render shows through
/// wherever a grain is, over the "empty" one. Code keeps the timer, the
/// springs, the sand, sound, haptics and data.
struct RenderedTrainFace: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        if let art = RenderedArt.trainLayout {
            face(art, ArtPlacer(model: model, layout: layout, labels: art.labels))
        }
    }

    private func face(_ art: RenderedArt.TrainLayout, _ place: ArtPlacer) -> some View {
        ZStack(alignment: .topLeading) {
            PlacedSprite(name: "night-train-backdrop", layout: layout)

            // Empty face area: horizontal swipes turn the prism.
            Color.clear.contentShape(Rectangle()).modifier(FaceSwipe(model: model))

            place.header(.train, caption: model.dataCaption)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                hero(art, place, now: model.isFixture ? model.now() : context.date)
            }

            coach(art, place)
            hourglass(art)
            ImpactRays(model: model, face: .train)

            keys(art, place)
        }
        .coordinateSpace(name: PrismFace.train.space)
    }

    // MARK: Hero

    private func hero(_ art: RenderedArt.TrainLayout, _ place: ArtPlacer, now: Date) -> some View {
        let lines = heroLines(now: now)
        let widest = [lines.text, lines.reference].max { RenderedHero.width($0, size: 100) < RenderedHero.width($1, size: 100) } ?? lines.text
        let (size, origin) = place.hero(art.hero, widest: widest)
        return ZStack(alignment: .topLeading) {
            if RenderedArt.covers(lines.text) {
                place.heroGlyphs(lines.text, size: size, origin: origin)
            } else {
                Text(lines.text)
                    .font(TypeKit.display(size))
                    .foregroundStyle(ArtPlacer.ink)
                    .fixedSize()
                    .position(x: origin.x + RenderedHero.width(lines.text, size: size) / 2, y: origin.y - size * 0.36)
            }
            place.label("line1", lines.first, ArtPlacer.ink, tracking: 0.13)
            place.label("line2", lines.second, ArtPlacer.muted)

            // The hero and its lines pick the body part the rest is for.
            let bottom = place.point(0, (art.labels["line2"]?.y ?? 212) + 10).y
            Button { model.openInset(.exercise) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: layout.faceWidth - 2 * layout.side, height: bottom - origin.y + size * 0.9)
                .position(x: layout.faceWidth / 2, y: (origin.y - size * 0.9 + bottom) / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(lines.text). \(lines.first.lowercased()). \(lines.second.lowercased())")
                .accessibilityHint("Choose the body part you are resting")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("train.hero")
        }
    }

    /// The hero readout (the rest clock), the reference it is sized for, and its two lines.
    private func heroLines(now: Date) -> (text: String, reference: String, first: String, second: String) {
        let part = model.exercise.bodyPart.label
        if let rest = model.activeRest {
            let second = rest.addedSeconds > 0
                ? "SET TO \(RestCoach.format(rest.plannedSeconds)) + \(RestCoach.format(rest.addedSeconds)) ADDED"
                : "SET TO \(RestCoach.format(rest.plannedSeconds))"
            return (Readout.clock(rest.remaining(at: now)), "8:88", "RESTING · \(rest.bodyPart.label) · REST \(rest.afterSet)", second)
        }
        if let ended = model.restJustEnded {
            return ("GO", "8:88", "RESTED \(RestCoach.format(ended.actualSeconds ?? ended.totalSeconds)) · \(ended.bodyPart.label)",
                    "NEXT: REST \(model.nextRestNumber) · \(RestCoach.format(model.plannedRest))")
        }
        return (RestCoach.format(model.plannedRest), "8:88", "NEXT REST · \(part) · REST \(model.nextRestNumber)", "TAP TO CHANGE BODY PART")
    }

    // MARK: Coach

    /// The advice printed on the rendered plate, with the USE key under it when it differs from the plan.
    private func coach(_ art: RenderedArt.TrainLayout, _ place: ArtPlacer) -> some View {
        let advice = model.advice
        let plate = RenderedArt.rect(art.coach, layout)
        let reasons = place.anchor("coach.reasons")
        let top = place.point(reasons.x, reasons.y).y - reasons.size * 0.7
        return ZStack(alignment: .topLeading) {
            place.label("coach.title", "\(advice.bodyPart.label) \(RestCoach.format(advice.seconds))", ArtPlacer.ink, tracking: 0.08)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(advice.reasons.prefix(2).enumerated()), id: \.offset) { _, reason in
                    Text(reason)
                        .font(ArtPlacer.font(reasons.weight, reasons.size))
                        .foregroundStyle(ArtPlacer.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: plate.maxX - 14 - place.point(reasons.x, 0).x, height: max(plate.maxY - 10 - top, 0), alignment: .topLeading)
            .clipped()
            .position(x: (place.point(reasons.x, 0).x + plate.maxX - 14) / 2, y: (top + plate.maxY - 10) / 2)

            if model.activeRest == nil && model.plannedRest != advice.seconds {
                place.key("night-train-key-use", rect: art.keys["use"] ?? [], label: "Use \(RestCoach.format(advice.seconds)) rest",
                          printed: "USE \(RestCoach.format(advice.seconds))") { model.useAdvice() }
                    .accessibilityIdentifier("train.useAdvice")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Hourglass

    private func hourglass(_ art: RenderedArt.TrainLayout) -> some View {
        let s = RenderedArt.scale(layout)
        let glass = art.glass
        let share = CGFloat(model.glassHeight.position) / max(model.glassGeometry.maxHeight, 1)
        let base = CGPoint(x: (glass.centre.first ?? 0) * s.width, y: glass.baseY * s.height)
        let centre = CGPoint(x: base.x, y: base.y + ((glass.centre.last ?? 0) * s.height - base.y) * share)
        // The flip turns the glass about the line of sight. Nearest its upright
        // seat the upright renders show, nearest the turned-over seat the turned
        // ones, each turned by what is left of the flip; at the half-turn they meet.
        let theta = model.glassAngle.position
        let seat = Int((theta / .pi).rounded())
        let turn = theta - Double(seat) * .pi
        let pose = seat % 2 == 0 ? "a" : "b"
        return ZStack(alignment: .topLeading) {
            scaled("night-hourglass-shadow", about: base, share: share, s: s)
                .opacity(1 - 0.5 * abs(sin(turn)))
            ZStack(alignment: .topLeading) {
                scaled("night-hourglass-\(pose)-empty", about: base, share: share, s: s)
                scaled("night-hourglass-\(pose)-full", about: base, share: share, s: s)
                    .mask(alignment: .topLeading) { sandMask(glass, centre: centre, share: share, s: s, turned: pose == "b") }
            }
            .frame(width: layout.faceWidth, height: layout.faceHeight, alignment: .topLeading)
            .rotationEffect(.radians(-turn), anchor: UnitPoint(x: centre.x / max(layout.faceWidth, 1), y: centre.y / max(layout.faceHeight, 1)))
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Hourglass, \(RestCoach.format(Int(model.glassSeconds))) rest")
    }

    /// Where the grains are, laid over the glass: the grid in the glass's own
    /// frame, its A end along the glass's axis (pointing down when turned over).
    @ViewBuilder
    private func sandMask(_ glass: RenderedArt.Glass, centre: CGPoint, share: CGFloat, s: CGSize, turned: Bool) -> some View {
        let _ = model.sandVersion
        if let sand = model.sand, let mask = sand.mask(), let axis = glass.axis, axis.count == 2, let unit = glass.unitPoints {
            let along = (axis[0] * axis[0] + axis[1] * axis[1]).squareRoot()
            let lean = atan2(Double(axis[0]), Double(-axis[1]))
            let cell = CGFloat(SandGlass.cell)
            Image(decorative: mask, scale: 1)
                .resizable()
                .interpolation(.medium)
                .luminanceToAlpha()
                .frame(width: CGFloat(sand.cols) * cell * unit * s.width * share,
                       height: CGFloat(sand.rows) * cell * along * s.height * share)
                .rotationEffect(.radians(lean + (turned ? .pi : 0)))
                .position(centre)
        }
    }

    /// A picture scaled by `share` about `point` (the glass's base), in face points.
    private func scaled(_ name: String, about point: CGPoint, share: CGFloat, s: CGSize) -> some View {
        let r = RenderedArt.sprite(name)?.rect ?? [0, 0, 0, 0]
        let x = point.x + (r[0] * s.width - point.x) * share
        let y = point.y + (r[1] * s.height - point.y) * share
        let w = r[2] * s.width * share, h = r[3] * s.height * share
        return Group {
            if let image = RenderedArt.image(name) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: w, height: h)
                    .position(x: x + w / 2, y: y + h / 2)
            }
        }
    }

    // MARK: Keys

    @ViewBuilder
    private func keys(_ art: RenderedArt.TrainLayout, _ place: ArtPlacer) -> some View {
        if let rest = model.activeRest {
            place.key("night-train-key-add", rect: art.keys["add"] ?? [], label: "Add 30 seconds of rest") { model.addRestTime() }
                .accessibilityIdentifier("train.addTime")
            ZStack(alignment: .topLeading) {
                place.label("added.name", "ADDED", ArtPlacer.muted, tracking: 0.13)
                place.label("added.value", "+" + RestCoach.format(rest.addedSeconds), ArtPlacer.ink, tracking: 0.05)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Added \(rest.addedSeconds) seconds")
            place.key("night-train-key-stop", rect: art.keys["stop"] ?? [], label: "End rest") { model.endRest() }
                .accessibilityIdentifier("train.endRest")
        } else {
            place.key("night-train-key-shorter", rect: art.keys["shorter"] ?? [], label: "Shorter rest") {
                model.adjustPlannedRest(by: -RestLimits.step)
            }
            .accessibilityIdentifier("train.restShorter")
            ZStack(alignment: .topLeading) {
                place.label("rest.name", "REST", ArtPlacer.muted, tracking: 0.13)
                place.label("rest.value", RestCoach.format(model.plannedRest), ArtPlacer.ink, tracking: 0.05)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest \(model.plannedRest) seconds")
            .accessibilityValue(RestCoach.format(model.plannedRest))
            .accessibilityAdjustableAction { direction in
                model.adjustPlannedRest(by: direction == .increment ? RestLimits.step : -RestLimits.step)
            }
            place.key("night-train-key-longer", rect: art.keys["longer"] ?? [], label: "Longer rest") {
                model.adjustPlannedRest(by: RestLimits.step)
            }
            .accessibilityIdentifier("train.restLonger")
            place.key("night-train-key-start", rect: art.keys["start"] ?? [], label: "Start rest") { model.startRest() }
                .accessibilityHint("Flips the hourglass and starts the rest")
                .accessibilityIdentifier("train.startRest")
        }
    }
}
