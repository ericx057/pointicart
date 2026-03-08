import SwiftUI

struct ContentView: View {
    @State var appState: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: AR Camera (full screen)
                ARCameraView(appState: appState)
                    .ignoresSafeArea()

                // Layer 2: Scanning indicator at fingertip
                if let position = appState.fingertipPosition {
                    ScanningIndicator(
                        isDwelling: appState.isDwelling,
                        isIdentifying: appState.isIdentifying,
                        isProductRecognized: appState.isProductRecognized
                    )
                    .position(position)
                }

                // Layer 2.5: Loading indicator while identifying
                if appState.isIdentifying && !appState.showProductCard {
                    if let position = appState.fingertipPosition {
                        Text("Identifying...")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .position(x: position.x, y: position.y + 44)
                            .transition(.opacity)
                    }
                }

                // Layer 3: Object highlight + floating info card
                if appState.showProductCard, let product = appState.identifiedProduct {
                    ObjectHighlightOverlay(
                        product: product,
                        boundingBox: appState.identifiedBoundingBox,
                        fallbackPosition: appState.identifiedPosition,
                        screenSize: geo.size,
                        cartQuantity: appState.cartManager.quantity(of: product.id),
                        onAddToCart: {
                            appState.cancelAutoDismissTimer()
                            appState.addToCart(product)
                            appState.triggerCartConfirmFlash()
                            withAnimation(.spring(duration: 0.3)) { appState.dismissProductCard() }
                        },
                        onBuyNow: {
                            appState.cancelAutoDismissTimer()
                            appState.addToCart(product)
                            appState.showDirectCheckout = true
                        },
                        onIncrement: {
                            appState.cancelAutoDismissTimer()
                            appState.addToCart(product)
                            appState.startAutoDismissTimer()
                        },
                        onDecrement: {
                            appState.cancelAutoDismissTimer()
                            appState.cartManager.decrementOrRemove(product.id)
                            appState.startAutoDismissTimer()
                        },
                        onDismiss: {
                            appState.cancelAutoDismissTimer()
                            withAnimation(.spring(duration: 0.3)) { appState.dismissProductCard() }
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // Layer 4: Cart overlay (bottom bar)
                CartOverlayView(
                    cartManager: appState.cartManager,
                    storeName: appState.storeService.storeName,
                    suggestedProduct: appState.upsellProduct,
                    suggestedProducts: appState.activeSuggestedProducts,
                    onAddSuggested: { product in
                        appState.addToCart(product)
                    },
                    onPaymentComplete: { appState.onSessionPaymentComplete() }
                )

                // Layer 5: Store loading prompt (if no store loaded)
                if !appState.storeService.isLoaded {
                    StoreLoadingPrompt(appState: appState)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.35), value: appState.showProductCard)
        .sheet(isPresented: $appState.showDirectCheckout) {
            CheckoutSheet(
                cartManager: appState.cartManager,
                storeName: appState.storeService.storeName,
                suggestedProduct: appState.upsellProduct,
                suggestedProducts: appState.activeSuggestedProducts,
                onAddSuggested: { product in
                    appState.addToCart(product)
                },
                onPaymentComplete: {
                    appState.onSessionPaymentComplete()
                    appState.dismissProductCard()
                }
            )
        }
    }
}

// MARK: - Scanning Indicator

struct ScanningIndicator: View {
    let isDwelling: Bool
    let isIdentifying: Bool
    let isProductRecognized: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 52, height: 52)

            // Scanning arc
            if (isDwelling || isIdentifying) && !isProductRecognized {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(.white.opacity(0.8),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }

            // Recognized state
            if isProductRecognized {
                Circle()
                    .stroke(.white.opacity(0.7), lineWidth: 2)
                    .frame(width: 52, height: 52)
            }

            // Center dot
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 5, height: 5)

            // Crosshairs
            Group {
                Rectangle().frame(width: 0.5, height: 10).offset(y: -18)
                Rectangle().frame(width: 0.5, height: 10).offset(y: 18)
                Rectangle().frame(width: 10, height: 0.5).offset(x: -18)
                Rectangle().frame(width: 10, height: 0.5).offset(x: 18)
            }
            .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - Card Size Preference Key

private struct CardSizePreference: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Object Highlight Overlay

struct ObjectHighlightOverlay: View {
    let product: Product
    let boundingBox: CGRect?
    let fallbackPosition: CGPoint?
    let screenSize: CGSize
    let cartQuantity: Int
    let onAddToCart: () -> Void
    let onBuyNow: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onDismiss: () -> Void

    @State private var appear = false
    @State private var measuredCardHeight: CGFloat = 180

    private var cardWidth: CGFloat { isLandscape ? 280 : min(screenSize.width - 32, 280) }
    private let bracketLen: CGFloat = 20
    private let bracketThick: CGFloat = 2

    private var isLandscape: Bool { screenSize.width > screenSize.height }

    private var targetBox: CGRect {
        if let box = boundingBox { return box }
        let center = fallbackPosition ?? CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        return CGRect(x: center.x - 50, y: center.y - 50, width: 100, height: 100)
    }

    private var cardX: CGFloat {
        let raw: CGFloat
        if isLandscape {
            let rightEdge = targetBox.maxX + 12 + cardWidth
            raw = rightEdge < screenSize.width - 16
                ? targetBox.maxX + 12 + cardWidth / 2
                : targetBox.minX - 12 - cardWidth / 2
        } else {
            raw = screenSize.width / 2
        }
        let halfW = cardWidth / 2
        return min(max(raw, halfW + 16), screenSize.width - halfW - 16)
    }

    private var cardY: CGFloat {
        let half = measuredCardHeight / 2
        let raw: CGFloat
        if isLandscape {
            raw = targetBox.midY
        } else {
            let belowY = targetBox.maxY + 12 + half
            if belowY + half < screenSize.height - 16 {
                raw = belowY
            } else {
                let aboveY = targetBox.minY - 12 - half
                if aboveY - half > 16 {
                    raw = aboveY
                } else {
                    raw = screenSize.height / 2
                }
            }
        }
        return min(max(raw, half + 16), screenSize.height - half - 16)
    }

    private var connectorFrom: CGPoint {
        if isLandscape {
            return CGPoint(
                x: cardX < targetBox.midX ? targetBox.minX : targetBox.maxX,
                y: targetBox.midY
            )
        } else {
            return CGPoint(
                x: targetBox.midX,
                y: cardY < targetBox.midY ? targetBox.minY : targetBox.maxY
            )
        }
    }

    private var connectorTo: CGPoint {
        if isLandscape {
            return CGPoint(
                x: cardX < targetBox.midX ? cardX + cardWidth / 2 : cardX - cardWidth / 2,
                y: cardY
            )
        } else {
            let half = measuredCardHeight / 2
            return CGPoint(
                x: cardX,
                y: cardY < targetBox.midY ? cardY + half : cardY - half
            )
        }
    }

    var body: some View {
        ZStack {
            // Bounding box stroke
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(0.45), lineWidth: 1)
                .frame(width: targetBox.width, height: targetBox.height)
                .position(x: targetBox.midX, y: targetBox.midY)
                .opacity(appear ? 1 : 0)

            // Corner brackets
            CornerBrackets(rect: targetBox, len: bracketLen, thick: bracketThick)
                .opacity(appear ? 1 : 0)

            // Connector line
            ConnectorLine(from: connectorFrom, to: connectorTo)
                .opacity(appear ? 0.5 : 0)

            // Floating product card
            FloatingProductCard(
                product: product,
                cartQuantity: cartQuantity,
                onAddToCart: onAddToCart,
                onBuyNow: onBuyNow,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
                onDismiss: onDismiss
            )
            .frame(width: cardWidth)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: CardSizePreference.self, value: geo.size)
                }
            )
            .onPreferenceChange(CardSizePreference.self) { size in
                measuredCardHeight = size.height
            }
            .position(x: cardX, y: cardY)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.35)) { appear = true }
        }
    }
}

// MARK: - Corner Brackets

struct CornerBrackets: View {
    let rect: CGRect
    let len: CGFloat
    let thick: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let color = GraphicsContext.Shading.color(.white)
            let corners: [(CGPoint, Bool, Bool)] = [
                (CGPoint(x: rect.minX, y: rect.minY), false, false),
                (CGPoint(x: rect.maxX, y: rect.minY), true,  false),
                (CGPoint(x: rect.minX, y: rect.maxY), false, true),
                (CGPoint(x: rect.maxX, y: rect.maxY), true,  true),
            ]
            for (origin, flipX, flipY) in corners {
                let hxDir: CGFloat = flipX ? -1 : 1
                let vyDir: CGFloat = flipY ? -1 : 1
                var hPath = Path()
                hPath.move(to: origin)
                hPath.addLine(to: CGPoint(x: origin.x + hxDir * len, y: origin.y))
                ctx.stroke(hPath, with: color, lineWidth: thick)
                var vPath = Path()
                vPath.move(to: origin)
                vPath.addLine(to: CGPoint(x: origin.x, y: origin.y + vyDir * len))
                ctx.stroke(vPath, with: color, lineWidth: thick)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Connector Line

struct ConnectorLine: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            p.move(to: from)
            p.addLine(to: to)
            ctx.stroke(p, with: .color(.white.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Floating Product Card

struct FloatingProductCard: View {
    let product: Product
    let cartQuantity: Int
    let onAddToCart: () -> Void
    let onBuyNow: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(product.formattedPrice)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.1), in: Circle())
                }
            }

            // Actions — side by side for fewer taps
            HStack(spacing: 10) {
                if cartQuantity > 0 {
                    HStack(spacing: 0) {
                        Button(action: onDecrement) {
                            Image(systemName: "minus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                        }
                        Text("\(cartQuantity)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 28)
                        Button(action: onIncrement) {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    )
                } else {
                    Button(action: onAddToCart) {
                        Text("Add to Cart")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }

                Button(action: onBuyNow) {
                    Text("Buy Now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.3), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(20)
        .background {
            GlassBackground(cornerRadius: 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}

// MARK: - Glass Background (Reusable)

struct GlassBackground: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - Store Loading Prompt

struct StoreLoadingPrompt: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Scan NFC to Start")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Tap a tag or enter a store URL")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Button {
                    appState.loadStore(id: 42, demographic: .adult)
                } label: {
                    Text("Load Demo Store")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                }
            }
            .padding(28)
            .background { GlassBackground(cornerRadius: 24) }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .padding(.horizontal, 40)
            Spacer().frame(height: 100)
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}
