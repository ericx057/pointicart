import Foundation
import Observation

@Observable
final class StoreService {
    private(set) var storeId: Int?
    private(set) var storeName: String = ""
    private(set) var products: [String: Product] = [:]
    private(set) var suggestedProducts: [Product] = []

    var productKeys: [String] {
        Array(products.keys.sorted())
    }

    /// Only main products (ones with upsells) — excludes upsell accessories.
    var recognizableProductKeys: [String] {
        products.filter { $0.value.upsellId != nil }.keys.sorted()
    }

    var isLoaded: Bool {
        storeId != nil
    }

    func load(id: Int) {
        storeId = id
        switch id {
        case 42:
            storeName = "Pointicart Clothing"
            products = buildLifestyleStoreCatalog()
            suggestedProducts = buildSuggestedProducts()
        default:
            storeName = "Pointicart Clothing"
            products = buildLifestyleStoreCatalog()
            suggestedProducts = buildSuggestedProducts()
        }
    }

    func product(forKey key: String) -> Product? {
        products[key]
    }

    func upsell(for product: Product) -> Product? {
        guard let upsellId = product.upsellId else { return nil }
        return products.values.first { $0.id == upsellId }
    }

    private func buildLifestyleStoreCatalog() -> [String: Product] {
        [
            // Main products (recognizable by camera)
            "Jacket": Product(id: "jk_01", name: "Jacket", price: 129.99, imageSystemName: "jacket", upsellId: "sc_02", category: .apparel, availableSizes: ProductSize.allCases),
            "T-Shirt": Product(id: "ts_01", name: "T-Shirt", price: 34.99, imageSystemName: "tshirt", upsellId: "cp_02", category: .apparel, availableSizes: ProductSize.allCases),
            "Hoodie": Product(id: "hd_01", name: "Hoodie", price: 64.99, imageSystemName: "tshirt.fill", upsellId: "bn_02", category: .apparel, availableSizes: ProductSize.allCases),
            "Pants": Product(id: "pt_01", name: "Pants", price: 59.99, imageSystemName: "figure.walk", upsellId: "bt_02", category: .apparel, availableSizes: ProductSize.allCases),
            "Dress": Product(id: "dr_01", name: "Dress", price: 89.99, imageSystemName: "figure.dress.line.vertical.figure", upsellId: "cl_02", category: .apparel, availableSizes: ProductSize.allCases),
            "Sneakers": Product(id: "sn_01", name: "Sneakers", price: 109.99, imageSystemName: "shoe", upsellId: "lc_02", category: .footwear, availableSizes: ProductSize.allCases),
            // Upsell products
            "Scarf": Product(id: "sc_02", name: "Scarf", price: 24.99, imageSystemName: "wind", upsellId: nil, category: .accessories),
            "Cap": Product(id: "cp_02", name: "Cap", price: 19.99, imageSystemName: "baseball.diamond.bases", upsellId: nil, category: .accessories),
            "Beanie": Product(id: "bn_02", name: "Beanie", price: 22.99, imageSystemName: "cloud.fill", upsellId: nil, category: .accessories),
            "Belt": Product(id: "bt_02", name: "Belt", price: 29.99, imageSystemName: "line.diagonal", upsellId: nil, category: .accessories),
            "Clutch": Product(id: "cl_02", name: "Clutch", price: 39.99, imageSystemName: "handbag", upsellId: nil, category: .accessories),
            "Shoe Laces": Product(id: "lc_02", name: "Premium Laces", price: 9.99, imageSystemName: "shoelace.fill", upsellId: nil, category: .accessories),
        ]
    }

    private func buildSuggestedProducts() -> [Product] {
        [
            Product(id: "sg_01", name: "Sunglasses", price: 49.99, imageSystemName: "eyeglasses", category: .accessories),
            Product(id: "sg_02", name: "Watch", price: 149.99, imageSystemName: "applewatch", category: .accessories),
            Product(id: "sg_03", name: "Handbag", price: 89.99, imageSystemName: "handbag.fill", category: .accessories),
            Product(id: "sg_04", name: "Gloves", price: 29.99, imageSystemName: "hand.raised", category: .accessories),
            Product(id: "sg_05", name: "Socks", price: 12.99, imageSystemName: "shoeprint.fill", category: .apparel),
            Product(id: "sg_06", name: "Tank Top", price: 24.99, imageSystemName: "tshirt", category: .apparel, availableSizes: ProductSize.allCases),
        ]
    }
}
