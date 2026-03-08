import SwiftUI

struct ProductCardView: View {
    let product: Product
    let onAddToCart: () -> Void
    let onBuyNow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: product.imageSystemName)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
                .frame(height: 44)

            Text(product.name)
                .font(.headline)
                .foregroundStyle(.white)

            Text(product.formattedPrice)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 10) {
                Button(action: onAddToCart) {
                    Text("Add to Cart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )
                }

                Button(action: onBuyNow) {
                    Text("Buy Now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.3), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(20)
        .frame(width: 240)
        .background { GlassBackground(cornerRadius: 24) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}
