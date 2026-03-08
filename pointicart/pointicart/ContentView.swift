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
                        Text("Identifying product...")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.5), in: Capsule())
                            .position(x: position.x, y: position.y + 50)
                            .transition(.opacity)
                    }
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
                        onTryOn: {
                            appState.enterTryOnMode(
                                product: product,
                                snapshot: appState.lastIdentificationSnapshot,
                                boundingBox: appState.identifiedBoundingBox
                            )
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

                // Layer 3.5: Try-on mode overlay
                if appState.isTryOnMode {
                    TryOnOverlay(appState: appState)
                }

                // Layer 4: Cart overlay (bottom bar)
                CartOverlayView(
                    cartManager: appState.cartManager,
                    storeName: appState.storeService.storeName,
                    suggestedProduct: appState.upsellProduct,
                    onAddSuggested: { product in
                        appState.cartManager.add(product)
                    },
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
        .animation(.spring(duration: 0.4), value: appState.isTryOnMode)
        .sheet(isPresented: $appState.showDirectCheckout) {
            CheckoutSheet(
                cartManager: appState.cartManager,
                storeName: appState.storeService.storeName,
                suggestedProduct: appState.upsellProduct,
                onAddSuggested: { product in
                    appState.cartManager.add(product)
                },
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

// MARK: - Card Size Preference Key

private struct CardSizePreference: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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
    let onTryOn: () -> Void
    let onDismiss: () -> Void

    @State private var bracketOpacity: Double = 0
    @State private var bracketScale: CGFloat = 0.85
    @State private var glowOpacity: Double = 0
    @State private var measuredCardHeight: CGFloat = 200

    private var cardWidth: CGFloat { isLandscape ? 300 : min(screenSize.width - 32, 300) }
    private let bracketLen: CGFloat = 24
    private let bracketThick: CGFloat = 3

    private var isLandscape: Bool { screenSize.width > screenSize.height }

    /// The rect we draw brackets around — falls back to a default box at the fingertip.
    private var targetBox: CGRect {
        if let box = boundingBox { return box }
        let center = fallbackPosition ?? CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        return CGRect(x: center.x - 60, y: center.y - 60, width: 120, height: 120)
    }

    /// Card position depends on orientation.
    /// Landscape: beside the bounding box (right preferred, left fallback).
    /// Portrait: below the bounding box (above fallback if no room below).
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
        // Clamp to screen edges with 16pt minimum padding
        let halfW = cardWidth / 2
        return min(max(raw, halfW + 16), screenSize.width - halfW - 16)
    }

    private var cardY: CGFloat {
        let half = measuredCardHeight / 2
        let raw: CGFloat
        if isLandscape {
            raw = targetBox.midY
        } else {
            // Portrait: prefer below the box
            let belowY = targetBox.maxY + 12 + half
            if belowY + half < screenSize.height - 16 {
                raw = belowY
            } else {
                // Fallback: above the box
                let aboveY = targetBox.minY - 12 - half
                if aboveY - half > 16 {
                    raw = aboveY
                } else {
                    // Last resort: screen center
                    raw = screenSize.height / 2
                }
            }
        }
        // Clamp to screen edges with 16pt minimum padding
        return min(max(raw, half + 16), screenSize.height - half - 16)
    }

    /// Connector line start point on the bounding box edge.
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

    /// Connector line end point on the card edge.
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
                from: connectorFrom,
                to: connectorTo
            )
            .opacity(bracketOpacity * 0.6)

            // Floating product info card
            FloatingProductCard(
                product: product,
                onAddToCart: onAddToCart,
                onBuyNow: onBuyNow,
                onTryOn: onTryOn,
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
    var color: Color = .green

    var body: some View {
        Canvas { ctx, _ in
            let shading = GraphicsContext.Shading.color(color)
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
                ctx.stroke(hPath, with: shading, lineWidth: thick)
                var vPath = Path()
                vPath.move(to: origin)
                vPath.addLine(to: CGPoint(x: origin.x, y: origin.y + vyDir * len))
                ctx.stroke(vPath, with: shading, lineWidth: thick)
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
    let onAddToCart: () -> Void
    let onBuyNow: () -> Void
    let onTryOn: () -> Void
    let onDismiss: () -> Void

    @State private var shimmerOffset: CGFloat = -1
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: title + dismiss
            HStack(alignment: .top) {
                Text(product.name)
                    .font(.custom("DMSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                }
            }

            Text(product.formattedPrice)
                .font(.custom("DMSans-Bold", size: 24))
                .foregroundStyle(.primary)

            // Action buttons
            VStack(spacing: 10) {
                Button(action: onAddToCart) {
                    Text("Add to Cart")
                        .font(.custom("DMSans-Bold", size: 18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: onBuyNow) {
                    Text("Buy Now")
                        .font(.custom("DMSans-Bold", size: 18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .scaleEffect(pulseScale)

                if product.isClothing {
                    Button(action: onTryOn) {
                        Label("Try On", systemImage: "person.crop.rectangle")
                            .font(.custom("DMSans-Bold", size: 16))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .opacity(0.7)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [.green.opacity(0.6), .green.opacity(0.2), .green.opacity(0.6)],
                        startPoint: UnitPoint(x: shimmerOffset, y: 0),
                        endPoint: UnitPoint(x: shimmerOffset + 0.5, y: 1)
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .green.opacity(0.25), radius: 16, y: 6)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.5
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.03
            }
        }
    }
}

// MARK: - Try-On Overlay

struct TryOnOverlay: View {
    let appState: AppState
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var showZoomLabel: Bool = false

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
    }

    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    var body: some View {
        ZStack {
            // 1. Frozen frame — full screen, no shift
            if appState.tryOnResultImage == nil,
               let capturedImage = appState.capturedPersonImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // 2. Result image — true full screen
            if let resultImage = appState.tryOnResultImage {
                Image(uiImage: resultImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // 3. Pinch-to-zoom (live camera only, before capture)
            if appState.capturedPersonImage == nil && !appState.isGeneratingTryOn {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoom = (baseZoom * value).clamped(to: 1.0...5.0)
                                zoomScale = newZoom
                                appState.applyZoom?(newZoom)
                                showZoomLabel = true
                            }
                            .onEnded { _ in
                                baseZoom = zoomScale
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showZoomLabel = false
                                }
                            }
                    )
            }

            // 4. Zoom level label (centered, fades out)
            if showZoomLabel {
                Text(String(format: "%.1f×", zoomScale))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .transition(.opacity)
            }

            // 5. Loading indicator — centered in ZStack (not inside VStack)
            if appState.isGeneratingTryOn {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Generating try-on...")
                        .font(.custom("DMSans-Bold", size: 16))
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
            }

            // 6. Top banner — pushed below the status bar
            VStack(spacing: 0) {
                Color.clear.frame(height: safeTop)
                HStack {
                    Image(systemName: "tshirt").font(.headline)
                    Text("Try On\(appState.tryOnProduct.map { ": \($0.name)" } ?? "")")
                        .font(.custom("DMSans-Bold", size: 16))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // 7. Error + bottom buttons — always full-width centered
            VStack(spacing: 0) {
                Spacer()
                if let error = appState.tryOnError {
                    Text(error)
                        .font(.custom("DMSans-Bold", size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 12)
                }
                VStack(spacing: 12) {
                    if appState.capturedPersonImage == nil && !appState.isGeneratingTryOn {
                        Button { appState.captureAndGenerateTryOn() } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .font(.custom("DMSans-Bold", size: 18))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                    if appState.tryOnResultImage != nil ||
                       (appState.tryOnError != nil && !appState.isGeneratingTryOn) {
                        Button {
                            appState.tryOnResultImage = nil
                            appState.capturedPersonImage = nil
                            appState.tryOnError = nil
                        } label: {
                            Label("Retake", systemImage: "camera.fill")
                                .font(.custom("DMSans-Bold", size: 18))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                    Button {
                        withAnimation(.spring(duration: 0.3)) { appState.exitTryOnMode() }
                    } label: {
                        Label("Exit Try-On", systemImage: "xmark")
                            .font(.custom("DMSans-Bold", size: 18))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, safeBottom + 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onDisappear {
            // Reset zoom when overlay is dismissed
            zoomScale = 1.0
            baseZoom = 1.0
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
