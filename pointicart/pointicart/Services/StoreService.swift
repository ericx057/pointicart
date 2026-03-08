import Foundation
import Observation

@Observable
final class StoreService {
    private(set) var storeId: Int?
    private(set) var storeName: String = ""
    private(set) var products: [String: Product] = [:]

    var productKeys: [String] {
        Array(products.keys.sorted())
    }

    var isLoaded: Bool {
        storeId != nil
    }

    func load(id: Int) {
        storeId = id
        switch id {
        case 42:
            storeName = "Pointicart Store"
            products = buildLifestyleStoreCatalog()
        default:
            storeName = "Pointicart Store"
            products = buildLifestyleStoreCatalog()
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
            // Main products
            "Chair": Product(id: "ch_01", name: "Ergo Chair", price: 349.99, imageSystemName: "chair", upsellId: "cu_02"),
            "Headphones": Product(id: "hp_01", name: "Headphones", price: 199.99, imageSystemName: "headphones", upsellId: "hc_02"),
            "Water Bottle": Product(id: "wb_01", name: "Water Bottle", price: 39.99, imageSystemName: "waterbottle", upsellId: "cb_02"),
            // Upsell products
            "Chair Cushion": Product(id: "cu_02", name: "Foam Cushion", price: 29.99, imageSystemName: "square.fill", upsellId: nil),
            "Headphone Case": Product(id: "hc_02", name: "Carry Case", price: 24.99, imageSystemName: "bag", upsellId: nil),
            "Cleaning Brush": Product(id: "cb_02", name: "Cleaning Brush", price: 9.99, imageSystemName: "paintbrush", upsellId: nil),
        ]
    }
}
