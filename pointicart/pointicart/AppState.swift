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
    var identifiedPosition: CGPoint?
    var identifiedBoundingBox: CGRect?   // screen-space rect for the highlight overlay
    var isProductRecognized: Bool = false
    var showProductCard: Bool = false
    var showDirectCheckout: Bool = false

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
        NSLog("[PTIC] onDwellDetected ENTER — isIdentifying=%d", isIdentifying ? 1 : 0)
        guard !isIdentifying else {
            NSLog("[PTIC] onDwellDetected SKIP — already identifying")
            return
        }
        isIdentifying = true
        defer {
            isIdentifying = false
            NSLog("[PTIC] onDwellDetected EXIT — isIdentifying reset to false")
        }

        let candidates = storeService.productKeys
        NSLog("[PTIC] Store loaded=%d, candidates=%@",
              storeService.isLoaded ? 1 : 0,
              candidates.joined(separator: ", "))
        guard !candidates.isEmpty else {
            NSLog("[PTIC] onDwellDetected SKIP — no candidates (store not loaded)")
            return
        }

        let capturedPosition = fingertipPosition

        NSLog("[PTIC] Sending image %.0fx%.0f to Gemini with %d candidates",
              image.size.width, image.size.height, candidates.count)

        do {
            let result = try await inferenceService.identify(image: image, candidates: candidates)
            NSLog("[PTIC] Inference result: %@", String(describing: result?.productKey))
            if let result, storeService.product(forKey: result.productKey) != nil {
                identifiedProductKey = result.productKey
                identifiedPosition = capturedPosition
                identifiedBoundingBox = result.normalizedBox.map {
                    Self.screenRect(fromNormalized: $0, imageSize: image.size)
                }
                isProductRecognized = true
                showProductCard = true
                NSLog("[PTIC] Product recognized: %@ — showProductCard=true", result.productKey)
            } else {
                NSLog("[PTIC] No matching product in store for result")
            }
        } catch {
            NSLog("[PTIC] Inference ERROR: %@", String(describing: error))
            isDwelling = false
        }
    }

    // MARK: - Card Dismissal

    func dismissProductCard() {
        showProductCard = false
        identifiedProductKey = nil
        identifiedPosition = nil
        identifiedBoundingBox = nil
        isProductRecognized = false
        isDwelling = false
    }

    // MARK: - Coordinate Mapping

    /// Map a normalized box (0-1, portrait image space) to UIKit screen points.
    /// ARKit delivers landscape frames; after `.oriented(.right)` the portrait image
    /// has size (rawHeight × rawWidth). ARSCNView fills the screen with aspect-fill,
    /// so we replicate that transform here.
    private static func screenRect(fromNormalized box: CGRect, imageSize: CGSize) -> CGRect {
        let screen = UIScreen.main.bounds.size
        // imageSize is in pixels (UIImage.scale == 1 when built from CIContext cgImage).
        // Convert to points using the screen scale so math stays in UIKit point space.
        let scale = UIScreen.main.scale
        let imagePtWidth  = imageSize.width  / scale
        let imagePtHeight = imageSize.height / scale

        // Aspect-fill: scale so the image fully covers the screen.
        let fillScale = max(screen.width / imagePtWidth, screen.height / imagePtHeight)
        let scaledW = imagePtWidth  * fillScale
        let scaledH = imagePtHeight * fillScale
        let xOff = (scaledW - screen.width)  / 2
        let yOff = (scaledH - screen.height) / 2

        return CGRect(
            x:      box.minX * scaledW - xOff,
            y:      box.minY * scaledH - yOff,
            width:  box.width  * scaledW,
            height: box.height * scaledH
        )
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
