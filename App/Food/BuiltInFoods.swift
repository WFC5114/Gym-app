import Foundation

/// Whole foods that packaged-food databases cover poorly. Values per 100 g are
/// rounded from USDA FoodData Central (SR Legacy); the source tag says BUILT-IN
/// so they are never mistaken for a label.
enum BuiltInFoods {
    private static func item(_ name: String, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double,
                             serving: Double? = nil, label: String? = nil) -> FoodItem {
        FoodItem(id: "builtin:\(name)", name: name, brand: nil, source: .builtIn, barcode: nil,
                 per100g: Nutrients(kcal: kcal, protein: p, carbs: c, fat: f),
                 servingGrams: serving, servingLabel: label)
    }

    static let all: [FoodItem] = [
        item("Chicken breast, cooked", 165, 31, 0, 3.6, serving: 150, label: "1 FILLET"),
        item("Egg, whole", 143, 12.6, 0.7, 9.5, serving: 50, label: "1 LARGE EGG"),
        item("Egg white", 52, 10.9, 0.7, 0.2, serving: 33, label: "1 WHITE"),
        item("White rice, cooked", 130, 2.7, 28.2, 0.3, serving: 160, label: "1 CUP"),
        item("Brown rice, cooked", 123, 2.7, 25.6, 1.0, serving: 160, label: "1 CUP"),
        item("Oats, dry", 389, 16.9, 66.3, 6.9, serving: 40, label: "½ CUP"),
        item("Banana", 89, 1.1, 22.8, 0.3, serving: 118, label: "1 MEDIUM"),
        item("Apple", 52, 0.3, 13.8, 0.2, serving: 182, label: "1 MEDIUM"),
        item("Whole milk", 61, 3.2, 4.8, 3.3, serving: 244, label: "1 CUP"),
        item("Greek yogurt, plain, nonfat", 59, 10.2, 3.6, 0.4, serving: 170, label: "1 POT"),
        item("Salmon, cooked", 206, 22.1, 0, 12.4, serving: 150, label: "1 FILLET"),
        item("Beef mince 90% lean, cooked", 217, 26.1, 0, 11.7, serving: 113, label: "4 OZ"),
        item("Tofu, firm", 144, 17.3, 2.8, 8.7, serving: 126, label: "½ CUP"),
        item("Broccoli, raw", 34, 2.8, 6.6, 0.4, serving: 91, label: "1 CUP"),
        item("Sweet potato, baked", 90, 2.0, 20.7, 0.2, serving: 130, label: "1 MEDIUM"),
        item("Potato, baked", 93, 2.5, 21.2, 0.1, serving: 173, label: "1 MEDIUM"),
        item("White bread", 266, 7.6, 50.6, 3.3, serving: 30, label: "1 SLICE"),
        item("Olive oil", 884, 0, 0, 100, serving: 13.5, label: "1 TBSP"),
        item("Peanut butter", 588, 25.1, 20.0, 50.4, serving: 32, label: "2 TBSP"),
        item("Almonds", 579, 21.2, 21.6, 49.9, serving: 28, label: "1 OZ"),
        item("Avocado", 160, 2.0, 8.5, 14.7, serving: 150, label: "1 FRUIT"),
        item("Cheddar cheese", 403, 22.9, 3.1, 33.3, serving: 28, label: "1 OZ"),
        item("Pasta, cooked", 158, 5.8, 30.9, 0.9, serving: 140, label: "1 CUP"),
        item("Tuna, canned in water", 116, 25.5, 0, 0.8, serving: 142, label: "1 CAN"),
    ]

    static func search(_ query: String) -> [FoodItem] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return [] }
        return all.filter { item in words.allSatisfy { item.name.lowercased().contains($0) } }
    }
}
