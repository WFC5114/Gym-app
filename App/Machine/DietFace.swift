import SwiftUI

/// DIET: remaining energy on top, the counterweight deck in the middle, the
/// loading rail and intake control at the bottom.
struct DietFace: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        let totals = model.totals
        let targets = model.targets
        let remaining = totals.remainingKcal(target: targets)
        let g = model.deckGeometry
        let rail = model.rail
        ZStack(alignment: .topLeading) {
            // Empty face area: horizontal swipes turn the prism.
            Color.clear.contentShape(Rectangle()).modifier(FaceSwipe(model: model))

            FaceHeader(model: model, layout: layout, face: .diet, caption: model.dataCaption)

            DietHero(model: model, layout: layout, remaining: remaining, totals: totals, targets: targets)
                .frame(width: layout.heroRect.width, alignment: .leading)
                .position(x: layout.heroRect.midX, y: layout.heroRect.minY + 58 + layout.heroRect.height * 0.36)

            // Engraved TARGET mark on the left post.
            HStack(spacing: 6) {
                Rectangle().fill(Color.white.opacity(0.55)).frame(width: 14, height: 1.5)
                Engraved(text: "TARGET \(Readout.kcal(targets.kcal))", size: 8.5, color: .white.opacity(0.55))
            }
            .position(x: g.centerX - g.deckWidth / 2 + 46, y: g.targetLineY)
            .accessibilityHidden(true)

            if model.isDragging {
                LandingGuide(rect: model.landingRect, active: model.isAnyBlockOverLanding)
            }

            Color.clear
                .frame(width: model.landingRect.width, height: model.landingRect.height)
                .position(x: model.landingRect.midX, y: model.landingRect.midY)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("Deck, \(Readout.kcal(totals.kcal)) kilocalories loaded")
                .accessibilityIdentifier("deck.landing")

            SlabLabels(model: model)

            if model.isStackScaled {
                Engraved(text: "STACK SCALED TO FIT", size: 8, color: .white.opacity(0.5))
                    .position(x: g.centerX, y: g.mech.minY + 8)
            }

            // Rail: quick-add blocks, or the formed food block.
            if let pending = model.pending {
                PendingBlockHandle(model: model, pending: pending, rail: rail)
            } else {
                ForEach(Deck.weights, id: \.self) { kcal in
                    QuickBlockHandle(model: model, kcal: kcal, rail: rail)
                }
            }
            FlyingBlockLabels(model: model)

            ImpactRays(model: model, face: .diet)

            DietControls(model: model, rail: rail)
                .frame(width: rail.buttonRow.width, height: rail.buttonRow.height)
                .position(x: rail.buttonRow.midX, y: rail.buttonRow.midY)
        }
        .coordinateSpace(name: PrismFace.diet.space)
    }
}

struct DietHero: View {
    let model: MachineModel
    let layout: MachineLayout
    let remaining: Double
    let totals: DayTotals
    let targets: NutritionTargets

    var body: some View {
        // The number counts to its new value on a spring instead of jumping.
        let shown = model.heroKcal.position.rounded()
        let text = Readout.kcal(shown)
        let size = TypeKit.heroSize(for: Readout.kcal(remaining), screenWidth: layout.size.width, fraction: model.heroFraction,
                                    maxWidth: layout.contentWidth)
        Button { model.openInset(.ledger) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(TypeKit.display(size))
                    .tracking(TypeKit.heroTracking * size)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .monospacedDigit()
                    .scaleEffect(1 + 0.07 * model.heroPunch.position, anchor: .bottomLeading)
                    // Lit 3D glyphs take its place; it keeps the layout and reports its frame.
                    .glyphs3D(model: model, face: .diet, text: text, size: size)
                Engraved(text: remaining >= 0 ? "KCAL LEFT" : "KCAL OVER TARGET", size: 11, color: .white.opacity(0.85))
                Engraved(text: "\(Readout.kcal(totals.kcal)) OF \(Readout.kcal(targets.kcal)) EATEN", size: 10)
                HStack(spacing: 14) {
                    macro("PROTEIN", totals.protein, targets.protein)
                    macro("CARBS", totals.carbs, targets.carbs)
                    macro("FAT", totals.fat, targets.fat)
                }
                .padding(.top, 4)
                if totals.entriesWithUnknownMacros > 0 {
                    Engraved(text: "+\(totals.entriesWithUnknownMacros) QUICK-ADD\(totals.entriesWithUnknownMacros == 1 ? "" : "S") WITHOUT MACROS",
                             size: 8.5, color: .white.opacity(0.45))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Readout.kcal(abs(remaining))) kilocalories \(remaining >= 0 ? "left" : "over target"). Protein \(Int(totals.protein)) of \(Int(targets.protein)) grams.")
        .accessibilityHint("Opens today's food log")
        .accessibilityIdentifier("diet.hero")
    }

    /// "PROTEIN 118/180 G": amount eaten against target, so the tag is never ambiguous.
    private func macro(_ name: String, _ eaten: Double, _ target: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Engraved(text: name, size: 8.5, color: .white.opacity(0.45))
            Engraved(text: "\(Int(eaten.rounded()))/\(Int(target)) G", size: 11, color: .white.opacity(0.9), tracking: 0.6)
        }
    }
}

/// Machined guide marks showing where a released block will land.
struct LandingGuide: View {
    let rect: CGRect
    let active: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.white.opacity(active ? 0.55 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            Engraved(text: active ? "RELEASE TO LOAD" : "DROP ON THE DECK", size: 9, color: .white.opacity(active ? 0.9 : 0.45))
                .position(x: rect.width / 2, y: 18)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Names on the slabs that are tall enough to carry one.
struct SlabLabels: View {
    let model: MachineModel

    var body: some View {
        ForEach(model.slabRects()) { item in
            if item.rect.height >= 13 {
                HStack(spacing: 6) {
                    Text(item.entry.name.uppercased())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(Readout.kcal(item.entry.nutrients.kcal))
                }
                .font(TypeKit.label(min(9.5, item.rect.height * 0.55), weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Color.black.opacity(0.78))
                .padding(.horizontal, 10)
                .frame(width: item.rect.width, height: item.rect.height)
                .position(x: item.rect.midX, y: item.rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

/// Labels and re-grab handles for blocks in the air.
struct FlyingBlockLabels: View {
    let model: MachineModel

    var body: some View {
        ForEach(model.blocks.filter { $0.phase != .resting || $0.entryID != nil }) { block in
            BlockFace(block: block)
                .frame(width: block.size.width, height: block.size.height)
                .scaleEffect(1 + 0.05 * block.lift.position)
                .rotationEffect(.radians(block.tilt.position))
                .position(block.position)
                .allowsHitTesting(block.phase != .held)
                .blockDrag(model: model) { point, time in
                    switch block.kind {
                    case .quick(let kcal): return model.grabQuick(kcal: kcal, at: point, time: time)
                    case .food: return model.grabPending(at: point, time: time)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

/// What is printed on a block: its energy and, for food, its name.
struct BlockFace: View {
    let block: FlyingBlock

    var body: some View {
        VStack(spacing: 1) {
            switch block.kind {
            case .quick(let kcal):
                Text("\(kcal)").font(TypeKit.display(15)).tracking(-0.6)
                Engraved(text: "KCAL", size: 7.5, color: .black.opacity(0.6), tracking: 1.2)
            case .food(let food):
                Text(food.item.name.uppercased())
                    .font(TypeKit.label(9.5, weight: .heavy))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                Engraved(text: "\(Readout.grams(food.grams)) G · \(Readout.kcal(food.nutrients.kcal)) KCAL", size: 8, color: .black.opacity(0.6), tracking: 0.8)
            }
        }
        .foregroundStyle(.black)
    }
}

/// Shared drag handling: touch-down grabs immediately (no long press), the
/// block follows the finger, release drops or springs back. Once a block owns
/// the touch it keeps it until release.
struct BlockDrag: ViewModifier {
    let model: MachineModel
    let grab: @MainActor (CGPoint, CFTimeInterval) -> UUID?
    @State private var holding: UUID?
    @GestureState private var active = false

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("face"))
                .updating($active) { _, state, _ in state = true }
                .onChanged { value in
                    let t = CACurrentMediaTime()
                    if holding == nil { holding = grab(value.startLocation, t) }
                    if let id = holding { model.dragBlock(id, to: value.location, time: t) }
                }
                .onEnded { _ in
                    if let id = holding { model.releaseBlock(id) }
                    holding = nil
                }
        )
        .onChange(of: active) { _, isActive in
            // A cancelled drag never calls onEnded: the block springs home and logs nothing.
            guard !isActive else { return }
            DispatchQueue.main.async {
                if let id = holding { model.cancelBlock(id) }
                holding = nil
            }
        }
    }
}

extension View {
    func blockDrag(model: MachineModel, grab: @escaping @MainActor (CGPoint, CFTimeInterval) -> UUID?) -> some View {
        modifier(BlockDrag(model: model, grab: grab))
    }
}

struct QuickBlockHandle: View {
    let model: MachineModel
    let kcal: Int
    let rail: RailGeometry

    var body: some View {
        let size = rail.quickBlockSize(kcal: kcal)
        let home = rail.quickBlockHome(kcal: kcal)
        let inFlight = model.blocks.contains { if case .quick(kcal) = $0.kind { return true }; return false }
        ZStack {
            if !inFlight {
                BlockFace(block: FlyingBlock(id: UUID(), kind: .quick(kcal), size: size, home: home, position: home))
            }
        }
        .frame(width: size.width, height: max(size.height, 44))
        .contentShape(Rectangle())
        .position(x: home.x, y: home.y - max(0, 44 - size.height) / 2)
        .blockDrag(model: model) { point, time in model.grabQuick(kcal: kcal, at: point, time: time) }
        .accessibilityElement()
        .accessibilityLabel("Quick add \(kcal) kilocalories")
        .accessibilityHint("Drag onto the deck. Records calories without macros.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.loadQuick(kcal: kcal) }
        .accessibilityIdentifier("rail.block.\(kcal)")
    }
}

struct PendingBlockHandle: View {
    let model: MachineModel
    let pending: PendingFood
    let rail: RailGeometry

    var body: some View {
        let kcal = pending.nutrients.kcal
        let size = rail.foodBlockSize(kcal: kcal)
        let home = rail.foodBlockHome(kcal: kcal)
        let inFlight = model.blocks.contains { $0.entryID == pending.entryID }
        ZStack {
            if !inFlight {
                BlockFace(block: FlyingBlock(id: UUID(), kind: .food(pending), size: size, home: home, position: home))
            }
        }
        .frame(width: size.width, height: max(size.height, 44))
        .contentShape(Rectangle())
        .position(home)
        .blockDrag(model: model) { point, time in model.grabPending(at: point, time: time) }
        .accessibilityElement()
        .accessibilityLabel("\(pending.item.name), \(Readout.grams(pending.grams)) grams, \(Readout.kcal(kcal)) kilocalories")
        .accessibilityHint("Drag onto the deck to log it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.loadPending() }
        .accessibilityIdentifier("rail.pending")
    }
}

struct DietControls: View {
    let model: MachineModel
    let rail: RailGeometry

    var body: some View {
        HStack(spacing: 10) {
            if model.pending != nil {
                Button("LOAD") { model.loadPending() }
                    .buttonStyle(MachineButtonStyle(primary: true))
                    .accessibilityIdentifier("intake.load")
                Button("DISCARD") { model.discardPending() }
                    .buttonStyle(MachineButtonStyle())
                    .frame(maxWidth: rail.controls.width * 0.34)
            } else {
                Button("LOG FOOD") { model.openInset(.search) }
                    .buttonStyle(MachineButtonStyle(primary: true))
                    .accessibilityIdentifier("intake.open")
                Button("UNDO") { model.undoFood() }
                    .buttonStyle(MachineButtonStyle())
                    .frame(maxWidth: rail.controls.width * 0.3)
                    .disabled(!model.store.canUndoFood)
                    .accessibilityIdentifier("diet.undo")
            }
        }
    }
}

/// Hit rays thrown out from a contact. Angles and lengths come from each
/// burst's seed, so no two bursts look the same; on DIET they fly up and out
/// of the deck, never into it. Driven by the burst spring, not a timeline.
struct ImpactRays: View {
    let model: MachineModel
    let face: PrismFace

    var body: some View {
        let bursts = model.bursts.filter { $0.face == face }
        Canvas { ctx, _ in
            for burst in bursts {
                var rng = burst.seed
                func next() -> Double {
                    rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
                    return Double(rng % 10_000) / 10_000
                }
                let p: Double = min(max(burst.progress.position, 0), 1.05)
                let count: Int = 9 + Int(next() * 6)
                let reach: Double = 54 + 96 * burst.strength
                let upward = face == .diet
                for k in 0..<count {
                    let slot: Double = (Double(k) + 0.2 + next() * 0.6) / Double(count)
                    let angle: Double = upward ? -Double.pi * (0.06 + 0.88 * slot) : 2 * Double.pi * slot
                    let length: Double = reach * (0.55 + 0.45 * next())
                    let outer = CGFloat(length * p)
                    let inner = CGFloat(length * p * p * 0.9)
                    let dir = CGVector(dx: CGFloat(cos(angle)), dy: CGFloat(sin(angle)))
                    var path = Path()
                    path.move(to: CGPoint(x: burst.origin.x + dir.dx * inner, y: burst.origin.y + dir.dy * inner))
                    path.addLine(to: CGPoint(x: burst.origin.x + dir.dx * outer, y: burst.origin.y + dir.dy * outer))
                    let fade: Double = max(0, 1 - p)
                    let heft: Double = 0.6 + 0.4 * burst.strength
                    let width = CGFloat(0.8 + 3.2 * fade * heft)
                    ctx.stroke(path, with: .color(.white.opacity(0.9 * fade)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
