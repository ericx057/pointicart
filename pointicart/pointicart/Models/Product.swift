import Foundation

struct Product: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
    let imageSystemName: String
    let assetImageName: String?
    let upsellId: String?
    let category: ProductCategory
    let availableSizes: [ProductSize]?

    init(id: String, name: String, price: Double, imageSystemName: String, upsellId: String?,
         category: ProductCategory = .unsized, availableSizes: [ProductSize]? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.imageSystemName = imageSystemName
        self.assetImageName = nil
        self.upsellId = upsellId
        self.category = category
        self.availableSizes = availableSizes
    }

    init(id: String, name: String, price: Double, assetImageName: String, upsellId: String? = nil,
         category: ProductCategory = .unsized, availableSizes: [ProductSize]? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.imageSystemName = "bag"
        self.assetImageName = assetImageName
        self.upsellId = upsellId
        self.category = category
        self.availableSizes = availableSizes
    }

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    var hasAssetImage: Bool {
        assetImageName != nil
    }
}

struct CartItem: Identifiable {
    let id: UUID
    let product: Product
    var quantity: Int
    let selectedSize: ProductSize?

    init(product: Product, quantity: Int = 1, selectedSize: ProductSize? = nil) {
        self.id = UUID()
        self.product = product
        self.quantity = quantity
        self.selectedSize = selectedSize
    }

    var subtotal: Double {
        product.price * Double(quantity)
    }
}
