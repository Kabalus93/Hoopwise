import Foundation
import SwiftData

@Model
final class SDSchool {
    var id: UUID = UUID()
    var name: String = ""
    var chineseName: String?
    var contactName: String?
    var contactPhone: String?
    var contactEmail: String?
    var address: String?
    var notes: String?
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

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

    static func from(_ school: School) -> SDSchool {
        SDSchool(
            id: school.id,
            name: school.name,
            chineseName: school.chineseName,
            contactName: school.contactName,
            contactPhone: school.contactPhone,
            contactEmail: school.contactEmail,
            address: school.address,
            notes: school.notes,
            isActive: school.isActive,
            createdAt: school.createdAt,
            updatedAt: school.updatedAt
        )
    }

    func toSchool() -> School {
        School(
            id: id,
            name: name,
            chineseName: chineseName,
            contactName: contactName,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            address: address,
            notes: notes,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
