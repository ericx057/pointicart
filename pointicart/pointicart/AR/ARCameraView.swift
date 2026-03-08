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

            // Don't process hand tracking until a store is loaded (NFC/demo)
            guard appState.storeService.isLoaded else { return }

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
                        if elapsed >= 0.8 && !hasFiredDwell {
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
            let extent = ciImage.extent
            NSLog("[PTIC] CIImage extent: %@", NSCoder.string(for: extent))

            // Crop around the fingertip so Gemini focuses on what the user is pointing at.
            // Map screen position to image-pixel position, then take a region around it.
            let cropRect: CGRect
            if let tip = lastPosition, let bounds = sceneView?.bounds, bounds.width > 0, bounds.height > 0 {
                // Screen-point → normalized (0-1)
                let nx = tip.x / bounds.width
                let ny = tip.y / bounds.height

                // Normalized → image-pixel (portrait oriented image)
                let imgX = nx * extent.width
                let imgY = ny * extent.height

                // Crop a square region around the finger (40% of the shorter dimension)
                let cropSize = min(extent.width, extent.height) * 0.5
                let half = cropSize / 2.0
                let rawRect = CGRect(x: imgX - half, y: imgY - half, width: cropSize, height: cropSize)

                // Clamp to image bounds
                cropRect = rawRect.intersection(extent)
                NSLog("[PTIC] Cropping around fingertip: screen=(%.0f,%.0f) img=(%.0f,%.0f) crop=%@",
                      tip.x, tip.y, imgX, imgY, NSCoder.string(for: cropRect))
            } else {
                cropRect = extent
                NSLog("[PTIC] No fingertip — using full image")
            }

            let ctx = CIContext()
            let cgImage = ctx.createCGImage(ciImage, from: cropRect)
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
