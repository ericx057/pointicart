import Foundation

/// Standard product sizes.
enum ProductSize: String, Codable, CaseIterable, Comparable {
    case xs = "XS"
    case s  = "S"
    case m  = "M"
    case l  = "L"
    case xl = "XL"

    private var sortOrder: Int {
        switch self {
        case .xs: return 0
        case .s:  return 1
        case .m:  return 2
        case .l:  return 3
        case .xl: return 4
        }
    }

    static func < (lhs: ProductSize, rhs: ProductSize) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Product categories that participate in sizing.
enum ProductCategory: String, Codable {
    case apparel
    case footwear
    case accessories
    case unsized
}

/// Geographic context for a store, used to walk the sizing hierarchy.
struct LocationContext {
    let storeId: Int
    let mallId: String?
    let city: String
    let province: String
    let country: String
}

/// A single sizing data point in the lookup table.
struct SizingDataPoint {
    let demographic: Demographic
    let category: ProductCategory
    let medianSize: ProductSize
    let sampleCount: Int
}

/// The levels of the sizing hierarchy, from most specific to least.
enum LocationLevel: Hashable {
    case store(Int)
    case mall(String)
    case city(String)
    case province(String)
    case national(String)
}
