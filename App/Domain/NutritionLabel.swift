import Foundation

/// Reads a nutrition facts panel from the text the camera recognised on it
/// (on-device text recognition, VisionKit: nothing leaves the phone). Handles
/// EU panels ("Energy 1046 kJ / 250 kcal", "per 100 g" first) and US panels
/// ("Calories 250", "Serving size 1 cup (240g)", values per serving).
///
/// Values per serving are turned into per 100 g using the serving's grams.
/// When the panel names neither "per 100 g" nor a serving weight, the values
/// are taken as per 100 g and the item says so in its serving label, so it is
/// never presented as more certain than it is.
struct NutritionLabel: Equatable {
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    /// The panel's own serving weight, when printed.
    var servingGrams: Double?
    /// True when the values read are per 100 g (printed so, or assumed).
    var per100g: Bool
    /// True when "per 100 g" was not printed and no serving weight was found.
    var basisAssumed: Bool

    /// The food the serving inset opens with.
    func item(name: String = "Scanned label") -> FoodItem {
        let factor = per100g ? 1 : 100 / (servingGrams ?? 100)
        let nutrients = Nutrients(kcal: kcal * factor, protein: protein.map { $0 * factor },
                                  carbs: carbs.map { $0 * factor }, fat: fat.map { $0 * factor })
        let label = basisAssumed ? "PER 100 G ASSUMED" : servingGrams.map { "1 SERVING · \(Int($0.rounded())) G" }
        return FoodItem(id: "label-\(Int(kcal))-\(Int(protein ?? -1))-\(Int(carbs ?? -1))-\(Int(fat ?? -1))", name: name, brand: nil,
                        source: .label, barcode: nil, per100g: nutrients, servingGrams: servingGrams, servingLabel: label)
    }

    /// Nil until at least the energy has been read.
    static func parse(_ lines: [String]) -> NutritionLabel? {
        let text = lines.map { $0.lowercased().replacingOccurrences(of: ",", with: ".") }
        let joined = text.joined(separator: "\n")

        var kcal: Double?
        for (i, line) in text.enumerated() {
            let window = line + " " + (i + 1 < text.count ? text[i + 1] : "")
            if let v = number(before: "kcal", in: line) ?? number(before: "kcal", in: window) { kcal = v; break }
            if line.contains("calories"), !line.contains("from fat"), let v = number(after: "calories", in: window) { kcal = v; break }
            if line.contains("energy") || line.contains("énergie"), let kj = number(before: "kj", in: window) { kcal = kj / 4.184; break }
        }
        guard let energy = kcal, energy > 0, energy < 2000 else { return nil }

        let protein = grams(for: ["protein", "proteins", "eiweiß", "protéines"], in: text)
        let carbs = grams(for: ["total carbohydrate", "carbohydrate", "carbohydrates", "carbs", "kohlenhydrate", "glucides"], in: text)
        let fat = grams(for: ["total fat", "fat", "fett", "matières grasses", "lipides"], in: text, excluding: ["saturated", "trans", "from fat", "of which"])

        let printedPer100 = joined.contains("per 100") || joined.contains("100 g") && joined.contains("per") || joined.contains("pour 100")
            || joined.contains("je 100") || joined.contains("100g")
        let serving = servingWeight(in: text)
        let per100 = printedPer100 || serving == nil
        return NutritionLabel(kcal: energy, protein: protein, carbs: carbs, fat: fat, servingGrams: serving,
                              per100g: per100, basisAssumed: !printedPer100 && serving == nil)
    }

    // MARK: Reading numbers

    private static let numberPattern = try! NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)")

    private static func numbers(in s: String) -> [(value: Double, range: Range<String.Index>)] {
        numberPattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let r = Range(m.range(at: 1), in: s), let v = Double(s[r]) else { return nil }
            return (v, r)
        }
    }

    /// The number printed just before `unit` ("250 kcal", "250kcal").
    private static func number(before unit: String, in s: String) -> Double? {
        guard let u = s.range(of: unit) else { return nil }
        return numbers(in: s).last { $0.range.upperBound <= u.lowerBound && s[$0.range.upperBound..<u.lowerBound].allSatisfy { $0 == " " } }?.value
    }

    /// The first number after `word` ("calories 250").
    private static func number(after word: String, in s: String) -> Double? {
        guard let w = s.range(of: word) else { return nil }
        return numbers(in: s).first { $0.range.lowerBound >= w.upperBound }?.value
    }

    /// Grams on the line naming one of `names` (or the next line, when the panel
    /// splits the name and its value), skipping sub-lines like "saturated fat".
    private static func grams(for names: [String], in text: [String], excluding: [String] = []) -> Double? {
        for (i, line) in text.enumerated() {
            guard names.contains(where: { line.contains($0) }), !excluding.contains(where: { line.contains($0) }) else { continue }
            let window = numbers(in: line).isEmpty && i + 1 < text.count ? text[i + 1] : line
            let start = names.compactMap { window.range(of: $0)?.upperBound }.max() ?? window.startIndex
            if let v = numbers(in: window).first(where: { $0.range.lowerBound >= start })?.value, v < 1000 { return v }
        }
        return nil
    }

    /// "Serving size 1 cup (240g)", "Portion 30 g", "per serving (40 g)".
    private static func servingWeight(in text: [String]) -> Double? {
        for line in text where line.contains("serving") || line.contains("portion") {
            for n in numbers(in: line) {
                let rest = line[n.range.upperBound...].drop { $0 == " " }
                if rest.hasPrefix("g") && !rest.hasPrefix("gr ") || rest.hasPrefix("ml") { return n.value }
            }
        }
        return nil
    }
}
