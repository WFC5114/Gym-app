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
        let carried = BodyObservation.carried(model.bodyHistory, upTo: index)
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

            Engraved(text: "SCHEMATIC · NOT A BODY SCAN", size: 8, color: Ink.text(0.4))
                .position(x: layout.faceWidth / 2, y: layout.mechanismRect.minY + 10)

            if let ghost = model.ghostFigure {
                GhostOutline(shape: ghost.shape, daysBack: ghost.daysBack, yaw: model.figureYaw,
                             geometry: FigureGeometry(layout: layout))
            }

            HStack(spacing: 22) {
                reading("FAT", carried.fat.map { String(format: "%.1f %%", $0) })
                reading("LEAN", carried.lean.map { String(format: "%.1f KG", $0) })
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
                // Vernier index: a finer scale riding on the cursor.
                let cx = w * CGFloat(model.scrubSpring.position) / CGFloat(count)
                for k in -5...5 {
                    let x = cx + CGFloat(k) * (w / CGFloat(count)) * 0.9
                    let rect = CGRect(x: x - 0.5, y: 0, width: 1, height: k == 0 ? size.height * 0.9 : size.height * 0.18)
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
        let rects = shape.torsoOutline(yaw: yaw).map { r in
            CGRect(origin: g.point(x: r.minX, y: r.maxY), size: CGSize(width: r.width * g.unit, height: r.height * g.unit))
        }
        let chest = rects[0]
        let outline = Path(roundedRect: chest, cornerRadius: g.unit * 0.06)
            .union(Path(roundedRect: rects[1], cornerRadius: g.unit * 0.08))
        let labelStart = CGPoint(x: g.feet.x + g.unit * 0.24, y: chest.minY - 26)
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

    private var label: String {
        daysBack == 7 ? "1 WEEK EARLIER" : daysBack % 7 == 0 ? "\(daysBack / 7) WEEKS EARLIER" : "\(daysBack) DAYS EARLIER"
    }
}
