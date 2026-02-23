import Foundation
import SwiftData

@Model
final class SDLocation {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String?
    var city: String?
    var courtCount: Int
    var courtTypeRaw: String
    var hasIndoor: Bool
    var amenities: [String]
    var maxCapacity: Int?
    var contactPhone: String?
    var notes: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    
    var courtType: CourtType {
        get { CourtType(rawValue: courtTypeRaw) ?? .indoor }
        set { courtTypeRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        city: String? = nil,
        courtCount: Int = 1,
        courtType: CourtType = .indoor,
        hasIndoor: Bool = true,
        amenities: [String] = [],
        maxCapacity: Int? = nil,
        contactPhone: String? = nil,
        notes: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.courtCount = courtCount
        self.courtTypeRaw = courtType.rawValue
        self.hasIndoor = hasIndoor
        self.amenities = amenities
        self.maxCapacity = maxCapacity
        self.contactPhone = contactPhone
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Conversion Methods
    static func from(_ location: Location) -> SDLocation {
        SDLocation(
            id: location.id,
            name: location.name,
            address: location.address,
            city: location.city,
            courtCount: location.courtCount,
            courtType: location.courtType,
            hasIndoor: location.hasIndoor,
            amenities: location.amenities,
            maxCapacity: location.maxCapacity,
            contactPhone: location.contactPhone,
            notes: location.notes,
            isActive: location.isActive,
            createdAt: location.createdAt,
            updatedAt: location.updatedAt
        )
    }
    
    func toLocation() -> Location {
        Location(
            id: id,
            name: name,
            address: address,
            city: city,
            courtCount: courtCount,
            courtType: courtType,
            hasIndoor: hasIndoor,
            amenities: amenities,
            maxCapacity: maxCapacity,
            contactPhone: contactPhone,
            notes: notes,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
