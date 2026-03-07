import SwiftUI

struct ContentView: View {
    @State var appState: AppState

    var body: some View {
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

            // Layer 3: Product highlight glow at identified position
            if appState.isProductRecognized, let pos = appState.identifiedPosition {
                ProductHighlight()
                    .position(pos)
            }

            // Layer 4: Product identification cards
            if appState.showProductCard, let product = appState.identifiedProduct {
                VStack(spacing: 12) {
                    Spacer()
                    ProductCardView(
                        product: product,
                        onAddToCart: {
                            appState.cartManager.add(product)
                            appState.startAbandonedCartTimer()
                        },
                        onBuyNow: {
                            appState.cartManager.add(product)
                            appState.showDirectCheckout = true
                        }
                    )
                    if let upsell = appState.upsellProduct {
                        UpsellCardView(product: upsell) {
                            appState.cartManager.add(upsell)
                        }
                    }
                    Spacer().frame(height: 80)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
                .onTapGesture { } // Prevent tap-through
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { _ in
                            withAnimation(.spring(duration: 0.3)) {
                                appState.dismissProductCard()
                            }
                        }
                )
            }

            // Layer 5: Cart overlay (bottom bar)
            CartOverlayView(
                cartManager: appState.cartManager,
                storeName: appState.storeService.storeName,
                onPaymentComplete: { appState.cancelAbandonedCartTimer() }
            )

            // Layer 6: Store loading prompt (if no store loaded)
            if !appState.storeService.isLoaded {
                StoreLoadingPrompt(appState: appState)
            }
        }
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

// MARK: - Product Highlight

struct ProductHighlight: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: 100, height: 100)
                .scaleEffect(scale)
                .opacity(opacity)
            Circle()
                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                .frame(width: 140, height: 140)
                .scaleEffect(scale)
                .opacity(opacity * 0.5)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                scale = 1.15
                opacity = 0.4
            }
        }
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
