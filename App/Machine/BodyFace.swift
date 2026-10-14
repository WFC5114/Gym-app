import SwiftUI

/// BODY: weight on top, the figurine on its turntable in the middle, the vernier
/// ruler at the bottom. Scrubbing moves date, values and figure together.
struct BodyFace: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        let rail = model.rail
        let index = Int(model.bodyNumbers.target.rounded())
        let obs = model.bodyObservation
        let composition = model.bodyComposition
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).modifier(FaceSwipe(model: model))

            FaceHeader(model: model, layout: layout, face: .body, caption: model.bodyCaption)

            VStack(alignment: .leading, spacing: 6) {
                let text = obs?.weightKg.map { String(format: "%.1f", $0) } ?? "—"
                let size = TypeKit.heroSize(for: text, reference: "88.8", screenWidth: layout.size.width,
                                            fraction: model.heroFraction, maxWidth: layout.contentWidth * 0.8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(text)
                        .font(TypeKit.display(size))
                        .tracking(TypeKit.heroTracking * size)
                        .foregroundStyle(.white)
                        .fixedSize()
                        .glyphs3D(model: model, face: .body, text: text, size: size)
                    Engraved(text: "KG", size: 14, color: Ink.text(0.85))
                }
                Engraved(text: weeklyDelta(index: index), size: 10.5, color: Ink.text(0.85))
                Engraved(text: dateLine(obs), size: 10)
            }
            .frame(width: layout.heroRect.width, alignment: .leading)
            .position(x: layout.heroRect.midX, y: layout.heroRect.minY + 58 + layout.heroRect.height * 0.36)
            .accessibilityElement(children: .combine)

            VStack(spacing: 3) {
                Engraved(text: "SCHEMATIC · NOT A BODY SCAN", size: 8, color: Ink.text(0.4))
                Engraved(text: shapeSources(composition), size: 7, color: Ink.text(0.35))
            }
            .position(x: layout.faceWidth / 2, y: layout.mechanismRect.minY + 14)

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
                GhostOutline(shape: ghost.shape, daysBack: ghost.daysBack, yaw: model.figureYaw,
                             geometry: FigureGeometry(layout: layout))
            }

            HStack(spacing: 22) {
                reading(composition.fatIsEstimate ? "FAT · EST" : "FAT",
                        composition.fatPercent.map { String(format: composition.fatIsEstimate ? "≈ %.1f %%" : "%.1f %%", $0) })
                reading("LEAN", composition.leanKg.map { String(format: "%.1f KG", $0) })
                reading("SOURCE", obs.map { $0.isScan ? "INBODY" : "SCALE" })
            }
            .position(x: layout.faceWidth / 2, y: layout.mechanismRect.maxY + 10)

            VernierRuler(model: model)
                .frame(width: rail.controls.width, height: rail.controls.height * 0.62)
                .position(x: rail.controls.midX, y: rail.controls.minY + rail.controls.height * 0.45)
        }
        .coordinateSpace(name: PrismFace.body.space)
    }

    private func reading(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 2) {
            Engraved(text: title, size: 8, color: Ink.text(0.45))
            Engraved(text: value ?? "NO DATA", size: 11, color: Ink.text(value == nil ? 0.4 : 0.9), tracking: 0.6)
        }
    }

    /// What the figure's shape comes from, estimates named as such.
    private func shapeSources(_ c: BodyComposition) -> String {
        var parts = [model.bodyUsesSample ? "SHAPE FROM SAMPLE DATA" : "SHAPE FROM INBODY + HEALTH"]
        if c.fatIsEstimate { parts.append("FAT FROM SCALE TREND (EST.)") }
        if !model.figureTilt.isEven { parts.append("TRAINING TILT (EST.)") }
        return parts.joined(separator: " · ")
    }

    private func weeklyDelta(index: Int) -> String {
        let h = model.bodyHistory
        guard h.indices.contains(index), let now = h[index].weightKg else { return "NO WEIGHT THIS DAY" }
        let back = max(index - 7, 0)
        guard let then = h[back].weightKg, back != index else { return "NOT ENOUGH HISTORY" }
        let d = now - then
        return String(format: "%@%.1f KG / WK", d >= 0 ? "+" : "−", abs(d))
    }

    private func dateLine(_ obs: BodyObservation?) -> String {
        guard let obs else { return "" }
        return obs.date.formatted(.dateTime.day().month(.abbreviated).year()).uppercased() + (obs.isScan ? " · SCAN DAY" : "")
    }
}

/// A ruler of days with taller ticks on scan days. Drag to scrub; each day
/// crossed clicks like an encoder detent.
struct VernierRuler: View {
    let model: MachineModel

    var body: some View {
        GeometryReader { geo in
            let history = model.bodyHistory
            let count = max(history.count - 1, 1)
            Canvas { ctx, size in
                let w = size.width
                for (i, obs) in history.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(count)
                    let h: CGFloat = obs.isScan ? size.height * 0.62 : (i % 7 == 0 ? size.height * 0.38 : size.height * 0.22)
                    let rect = CGRect(x: x - 0.75, y: size.height - h, width: 1.5, height: h)
                    ctx.fill(Path(rect), with: .color(.white.opacity(obs.isScan ? 0.9 : 0.4)))
                }
                // Vernier index: a finer scale riding on the cursor, kept below the
                // top of the scan ticks so it never reaches the readings above.
                let cx = w * CGFloat(model.scrubSpring.position) / CGFloat(count)
                let top = size.height * 0.3
                for k in -5...5 {
                    let x = cx + CGFloat(k) * (w / CGFloat(count)) * 0.9
                    let rect = CGRect(x: x - 0.5, y: top, width: 1, height: k == 0 ? size.height - top : size.height * 0.14)
                    ctx.fill(Path(rect), with: .color(.white.opacity(k == 0 ? 1 : 0.35)))
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in model.scrubBody(toFraction: Double(value.location.x / max(geo.size.width, 1))) }
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

/// Dashed outline of the torso some weeks before the scrubbed day, turned with
/// the figurine, with an engraved label on a leader line.
struct GhostOutline: View {
    let shape: FigureShape
    let daysBack: Int
    let yaw: Float
    let geometry: FigureGeometry

    var body: some View {
        let g = geometry
        let shapes = shape.torsoOutline(yaw: yaw)
        let chest = onFace(shapes.torso)
        let outline = Path(roundedRect: chest, cornerRadius: min(chest.width, g.unit * 0.16) * 0.42)
            .union(Path(ellipseIn: onFace(shapes.belly)))
        let labelStart = CGPoint(x: g.feet.x + g.unit * 0.2, y: chest.minY - 26)
        ZStack(alignment: .topLeading) {
            outline.stroke(Ink.text(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            Path { p in
                p.move(to: CGPoint(x: labelStart.x - 4, y: labelStart.y))
                p.addLine(to: CGPoint(x: chest.maxX - 6, y: chest.minY + 4))
            }
            .stroke(Ink.text(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Engraved(text: label, size: 8.5, color: Ink.text(0.9))
                .fixedSize()
                .frame(width: 160, alignment: .leading)
                .position(x: labelStart.x + 80, y: labelStart.y)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Dashed outline: torso \(label.lowercased())")
    }

    /// A figure-unit rect (y up) in face-local points.
    private func onFace(_ r: CGRect) -> CGRect {
        // The stand leans its top toward the viewer, so heights read a little shorter.
        let k = CGFloat(cos(FigureGeometry.lean))
        return CGRect(origin: geometry.point(x: r.minX, y: r.maxY * k),
                      size: CGSize(width: r.width * geometry.unit, height: r.height * geometry.unit * k))
    }

    private var label: String {
        daysBack == 7 ? "1 WEEK EARLIER" : daysBack % 7 == 0 ? "\(daysBack / 7) WEEKS EARLIER" : "\(daysBack) DAYS EARLIER"
    }
}
