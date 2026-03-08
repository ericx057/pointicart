import Foundation

/// A snapshot of session interaction features at a point in time.
/// This is the "local vector" stored in the vector base.
struct InteractionVector: Codable {
    let timestamp: Date
    let timeInStoreSeconds: Double
    let cartItemCount: Int
    let totalCartAdds: Int
    let dwellCount: Int
    let uniqueProductsViewed: Int
    let demographic: String

    /// Adds per minute. Extrapolates for sessions under 30 seconds.
    var addFrequency: Double {
        let minutes = timeInStoreSeconds / 60.0
        guard minutes >= 0.5 else {
            return Double(totalCartAdds) * 2.0
        }
        return Double(totalCartAdds) / minutes
    }

    /// The normalized feature array used by the recommendation engine.
    /// Order: [timeNorm, cartNorm, freqNorm, dwellNorm, viewNorm]
    func normalizedFeatures(
        maxTime: Double = 600,
        maxCart: Double = 5,
        maxFreq: Double = 2,
        maxDwell: Double = 10,
        maxViews: Double = 8
    ) -> [Double] {
        [
            min(timeInStoreSeconds / maxTime, 1.0),
            min(Double(cartItemCount) / maxCart, 1.0),
            min(addFrequency / maxFreq, 1.0),
            min(Double(dwellCount) / maxDwell, 1.0),
            min(Double(uniqueProductsViewed) / maxViews, 1.0)
        ]
    }
}
