import UIKit
import Observation

@Observable
final class CartManager {
    private(set) var items: [CartItem] = []
    private(set) var lastInteractionAt: Date?

    var total: Double {
        items.reduce(0) { $0 + $1.subtotal }
    }

    var formattedTotal: String {
        String(format: "$%.2f", total)
    }

    var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var itemIds: String {
        items.map(\.product.id).joined(separator: ",")
    }

    var firstProductName: String? {
        items.first?.product.name
    }

    func contains(_ productId: String) -> Bool {
        items.contains { $0.product.id == productId }
    }

    func quantity(of productId: String) -> Int {
        items.first { $0.product.id == productId }?.quantity ?? 0
    }

    func decrementOrRemove(_ productId: String) {
        guard let index = items.firstIndex(where: { $0.product.id == productId }) else { return }
        if items[index].quantity <= 1 {
            items = items.filter { $0.product.id != productId }
        } else {
            var updated = items
            updated[index] = CartItem(
                product: items[index].product,
                quantity: items[index].quantity - 1,
                selectedSize: items[index].selectedSize
            )
            items = updated
        }
        lastInteractionAt = Date()
    }

    func add(_ product: Product, selectedSize: ProductSize? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let index = items.firstIndex(where: { $0.product.id == product.id }) {
            var updated = items
            updated[index] = CartItem(
                product: items[index].product,
                quantity: items[index].quantity + 1,
                selectedSize: items[index].selectedSize
            )
            items = updated
        } else {
            items = items + [CartItem(product: product, selectedSize: selectedSize)]
        }
        lastInteractionAt = Date()
    }

    func remove(_ productId: String) {
        items = items.filter { $0.product.id != productId }
        lastInteractionAt = Date()
    }

    func updateSize(_ size: ProductSize, for productId: String) {
        guard let index = items.firstIndex(where: { $0.product.id == productId }) else { return }
        var updated = items
        updated[index] = CartItem(
            product: items[index].product,
            quantity: items[index].quantity,
            selectedSize: size
        )
        items = updated
    }

    func clear() {
        items = []
        lastInteractionAt = nil
    }
}
