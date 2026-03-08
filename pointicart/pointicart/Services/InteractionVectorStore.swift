import Foundation
import Observation

/// Tracks all session interactions and maintains the local vector base.
@Observable
final class InteractionVectorStore {

    // MARK: - Current Session State

    private(set) var sessionStart: Date?
    private(set) var totalCartAdds: Int = 0
    private(set) var dwellCount: Int = 0
    private(set) var viewedProductKeys: Set<String> = []
    private(set) var demographic: Demographic?

    // MARK: - Historical Vectors (Persisted)

    private(set) var historicalVectors: [InteractionVector] = []

    private let storageKey = "pointicart_interaction_vectors"

    // MARK: - Computed Properties

    var timeInStoreSeconds: TimeInterval {
        guard let start = sessionStart else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var isSessionActive: Bool {
        sessionStart != nil
    }

    var addFrequency: Double {
        let minutes = timeInStoreSeconds / 60.0
        guard minutes >= 0.5 else {
            return Double(totalCartAdds) * 2.0
        }
        return Double(totalCartAdds) / minutes
    }

    var currentFeatureVector: [Double] {
        [
            timeInStoreSeconds,
            Double(totalCartAdds),
            addFrequency,
            Double(dwellCount),
            Double(viewedProductKeys.count)
        ]
    }

    // MARK: - Init

    init() {
        loadPersistedVectors()
    }

    // MARK: - Session Lifecycle

    func beginSession(demographic: Demographic) {
        self.demographic = demographic
        sessionStart = Date()
        totalCartAdds = 0
        dwellCount = 0
        viewedProductKeys = []
    }

    func endSession(cartItemCount: Int) {
        guard let demo = demographic else { return }
        let vector = InteractionVector(
            timestamp: Date(),
            timeInStoreSeconds: timeInStoreSeconds,
            cartItemCount: cartItemCount,
            totalCartAdds: totalCartAdds,
            dwellCount: dwellCount,
            uniqueProductsViewed: viewedProductKeys.count,
            demographic: demo.rawValue
        )
        historicalVectors.append(vector)
        persistVectors()

        sessionStart = nil
        totalCartAdds = 0
        dwellCount = 0
        viewedProductKeys = []
        demographic = nil
    }

    // MARK: - Event Recording

    func recordCartAdd() {
        totalCartAdds += 1
    }

    func recordDwell() {
        dwellCount += 1
    }

    func recordProductView(productKey: String) {
        viewedProductKeys.insert(productKey)
    }

    // MARK: - Persistence

    private func persistVectors() {
        guard let data = try? JSONEncoder().encode(historicalVectors) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadPersistedVectors() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let vectors = try? JSONDecoder().decode([InteractionVector].self, from: data)
        else { return }
        historicalVectors = vectors
    }
}
