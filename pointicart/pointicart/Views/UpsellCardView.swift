import SwiftUI

struct UpsellCardView: View {
    let product: Product
    let onAddToCart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Frequently Bought Together")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Image(systemName: product.imageSystemName)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(product.formattedPrice)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Button(action: onAddToCart) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(14)
        .frame(width: 220)
        .background { GlassBackground(cornerRadius: 20) }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
    }
}
