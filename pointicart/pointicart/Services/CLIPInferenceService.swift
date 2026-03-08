import UIKit
import CoreML
import Accelerate

// MARK: - CLIP Local Inference
// Uses a CoreML CLIP image encoder + pre-computed text embeddings to identify products on-device.
// No network calls — completely offline inference.

final class CLIPInferenceService: InferenceService {

    // MARK: - Model & Embeddings

    private var model: MLModel?
    private var textEmbeddings: [String: [Float]] = [:]
    private let embeddingDim = 512  // CLIP embedding dimension

    // CLIP normalization constants (ImageNet-style, used by OpenAI CLIP)
    private let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
    private let std: [Float] = [0.26862954, 0.26130258, 0.27577711]
    private let imageSize = 224  // Standard CLIP input size

    // Confidence threshold — below this, return "none"
    private let confidenceThreshold: Float = 0.15

    init() {
        loadModel()
        loadTextEmbeddings()
    }

    // MARK: - Model Loading

    private func loadModel() {
        // Try compiled model first, then mlpackage
        let modelNames = ["MobileCLIP", "MobileClip", "clip_image_encoder", "CLIP"]
        var modelURL: URL?

        for name in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                modelURL = url
                break
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                modelURL = url
                break
            }
        }

        guard let url = modelURL else {
            NSLog("[PTIC][CLIP] ERROR: No CLIP model found in bundle. Add MobileCLIP.mlpackage to your Xcode project.")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try MLModel(contentsOf: url, configuration: config)
            NSLog("[PTIC][CLIP] Model loaded from %@", url.lastPathComponent)

            // Log model input/output for debugging
            if let desc = model?.modelDescription {
                NSLog("[PTIC][CLIP] Inputs: %@", desc.inputDescriptionsByName.keys.joined(separator: ", "))
                NSLog("[PTIC][CLIP] Outputs: %@", desc.outputDescriptionsByName.keys.joined(separator: ", "))
            }
        } catch {
            NSLog("[PTIC][CLIP] Failed to load model: %@", error.localizedDescription)
        }
    }

    // MARK: - Text Embeddings

    private func loadTextEmbeddings() {
        // Load pre-computed text embeddings from bundled JSON
        guard let url = Bundle.main.url(forResource: "clip_text_embeddings", withExtension: "json") else {
            NSLog("[PTIC][CLIP] WARNING: clip_text_embeddings.json not found — using fallback embeddings")
            loadFallbackEmbeddings()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: [Float]].self, from: data)
            textEmbeddings = decoded
            NSLog("[PTIC][CLIP] Loaded %d text embeddings from JSON", textEmbeddings.count)
        } catch {
            NSLog("[PTIC][CLIP] Failed to load text embeddings: %@", error.localizedDescription)
            loadFallbackEmbeddings()
        }
    }

    private func loadFallbackEmbeddings() {
        // Fallback: generate random unit vectors (for testing only — won't give meaningful results)
        // In production, you MUST use real pre-computed CLIP text embeddings.
        let productNames = ["Jacket", "T-Shirt", "Hoodie", "Sweater", "Pants", "Dress", "Sneakers",
                           "Scarf", "Cap", "Beanie", "Gloves", "Belt", "Clutch", "Premium Laces"]
        for name in productNames {
            var embedding = (0..<embeddingDim).map { _ in Float.random(in: -1...1) }
            // Normalize to unit vector
            let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
            embedding = embedding.map { $0 / norm }
            textEmbeddings[name.lowercased()] = embedding
        }
        NSLog("[PTIC][CLIP] Generated %d fallback embeddings (random — for testing only!)", textEmbeddings.count)
    }

    // MARK: - Inference

    nonisolated func identify(image: UIImage, candidates: [String], candidateDescriptions: [String: String]) async throws -> IdentificationResult? {
        NSLog("[PTIC][CLIP] identify called — %d candidates", candidates.count)

        guard !candidates.isEmpty else {
            NSLog("[PTIC][CLIP] SKIP — empty candidates")
            return nil
        }

        // Get image embedding
        guard let imageEmbedding = await computeImageEmbedding(image: image) else {
            NSLog("[PTIC][CLIP] FAILED — could not compute image embedding")
            return nil
        }

        // Find best matching candidate via cosine similarity
        var bestMatch: String?
        var bestScore: Float = -1.0

        for candidate in candidates {
            let key = candidate.lowercased()
            guard let textEmb = await MainActor.run(body: { textEmbeddings[key] }) else {
                NSLog("[PTIC][CLIP] No embedding for '%@'", candidate)
                continue
            }

            let score = cosineSimilarity(imageEmbedding, textEmb)
            NSLog("[PTIC][CLIP] %@ → %.4f", candidate, score)

            if score > bestScore {
                bestScore = score
                bestMatch = candidate
            }
        }

        guard let match = bestMatch, bestScore >= confidenceThreshold else {
            NSLog("[PTIC][CLIP] No confident match (best=%.4f, threshold=%.4f)", bestScore, confidenceThreshold)
            return nil
        }

        NSLog("[PTIC][CLIP] MATCH: %@ (score=%.4f)", match, bestScore)
        return IdentificationResult(productKey: match, normalizedBox: nil)
    }

    // MARK: - Image Embedding

    private func computeImageEmbedding(image: UIImage) async -> [Float]? {
        guard let model = await MainActor.run(body: { self.model }) else {
            NSLog("[PTIC][CLIP] Model not loaded")
            return nil
        }

        // Preprocess image: resize to 224x224 and normalize
        guard let pixelBuffer = preprocessImage(image) else {
            NSLog("[PTIC][CLIP] Failed to preprocess image")
            return nil
        }

        // Run inference
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
            let output = try await Task.detached {
                try model.prediction(from: input)
            }.value

            // Extract embedding from output
            // Common output names: "image_features", "embedding", "output", "image_embedding"
            let outputNames = ["image_features", "embedding", "output", "image_embedding", "features"]
            for name in outputNames {
                if let multiArray = output.featureValue(for: name)?.multiArrayValue {
                    let embedding = multiArrayToFloatArray(multiArray)
                    if !embedding.isEmpty {
                        NSLog("[PTIC][CLIP] Got embedding from '%@': %d dims", name, embedding.count)
                        return normalizeVector(embedding)
                    }
                }
            }

            // If standard names don't work, try the first output
            if let firstKey = output.featureNames.first,
               let multiArray = output.featureValue(for: firstKey)?.multiArrayValue {
                let embedding = multiArrayToFloatArray(multiArray)
                NSLog("[PTIC][CLIP] Got embedding from first output '%@': %d dims", firstKey, embedding.count)
                return normalizeVector(embedding)
            }

            NSLog("[PTIC][CLIP] Could not extract embedding from model output")
            return nil

        } catch {
            NSLog("[PTIC][CLIP] Inference error: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Image Preprocessing

    private func preprocessImage(_ image: UIImage) -> CVPixelBuffer? {
        // Resize to 224x224
        let size = CGSize(width: imageSize, height: imageSize)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = resized?.cgImage else { return nil }

        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            imageSize, imageSize,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: imageSize,
            height: imageSize,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageSize, height: imageSize))

        return buffer
    }

    // MARK: - Utilities

    private func multiArrayToFloatArray(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            result[i] = ptr[i]
        }
        return result
    }

    private func normalizeVector(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot  // Vectors are already normalized, so dot product = cosine similarity
    }
}
