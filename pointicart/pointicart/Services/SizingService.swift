import Foundation
import Observation

/// Provides default product sizes based on demographic and location hierarchy.
///
/// Hierarchy (highest priority first):
///   in-store data > mall data > city data > province data > national data
@Observable
final class SizingService {

    static let minimumSampleCount: Int = 30

    private(set) var locationContext: LocationContext?

    // MARK: - Hardcoded Sizing Lookup Table

    private let sizingTable: [LocationLevel: [SizingDataPoint]] = [
        .national("CA"): [
            SizingDataPoint(demographic: .adult, category: .apparel,     medianSize: .m,  sampleCount: 12000),
            SizingDataPoint(demographic: .adult, category: .footwear,    medianSize: .m,  sampleCount: 9500),
            SizingDataPoint(demographic: .adult, category: .accessories, medianSize: .m,  sampleCount: 7000),
            SizingDataPoint(demographic: .kid,   category: .apparel,     medianSize: .s,  sampleCount: 6000),
            SizingDataPoint(demographic: .kid,   category: .footwear,    medianSize: .s,  sampleCount: 4500),
            SizingDataPoint(demographic: .kid,   category: .accessories, medianSize: .s,  sampleCount: 3000),
        ],

        .national("US"): [
            SizingDataPoint(demographic: .adult, category: .apparel,     medianSize: .l,  sampleCount: 18000),
            SizingDataPoint(demographic: .adult, category: .footwear,    medianSize: .l,  sampleCount: 14000),
            SizingDataPoint(demographic: .adult, category: .accessories, medianSize: .m,  sampleCount: 10000),
            SizingDataPoint(demographic: .kid,   category: .apparel,     medianSize: .s,  sampleCount: 8000),
            SizingDataPoint(demographic: .kid,   category: .footwear,    medianSize: .s,  sampleCount: 6000),
            SizingDataPoint(demographic: .kid,   category: .accessories, medianSize: .s,  sampleCount: 4000),
        ],

        .province("ON"): [
            SizingDataPoint(demographic: .adult, category: .apparel,  medianSize: .m, sampleCount: 3200),
            SizingDataPoint(demographic: .adult, category: .footwear, medianSize: .l, sampleCount: 2800),
            SizingDataPoint(demographic: .kid,   category: .apparel,  medianSize: .s, sampleCount: 1600),
            SizingDataPoint(demographic: .kid,   category: .footwear, medianSize: .s, sampleCount: 1200),
        ],

        .province("IL"): [
            SizingDataPoint(demographic: .adult, category: .apparel,  medianSize: .l, sampleCount: 2900),
            SizingDataPoint(demographic: .adult, category: .footwear, medianSize: .l, sampleCount: 2400),
            SizingDataPoint(demographic: .kid,   category: .apparel,  medianSize: .m, sampleCount: 1400),
            SizingDataPoint(demographic: .kid,   category: .footwear, medianSize: .s, sampleCount: 1000),
        ],

        .city("Toronto"): [
            SizingDataPoint(demographic: .adult, category: .apparel,  medianSize: .m,  sampleCount: 850),
            SizingDataPoint(demographic: .adult, category: .footwear, medianSize: .l,  sampleCount: 720),
            SizingDataPoint(demographic: .kid,   category: .apparel,  medianSize: .xs, sampleCount: 210),
            SizingDataPoint(demographic: .kid,   category: .footwear, medianSize: .s,  sampleCount: 180),
        ],

        .city("Chicago"): [
            SizingDataPoint(demographic: .adult, category: .apparel,  medianSize: .m, sampleCount: 1100),
            SizingDataPoint(demographic: .adult, category: .footwear, medianSize: .l, sampleCount: 900),
            SizingDataPoint(demographic: .kid,   category: .apparel,  medianSize: .m, sampleCount: 320),
            SizingDataPoint(demographic: .kid,   category: .footwear, medianSize: .s, sampleCount: 250),
        ],

        .city("Vancouver"): [
            SizingDataPoint(demographic: .adult, category: .apparel,  medianSize: .l, sampleCount: 780),
            SizingDataPoint(demographic: .adult, category: .footwear, medianSize: .l, sampleCount: 650),
            SizingDataPoint(demographic: .kid,   category: .apparel,  medianSize: .s, sampleCount: 190),
            SizingDataPoint(demographic: .kid,   category: .footwear, medianSize: .m, sampleCount: 150),
        ],

        .store(42): [
            SizingDataPoint(demographic: .adult, category: .apparel,  medianSize: .l, sampleCount: 55),
            SizingDataPoint(demographic: .adult, category: .footwear, medianSize: .l, sampleCount: 42),
            SizingDataPoint(demographic: .kid,   category: .apparel,  medianSize: .s, sampleCount: 18),
            SizingDataPoint(demographic: .kid,   category: .footwear, medianSize: .s, sampleCount: 12),
        ],
    ]

    // MARK: - Public API

    func setLocation(_ context: LocationContext) {
        self.locationContext = context
    }

    /// Returns the default size for a product category given the current
    /// demographic and location, walking the hierarchy from store -> national.
    func defaultSize(
        for category: ProductCategory,
        demographic: Demographic
    ) -> ProductSize? {
        guard category != .unsized else { return nil }
        guard let loc = locationContext else {
            return demographic == .kid ? .s : .m
        }

        var chain: [LocationLevel] = [.store(loc.storeId)]
        if let mallId = loc.mallId {
            chain.append(.mall(mallId))
        }
        chain.append(contentsOf: [
            .city(loc.city),
            .province(loc.province),
            .national(loc.country)
        ])

        for level in chain {
            guard let entries = sizingTable[level] else { continue }
            if let match = entries.first(where: {
                $0.demographic == demographic
                && $0.category == category
                && $0.sampleCount >= Self.minimumSampleCount
            }) {
                NSLog("[PTIC][Sizing] Hit at %@ for %@/%@: %@ (n=%d)",
                      String(describing: level),
                      demographic.rawValue,
                      category.rawValue,
                      match.medianSize.rawValue,
                      match.sampleCount)
                return match.medianSize
            }
        }

        NSLog("[PTIC][Sizing] No data found, using absolute fallback for %@", demographic.rawValue)
        return demographic == .kid ? .s : .m
    }
}
