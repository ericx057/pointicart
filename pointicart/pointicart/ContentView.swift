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

                // Layer 3: Object highlight + floating info card
                if appState.showProductCard, let product = appState.identifiedProduct {
                    ObjectHighlightOverlay(
                        product: product,
                        upsell: appState.upsellProduct,
                        boundingBox: appState.identifiedBoundingBox,
                        fallbackPosition: appState.identifiedPosition,
                        screenSize: geo.size,
                        onAddToCart: {
                            appState.cartManager.add(product)
                            appState.startAbandonedCartTimer()
                            withAnimation(.spring(duration: 0.3)) { appState.dismissProductCard() }
                        },
                        onBuyNow: {
                            appState.cartManager.add(product)
                            appState.showDirectCheckout = true
                        },
                        onDismiss: {
                            withAnimation(.spring(duration: 0.3)) { appState.dismissProductCard() }
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // Layer 4: Cart overlay (bottom bar)
                CartOverlayView(
                    cartManager: appState.cartManager,
                    storeName: appState.storeService.storeName,
                    onPaymentComplete: { appState.cancelAbandonedCartTimer() }
                )

                // Layer 5: Store loading prompt (if no store loaded)
                if !appState.storeService.isLoaded {
                    StoreLoadingPrompt(appState: appState)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.4), value: appState.showProductCard)
        .sheet(isPresented: $appState.showDirectCheckout) {
            CheckoutSheet(
                cartManager: appState.cartManager,
                storeName: appState.storeService.storeName,
                onPaymentComplete: {
                    appState.cancelAbandonedCartTimer()
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

    private var ringColor: Color {
        if isProductRecognized { return .green }
        if isDwelling || isIdentifying { return .yellow }
        return .white
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(ringColor, lineWidth: 2)
                .frame(width: 60, height: 60)
                .opacity(0.8)

            // Scanning arc (amber while dwelling/identifying)
            if (isDwelling || isIdentifying) && !isProductRecognized {
                Circle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }

            // Recognized arc (green pulse when product confirmed)
            if isProductRecognized {
                Circle()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }

            // Center dot
            Circle()
                .fill(isProductRecognized ? Color.green : (isDwelling || isIdentifying ? Color.yellow : Color.white))
                .frame(width: 8, height: 8)

            // Crosshair lines
            Group {
                Rectangle().frame(width: 1, height: 20).offset(y: -20)
                Rectangle().frame(width: 1, height: 20).offset(y: 20)
                Rectangle().frame(width: 20, height: 1).offset(x: -20)
                Rectangle().frame(width: 20, height: 1).offset(x: 20)
            }
            .foregroundStyle(ringColor)
            .opacity(0.6)
        }
    }
}

// MARK: - Object Highlight Overlay

/// Draws animated corner brackets around the detected object and shows
/// a floating product info card adjacent to the bounding box.
struct ObjectHighlightOverlay: View {
    let product: Product
    let upsell: Product?
    let boundingBox: CGRect?
    let fallbackPosition: CGPoint?
    let screenSize: CGSize
    let onAddToCart: () -> Void
    let onBuyNow: () -> Void
    let onDismiss: () -> Void

    @State private var bracketOpacity: Double = 0
    @State private var bracketScale: CGFloat = 0.85
    @State private var glowOpacity: Double = 0

    private let cardWidth: CGFloat = 230
    private let bracketLen: CGFloat = 24
    private let bracketThick: CGFloat = 3

    /// The rect we draw brackets around — falls back to a default box at the fingertip.
    private var targetBox: CGRect {
        if let box = boundingBox { return box }
        let center = fallbackPosition ?? CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        return CGRect(x: center.x - 60, y: center.y - 60, width: 120, height: 120)
    }

    /// Card x position: prefer right side, fall back to left.
    private var cardX: CGFloat {
        let rightEdge = targetBox.maxX + 12 + cardWidth
        return rightEdge < screenSize.width
            ? targetBox.maxX + 12 + cardWidth / 2
            : targetBox.minX - 12 - cardWidth / 2
    }

    /// Card y position: vertically center on the box, clamped to screen.
    private var cardY: CGFloat {
        let half = estimatedCardHeight / 2
        return min(max(targetBox.midY, half + 8), screenSize.height - half - 8)
    }

    private var estimatedCardHeight: CGFloat { upsell == nil ? 220 : 290 }

    var body: some View {
        ZStack {
            // Bounding box glow fill
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08))
                .frame(width: targetBox.width, height: targetBox.height)
                .position(x: targetBox.midX, y: targetBox.midY)
                .opacity(glowOpacity)

            // Bounding box stroke
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                .frame(width: targetBox.width, height: targetBox.height)
                .position(x: targetBox.midX, y: targetBox.midY)
                .opacity(bracketOpacity)

            // Corner brackets
            CornerBrackets(rect: targetBox, len: bracketLen, thick: bracketThick)
                .scaleEffect(bracketScale)
                .opacity(bracketOpacity)

            // Connector line from box edge to card
            ConnectorLine(
                from: CGPoint(x: cardX < targetBox.midX ? targetBox.minX : targetBox.maxX,
                              y: targetBox.midY),
                to: CGPoint(x: cardX < targetBox.midX ? cardX + cardWidth / 2 : cardX - cardWidth / 2,
                            y: cardY)
            )
            .opacity(bracketOpacity * 0.6)

            // Floating product info card
            FloatingProductCard(
                product: product,
                upsell: upsell,
                onAddToCart: onAddToCart,
                onBuyNow: onBuyNow,
                onDismiss: onDismiss
            )
            .frame(width: cardWidth)
            .position(x: cardX, y: cardY)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.4)) {
                bracketOpacity = 1
                bracketScale = 1
                glowOpacity = 1
            }
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
            let color = GraphicsContext.Shading.color(.green)
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
// `from` and `to` are in the coordinate space of ObjectHighlightOverlay's ZStack
// (which is sized to fill the screen via .frame(width:height:) in ContentView).

struct ConnectorLine: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            p.move(to: from)
            p.addLine(to: to)
            ctx.stroke(p, with: .color(.green.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Floating Product Card

struct FloatingProductCard: View {
    let product: Product
    let upsell: Product?
    let onAddToCart: () -> Void
    let onBuyNow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: product.imageSystemName)
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            Text(product.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(product.formattedPrice)
                .font(.title3.bold())
                .foregroundStyle(.green)

            // Action buttons
            VStack(spacing: 6) {
                Button(action: onAddToCart) {
                    Label("Add to Cart", systemImage: "cart.badge.plus")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: onBuyNow) {
                    Label("Buy Now", systemImage: "bolt.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            // Upsell suggestion
            if let upsell {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: upsell.imageSystemName)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Often paired with")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(upsell.name)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Text(upsell.formattedPrice)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .green.opacity(0.2), radius: 12, y: 4)
    }
}

// MARK: - Store Loading Prompt

struct StoreLoadingPrompt: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                Text("Scan NFC Tag to Start")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Tap an NFC tag or enter a store URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Demo button for hackathon
                Button("Load Demo Store (ID: 42)") {
                    appState.storeService.load(id: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            Spacer().frame(height: 100)
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}
