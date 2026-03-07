import SwiftUI

struct UpsellCardView: View {
    let product: Product
    let onAddToCart: () -> Void
    @State private var isGlowing = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Frequently Bought Together")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Image(systemName: product.imageSystemName)
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(product.formattedPrice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onAddToCart) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isGlowing ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .shadow(color: isGlowing ? .orange.opacity(0.4) : .black.opacity(0.2), radius: isGlowing ? 12 : 8, y: 5)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}
