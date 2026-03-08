import UIKit
import Observation

@Observable
final class AppState {
    let storeService = StoreService()
    let cartManager = CartManager()
    let inferenceService: any InferenceService = GeminiInferenceService(apiKey: Secrets.geminiAPIKey)
    let tryOnService = VirtualTryOnService(
        projectID: Secrets.gcpProjectID,
        location: Secrets.gcpLocation,
        clientID: Secrets.gcpClientID,
        clientSecret: Secrets.gcpClientSecret,
        refreshToken: Secrets.gcpRefreshToken
    )

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
    var lastIdentificationSnapshot: UIImage?  // kept for try-on cropping

    // Try-on mode
    var isTryOnMode: Bool = false
    var tryOnProduct: Product?
    var tryOnProductImage: UIImage?       // clean clothing image for the API
    var tryOnResultImage: UIImage?        // generated try-on composite
    var capturedPersonImage: UIImage?     // frozen camera frame shown during generation
    var isGeneratingTryOn: Bool = false
    var tryOnError: String?

    /// Set by ARCameraView so we can capture a frame on demand.
    var captureSnapshot: (() -> UIImage?)?
    /// Set by ARCameraView so we can adjust camera zoom (1.0 = default).
    var applyZoom: ((CGFloat) -> Void)?

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
        guard !isIdentifying, !isTryOnMode else {
            NSLog("[PTIC] onDwellDetected SKIP — already identifying or in try-on mode")
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
                lastIdentificationSnapshot = image
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
        lastIdentificationSnapshot = nil
    }

    // MARK: - Try-On Mode

    func enterTryOnMode(product: Product, snapshot: UIImage?, boundingBox: CGRect?) {
        // Prefer bundled asset image for try-on; fall back to camera crop
        if let assetName = product.tryOnImageName, let assetImage = UIImage(named: assetName) {
            tryOnProductImage = assetImage
        } else if let snapshot, let box = boundingBox {
            tryOnProductImage = Self.cropImage(snapshot, to: box)
        } else {
            tryOnProductImage = nil
        }
        tryOnProduct = product
        tryOnResultImage = nil
        tryOnError = nil
        isTryOnMode = true
        isGeneratingTryOn = false
        dismissProductCard()
        NSLog("[PTIC] Entered try-on mode for: %@", product.name)
    }

    func exitTryOnMode() {
        isTryOnMode = false
        tryOnProduct = nil
        tryOnProductImage = nil
        tryOnResultImage = nil
        capturedPersonImage = nil
        isGeneratingTryOn = false
        tryOnError = nil
        applyZoom?(1.0) // reset camera zoom
        NSLog("[PTIC] Exited try-on mode")
    }

    /// Called when the user taps "Take Photo" in try-on mode.
    /// Captures the current AR frame, freezes it on screen, and sends it + the product image to Gemini.
    func captureAndGenerateTryOn() {
        guard let snapshot = captureSnapshot?() else {
            tryOnError = "Could not capture camera frame"
            NSLog("[PTIC] TryOn capture failed — no snapshot")
            return
        }

        guard let productImage = tryOnProductImage else {
            tryOnError = "No product image available"
            NSLog("[PTIC] TryOn capture failed — no product image")
            return
        }

        capturedPersonImage = snapshot
        isGeneratingTryOn = true
        tryOnError = nil
        NSLog("[PTIC] TryOn: captured person %.0fx%.0f, sending to API...",
              snapshot.size.width, snapshot.size.height)

        Task { @MainActor in
            do {
                let result = try await tryOnService.tryOn(
                    personImage: snapshot,
                    productImage: productImage
                )
                tryOnResultImage = result
                isGeneratingTryOn = false
                NSLog("[PTIC] TryOn: generated result %.0fx%.0f", result.size.width, result.size.height)
            } catch {
                isGeneratingTryOn = false
                tryOnError = error.localizedDescription
                NSLog("[PTIC] TryOn ERROR: %@", String(describing: error))
            }
        }
    }

    /// Crop a region from a UIImage given a screen-rect.
    private static func cropImage(_ image: UIImage, to screenRect: CGRect) -> UIImage? {
        let scale = image.scale
        let cropRect = CGRect(
            x: screenRect.minX * scale,
            y: screenRect.minY * scale,
            width: screenRect.width * scale,
            height: screenRect.height * scale
        )
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
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
