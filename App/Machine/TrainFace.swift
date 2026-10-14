import SwiftUI

/// TRAIN: the set on top, the hourglass in the middle, rest controls and
/// SET DONE at the bottom. The glass is only a picture of the logged rest;
/// the exact time is always printed.
struct TrainFace: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        let rail = model.rail
        let glass = model.glassGeometry
        let glassHeight = CGFloat(model.glassHeight.position)
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).modifier(FaceSwipe(model: model))

            FaceHeader(model: model, layout: layout, face: .train, caption: model.dataCaption)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                TrainHero(model: model, layout: layout, now: model.isFixture ? model.now() : context.date)
            }
            .frame(width: layout.heroRect.width, alignment: .leading)
            .position(x: layout.heroRect.midX, y: layout.heroRect.minY + 58 + layout.heroRect.height * 0.36)

            // Engraved rest length under the glass.
            VStack(spacing: 2) {
                Engraved(text: RestCoach.format(Int(model.glassSeconds)), size: 12, color: Ink.text(0.85))
                Engraved(text: model.activeRest == nil ? "NEXT REST" : "THIS REST", size: 8, color: Ink.text(0.45))
            }
            .position(x: glass.center(forHeight: glassHeight).x, y: glass.labelY)
            .accessibilityHidden(true)

            ImpactRays(model: model, face: .train)

            CoachNote(model: model)
                .frame(width: layout.contentWidth * HourglassGeometry.noteShare, alignment: .leading)
                .position(x: layout.side + layout.contentWidth * HourglassGeometry.noteShare / 2, y: layout.mechanismRect.minY + 70)

            TrainControls(model: model, rail: rail)
                .frame(width: rail.controls.width, height: rail.controls.height)
                .position(x: rail.controls.midX, y: rail.controls.midY)
        }
        .coordinateSpace(name: PrismFace.train.space)
    }
}

struct TrainHero: View {
    let model: MachineModel
    let layout: MachineLayout
    let now: Date

    var body: some View {
        let rest = model.activeRest
        Button { model.openInset(.exercise) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let rest {
                    let remaining = rest.remaining(at: now)
                    let text = Readout.clock(remaining)
                    hero(text, reference: "8:88")
                    Engraved(text: "REST AFTER SET \(rest.afterSet) · \(rest.exercise.uppercased())", size: 10.5, color: Ink.text(0.85))
                    if rest.addedSeconds > 0 {
                        Engraved(text: "SET \(RestCoach.format(rest.plannedSeconds)) + \(RestCoach.format(rest.addedSeconds)) ADDED", size: 10)
                    } else {
                        Engraved(text: "SET \(RestCoach.format(rest.plannedSeconds))", size: 10)
                    }
                } else if let ended = model.restJustEnded {
                    hero("GO", reference: "8:88")
                    Engraved(text: "RESTED \(RestCoach.format(ended.actualSeconds ?? ended.totalSeconds)) · SET \(model.nextSetNumber) NEXT", size: 10.5, color: Ink.text(0.85))
                    Engraved(text: "\(Readout.load(model.loadKg)) KG × \(model.reps) · \(model.exercise.name.uppercased())", size: 10)
                } else {
                    hero("\(Readout.load(model.loadKg))×\(model.reps)", reference: "88×8")
                    Engraved(text: "KG × REPS · SET \(model.nextSetNumber)", size: 10.5, color: Ink.text(0.85))
                    Engraved(text: model.exercise.name.uppercased() + " · " + model.exercise.bodyPart.label, size: 10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change exercise, load and reps")
        .accessibilityIdentifier("train.hero")
    }

    private func hero(_ text: String, reference: String) -> some View {
        let size = TypeKit.heroSize(for: text, reference: reference, screenWidth: layout.size.width,
                                    fraction: model.heroFraction, maxWidth: layout.contentWidth)
        return Text(text)
            .font(TypeKit.display(size))
            .tracking(TypeKit.heroTracking * size)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .glyphs3D(model: model, face: .train, text: text, size: size)
    }
}

/// The coach's recommendation for this body part, with the first reason.
struct CoachNote: View {
    let model: MachineModel

    var body: some View {
        let advice = model.advice
        VStack(alignment: .leading, spacing: 4) {
            Engraved(text: "COACH", size: 8.5, color: Ink.text(0.45))
            Engraved(text: "\(advice.bodyPart.label) \(RestCoach.format(advice.seconds))", size: 12, color: Ink.text(0.9), tracking: 0.8)
            ForEach(Array(advice.reasons.prefix(2).enumerated()), id: \.offset) { _, reason in
                Text(reason)
                    .font(TypeKit.label(8, weight: .semibold))
                    .foregroundStyle(Ink.text(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.activeRest == nil && model.plannedRest != advice.seconds {
                Button("USE \(RestCoach.format(advice.seconds))") { model.useAdvice() }
                    .buttonStyle(MachineButtonStyle(part: "train.useAdvice"))
                    .frame(height: 44)
                    .accessibilityIdentifier("train.useAdvice")
            }
        }
        // On clay faces the note sits on a low raised plate.
        .background { Color.clear.clayPart("train.coach", .panel).padding(-12) }
        .accessibilityElement(children: .contain)
    }
}

struct TrainControls: View {
    let model: MachineModel
    let rail: RailGeometry

    var body: some View {
        VStack(spacing: rail.controls.height * 0.08) {
            HStack(spacing: 10) {
                if model.activeRest != nil {
                    Button("+0:30 REST") { model.addRestTime() }
                        .buttonStyle(MachineButtonStyle(part: "train.add"))
                        .accessibilityIdentifier("train.addTime")
                    Button("END REST") { model.endRest() }
                        .buttonStyle(MachineButtonStyle(part: "train.end"))
                        .accessibilityIdentifier("train.endRest")
                } else {
                    Button("−0:15") { model.adjustPlannedRest(by: -RestLimits.step) }
                        .buttonStyle(MachineButtonStyle(part: "train.shorter"))
                        .accessibilityLabel("Shorter rest")
                        .accessibilityIdentifier("train.restShorter")
                    VStack(spacing: 2) {
                        Engraved(text: "REST", size: 8, color: Ink.text(0.45))
                        Engraved(text: RestCoach.format(model.plannedRest), size: 13, color: Ink.text(1), tracking: 0.8)
                    }
                    .frame(minWidth: 70)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rest \(model.plannedRest) seconds")
                    .accessibilityValue(RestCoach.format(model.plannedRest))
                    .accessibilityAdjustableAction { direction in
                        model.adjustPlannedRest(by: direction == .increment ? RestLimits.step : -RestLimits.step)
                    }
                    Button("+0:15") { model.adjustPlannedRest(by: RestLimits.step) }
                        .buttonStyle(MachineButtonStyle(part: "train.longer"))
                        .accessibilityLabel("Longer rest")
                        .accessibilityIdentifier("train.restLonger")
                }
            }
            .frame(height: rail.controls.height * 0.4)
            Button("SET DONE") { model.setDone() }
                .buttonStyle(MachineButtonStyle(primary: true, part: "train.setDone"))
                .accessibilityHint("Logs the set and flips the hourglass")
                .accessibilityIdentifier("train.setDone")
        }
    }
}
