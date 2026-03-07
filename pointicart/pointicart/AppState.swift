import UIKit
import Observation

@Observable
final class AppState {
    let storeService = StoreService()
    let cartManager = CartManager()
    let inferenceService: any InferenceService = GeminiInferenceService(apiKey: Secrets.geminiAPIKey)

    // Hand tracking state
    var fingertipPosition: CGPoint?
    var isDwelling: Bool = false
    var isIdentifying: Bool = false

    // Identified product
    var identifiedProductKey: String?
    var showProductCard: Bool = false

    // Abandoned cart timer
    private var abandonedCartTask: Task<Void, Never>?

    var identifiedProduct: Product? {
        guard let key = identifiedProductKey else { return nil }
        return storeService.product(forKey: key)
    }

    var upsellProduct: Product? {
        guard let product = identifiedProduct else { return nil }
        return storeService.upsell(for: product)
    }

    // MARK: - URL Routing

    func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // Handle: pointwise.shop/store?id=42
        if components.path.contains("store"),
           let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
           let storeId = Int(idString) {
            storeService.load(id: storeId)
            return
        }

        // Handle: pointwise.shop/checkout?items=kb_01,wr_02
        if components.path.contains("checkout"),
           let itemsString = components.queryItems?.first(where: { $0.name == "items" })?.value {
            restoreCart(from: itemsString)
        }
    }

    // MARK: - Inference Callback

    func onDwellDetected(image: UIImage) async {
        guard !isIdentifying else { return }
        isIdentifying = true

        let candidates = storeService.productKeys
        guard !candidates.isEmpty else {
            isIdentifying = false
            return
        }

        do {
            let result = try await inferenceService.identify(image: image, candidates: candidates)
            if let key = result, storeService.product(forKey: key) != nil {
                identifiedProductKey = key
                showProductCard = true
            }
        } catch {
            // Inference failed silently — user can re-point
        }

        isIdentifying = false
    }

    // MARK: - Card Dismissal

    func dismissProductCard() {
        showProductCard = false
        identifiedProductKey = nil
        isDwelling = false
    }

    // MARK: - Abandoned Cart

    func startAbandonedCartTimer() {
        abandonedCartTask?.cancel()
        abandonedCartTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, !cartManager.isEmpty else { return }

            let granted = await NotificationService.requestPermission()
            guard granted else { return }

            NotificationService.scheduleAbandonedCartReminder(
                storeName: storeService.storeName,
                productName: cartManager.firstProductName ?? "your items",
                cartItemIds: cartManager.itemIds
            )
        }
    }

    func cancelAbandonedCartTimer() {
        abandonedCartTask?.cancel()
        NotificationService.cancelAbandonedCartReminders()
    }

    // MARK: - Cart Restoration (Deep Link)

    private func restoreCart(from itemIds: String) {
        let ids = itemIds.split(separator: ",").map(String.init)
        for id in ids {
            if let product = storeService.products.values.first(where: { $0.id == id }) {
                cartManager.add(product)
            }
        }
    }
}
