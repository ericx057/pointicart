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
                ScanningIndicator(isDwelling: appState.isDwelling, isIdentifying: appState.isIdentifying)
                    .position(position)
            }

            // Layer 3: Product identification cards
            if appState.showProductCard, let product = appState.identifiedProduct {
                VStack(spacing: 12) {
                    Spacer()
                    ProductCardView(product: product) {
                        appState.cartManager.add(product)
                        appState.startAbandonedCartTimer()
                    }
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
        .animation(.spring(duration: 0.4), value: appState.showProductCard)
    }
}

// MARK: - Scanning Indicator

struct ScanningIndicator: View {
    let isDwelling: Bool
    let isIdentifying: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(isDwelling ? Color.green : Color.white, lineWidth: 2)
                .frame(width: 60, height: 60)
                .opacity(0.8)

            // Dwell progress arc
            if isDwelling {
                Circle()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }

            // Center dot
            Circle()
                .fill(isIdentifying ? Color.yellow : (isDwelling ? Color.green : Color.white))
                .frame(width: 8, height: 8)

            // Crosshair lines
            Group {
                Rectangle().frame(width: 1, height: 20).offset(y: -20)
                Rectangle().frame(width: 1, height: 20).offset(y: 20)
                Rectangle().frame(width: 20, height: 1).offset(x: -20)
                Rectangle().frame(width: 20, height: 1).offset(x: 20)
            }
            .foregroundStyle(isDwelling ? Color.green : Color.white)
            .opacity(0.6)
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
