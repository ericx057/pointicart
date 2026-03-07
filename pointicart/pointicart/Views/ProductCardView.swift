import SwiftUI

struct ProductCardView: View {
    let product: Product
    let onAddToCart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: product.imageSystemName)
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .frame(height: 50)

            Text(product.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(product.formattedPrice)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Button(action: onAddToCart) {
                Label("Add to Cart", systemImage: "cart.badge.plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(20)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}
