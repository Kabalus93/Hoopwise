import Foundation
import SwiftUI
import CoreLocation

// MARK: - Access Level for Staff Coaches
/// Determines what data and actions a coach can access when logged in
enum AccessLevel: String, Codable, CaseIterable, Hashable {
    case admin = "Admin"
    case coachingStaff = "Coaching Staff"
    
    var description: String {
        switch self {
        case .admin:
            return "Full access to all data, can create, edit, and delete anything"
        case .coachingStaff:
            return "Can only see and manage their own assigned students, programs, sessions, teams, and contracts"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .admin:
            return "Full access"
        case .coachingStaff:
            return "Own data only"
        }
    }
    
    var icon: String {
        switch self {
        case .admin: return "shield.checkered"
        case .coachingStaff: return "person.badge.shield.checkmark"
        }
    }
    
    var color: Color {
        switch self {
        case .admin: return Color(hex: "#7C3AED")
        case .coachingStaff: return Color(hex: "#3B82F6")
        }
    }
    
    // MARK: - Permission Checks
    
    /// Can view all data regardless of assignment
    var canViewAllData: Bool {
        self == .admin
    }
    
    /// Can create new items (students, programs, etc.)
    var canCreate: Bool {
        true // Both can create
    }
    
    /// Can edit items they didn't create (admin only)
    var canEditOthersData: Bool {
        self == .admin
    }
    
    /// Can delete items they didn't create (admin only)
    var canDeleteOthersData: Bool {
        self == .admin
    }
    
    /// Can manage organization settings (coaches, locations, categories)
    var canManageOrganization: Bool {
        self == .admin
    }
    
    /// Can assign coaches to programs/teams/sessions
    var canAssignCoaches: Bool {
        self == .admin
    }
    
    /// Can view financial data (contracts, payments)
    var canViewFinancials: Bool {
        self == .admin
    }
    
    /// Can export data
    var canExportData: Bool {
        self == .admin
    }
}

// MARK: - Staff Coach (different from the main app Coach profile)
struct StaffCoach: Identifiable, Codable, Hashable {
    let id: UUID
    var organizationId: UUID?     // Organization this coach belongs to
    var name: String              // English name
    var chineseName: String?      // Chinese name (preferred for display)
    var email: String?
    var phone: String?
    var role: CoachRole
    var accessLevel: AccessLevel
    var specializations: [String]
    var ageGroups: [AgeGroup]  // Which age groups they can coach
    var avatarColor: AvatarColor
    var isActive: Bool
    var hireDate: Date?
    var notes: String?
    var profileImageData: Data?  // Profile picture stored as Data
    var createdAt: Date
    var updatedAt: Date
    
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
        self.role = role
        self.accessLevel = accessLevel
        self.specializations = specializations
        self.ageGroups = ageGroups
        self.avatarColor = avatarColor
        self.isActive = isActive
        self.hireDate = hireDate
        self.notes = notes
        self.profileImageData = profileImageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Display name - favors Chinese name when available, falls back to English
    var displayName: String {
        if let chinese = chineseName, !chinese.isEmpty {
            return chinese
        }
        return name
    }
    
    /// Full display with both names when available
    var fullDisplayName: String {
        if let chinese = chineseName, !chinese.isEmpty {
            return "\(chinese) (\(name))"
        }
        return name
    }
    
    var initials: String {
        // Use Chinese name first character if available
        if let chinese = chineseName, !chinese.isEmpty {
            return String(chinese.prefix(1))
        }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    /// Check if this coach can edit a specific item
    func canEdit(createdByCoachId: UUID?) -> Bool {
        if accessLevel.canEditOthersData { return true }
        return createdByCoachId == id
    }
    
    /// Check if this coach can delete a specific item
    func canDelete(createdByCoachId: UUID?) -> Bool {
        if accessLevel.canDeleteOthersData { return true }
        return createdByCoachId == id
    }
    
    /// Check if this coach can view a specific item based on assignment
    func canView(assignedCoachId: UUID?, createdByCoachId: UUID?) -> Bool {
        if accessLevel.canViewAllData { return true }
        // Can view if assigned to them or created by them
        return assignedCoachId == id || createdByCoachId == id
    }
    
    static let samples: [StaffCoach] = [
        StaffCoach(name: "John Smith", email: "john@academy.com", role: .head, accessLevel: .admin, specializations: ["Offense", "Player Development"], ageGroups: [.u14, .u16, .u18]),
        StaffCoach(name: "Sarah Johnson", email: "sarah@academy.com", role: .assistant, accessLevel: .coachingStaff, specializations: ["Defense", "Conditioning"], ageGroups: [.u12, .u14]),
        StaffCoach(name: "Mike Chen", role: .volunteer, accessLevel: .coachingStaff, specializations: ["Youth Development"], ageGroups: [.u8, .u10])
    ]
}

enum CoachRole: String, Codable, CaseIterable {
    case head = "Head Coach"
    case assistant = "Assistant Coach"
    case volunteer = "Volunteer"
    case trainee = "Trainee"
    
    var color: Color {
        switch self {
        case .head: return Color(hex: "#7C3AED")
        case .assistant: return Color(hex: "#3B82F6")
        case .volunteer: return Color(hex: "#10B981")
        case .trainee: return Color(hex: "#F59E0B")
        }
    }
    
    var icon: String {
        switch self {
        case .head: return "star.fill"
        case .assistant: return "person.wave.2.fill"
        case .volunteer: return "heart.fill"
        case .trainee: return "graduationcap.fill"
        }
    }
}

// MARK: - Location / Venue
struct Location: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String?
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var courtCount: Int
    var courtType: CourtType
    var hasIndoor: Bool
    var amenities: [String]
    var maxCapacity: Int?
    var contactPhone: String?
    var notes: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        city: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
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
        self.latitude = latitude
        self.longitude = longitude
        self.courtCount = courtCount
        self.courtType = courtType
        self.hasIndoor = hasIndoor
        self.amenities = amenities
        self.maxCapacity = maxCapacity
        self.contactPhone = contactPhone
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var fullAddress: String? {
        if let address = address, let city = city {
            return "\(address), \(city)"
        }
        return address ?? city
    }
    
    static let samples: [Location] = [
        Location(name: "Main Gym", address: "123 Sports Ave", city: "Downtown", courtCount: 2, courtType: .indoor, amenities: ["Locker Rooms", "Scoreboard", "Bleachers"], maxCapacity: 200),
        Location(name: "Community Center", address: "456 Park Rd", city: "Westside", courtCount: 1, courtType: .indoor, amenities: ["Parking", "Water Fountain"]),
        Location(name: "Outdoor Courts", address: "789 Recreation Blvd", city: "Eastside", courtCount: 3, courtType: .outdoor, hasIndoor: false, amenities: ["Lights", "Benches"])
    ]
}

enum CourtType: String, Codable, CaseIterable {
    case indoor = "Indoor"
    case outdoor = "Outdoor"
    case mixed = "Mixed"
    
    var icon: String {
        switch self {
        case .indoor: return "building.2.fill"
        case .outdoor: return "sun.max.fill"
        case .mixed: return "square.split.2x1.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .indoor: return Color(hex: "#5B8DEF")
        case .outdoor: return Color(hex: "#6BCB77")
        case .mixed: return Color(hex: "#FFB347")
        }
    }
}

// MARK: - Custom Age Category (user-defined)
struct CustomAgeCategory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var shortName: String  // e.g., "U8", "U10"
    var minAge: Int
    var maxAge: Int
    var colorHex: String
    var ballSize: BallSize
    var rimHeight: RimHeight
    var description: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var customIconData: Data?  // User-uploaded custom icon image
    var mascotNameOverride: String?  // Optional override for mascot name
    
    init(
        id: UUID = UUID(),
        name: String,
        shortName: String,
        minAge: Int,
        maxAge: Int,
        colorHex: String = "#5B8DEF",
        ballSize: BallSize = .size5,
        rimHeight: RimHeight = .feet10,
        description: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        customIconData: Data? = nil,
        mascotNameOverride: String? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.minAge = minAge
        self.maxAge = maxAge
        self.colorHex = colorHex
        self.ballSize = ballSize
        self.rimHeight = rimHeight
        self.description = description
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.customIconData = customIconData
        self.mascotNameOverride = mascotNameOverride
    }
    
    var color: Color { Color(hex: colorHex) }
    
    var ageRange: String { "\(minAge)-\(maxAge) years" }
    
    /// Maps shortName to the corresponding AgeGroup enum for mascot info
    var ageGroup: AgeGroup? {
        switch shortName.uppercased() {
        case "U6": return .u6
        case "U8": return .u8
        case "U10": return .u10
        case "U12": return .u12
        case "U14": return .u14
        case "U16": return .u16
        case "U18": return .u18
        case "18+", "ADULT": return .adult
        default: return nil
        }
    }
    
    /// Mascot name (uses override if set, otherwise from AgeGroup)
    var mascotName: String {
        mascotNameOverride ?? ageGroup?.mascotName ?? shortName
    }
    
    /// Mascot name in Chinese from the corresponding AgeGroup
    var mascotNameChinese: String {
        ageGroup?.mascotNameChinese ?? shortName
    }
    
    /// Mascot icon from the corresponding AgeGroup (SF Symbol fallback)
    var mascotIcon: String {
        ageGroup?.mascotIcon ?? "rectangle.stack.fill"
    }
    
    /// Whether this category has a custom uploaded icon
    var hasCustomIcon: Bool {
        customIconData != nil
    }
    
    /// Get UIImage from custom icon data
    #if os(iOS)
    var customIconImage: UIImage? {
        guard let data = customIconData else { return nil }
        return UIImage(data: data)
    }
    #endif
    
    static let defaults: [CustomAgeCategory] = [
        CustomAgeCategory(name: "Under 6", shortName: "U6", minAge: 4, maxAge: 5, colorHex: "#FFD93D", ballSize: .size5, rimHeight: .feet8),
        CustomAgeCategory(name: "Under 8", shortName: "U8", minAge: 5, maxAge: 7, colorHex: "#F8A5C2", ballSize: .size5, rimHeight: .feet8),
        CustomAgeCategory(name: "Under 10", shortName: "U10", minAge: 8, maxAge: 9, colorHex: "#FFB347", ballSize: .size5, rimHeight: .feet9),
        CustomAgeCategory(name: "Under 12", shortName: "U12", minAge: 10, maxAge: 11, colorHex: "#FFE066", ballSize: .size6, rimHeight: .feet9),
        CustomAgeCategory(name: "Under 14", shortName: "U14", minAge: 12, maxAge: 13, colorHex: "#6BCB77", ballSize: .size6, rimHeight: .feet10),
        CustomAgeCategory(name: "Under 16", shortName: "U16", minAge: 14, maxAge: 15, colorHex: "#5B8DEF", ballSize: .size7, rimHeight: .feet10),
        CustomAgeCategory(name: "Under 18", shortName: "U18", minAge: 16, maxAge: 17, colorHex: "#9B7EDE", ballSize: .size7, rimHeight: .feet10),
        CustomAgeCategory(name: "Adult", shortName: "18+", minAge: 18, maxAge: 99, colorHex: "#95A5A6", ballSize: .size7, rimHeight: .feet10)
    ]
}
