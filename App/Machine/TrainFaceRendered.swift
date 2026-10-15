import SwiftUI

/// TRAIN drawn from Blender (see `RenderedArt`, design/render/night_train.py):
/// the tray and coach's plate, the keys and the clay hourglass are rendered
/// pictures where the Blender layout put them. The glass is one of 21 renders
/// by sand level, crossfaded as the rest runs, upright or turned over; it
/// scales about its base with the rest length and turns about its centre on
/// the flip spring. Code keeps the timer, the springs, sound, haptics and data.
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
            place.label("glass.value", RestCoach.format(Int(model.glassSeconds)), ArtPlacer.ink)
                .accessibilityHidden(true)
            place.label("glass.name", model.activeRest == nil ? "NEXT REST" : "THIS REST", ArtPlacer.muted, tracking: 0.13)
                .accessibilityHidden(true)
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

            // The hero and its lines change the exercise, load and reps.
            let bottom = place.point(0, (art.labels["line2"]?.y ?? 212) + 10).y
            Button { model.openInset(.exercise) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: layout.faceWidth - 2 * layout.side, height: bottom - origin.y + size * 0.9)
                .position(x: layout.faceWidth / 2, y: (origin.y - size * 0.9 + bottom) / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(lines.text). \(lines.first.lowercased()). \(lines.second.lowercased())")
                .accessibilityHint("Change exercise, load and reps")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("train.hero")
        }
    }

    /// The hero readout, the reference it is sized for, and its two lines.
    private func heroLines(now: Date) -> (text: String, reference: String, first: String, second: String) {
        if let rest = model.activeRest {
            let second = rest.addedSeconds > 0
                ? "SET \(RestCoach.format(rest.plannedSeconds)) + \(RestCoach.format(rest.addedSeconds)) ADDED"
                : "SET \(RestCoach.format(rest.plannedSeconds))"
            return (Readout.clock(rest.remaining(at: now)), "8:88",
                    "REST AFTER SET \(rest.afterSet) · \(rest.exercise.uppercased())", second)
        }
        if let ended = model.restJustEnded {
            return ("GO", "8:88", "RESTED \(RestCoach.format(ended.actualSeconds ?? ended.totalSeconds)) · SET \(model.nextSetNumber) NEXT",
                    "\(Readout.load(model.loadKg)) KG × \(model.reps) · \(model.exercise.name.uppercased())")
        }
        return ("\(Readout.load(model.loadKg))×\(model.reps)", "88×8", "KG × REPS · SET \(model.nextSetNumber)",
                model.exercise.name.uppercased() + " · " + model.exercise.bodyPart.label)
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
                        .fixedSize(horizontal: false, vertical: true)
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
        // Sand in the world-top bulb; before the half-turn the glass still holds it the old way up.
        let worldTop = model.aIsUp ? model.sandA.position : model.sandB.position
        let top = min(max(seat == model.glassParity ? worldTop : 1 - worldTop, 0), 1)
        let level = top * 20
        let low = Int(level.rounded(.down)), high = min(low + 1, 20)
        let mix = level - Double(low)
        return ZStack(alignment: .topLeading) {
            scaled("night-hourglass-shadow", about: base, share: share, s: s)
                .opacity(1 - 0.5 * abs(sin(turn)))
            ZStack(alignment: .topLeading) {
                scaled(String(format: "night-hourglass-%@-%02d", pose, low), about: base, share: share, s: s)
                    .opacity(1 - mix)
                scaled(String(format: "night-hourglass-%@-%02d", pose, high), about: base, share: share, s: s)
                    .opacity(mix)
            }
            .frame(width: layout.faceWidth, height: layout.faceHeight, alignment: .topLeading)
            .rotationEffect(.radians(-turn), anchor: UnitPoint(x: centre.x / max(layout.faceWidth, 1), y: centre.y / max(layout.faceHeight, 1)))
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Hourglass, \(RestCoach.format(Int(model.glassSeconds))) rest")
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
        if model.activeRest != nil {
            place.key("night-train-key-add", rect: art.keys["add"] ?? [], label: "Add 30 seconds of rest") { model.addRestTime() }
                .accessibilityIdentifier("train.addTime")
            place.key("night-train-key-end", rect: art.keys["end"] ?? [], label: "End rest") { model.endRest() }
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
        }
        place.key("night-train-key-setdone", rect: art.keys["setdone"] ?? [], label: "Set done") { model.setDone() }
            .accessibilityHint("Logs the set and flips the hourglass")
            .accessibilityIdentifier("train.setDone")
    }
}
