import Foundation
import SwiftData

@Model
final class SDStudent {
    @Attribute(.unique) var id: UUID
    var name: String
    var chineseName: String?
    var avatarColorRaw: String
    var attendanceStatusRaw: String
    var categoryId: UUID?
    var coachId: UUID?
    var programId: UUID?
    var birthdate: Date?
    var birthMonth: Int?  // 1-12, for month/year only input
    var birthYear: Int?   // For month/year only input
    var schoolGradeRaw: String?  // School grade for age estimation
    var profileImageUrl: String?
    var createdByCoachId: UUID?  // For access control
    var parentalTouchpointsData: Data?  // JSON encoded [ParentalTouchpoint]
    var lastParentContact: Date?
    var mediaAssetsData: Data?  // JSON encoded MediaAssetStatus
    var personalBestsData: Data?  // JSON encoded [String: Double]
    var performanceGradeRaw: String?  // Performance grade (A/B/C) manual override
    var gradeHistoryData: Data?  // JSON encoded [GradeHistoryEntry]
    var createdAt: Date
    var updatedAt: Date
    
    /// Get/set parentalTouchpoints as array
    var parentalTouchpoints: [ParentalTouchpoint] {
        get {
            guard let data = parentalTouchpointsData else { return [] }
            return (try? JSONDecoder().decode([ParentalTouchpoint].self, from: data)) ?? []
        }
        set {
            parentalTouchpointsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Get/set mediaAssets
    var mediaAssets: MediaAssetStatus {
        get {
            guard let data = mediaAssetsData else { return MediaAssetStatus() }
            return (try? JSONDecoder().decode(MediaAssetStatus.self, from: data)) ?? MediaAssetStatus()
        }
        set {
            mediaAssetsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Get/set personalBests
    var personalBests: [String: Double] {
        get {
            guard let data = personalBestsData else { return [:] }
            return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        }
        set {
            personalBestsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Get/set performanceGrade
    var performanceGrade: PerformanceGrade? {
        get {
            guard let raw = performanceGradeRaw else { return nil }
            return PerformanceGrade(rawValue: raw)
        }
        set {
            performanceGradeRaw = newValue?.rawValue
        }
    }
    
    /// Get/set gradeHistory
    var gradeHistory: [GradeHistoryEntry] {
        get {
            guard let data = gradeHistoryData else { return [] }
            return (try? JSONDecoder().decode([GradeHistoryEntry].self, from: data)) ?? []
        }
        set {
            gradeHistoryData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \SDPlayer.student)
    var player: SDPlayer?
    
    @Relationship(deleteRule: .cascade, inverse: \SDContract.student)
    var contracts: [SDContract]?
    
    @Relationship(deleteRule: .nullify, inverse: \SDMeasurement.student)
    var measurements: [SDMeasurement]?
    
    init(
        id: UUID = UUID(),
        name: String,
        chineseName: String? = nil,
        avatarColor: AvatarColor = .blue,
        attendanceStatus: AttendanceStatus = .present,
        categoryId: UUID? = nil,
        coachId: UUID? = nil,
        programId: UUID? = nil,
        birthdate: Date? = nil,
        profileImageUrl: String? = nil,
        createdByCoachId: UUID? = nil,
        parentalTouchpointsData: Data? = nil,
        lastParentContact: Date? = nil,
        mediaAssetsData: Data? = nil,
        personalBestsData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.chineseName = chineseName
        self.avatarColorRaw = avatarColor.rawValue
        self.attendanceStatusRaw = attendanceStatus.rawValue
        self.categoryId = categoryId
        self.coachId = coachId
        self.programId = programId
        self.birthdate = birthdate
        self.profileImageUrl = profileImageUrl
        self.createdByCoachId = createdByCoachId
        self.parentalTouchpointsData = parentalTouchpointsData
        self.lastParentContact = lastParentContact
        self.mediaAssetsData = mediaAssetsData
        self.personalBestsData = personalBestsData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var avatarColor: AvatarColor {
        get { AvatarColor(rawValue: avatarColorRaw) ?? .blue }
        set { avatarColorRaw = newValue.rawValue }
    }
    
    var attendanceStatus: AttendanceStatus {
        get { AttendanceStatus(rawValue: attendanceStatusRaw) ?? .present }
        set { attendanceStatusRaw = newValue.rawValue }
    }
    
    var schoolGrade: SchoolGrade? {
        get {
            guard let raw = schoolGradeRaw else { return nil }
            return SchoolGrade(rawValue: raw)
        }
        set {
            schoolGradeRaw = newValue?.rawValue
        }
    }
    
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    var age: Int? {
        guard let birthdate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year
    }
    
    /// Convert to legacy Student struct for compatibility
    func toStruct() -> Student {
        Student(
            id: id,
            name: name,
            chineseName: chineseName,
            avatarColor: avatarColor,
            attendanceStatus: attendanceStatus,
            categoryId: categoryId,
            coachId: coachId,
            programId: programId,
            birthdate: birthdate,
            birthMonth: birthMonth,
            birthYear: birthYear,
            schoolGrade: schoolGrade,
            profileImageUrl: profileImageUrl,
            createdByCoachId: createdByCoachId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            parentalTouchpoints: parentalTouchpoints,
            lastParentContact: lastParentContact,
            mediaAssets: mediaAssets,
            personalBests: personalBests,
            performanceGrade: performanceGrade,
            gradeHistory: gradeHistory
        )
    }
    
    /// Create from legacy Student struct
    static func from(_ student: Student) -> SDStudent {
        let sd = SDStudent(
            id: student.id,
            name: student.name,
            chineseName: student.chineseName,
            avatarColor: student.avatarColor,
            attendanceStatus: student.attendanceStatus,
            categoryId: student.categoryId,
            coachId: student.coachId,
            programId: student.programId,
            birthdate: student.birthdate,
            profileImageUrl: student.profileImageUrl,
            createdByCoachId: student.createdByCoachId,
            createdAt: student.createdAt,
            updatedAt: student.updatedAt
        )
        sd.birthMonth = student.birthMonth
        sd.birthYear = student.birthYear
        sd.schoolGrade = student.schoolGrade
        sd.parentalTouchpoints = student.parentalTouchpoints
        sd.lastParentContact = student.lastParentContact
        sd.mediaAssets = student.mediaAssets
        sd.personalBests = student.personalBests
        sd.performanceGrade = student.performanceGrade
        sd.gradeHistory = student.gradeHistory
        return sd
    }
}
