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
            storeName = "Tech Haven"
            products = buildTechHavenCatalog()
        default:
            storeName = "Demo Store"
            products = [
                "Mug": Product(id: "mg_01", name: "Coffee Mug", price: 12.99, imageSystemName: "cup.and.saucer", upsellId: nil),
                "Pen": Product(id: "pn_01", name: "Ballpoint Pen", price: 4.99, imageSystemName: "pencil", upsellId: nil),
            ]
        }
    }

    func product(forKey key: String) -> Product? {
        products[key]
    }

    func upsell(for product: Product) -> Product? {
        guard let upsellId = product.upsellId else { return nil }
        return products.values.first { $0.id == upsellId }
    }

    private func buildTechHavenCatalog() -> [String: Product] {
        [
            // Main products
            "Keyboard": Product(id: "kb_01", name: "Mechanical Keyboard", price: 129.99, imageSystemName: "keyboard", upsellId: "wr_02"),
            "Mouse": Product(id: "ms_01", name: "Wireless Mouse", price: 79.99, imageSystemName: "computermouse", upsellId: "mp_02"),
            "Headphones": Product(id: "hp_01", name: "Studio Headphones", price: 249.99, imageSystemName: "headphones", upsellId: "hc_02"),
            "Monitor": Product(id: "mn_01", name: "4K Display", price: 599.99, imageSystemName: "display", upsellId: "mc_02"),
            "Mug": Product(id: "mg_01", name: "Developer Mug", price: 14.99, imageSystemName: "cup.and.saucer", upsellId: "cs_02"),
            // Upsell products
            "Wrist Rest": Product(id: "wr_02", name: "Ergonomic Wrist Rest", price: 29.99, imageSystemName: "hand.raised", upsellId: nil),
            "Mouse Pad": Product(id: "mp_02", name: "XL Mouse Pad", price: 24.99, imageSystemName: "rectangle", upsellId: nil),
            "Headphone Case": Product(id: "hc_02", name: "Headphone Case", price: 34.99, imageSystemName: "bag", upsellId: nil),
            "Monitor Cable": Product(id: "mc_02", name: "USB-C Cable", price: 19.99, imageSystemName: "cable.connector", upsellId: nil),
            "Coaster Set": Product(id: "cs_02", name: "Cork Coaster Set", price: 9.99, imageSystemName: "circle.grid.2x2", upsellId: nil),
        ]
    }
}
