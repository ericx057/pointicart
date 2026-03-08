import SwiftUI
import UIKit

// MARK: - Try-On Overlay
// Full-screen AR overlay that captures a frame on demand and sends it to Vertex AI.

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
            // 1. Frozen frame — full screen, shown after capture, before result
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

            // 3. Pinch-to-zoom on live camera (before capture)
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

            // 5. Loading indicator — centered
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

            // 6. Top banner — below status bar
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

            // 7. Error + bottom buttons
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
