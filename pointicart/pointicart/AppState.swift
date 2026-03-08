import UIKit
import Observation

@MainActor
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

    // Recommendation engine services
    let vectorStore = InteractionVectorStore()
    let sizingService = SizingService()

    // Session / demographic state
    private(set) var demographic: Demographic?
    private(set) var nfcTagData: NFCTagData?

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
    var lastIdentificationSnapshot: UIImage?

    // Try-on mode
    var isTryOnMode: Bool = false
    var tryOnProduct: Product?
    var tryOnProductImage: UIImage?
    var tryOnResultImage: UIImage?
    var capturedPersonImage: UIImage?
    var isGeneratingTryOn: Bool = false
    var tryOnError: String?

    /// Set by ARCameraView so we can capture a frame on demand.
    var captureSnapshot: (() -> UIImage?)?
    /// Set by ARCameraView so we can adjust camera zoom (1.0 = default).
    var applyZoom: ((CGFloat) -> Void)?

    // UX: Cart confirm flash (feature 7)
    var showCartConfirmFlash: Bool = false

    // UX: Position cache for instant re-identification (feature 1)
    private var positionCache: [String: PositionCacheEntry] = [:]
    private let positionCacheTTL: TimeInterval = 30.0

    // UX: Auto-dismiss timer (feature 5)
    private var autoDismissTask: Task<Void, Never>?
    private let autoDismissDelay: TimeInterval = 4.0

    // UX: Cooldown between inference calls
    private var lastInferenceTime: Date = .distantPast
    private let inferenceCooldown: TimeInterval = 5.0

    // Persistent rate-limit: survives app restarts so we don't immediately 429 on relaunch
    private var rateLimitedUntil: Date {
        get {
            let ts = UserDefaults.standard.double(forKey: "ptic_rate_limited_until")
            return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "ptic_rate_limited_until")
        }
    }

    // Abandoned cart timer
    private var abandonedCartTask: Task<Void, Never>?

    // MARK: - Position Cache Entry

    struct PositionCacheEntry {
        let productKey: String
        let boundingBox: CGRect?
        let timestamp: Date
    }

    var identifiedProduct: Product? {
        guard let key = identifiedProductKey else { return nil }
        return storeService.product(forKey: key)
    }

    var upsellProduct: Product? {
        guard let product = identifiedProduct else { return nil }
        return storeService.upsell(for: product)
    }

    // MARK: - Store Entry (Simulated NFC)

    /// Called when the user enters a store (NFC tap or demo button).
    func loadStore(id: Int, demographic: Demographic) {
        let tag = NFCTagData(storeId: id, demographic: demographic)
        self.nfcTagData = tag
        self.demographic = demographic

        storeService.load(id: id)
        vectorStore.beginSession(demographic: demographic)

        let location = Self.locationContext(forStoreId: id)
        sizingService.setLocation(location)
    }

    private static func locationContext(forStoreId id: Int) -> LocationContext {
        switch id {
        case 42:
            return LocationContext(
                storeId: 42, mallId: nil,
                city: "Toronto", province: "ON", country: "CA"
            )
        default:
            return LocationContext(
                storeId: id, mallId: nil,
                city: "Toronto", province: "ON", country: "CA"
            )
        }
    }

    // MARK: - Cart Add (with interaction tracking + sizing)

    /// Add a product to cart with automatic size defaulting and interaction recording.
    func addToCart(_ product: Product) {
        let defaultSize: ProductSize?
        if let demo = demographic, product.category != .unsized {
            defaultSize = sizingService.defaultSize(for: product.category, demographic: demo)
        } else {
            defaultSize = nil
        }

        cartManager.add(product, selectedSize: defaultSize)
        vectorStore.recordCartAdd()
        startAbandonedCartTimer()
    }

    // MARK: - Recommendation Engine Output

    /// The suggested products to show, filtered by recommendation intensity.
    var activeSuggestedProducts: [Product] {
        let intensity = RecommendationEngine.computeIntensity(
            timeInStore: vectorStore.timeInStoreSeconds,
            cartItemCount: cartManager.itemCount,
            addFrequency: vectorStore.addFrequency,
            dwellCount: vectorStore.dwellCount
        )

        let maxCount = RecommendationEngine.maxSuggestedProducts(
            forIntensity: intensity,
            totalAvailable: storeService.suggestedProducts.count
        )

        NSLog("[PTIC][Reco] intensity=%.3f, maxProducts=%d (time=%.0fs, cart=%d, freq=%.2f, dwells=%d)",
              intensity, maxCount,
              vectorStore.timeInStoreSeconds,
              cartManager.itemCount,
              vectorStore.addFrequency,
              vectorStore.dwellCount)

        // Only include products that have a loadable image asset
        let withImages = storeService.suggestedProducts.filter { product in
            guard let name = product.assetImageName else { return false }
            return UIImage(named: name) != nil
        }
        return Array(withImages.prefix(maxCount))
    }

    // MARK: - URL Routing

    func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // Handle: pointwise.shop/store?id=42
        if components.path.contains("store"),
           let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
           let storeId = Int(idString) {
            loadStore(id: storeId, demographic: .adult)
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

        // Persistent rate-limit check (survives app restarts)
        let now = Date()
        let rateLimitRemaining = rateLimitedUntil.timeIntervalSince(now)
        if rateLimitRemaining > 0 {
            NSLog("[PTIC] onDwellDetected SKIP — rate limited for %.1fs more", rateLimitRemaining)
            return
        }

        // Cooldown: don't call Gemini more than once per inferenceCooldown seconds
        let timeSinceLast = now.timeIntervalSince(lastInferenceTime)
        guard timeSinceLast >= inferenceCooldown else {
            NSLog("[PTIC] onDwellDetected SKIP — cooldown (%.1fs since last call)", timeSinceLast)
            return
        }

        // Only send main products (not upsell accessories) as candidates
        let candidates = storeService.recognizableProductKeys.isEmpty
            ? storeService.productKeys
            : storeService.recognizableProductKeys
        guard !candidates.isEmpty else {
            NSLog("[PTIC] onDwellDetected SKIP — no candidates (store not loaded)")
            return
        }

        let capturedPosition = fingertipPosition

        // Feature 1: Check position cache first — skip Gemini if we recently identified here
        if let cached = cachedProduct(near: capturedPosition) {
            NSLog("[PTIC] Cache HIT for %@", cached.productKey)

            // Feature 2: Second-dwell = auto add to cart (no card)
            if showProductCard, identifiedProductKey == cached.productKey {
                if let product = storeService.product(forKey: cached.productKey) {
                    addToCart(product)
                    triggerCartConfirmFlash()
                    dismissProductCard()
                    NSLog("[PTIC] Second-dwell auto-add: %@", cached.productKey)
                }
                return
            }

            // Feature 8: Intensity-gated auto-add — high engagement skips card
            let intensity = RecommendationEngine.computeIntensity(
                timeInStore: vectorStore.timeInStoreSeconds,
                cartItemCount: cartManager.itemCount,
                addFrequency: vectorStore.addFrequency,
                dwellCount: vectorStore.dwellCount
            )
            if intensity > 0.8, let product = storeService.product(forKey: cached.productKey),
               !cartManager.contains(product.id) {
                addToCart(product)
                triggerCartConfirmFlash()
                NSLog("[PTIC] Intensity-gated auto-add (%.2f): %@", intensity, cached.productKey)
                return
            }

            // Show card instantly from cache
            identifiedProductKey = cached.productKey
            identifiedPosition = capturedPosition
            identifiedBoundingBox = cached.boundingBox
            isProductRecognized = true
            showProductCard = true
            startAutoDismissTimer()
            vectorStore.recordDwell()
            return
        }

        // No cache hit — call Gemini
        isIdentifying = true
        lastInferenceTime = Date()
        defer {
            isIdentifying = false
            NSLog("[PTIC] onDwellDetected EXIT — isIdentifying reset to false")
        }

        // Build visual description map from store catalog
        var descriptions: [String: String] = [:]
        for key in candidates {
            if let product = storeService.product(forKey: key),
               let desc = product.visualDescription {
                descriptions[key] = desc
            }
        }

        NSLog("[PTIC] Sending image %.0fx%.0f to Gemini with %d candidates (%d with descriptions)",
              image.size.width, image.size.height, candidates.count, descriptions.count)

        do {
            let result = try await inferenceService.identify(
                image: image,
                candidates: candidates,
                candidateDescriptions: descriptions
            )
            NSLog("[PTIC] Inference result: %@", String(describing: result?.productKey))
            if let result, storeService.product(forKey: result.productKey) != nil {
                identifiedProductKey = result.productKey
                identifiedPosition = capturedPosition

                // Convert normalized bounding box (0-1) to screen-space
                if let normalizedBox = result.normalizedBox {
                    identifiedBoundingBox = Self.screenRect(
                        fromNormalized: normalizedBox,
                        imageSize: image.size
                    )
                } else {
                    identifiedBoundingBox = nil
                }

                isProductRecognized = true
                showProductCard = true
                lastIdentificationSnapshot = image
                NSLog("[PTIC] Product recognized: %@ — showProductCard=true", result.productKey)

                // Cache this identification (feature 1)
                cacheIdentification(
                    productKey: result.productKey,
                    position: capturedPosition,
                    boundingBox: identifiedBoundingBox
                )

                // Feature 5: Start auto-dismiss timer
                startAutoDismissTimer()

                // Record browsing behavior for recommendation engine
                vectorStore.recordDwell()
                vectorStore.recordProductView(productKey: result.productKey)
            } else {
                // Valid response, just no product matched — NOT an error
                NSLog("[PTIC] No matching product visible — this is normal")
                isDwelling = false
            }
        } catch GeminiError.rateLimited(let retryAfter) {
            NSLog("[PTIC] RATE LIMITED (429) — blocking inference for %.1fs (persisted)", retryAfter)
            isDwelling = false
            isProductRecognized = false
            // Persist the rate-limit expiry so it survives app restarts
            rateLimitedUntil = Date().addingTimeInterval(retryAfter)
        } catch {
            NSLog("[PTIC] Inference ERROR: %@", String(describing: error))
            isDwelling = false
            isProductRecognized = false
        }
    }

    // MARK: - Position Cache (Feature 1)

    private func cacheIdentification(productKey: String, position: CGPoint?, boundingBox: CGRect?) {
        let entry = PositionCacheEntry(
            productKey: productKey,
            boundingBox: boundingBox,
            timestamp: Date()
        )
        positionCache[productKey] = entry
    }

    private func cachedProduct(near position: CGPoint?) -> PositionCacheEntry? {
        let now = Date()
        // Evict expired entries
        positionCache = positionCache.filter { now.timeIntervalSince($0.value.timestamp) < positionCacheTTL }

        guard let pos = position else { return nil }

        // Check if fingertip is inside any cached bounding box
        for entry in positionCache.values {
            if let box = entry.boundingBox, box.insetBy(dx: -20, dy: -20).contains(pos) {
                return entry
            }
        }
        return nil
    }

    // MARK: - Auto-Dismiss Timer (Feature 5)

    func startAutoDismissTimer() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoDismissDelay))
            guard !Task.isCancelled, showProductCard else { return }
            dismissProductCard()
            NSLog("[PTIC] Auto-dismissed product card after %.0fs", autoDismissDelay)
        }
    }

    func cancelAutoDismissTimer() {
        autoDismissTask?.cancel()
    }

    // MARK: - Cart Confirm Flash (Feature 7)

    func triggerCartConfirmFlash() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        showCartConfirmFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            showCartConfirmFlash = false
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
        if let assetName = product.assetImageName, let assetImage = UIImage(named: assetName) {
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
        applyZoom?(1.0)
        NSLog("[PTIC] Exited try-on mode")
    }

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
        NotificationService.cancelAbandonedCartReminders()
        abandonedCartTask = Task {
            let granted = await NotificationService.requestPermission()
            guard granted, !Task.isCancelled, !cartManager.isEmpty else { return }

            NotificationService.scheduleAbandonedCartReminder(
                storeName: storeService.storeName,
                productName: cartManager.firstProductName ?? "your items",
                cartItemIds: cartManager.itemIds,
                delayMinutes: 120
            )
        }
    }

    func cancelAbandonedCartTimer() {
        abandonedCartTask?.cancel()
        NotificationService.cancelAbandonedCartReminders()
    }

    /// Called when payment completes — ends the session and persists the interaction vector.
    func onSessionPaymentComplete() {
        cancelAbandonedCartTimer()
        vectorStore.endSession(cartItemCount: cartManager.itemCount)
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
