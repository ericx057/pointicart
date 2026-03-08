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
            "Jacket": Product(id: "jk_01", name: "Jacket", price: 129.99, imageSystemName: "jacket", upsellId: "sc_02", category: .apparel, availableSizes: ProductSize.allCases,
                visualDescription: "A structured outerwear jacket, typically with a front zipper or buttons, collar, and pockets. May be leather, denim, or polyester."),
            "T-Shirt": Product(id: "ts_01", name: "T-Shirt", price: 34.99, imageSystemName: "tshirt", upsellId: "cp_02", category: .apparel, availableSizes: ProductSize.allCases,
                visualDescription: "A simple short-sleeved crew-neck or V-neck tee made from cotton jersey. Lightweight, no collar, no buttons."),
            "Hoodie": Product(id: "hd_01", name: "Hoodie", price: 64.99, imageSystemName: "tshirt.fill", upsellId: "bn_02", category: .apparel, availableSizes: ProductSize.allCases,
                visualDescription: "A pullover or zip-up sweatshirt with an attached hood and front kangaroo pocket. Thick fleece or cotton fabric."),
            "Sweater": Product(id: "sw_01", name: "Sweater", price: 79.99, imageSystemName: "tshirt.fill", upsellId: "gl_02", category: .apparel, availableSizes: ProductSize.allCases,
                visualDescription: "A chunky knit pullover sweater with a gradient ombre pattern fading from black to grey. Horizontal ribbed knit bands, crew neck, no hood, no zipper. Thick knitted wool or acrylic yarn with visible knit texture."),
            "Pants": Product(id: "pt_01", name: "Pants", price: 59.99, imageSystemName: "figure.walk", upsellId: "bt_02", category: .apparel, availableSizes: ProductSize.allCases,
                visualDescription: "Full-length trousers or pants covering both legs, with a waistband, fly, and pockets. May be jeans, chinos, or joggers."),
            "Dress": Product(id: "dr_01", name: "Dress", price: 89.99, imageSystemName: "figure.dress.line.vertical.figure", upsellId: "cl_02", category: .apparel, availableSizes: ProductSize.allCases,
                visualDescription: "A one-piece garment with a top and skirt section. Covers the torso and extends down past the waist. May be casual or formal."),
            "Sneakers": Product(id: "sn_01", name: "Sneakers", price: 109.99, imageSystemName: "shoe", upsellId: "lc_02", category: .footwear, availableSizes: ProductSize.allCases,
                visualDescription: "Athletic or casual shoes with rubber soles, laces, and a cushioned design. Typically low-cut, made from canvas, leather, or mesh."),
            // Upsell products
            "Scarf": Product(id: "sc_02", name: "Scarf", price: 24.99, imageSystemName: "wind", upsellId: nil, category: .accessories,
                visualDescription: "A long, narrow strip of fabric worn around the neck. Knit, woven, or silk."),
            "Cap": Product(id: "cp_02", name: "Cap", price: 19.99, imageSystemName: "baseball.diamond.bases", upsellId: nil, category: .accessories,
                visualDescription: "A baseball cap with a curved brim, structured crown, and adjustable back strap."),
            "Beanie": Product(id: "bn_02", name: "Beanie", price: 22.99, imageSystemName: "cloud.fill", upsellId: nil, category: .accessories,
                visualDescription: "A snug, brimless knitted hat that fits close to the head. May have a folded cuff."),
            "Gloves": Product(id: "gl_02", name: "Gloves", price: 24.99, imageSystemName: "hand.raised", upsellId: nil, category: .accessories,
                visualDescription: "Hand coverings with individual finger slots. Knit, leather, or wool."),
            "Belt": Product(id: "bt_02", name: "Belt", price: 29.99, imageSystemName: "line.diagonal", upsellId: nil, category: .accessories,
                visualDescription: "A narrow strap of leather or fabric with a metal buckle, worn around the waist."),
            "Clutch": Product(id: "cl_02", name: "Clutch", price: 39.99, imageSystemName: "handbag", upsellId: nil, category: .accessories,
                visualDescription: "A small, flat handbag without a strap, designed to be held in one hand."),
            "Shoe Laces": Product(id: "lc_02", name: "Premium Laces", price: 9.99, imageSystemName: "shoelace.fill", upsellId: nil, category: .accessories,
                visualDescription: "Thin cords or flat strings used to fasten shoes, often in a contrasting color."),
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
