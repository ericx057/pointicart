import SwiftUI

struct CartOverlayView: View {
    let cartManager: CartManager
    let storeName: String
    let suggestedProduct: Product?
    let suggestedProducts: [Product]
    let onAddSuggested: (Product) -> Void
    let onPaymentComplete: () -> Void
    @State private var showCheckout = false

    var body: some View {
        if !cartManager.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(cartManager.itemCount) item\(cartManager.itemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(cartManager.formattedTotal)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button {
                        showCheckout = true
                    } label: {
                        Text("Checkout")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.2), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .padding(.bottom, 20)
                .background {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.1), .white.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 0.5)
                    }
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutSheet(
                    cartManager: cartManager,
                    storeName: storeName,
                    suggestedProduct: suggestedProduct,
                    suggestedProducts: suggestedProducts,
                    onAddSuggested: onAddSuggested,
                    onPaymentComplete: onPaymentComplete
                )
            }
        }
    }
}

// MARK: - Checkout Sheet

struct CheckoutSheet: View {
    let cartManager: CartManager
    let storeName: String
    let suggestedProduct: Product?
    let suggestedProducts: [Product]
    let onAddSuggested: (Product) -> Void
    let onPaymentComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didPay = false
    @State private var addedSuggestion = false
    @State private var addedSuggestedIds: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Your Cart") {
                        ForEach(cartManager.items) { item in
                            HStack(spacing: 12) {
                                ProductImageView(product: item.product, size: 36, color: .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.product.name)
                                        .font(.subheadline.weight(.medium))
                                    if item.quantity > 1 {
                                        Text("x\(item.quantity)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text(String(format: "$%.2f", item.subtotal))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Recommended product (paired upsell)
                    if let suggested = suggestedProduct, !addedSuggestion {
                        Section("Recommended") {
                            HStack(spacing: 12) {
                                ProductImageView(product: suggested, size: 36, color: .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggested.name)
                                        .font(.subheadline.weight(.medium))
                                    Text("Often paired with your items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    onAddSuggested(suggested)
                                    withAnimation { addedSuggestion = true }
                                } label: {
                                    Text("Add  \(suggested.formattedPrice)")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.primary.opacity(0.85))
                                .controlSize(.small)
                            }
                        }
                    }

                    // Suggested products carousel
                    if !visibleSuggestedProducts.isEmpty {
                        Section("You Might Also Like") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(visibleSuggestedProducts) { product in
                                        SuggestedProductCard(product: product) {
                                            onAddSuggested(product)
                                            withAnimation {
                                                addedSuggestedIds.insert(product.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        }
                    }

                    Section {
                        HStack {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(cartManager.formattedTotal)
                                .font(.title3.weight(.semibold))
                        }
                    }
                }

                if didPay {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("Payment Complete")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        withAnimation { didPay = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            onPaymentComplete()
                            cartManager.clear()
                            dismiss()
                        }
                    } label: {
                        Label("Pay with Apple Pay", systemImage: "apple.logo")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(storeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var visibleSuggestedProducts: [Product] {
        let cartIds = Set(cartManager.items.map(\.product.id))
        return suggestedProducts.filter { product in
            !cartIds.contains(product.id) && !addedSuggestedIds.contains(product.id)
        }
    }
}

// MARK: - Product Image View

struct ProductImageView: View {
    let product: Product
    let size: CGFloat
    let color: Color

    var body: some View {
        if let assetName = product.assetImageName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: product.imageSystemName)
                .font(.system(size: size * 0.5))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Suggested Product Card

struct SuggestedProductCard: View {
    let product: Product
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let assetName = product.assetImageName {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: product.imageSystemName)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, height: 90)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(product.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Text(product.formattedPrice)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Add") {
                onAdd()
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.primary.opacity(0.85))
        }
        .frame(width: 110)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}
