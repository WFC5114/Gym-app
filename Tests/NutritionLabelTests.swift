import XCTest
@testable import GymApp

/// Reading a nutrition facts panel from recognised text (the camera's part runs only on a phone).
final class NutritionLabelTests: XCTestCase {
    func testEUPanelReadsThePer100GramColumn() throws {
        let lines = ["NUTRITION INFORMATION", "Typical values", "Per 100g", "Per 30g serving", "Energy", "1569kJ / 373kcal", "471kJ",
                     "Fat 6,5g 2,0g", "of which saturates 1,2g", "Carbohydrate 62g 18,6g", "of which sugars 1,1g", "Protein 13g 3,9g"]
        let label = try XCTUnwrap(NutritionLabel.parse(lines))
        XCTAssertEqual(label.kcal, 373)
        XCTAssertEqual(label.fat, 6.5)
        XCTAssertEqual(label.carbs, 62)
        XCTAssertEqual(label.protein, 13)
        XCTAssertTrue(label.per100g)
        XCTAssertFalse(label.basisAssumed)
        XCTAssertEqual(label.item().per100g.kcal, 373)
    }

    func testUSPanelPerServingBecomesPer100Grams() throws {
        let lines = ["Nutrition Facts", "8 servings per container", "Serving size 2/3 cup (55g)", "Amount per serving", "Calories 230",
                     "Total Fat 8g 10%", "Saturated Fat 1g", "Trans Fat 0g", "Sodium 160mg", "Total Carbohydrate 37g 13%", "Protein 3g"]
        let label = try XCTUnwrap(NutritionLabel.parse(lines))
        XCTAssertEqual(label.kcal, 230)
        XCTAssertEqual(label.fat, 8, "total fat, not saturated")
        XCTAssertEqual(label.servingGrams, 55)
        XCTAssertFalse(label.per100g)
        let item = label.item()
        XCTAssertEqual(item.per100g.kcal, 230 * 100 / 55, accuracy: 0.01)
        XCTAssertEqual(item.servingGrams, 55)
        XCTAssertEqual(item.source, .label)
    }

    func testPanelWithoutABasisSaysItIsAssumed() throws {
        let label = try XCTUnwrap(NutritionLabel.parse(["Calories", "120", "Fat 2 g", "Carbs 20 g", "Protein 5 g"]))
        XCTAssertTrue(label.basisAssumed)
        XCTAssertEqual(label.item().servingLabel, "PER 100 G ASSUMED")
    }

    func testTextWithoutEnergyIsNotALabel() {
        XCTAssertNil(NutritionLabel.parse(["hello", "world 12"]))
    }
}
