import Foundation

/// A partner school for school-collaboration programs.
/// Lightweight on purpose — coaches just need a name, contact, and a
/// scratch-pad. Tracked separately from `Location` because a school may
/// run sessions across multiple courts/venues and may not be a venue at all
/// from the company's bookings perspective.
struct School: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Optional Chinese name — surfaced when the app is in Chinese mode.
    var chineseName: String?
    var contactName: String?
    var contactPhone: String?
    var contactEmail: String?
    var address: String?
    var notes: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        chineseName: String? = nil,
        contactName: String? = nil,
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        address: String? = nil,
        notes: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.chineseName = chineseName
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.address = address
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display name that respects the active language: Chinese name when
    /// the app is in Chinese mode and one is set, otherwise the canonical name.
    var displayName: String {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        if isCN, let cn = chineseName, !cn.isEmpty { return cn }
        return name
    }
}
