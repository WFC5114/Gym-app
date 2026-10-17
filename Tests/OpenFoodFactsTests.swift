import XCTest
@testable import GymApp

final class OpenFoodFactsTests: XCTestCase {
    func testParsesProductWithNumbersAndStrings() throws {
        let json = """
        {"code":"3017624010701","status":1,"product":{"product_name":"Nutella","brands":"Ferrero, Nutella",
         "serving_quantity":"15","serving_size":"15 g",
         "nutriments":{"energy-kcal_100g":539,"proteins_100g":"6.3","carbohydrates_100g":57.5,"fat_100g":30.9}}}
        """
        let item = try XCTUnwrap(OpenFoodFacts.parseProduct(Data(json.utf8)))
        XCTAssertEqual(item.name, "Nutella")
        XCTAssertEqual(item.brand, "Ferrero")
        XCTAssertEqual(item.barcode, "3017624010701")
        XCTAssertEqual(item.per100g.kcal, 539)
        XCTAssertEqual(item.per100g.protein, 6.3)
        XCTAssertEqual(item.servingGrams, 15)
        XCTAssertEqual(item.nutrients(grams: 15).kcal, 80.85, accuracy: 0.001)
    }

    func testMissingMacrosStayUnknown() throws {
        let json = #"{"products":[{"code":"1","product_name":"Mystery bar","nutriments":{"energy-kcal_100g":400}}]}"#
        let items = OpenFoodFacts.parseSearch(Data(json.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].per100g.protein)
        XCTAssertFalse(items[0].per100g.hasMacros)
    }

    func testFallsBackToKilojoules() throws {
        let json = #"{"products":[{"code":"2","product_name":"Juice","nutriments":{"energy-kj_100g":184}}]}"#
        XCTAssertEqual(OpenFoodFacts.parseSearch(Data(json.utf8)).first?.per100g.kcal ?? 0, 44, accuracy: 0.1)
    }

    func testSkipsProductsWithoutNameOrEnergy() {
        let json = #"{"products":[{"code":"3","product_name":"","nutriments":{"energy-kcal_100g":100}},{"code":"4","product_name":"No energy","nutriments":{}}]}"#
        XCTAssertTrue(OpenFoodFacts.parseSearch(Data(json.utf8)).isEmpty)
    }

    func testNotFoundProduct() {
        XCTAssertNil(OpenFoodFacts.parseProduct(Data(#"{"status":0,"status_verbose":"product not found"}"#.utf8)))
    }

    func testBuiltInSearchMatchesAllWords() {
        XCTAssertEqual(BuiltInFoods.search("chicken cooked").first?.name, "Chicken breast, cooked")
        XCTAssertTrue(BuiltInFoods.search("xyz").isEmpty)
        for item in BuiltInFoods.all {
            let n = item.per100g
            // Energy roughly matches 4/4/9 within 15% for every built-in value.
            let estimate = 4 * (n.protein ?? 0) + 4 * (n.carbs ?? 0) + 9 * (n.fat ?? 0)
            XCTAssertEqual(estimate, n.kcal, accuracy: max(n.kcal * 0.15, 12), item.name)
        }
    }
}
