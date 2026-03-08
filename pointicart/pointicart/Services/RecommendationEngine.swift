import Foundation

/// Computes recommendation intensity from session interaction features.
/// Pure stateless engine — all state lives in InteractionVectorStore.
enum RecommendationEngine {

    // MARK: - Feature Weights (sum to 1.0)

    static let timeWeight: Double = 0.30
    static let cartWeight: Double = 0.25
    static let frequencyWeight: Double = 0.25
    static let browsingWeight: Double = 0.20

    // MARK: - Normalization Caps

    static let maxTimeSeconds: Double  = 600.0
    static let maxCartItems: Double    = 5.0
    static let maxAddFrequency: Double = 2.0
    static let maxDwellCount: Double   = 10.0

    // MARK: - Scoring

    /// Compute a recommendation intensity score from 0.0 to 1.0.
    ///
    /// - 0.0 means "quick in-out shopper, show no recommendations"
    /// - 1.0 means "active browser, show all recommendations"
    static func computeIntensity(
        timeInStore: TimeInterval,
        cartItemCount: Int,
        addFrequency: Double,
        dwellCount: Int
    ) -> Double {
        let tNorm = min(timeInStore / maxTimeSeconds, 1.0)
        let cNorm = min(Double(cartItemCount) / maxCartItems, 1.0)
        let fNorm = min(addFrequency / maxAddFrequency, 1.0)
        let dNorm = min(Double(dwellCount) / maxDwellCount, 1.0)

        let raw = timeWeight * tNorm
                + cartWeight * cNorm
                + frequencyWeight * fNorm
                + browsingWeight * dNorm

        return min(max(raw, 0.0), 1.0)
    }

    // MARK: - Mapping to Product Count

    /// Convert a recommendation intensity score to the maximum number
    /// of suggested products to display.
    static func maxSuggestedProducts(
        forIntensity intensity: Double,
        totalAvailable: Int
    ) -> Int {
        switch intensity {
        case ..<0.15:
            return 0
        case 0.15..<0.30:
            return min(1, totalAvailable)
        case 0.30..<0.50:
            return min(2, totalAvailable)
        case 0.50..<0.70:
            return min(3, totalAvailable)
        case 0.70..<0.85:
            return min(4, totalAvailable)
        default:
            return totalAvailable
        }
    }
}
