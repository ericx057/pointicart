@preconcurrency import ARKit
@preconcurrency import Vision
import SwiftUI

struct ARCameraView: UIViewRepresentable {
    let appState: AppState

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        sceneView.session.delegate = context.coordinator
        sceneView.automaticallyUpdatesLighting = true
        sceneView.showsStatistics = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        sceneView.session.run(config)

        context.coordinator.sceneView = sceneView
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    // MARK: - Coordinator (ARSessionDelegate + Hand Tracking)

    class Coordinator: NSObject, ARSessionDelegate {
        let appState: AppState
        weak var sceneView: ARSCNView?
        private var frameCount = 0
        private var isProcessing = false
        private var lastPosition: CGPoint?
        private var dwellStart: Date?
        private var hasFiredDwell = false
        private let processEveryN = 4

        init(appState: AppState) {
            self.appState = appState
            super.init()
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let pixelBuffer = frame.capturedImage
            Task { @MainActor [weak self] in
                self?.handleFrame(pixelBuffer)
            }
        }

        private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
            frameCount += 1
            guard frameCount % processEveryN == 0, !isProcessing else { return }
            isProcessing = true

            Task { [weak self] in
                guard let self else { return }
                let normalizedPoint = await Self.detectIndexTip(in: pixelBuffer)
                self.processTipResult(normalizedPoint, pixelBuffer: pixelBuffer)
            }
        }

        private func processTipResult(_ normalizedPoint: CGPoint?, pixelBuffer: CVPixelBuffer) {
            guard let point = normalizedPoint else {
                appState.fingertipPosition = nil
                appState.isDwelling = false
                dwellStart = nil
                hasFiredDwell = false
                isProcessing = false
                return
            }

            let bounds = sceneView?.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
            let screenPoint = CGPoint(
                x: point.x * bounds.width,
                y: (1 - point.y) * bounds.height
            )
            appState.fingertipPosition = screenPoint

            // Dwell detection
            if let last = lastPosition {
                let dist = hypot(screenPoint.x - last.x, screenPoint.y - last.y)
                if dist < 30 {
                    if let start = dwellStart {
                        if Date().timeIntervalSince(start) >= 0.5 && !hasFiredDwell {
                            appState.isDwelling = true
                            hasFiredDwell = true
                            fireDwellIdentification(pixelBuffer: pixelBuffer)
                        }
                    } else {
                        dwellStart = Date()
                    }
                } else {
                    dwellStart = nil
                    appState.isDwelling = false
                    hasFiredDwell = false
                }
            }
            lastPosition = screenPoint
            isProcessing = false
        }

        private func fireDwellIdentification(pixelBuffer: CVPixelBuffer) {
            // ARKit recycles pixel buffers every frame. CIImage is lazy — it just
            // holds a reference to the buffer, not a copy. If we defer rendering
            // to an async Task the buffer is gone and createCGImage returns nil.
            //
            // Fix: lock the buffer, force-render to CGImage (copies the bits)
            // synchronously, then hand the UIImage to the async Task.
            print("[AR] fireDwellIdentification called")
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            let ctx = CIContext()
            let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

            guard let cgImage else {
                print("[AR] cgImage snapshot failed")
                return
            }
            let snapshot = UIImage(cgImage: cgImage)
            print("[AR] snapshot size: \(snapshot.size)")

            Task {
                await appState.onDwellDetected(image: snapshot)
            }
        }

        // MARK: - Background Vision Processing

        nonisolated private static func detectIndexTip(in pixelBuffer: CVPixelBuffer) async -> CGPoint? {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 1

            do {
                try handler.perform([request])
            } catch {
                return nil
            }

            guard let observation = request.results?.first,
                  let indexTip = try? observation.recognizedPoint(.indexTip),
                  indexTip.confidence > 0.3 else {
                return nil
            }

            return indexTip.location
        }
    }
}
