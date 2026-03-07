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
                            fireDwellIdentification(pixelBuffer: pixelBuffer, normalizedPoint: point)
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

        private func fireDwellIdentification(pixelBuffer: CVPixelBuffer, normalizedPoint: CGPoint) {
            Task {
                let image = await Self.cropImage(from: pixelBuffer, around: normalizedPoint)
                if let img = image {
                    await appState.onDwellDetected(image: img)
                }
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

        nonisolated private static func cropImage(from pixelBuffer: CVPixelBuffer, around normalizedPoint: CGPoint) async -> UIImage? {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let cropSize: CGFloat = 400
            let halfSize = cropSize / 2
            let centerX = normalizedPoint.x * imageWidth
            let centerY = normalizedPoint.y * imageHeight

            let cropRect = CGRect(
                x: max(0, centerX - halfSize),
                y: max(0, centerY - halfSize),
                width: min(cropSize, imageWidth - max(0, centerX - halfSize)),
                height: min(cropSize, imageHeight - max(0, centerY - halfSize))
            )

            let cropped = ciImage.cropped(to: cropRect)
            let context = CIContext()
            guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }
}
