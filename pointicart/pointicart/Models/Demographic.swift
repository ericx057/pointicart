import Foundation

/// Binary demographic group, determined by NFC tag data at store entry.
enum Demographic: String, Codable, CaseIterable {
    case kid
    case adult
}

/// Simulated NFC tag payload. In production, this would come from
/// CoreNFC's NFCNDEFMessage. For now, it is constructed at store load time.
struct NFCTagData {
    let storeId: Int
    let demographic: Demographic
    let profileId: String?

    init(storeId: Int, demographic: Demographic, profileId: String? = nil) {
        self.storeId = storeId
        self.demographic = demographic
        self.profileId = profileId
    }
}
