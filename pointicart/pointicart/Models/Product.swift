import Foundation

struct Product: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
    let imageSystemName: String
    let upsellId: String?
    let isClothing: Bool
    /// Asset catalog image name for try-on overlay (nil = crop from camera)
    let tryOnImageName: String?

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }
}

struct CartItem: Identifiable {
    let id: UUID
    let product: Product
    var quantity: Int

    init(product: Product, quantity: Int = 1) {
        self.id = UUID()
        self.product = product
        self.quantity = quantity
    }

    var subtotal: Double {
        product.price * Double(quantity)
    }
}
