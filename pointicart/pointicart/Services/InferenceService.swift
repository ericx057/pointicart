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
    /// Identify a product from the image.
    /// - Parameters:
    ///   - image: The camera frame snapshot.
    ///   - candidates: Product name keys from the store catalog.
    ///   - candidateDescriptions: Maps each candidate name to a visual description for comparison.
    func identify(image: UIImage, candidates: [String], candidateDescriptions: [String: String]) async throws -> IdentificationResult?
}
