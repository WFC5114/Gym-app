import Foundation

/// Open Food Facts: free, open packaged-food database. The only network calls
/// the app makes for food (CLAUDE.md). Parsing is tolerant because fields arrive
/// as numbers or strings depending on who entered the product.
struct OpenFoodFacts {
    var session: URLSession = .shared
    static let userAgent = "GYM-iOS/0.1 (personal app; github.com/WFC5114/Gym-app)"
    private static let fields = "code,product_name,brands,nutriments,serving_quantity,serving_size"

    enum Failure: Error, Equatable {
        case offline
        case notFound
        case badResponse
    }

    func search(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: Self.fields),
        ]
        let data = try await get(components.url!)
        return Self.parseSearch(data)
    }

    func product(barcode: String) async throws -> FoodItem {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { throw Failure.notFound }
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits)?fields=\(Self.fields)")!
        let data = try await get(url)
        guard let item = Self.parseProduct(data) else { throw Failure.notFound }
        return item
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
            if http.statusCode == 404 { throw Failure.notFound }
            guard (200..<300).contains(http.statusCode) else { throw Failure.badResponse }
            return data
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .timedOut ? Failure.offline : Failure.badResponse
        }
    }

    // MARK: Parsing

    static func parseSearch(_ data: Data) -> [FoodItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return [] }
        return products.compactMap(item(from:))
    }

    static func parseProduct(_ data: Data) -> FoodItem? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let status = number(root["status"]), status == 0 { return nil }
        guard var product = root["product"] as? [String: Any] else { return nil }
        if product["code"] == nil, let code = root["code"] { product["code"] = code }
        return item(from: product)
    }

    /// Products without a name or without energy per 100 g are skipped: logging
    /// them would mean guessing.
    static func item(from product: [String: Any]) -> FoodItem? {
        guard let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let nutriments = product["nutriments"] as? [String: Any] else { return nil }
        var kcal = number(nutriments["energy-kcal_100g"])
        if kcal == nil, let kj = number(nutriments["energy-kj_100g"]) ?? number(nutriments["energy_100g"]) {
            kcal = kj / 4.184
        }
        guard let kcal, kcal >= 0, kcal < 1000 else { return nil }
        let code = (product["code"] as? String) ?? number(product["code"]).map { String(Int($0)) }
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        return FoodItem(
            id: "off:\(code ?? name)",
            name: name,
            brand: brand?.isEmpty == true ? nil : brand,
            source: .openFoodFacts,
            barcode: code,
            per100g: Nutrients(
                kcal: kcal,
                protein: number(nutriments["proteins_100g"]),
                carbs: number(nutriments["carbohydrates_100g"]),
                fat: number(nutriments["fat_100g"])
            ),
            servingGrams: serving,
            servingLabel: (product["serving_size"] as? String).map { $0.uppercased() }
        )
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }
}
