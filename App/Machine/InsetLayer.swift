import SwiftUI

/// Secondary functions unfold inside the active face as a recessed inset with
/// an obvious CLOSE. The prism cannot turn while one is open. This layer keeps
/// keyboard avoidance, so with the keyboard up the inset shortens instead of
/// being covered (art direction §14: in-face accessible layout).
struct InsetLayer: View {
    let model: MachineModel

    var body: some View {
        let layout = model.layout
        if model.inset != .closed {
            VStack(spacing: 0) {
                Group {
                    switch model.inset {
                    case .search: FoodSearchInset(model: model)
                    case .serving(let item): ServingInset(model: model, item: item)
                    case .ledger: LedgerInset(model: model)
                    case .entry(let id): EntryInset(model: model, id: id)
                    case .exercise: ExerciseInset(model: model)
                    case .closed: EmptyView()
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(RenderedArt.insetOn ? 6 : 0)
                .background {
                    if RenderedArt.insetOn {
                        // The recessed graphite well from Blender, sliced to fit.
                        SlicedSprite(name: "night-inset-panel")
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(white: 0.035))
                            .overlay(
                                // A machined recess: dark top lip, faint lower edge.
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(LinearGradient(colors: [.black, Color(white: 0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                            )
                    }
                }
            }
            // Starts under the face header and covers the whole hero: a hero
            // cut in half by the inset edge read as a clipping bug (§14).
            .padding(.top, max(layout.faceTop - layout.safe.top, 0) + 52)
            .padding(.horizontal, layout.margin + 8)
            .padding(.bottom, 12)
            .environment(\.colorScheme, .dark)
        }
    }
}

struct InsetHeader: View {
    let title: String
    var back: (@MainActor () -> Void)?
    let close: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let back {
                Button(action: back) { Engraved(text: "‹ BACK", size: 11, color: .white.opacity(0.8)).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Back")
            }
            Engraved(text: title, size: 12, color: .white)
            Spacer()
            Button(action: close) { Engraved(text: "CLOSE ×", size: 11, color: .white.opacity(0.8)).frame(minWidth: 60, minHeight: 44) }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("inset.close")
        }
    }
}

// MARK: Food search

@MainActor
@Observable
final class FoodSearch {
    var query = ""
    var remote: [FoodItem] = []
    var phase: Phase = .idle
    enum Phase: Equatable { case idle, loading, done, offline, failed }
    let client = OpenFoodFacts()
    var isOffline = false

    func run(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, !isOffline else { remote = []; phase = isOffline ? .offline : .idle; return }
        phase = .loading
        do {
            remote = try await client.search(trimmed)
            phase = .done
        } catch OpenFoodFacts.Failure.offline {
            phase = .offline
        } catch is CancellationError {
        } catch {
            phase = .failed
        }
    }
}

struct FoodSearchInset: View {
    let model: MachineModel
    @State private var search = FoodSearch()
    @State private var scanning = false
    @State private var barcode = ""
    @State private var lookupMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InsetHeader(title: "LOG FOOD", close: { model.closeInset() })
            HStack(spacing: 8) {
                TextField("", text: $search.query, prompt: Text("SEARCH FOOD OR BRAND").foregroundStyle(.white.opacity(0.35)))
                    .font(TypeKit.label(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(InsetFieldWell())
                    .accessibilityIdentifier("intake.search")
                Button(scanning ? "STOP" : "SCAN") { scanning.toggle(); focused = false }
                    .buttonStyle(MachineButtonStyle())
                    .frame(width: 78, height: 44)
                    .accessibilityLabel(scanning ? "Stop scanning" : "Scan barcode")
                    .accessibilityIdentifier("intake.scan")
            }
            if scanning {
                BarcodePanel(barcode: $barcode, message: lookupMessage) { code in lookUp(code) }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let q = search.query
                    if q.trimmingCharacters(in: .whitespaces).isEmpty {
                        if !model.store.data.recentFoods.isEmpty {
                            section("RECENT")
                            ForEach(model.store.data.recentFoods) { row($0) }
                        }
                        section("BUILT-IN")
                        ForEach(BuiltInFoods.all.prefix(12)) { row($0) }
                    } else {
                        let local = BuiltInFoods.search(q) + model.store.data.recentFoods.filter { $0.name.lowercased().contains(q.lowercased()) }
                        if !local.isEmpty {
                            section("BUILT-IN AND RECENT")
                            ForEach(local) { row($0) }
                        }
                        section("OPEN FOOD FACTS")
                        switch search.phase {
                        case .loading: note("SEARCHING…")
                        case .offline: note("OFFLINE. BUILT-IN AND RECENT FOODS STILL WORK.")
                        case .failed: note("OPEN FOOD FACTS DIDN'T ANSWER. TRY AGAIN.")
                        case .done where search.remote.isEmpty: note("NOTHING FOUND. TRY A BRAND OR SCAN THE BARCODE.")
                        default: EmptyView()
                        }
                        ForEach(search.remote) { row($0) }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task(id: search.query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search.run(search.query)
        }
        .onAppear {
            search.isOffline = model.isFixture
            if !model.isFixture { focused = true }
        }
    }

    private func lookUp(_ code: String) {
        lookupMessage = "LOOKING UP \(code)…"
        Task {
            do {
                let item = try await OpenFoodFacts().product(barcode: code)
                lookupMessage = nil
                scanning = false
                model.openInset(.serving(item))
            } catch OpenFoodFacts.Failure.notFound {
                lookupMessage = "\(code) IS NOT IN OPEN FOOD FACTS. SEARCH BY NAME INSTEAD."
            } catch {
                lookupMessage = "COULDN'T REACH OPEN FOOD FACTS."
            }
        }
    }

    private func section(_ title: String) -> some View {
        Engraved(text: title, size: 9, color: .white.opacity(0.4)).padding(.top, 10).padding(.bottom, 2)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(TypeKit.label(10, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 6)
    }

    private func row(_ item: FoodItem) -> some View {
        Button { focused = false; model.openInset(.serving(item)) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.uppercased())
                    .font(TypeKit.label(12, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(rowDetail(item))
                    .font(TypeKit.label(9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose a serving")
    }

    private func rowDetail(_ item: FoodItem) -> String {
        let n = item.per100g
        var parts = ["\(Int(n.kcal.rounded())) KCAL/100 G"]
        parts.append("P \(Readout.grams(n.protein)) C \(Readout.grams(n.carbs)) F \(Readout.grams(n.fat))")
        parts.append([item.brand?.uppercased(), item.source.rawValue].compactMap { $0 }.joined(separator: " · "))
        return parts.joined(separator: " · ")
    }
}

// MARK: Serving

struct ServingInset: View {
    let model: MachineModel
    let item: FoodItem
    @State private var grams: Double = 100
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        let n = item.nutrients(grams: grams)
        VStack(alignment: .leading, spacing: 12) {
            InsetHeader(title: "SERVING", back: { model.openInset(.search) }, close: { model.closeInset() })
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.uppercased()).font(TypeKit.label(13, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                Engraved(text: [item.brand?.uppercased(), item.source.rawValue].compactMap { $0 }.joined(separator: " · "), size: 9)
            }
            HStack(alignment: .center, spacing: 10) {
                stepButton("−") { setGrams(grams - step) }
                    .accessibilityLabel("Less")
                VStack(spacing: 0) {
                    Text(Readout.grams(grams))
                        .font(TypeKit.display(40))
                        .tracking(-1.6)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: grams))
                        .lineLimit(1)
                        .minimumScaleFactor(1)
                    Engraved(text: "GRAMS", size: 9)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Readout.grams(grams)) grams")
                .accessibilityAdjustableAction { d in setGrams(grams + (d == .increment ? step : -step)) }
                stepButton("+") { setGrams(grams + step) }
                    .accessibilityLabel("More")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let s = item.servingGrams {
                        chip("\(item.servingLabel ?? "1 SERVING") · \(Readout.grams(s)) G") { setGrams(s) }
                        chip("2 × \(Readout.grams(s)) G") { setGrams(s * 2) }
                    }
                    chip("100 G") { setGrams(100) }
                    chip("50 G") { setGrams(50) }
                    TextField("", text: $typed, prompt: Text("EXACT G").foregroundStyle(.white.opacity(0.35)))
                        .keyboardType(.decimalPad)
                        .focused($typing)
                        .font(TypeKit.label(12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 40)
                        .padding(.horizontal, 8)
                        .background(InsetFieldWell())
                        .onChange(of: typed) { _, v in
                            if let g = Double(v.replacingOccurrences(of: ",", with: ".")), g > 0 { grams = min(g, 5000) }
                        }
                        .accessibilityLabel("Exact grams")
                }
            }
            HStack(spacing: 0) {
                readout("KCAL", Readout.kcal(n.kcal))
                readout("PROTEIN", Readout.grams(n.protein) + " G")
                readout("CARBS", Readout.grams(n.carbs) + " G")
                readout("FAT", Readout.grams(n.fat) + " G")
            }
            if !n.hasMacros {
                Engraved(text: "SOME MACROS MISSING FROM THE SOURCE: SHOWN AS ?", size: 8.5, color: .white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Button("FORM BLOCK") { model.formBlock(item: item, grams: grams) }
                .buttonStyle(MachineButtonStyle(primary: true))
                .frame(height: 52)
                .accessibilityHint("Puts the food on the rail. Drag it onto the deck to log it.")
                .accessibilityIdentifier("intake.formBlock")
        }
        .onAppear { grams = item.servingGrams ?? 100 }
    }

    private var step: Double { grams >= 100 ? 10 : 5 }

    private func setGrams(_ g: Double) {
        grams = min(max(g.rounded(), 1), 5000)
        typed = ""
        HapticEngine.shared.tick(intensity: 0.25, sharpness: 0.8)
        SoundEngine.shared.play(.detent, intensity: 0.5)
    }

    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MachineButtonStyle())
            .frame(width: 56, height: 56)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MachineButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 40)
    }

    private func readout(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Engraved(text: title, size: 8, color: .white.opacity(0.45))
            Engraved(text: value, size: 13, color: .white, tracking: 0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Ledger

/// The face's expanded readout: exact macros and every entry, editable.
struct LedgerInset: View {
    let model: MachineModel

    var body: some View {
        let totals = model.totals
        let t = model.targets
        VStack(alignment: .leading, spacing: 10) {
            InsetHeader(title: "TODAY", close: { model.closeInset() })
            HStack(spacing: 0) {
                total("KCAL", "\(Readout.kcal(totals.kcal))/\(Readout.kcal(t.kcal))")
                total("PROTEIN", "\(Int(totals.protein.rounded()))/\(Int(t.protein)) G")
                total("CARBS", "\(Int(totals.carbs.rounded()))/\(Int(t.carbs)) G")
                total("FAT", "\(Int(totals.fat.rounded()))/\(Int(t.fat)) G")
            }
            if totals.entriesWithUnknownMacros > 0 {
                Engraved(text: "MACROS EXCLUDE \(totals.entriesWithUnknownMacros) QUICK-ADD ENTRIES", size: 8.5, color: .white.opacity(0.5))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.today.isEmpty { Engraved(text: "NOTHING LOGGED YET", size: 10) }
                    ForEach(model.today.reversed()) { entry in
                        LedgerRow(model: model, entry: entry)
                    }
                }
            }
            Button("UNDO LAST CHANGE") { model.undoFood() }
                .buttonStyle(MachineButtonStyle())
                .frame(height: 46)
                .disabled(!model.store.canUndoFood)
        }
    }

    private func total(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Engraved(text: title, size: 8, color: .white.opacity(0.45))
            Engraved(text: value, size: 11, color: .white, tracking: 0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One logged food, opened by tapping its block in the jar.
struct EntryInset: View {
    let model: MachineModel
    let id: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InsetHeader(title: "FOOD", close: { model.closeInset() })
            if let entry = model.today.first(where: { $0.id == id }) {
                LedgerRow(model: model, entry: entry)
            } else {
                Engraved(text: "DELETED. UNDO BRINGS IT BACK.", size: 10)
            }
            Button("UNDO LAST CHANGE") { model.undoFood() }
                .buttonStyle(MachineButtonStyle())
                .frame(height: 46)
                .disabled(!model.store.canUndoFood)
            Button("ALL OF TODAY") { model.openInset(.ledger) }
                .buttonStyle(MachineButtonStyle())
                .frame(height: 46)
            Spacer(minLength: 0)
        }
    }
}

struct LedgerRow: View {
    let model: MachineModel
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name.uppercased()).font(TypeKit.label(11.5, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Engraved(text: Readout.kcal(entry.nutrients.kcal) + " KCAL", size: 11, color: .white, tracking: 0.4)
            }
            Text(detail).font(TypeKit.label(9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                if let grams = entry.grams, entry.per100g != nil {
                    Button("−10 G") { model.updateFood(entry.id, grams: max(grams - 10, 1)) }
                        .buttonStyle(MachineButtonStyle()).frame(height: 44)
                    Button("+10 G") { model.updateFood(entry.id, grams: grams + 10) }
                        .buttonStyle(MachineButtonStyle()).frame(height: 44)
                }
                Button("DELETE") { model.deleteFood(entry.id) }
                    .buttonStyle(MachineButtonStyle()).frame(height: 44)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let n = entry.nutrients
        let time = entry.loggedAt.formatted(date: .omitted, time: .shortened).uppercased()
        let grams = entry.grams.map { "\(Readout.grams($0)) G" } ?? "QUICK ADD"
        let macros = n.hasMacros ? "P \(Readout.grams(n.protein)) C \(Readout.grams(n.carbs)) F \(Readout.grams(n.fat))" : "MACROS UNKNOWN"
        return [time, grams, macros, entry.source.rawValue].joined(separator: " · ")
    }
}

// MARK: Exercise

struct ExerciseInset: View {
    let model: MachineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InsetHeader(title: "SET", close: { model.closeInset() })
            HStack(spacing: 10) {
                stepper("LOAD", Readout.load(model.loadKg) + " KG", minus: { model.adjustLoad(-2.5) }, plus: { model.adjustLoad(2.5) })
                stepper("REPS", "\(model.reps)", minus: { model.adjustReps(-1) }, plus: { model.adjustReps(1) })
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(BodyPart.allCases) { part in
                        Engraved(text: part.label, size: 9, color: .white.opacity(0.4)).padding(.top, 10)
                        ForEach(Exercise.library.filter { $0.bodyPart == part }) { ex in
                            Button { model.selectExercise(ex) } label: {
                                HStack {
                                    Text(ex.name.uppercased()).font(TypeKit.label(12, weight: .heavy))
                                    Spacer()
                                    if ex == model.exercise { Engraved(text: "SELECTED", size: 9, color: .white) }
                                }
                                .foregroundStyle(.white.opacity(ex == model.exercise ? 1 : 0.75))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(ex == model.exercise ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private func stepper(_ title: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Engraved(text: title, size: 8.5, color: .white.opacity(0.45))
            HStack(spacing: 6) {
                Button("−", action: minus).buttonStyle(MachineButtonStyle()).frame(width: 44, height: 44)
                Engraved(text: value, size: 13, color: .white, tracking: 0.4).frame(maxWidth: .infinity)
                Button("+", action: plus).buttonStyle(MachineButtonStyle()).frame(width: 44, height: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
