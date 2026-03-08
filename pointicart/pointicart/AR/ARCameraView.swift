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
        NSLog("[PTIC] ARCameraView makeUIView complete, sceneView assigned")
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
        private let processEveryN = 5

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

            Task { @MainActor [weak self] in
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
                        let elapsed = Date().timeIntervalSince(start)
                        if elapsed >= 0.3 && !hasFiredDwell {
                            NSLog("[PTIC] DWELL FIRED — elapsed=%.2fs, storeLoaded=%d, candidates=%d",
                                  elapsed,
                                  appState.storeService.isLoaded ? 1 : 0,
                                  appState.storeService.productKeys.count)
                            appState.isDwelling = true
                            hasFiredDwell = true
                            fireDwellIdentification()
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

        private func fireDwellIdentification() {
            NSLog("[PTIC] fireDwellIdentification — sceneView=%@, session=%@",
                  String(describing: sceneView),
                  String(describing: sceneView?.session))

            guard let currentBuffer = sceneView?.session.currentFrame?.capturedImage else {
                NSLog("[PTIC] FAILED — no current frame from ARSession")
                return
            }

            NSLog("[PTIC] Got fresh pixel buffer: %dx%d",
                  CVPixelBufferGetWidth(currentBuffer),
                  CVPixelBufferGetHeight(currentBuffer))

            let lockStatus = CVPixelBufferLockBaseAddress(currentBuffer, .readOnly)
            NSLog("[PTIC] Lock status: %d", lockStatus)

            let ciImage = CIImage(cvPixelBuffer: currentBuffer).oriented(.right)
            NSLog("[PTIC] CIImage extent: %@", NSCoder.string(for: ciImage.extent))

            let ctx = CIContext()
            let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent)
            CVPixelBufferUnlockBaseAddress(currentBuffer, .readOnly)

            guard let cgImage else {
                NSLog("[PTIC] FAILED — createCGImage returned nil")
                return
            }

            let snapshot = UIImage(cgImage: cgImage)
            NSLog("[PTIC] Snapshot OK: %.0fx%.0f", snapshot.size.width, snapshot.size.height)

            Task { @MainActor in
                NSLog("[PTIC] Calling onDwellDetected...")
                await self.appState.onDwellDetected(image: snapshot)
                NSLog("[PTIC] onDwellDetected returned")
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
