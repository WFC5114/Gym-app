import Foundation

/// Energy and macros. Macros are optional: a quick-add calorie block records
/// unknown macros as unknown, never as zero and never estimated from calories.
struct Nutrients: Codable, Equatable, Hashable {
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    static let zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0)

    var hasMacros: Bool { protein != nil && carbs != nil && fat != nil }

    func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            kcal: kcal * factor,
            protein: protein.map { $0 * factor },
            carbs: carbs.map { $0 * factor },
            fat: fat.map { $0 * factor }
        )
    }
}

/// Where a food's numbers came from, shown next to every value.
enum FoodSource: String, Codable, Equatable, Hashable {
    case builtIn = "BUILT-IN"
    case openFoodFacts = "OPEN FOOD FACTS"
    case quickAdd = "QUICK ADD"
    case manual = "MANUAL"
}

/// A catalogue food: values per 100 g plus an optional named serving.
struct FoodItem: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var brand: String?
    var source: FoodSource
    var barcode: String?
    var per100g: Nutrients
    /// Grams in one serving, when the source defines it (an egg, a scoop, a bar).
    var servingGrams: Double?
    var servingLabel: String?

    func nutrients(grams: Double) -> Nutrients { per100g.scaled(by: grams / 100) }
}

/// One logged food. Stores absolute values so later catalogue changes never
/// rewrite history.
struct FoodEntry: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var loggedAt: Date
    var name: String
    var brand: String?
    var source: FoodSource
    /// Nil for quick-add calorie blocks.
    var grams: Double?
    var nutrients: Nutrients
    /// Kept so an entry can be edited by grams later.
    var per100g: Nutrients?

    static func quickAdd(kcal: Int, id: UUID = UUID(), at date: Date) -> FoodEntry {
        FoodEntry(
            id: id, loggedAt: date, name: "\(kcal) KCAL", brand: nil, source: .quickAdd,
            grams: nil, nutrients: Nutrients(kcal: Double(kcal), protein: nil, carbs: nil, fat: nil), per100g: nil
        )
    }

    static func food(_ item: FoodItem, grams: Double, id: UUID = UUID(), at date: Date) -> FoodEntry {
        FoodEntry(
            id: id, loggedAt: date, name: item.name, brand: item.brand, source: item.source,
            grams: grams, nutrients: item.nutrients(grams: grams), per100g: item.per100g
        )
    }
}

struct NutritionTargets: Codable, Equatable {
    var kcal: Double = 2450
    var protein: Double = 180
    var carbs: Double = 250
    var fat: Double = 80
}

/// Today's totals. Unknown macros are counted separately so the UI can say
/// "P 118 g + 2 entries unknown" instead of pretending.
struct DayTotals: Equatable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var entriesWithUnknownMacros = 0

    init(entries: [FoodEntry]) {
        for e in entries {
            kcal += e.nutrients.kcal
            if let p = e.nutrients.protein, let c = e.nutrients.carbs, let f = e.nutrients.fat {
                protein += p; carbs += c; fat += f
            } else {
                entriesWithUnknownMacros += 1
            }
        }
    }

    func remainingKcal(target: NutritionTargets) -> Double { target.kcal - kcal }
}
