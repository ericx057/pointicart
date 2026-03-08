import SwiftUI

struct CartOverlayView: View {
    let cartManager: CartManager
    let storeName: String
    let suggestedProduct: Product?
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(cartManager.formattedTotal)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Button {
                        showCheckout = true
                    } label: {
                        Label("Checkout", systemImage: "creditcard")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .padding(.bottom, 20)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutSheet(
                    cartManager: cartManager,
                    storeName: storeName,
                    suggestedProduct: suggestedProduct,
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
    let onAddSuggested: (Product) -> Void
    let onPaymentComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didPay = false
    @State private var addedSuggestion = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Your Cart") {
                        ForEach(cartManager.items) { item in
                            HStack {
                                Image(systemName: item.product.imageSystemName)
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                    .frame(width: 30)

                                VStack(alignment: .leading) {
                                    Text(item.product.name)
                                        .font(.subheadline.bold())
                                    if item.quantity > 1 {
                                        Text("x\(item.quantity)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text(String(format: "$%.2f", item.subtotal))
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Recommended product
                    if let suggested = suggestedProduct, !addedSuggestion {
                        Section("Recommended") {
                            HStack {
                                Image(systemName: suggested.imageSystemName)
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                    .frame(width: 30)

                                VStack(alignment: .leading) {
                                    Text(suggested.name)
                                        .font(.subheadline.bold())
                                    Text("Often paired with your items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(suggested.formattedPrice)
                                        .font(.subheadline.bold())
                                    Button("Add") {
                                        onAddSuggested(suggested)
                                        withAnimation { addedSuggestion = true }
                                    }
                                    .font(.caption.bold())
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                }
                            }
                        }
                    }

                    Section {
                        HStack {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(cartManager.formattedTotal)
                                .font(.title3.bold())
                        }
                    }
                }

                if didPay {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Payment Complete")
                            .font(.headline)
                    }
                    .padding(30)
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
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
}
