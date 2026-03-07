import UIKit

// MARK: - Inference Result

struct IdentificationResult: Sendable {
    /// Matches a key in StoreService.products
    let productKey: String
    /// Bounding box in 0-1 normalized portrait-image space (origin top-left).
    /// nil if the model did not return a box.
    let normalizedBox: CGRect?
}

// MARK: - Inference Protocol

protocol InferenceService: Sendable {
    func identify(image: UIImage, candidates: [String]) async throws -> IdentificationResult?
}
