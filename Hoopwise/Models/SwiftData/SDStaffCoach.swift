import Foundation
import SwiftData

@Model
final class SDStaffCoach {
    @Attribute(.unique) var id: UUID
    var organizationId: UUID?
    var name: String
    var chineseName: String?
    var email: String?
    var phone: String?
    var roleRaw: String
    var accessLevelRaw: String = "Coaching Staff"  // Default for migration
    var specializations: [String]
    var ageGroupsRaw: [String]
    var avatarColorRaw: String
    var isActive: Bool
    var hireDate: Date?
    var notes: String?
    var profileImageData: Data?
    var createdAt: Date
    var updatedAt: Date
    
    var role: CoachRole {
        get { CoachRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }
    
    var accessLevel: AccessLevel {
        get { AccessLevel(rawValue: accessLevelRaw) ?? .coachingStaff }
        set { accessLevelRaw = newValue.rawValue }
    }
    
    var ageGroups: [AgeGroup] {
        get { ageGroupsRaw.compactMap { AgeGroup(rawValue: $0) } }
        set { ageGroupsRaw = newValue.map { $0.rawValue } }
    }
    
    var avatarColor: AvatarColor {
        get { AvatarColor(rawValue: avatarColorRaw) ?? .blue }
        set { avatarColorRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        organizationId: UUID? = nil,
        name: String,
        chineseName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        role: CoachRole = .assistant,
        accessLevel: AccessLevel = .coachingStaff,
        specializations: [String] = [],
        ageGroups: [AgeGroup] = [],
        avatarColor: AvatarColor = .blue,
        isActive: Bool = true,
        hireDate: Date? = nil,
        notes: String? = nil,
        profileImageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.organizationId = organizationId
        self.name = name
        self.chineseName = chineseName
        self.email = email
        self.phone = phone
        self.roleRaw = role.rawValue
        self.accessLevelRaw = accessLevel.rawValue
        self.specializations = specializations
        self.ageGroupsRaw = ageGroups.map { $0.rawValue }
        self.avatarColorRaw = avatarColor.rawValue
        self.isActive = isActive
        self.hireDate = hireDate
        self.notes = notes
        self.profileImageData = profileImageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Conversion Methods
    static func from(_ coach: StaffCoach) -> SDStaffCoach {
        let sdCoach = SDStaffCoach(
            id: coach.id,
            organizationId: coach.organizationId,
            name: coach.name,
            chineseName: coach.chineseName,
            email: coach.email,
            phone: coach.phone,
            role: coach.role,
            accessLevel: coach.accessLevel,
            specializations: coach.specializations,
            ageGroups: coach.ageGroups,
            avatarColor: coach.avatarColor,
            isActive: coach.isActive,
            hireDate: coach.hireDate,
            notes: coach.notes,
            profileImageData: coach.profileImageData,
            createdAt: coach.createdAt,
            updatedAt: coach.updatedAt
        )
        return sdCoach
    }
    
    func toStaffCoach() -> StaffCoach {
        StaffCoach(
            id: id,
            organizationId: organizationId,
            name: name,
            chineseName: chineseName,
            email: email,
            phone: phone,
            role: role,
            accessLevel: accessLevel,
            specializations: specializations,
            ageGroups: ageGroups,
            avatarColor: avatarColor,
            isActive: isActive,
            hireDate: hireDate,
            notes: notes,
            profileImageData: profileImageData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
