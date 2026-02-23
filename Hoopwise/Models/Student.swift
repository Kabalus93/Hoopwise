import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AttendanceStatus: String, Codable, CaseIterable {
    case present, absent, late, excused
    
    var displayName: String { rawValue.capitalized }
    var color: String {
        switch self {
        case .present: return "green"
        case .absent: return "red"
        case .late: return "orange"
        case .excused: return "gray"
        }
    }
}

enum AvatarColor: String, Codable, CaseIterable {
    case blue, green, orange, purple, red, teal, pink, indigo
    var displayName: String { rawValue.capitalized }
    
    #if canImport(UIKit)
    var color: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .red: return .systemRed
        case .teal: return .systemTeal
        case .pink: return .systemPink
        case .indigo: return .systemIndigo
        }
    }
    #elseif canImport(AppKit)
    var color: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .red: return .systemRed
        case .teal: return .systemTeal
        case .pink: return .systemPink
        case .indigo: return .systemIndigo
        }
    }
    #endif
}

// MARK: - School Grade for Age Estimation
enum SchoolGrade: String, Codable, CaseIterable {
    case kindergarten1 = "K1"
    case kindergarten2 = "K2"
    case kindergarten3 = "K3"
    case primary1 = "P1"
    case primary2 = "P2"
    case primary3 = "P3"
    case primary4 = "P4"
    case primary5 = "P5"
    case primary6 = "P6"
    case highschool1 = "H1"
    case highschool2 = "H2"
    case highschool3 = "H3"
    case highschool4 = "H4"
    case highschool5 = "H5"
    case highschool6 = "H6"
    
    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .kindergarten1: return isChinese ? "幼儿园小班" : "Kindergarten 1"
        case .kindergarten2: return isChinese ? "幼儿园中班" : "Kindergarten 2"
        case .kindergarten3: return isChinese ? "幼儿园大班" : "Kindergarten 3"
        case .primary1: return isChinese ? "小学一年级" : "Primary 1"
        case .primary2: return isChinese ? "小学二年级" : "Primary 2"
        case .primary3: return isChinese ? "小学三年级" : "Primary 3"
        case .primary4: return isChinese ? "小学四年级" : "Primary 4"
        case .primary5: return isChinese ? "小学五年级" : "Primary 5"
        case .primary6: return isChinese ? "小学六年级" : "Primary 6"
        case .highschool1: return isChinese ? "初一" : "High School 1"
        case .highschool2: return isChinese ? "初二" : "High School 2"
        case .highschool3: return isChinese ? "初三" : "High School 3"
        case .highschool4: return isChinese ? "高一" : "High School 4"
        case .highschool5: return isChinese ? "高二" : "High School 5"
        case .highschool6: return isChinese ? "高三" : "High School 6"
        }
    }
    
    var shortName: String {
        rawValue
    }
    
    /// Localized short name for picker buttons
    /// Shows Chinese local grade names (小班, 一年级, etc.) when in Chinese mode
    var localizedShortName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        guard isChinese else { return rawValue }
        
        switch self {
        case .kindergarten1: return "小班"
        case .kindergarten2: return "中班"
        case .kindergarten3: return "大班"
        case .primary1: return "一年级"
        case .primary2: return "二年级"
        case .primary3: return "三年级"
        case .primary4: return "四年级"
        case .primary5: return "五年级"
        case .primary6: return "六年级"
        case .highschool1: return "初一"
        case .highschool2: return "初二"
        case .highschool3: return "初三"
        case .highschool4: return "高一"
        case .highschool5: return "高二"
        case .highschool6: return "高三"
        }
    }
    
    /// Estimated age based on typical school grade ages
    var estimatedAge: Int {
        switch self {
        case .kindergarten1: return 3
        case .kindergarten2: return 4
        case .kindergarten3: return 5
        case .primary1: return 6
        case .primary2: return 7
        case .primary3: return 8
        case .primary4: return 9
        case .primary5: return 10
        case .primary6: return 11
        case .highschool1: return 12
        case .highschool2: return 13
        case .highschool3: return 14
        case .highschool4: return 15
        case .highschool5: return 16
        case .highschool6: return 17
        }
    }
    
    /// Creates an estimated birthdate based on school grade (September 1st of estimated birth year)
    var estimatedBirthdate: Date {
        let currentYear = Calendar.current.component(.year, from: Date())
        let birthYear = currentYear - estimatedAge
        var components = DateComponents()
        components.year = birthYear
        components.month = 9
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }
    
    /// Group grades for picker display
    static var kindergartenGrades: [SchoolGrade] {
        [.kindergarten1, .kindergarten2, .kindergarten3]
    }
    
    static var primaryGrades: [SchoolGrade] {
        [.primary1, .primary2, .primary3, .primary4, .primary5, .primary6]
    }
    
    static var highschoolGrades: [SchoolGrade] {
        [.highschool1, .highschool2, .highschool3, .highschool4, .highschool5, .highschool6]
    }
}

// MARK: - Performance Grade (A/B/C peer comparison)
enum PerformanceGrade: String, Codable, CaseIterable, Comparable {
    case A = "A"
    case B = "B"
    case C = "C"
    case ungraded = "—"
    
    var displayName: String { rawValue }
    
    var chineseName: String {
        switch self {
        case .A: return "优秀"
        case .B: return "良好"
        case .C: return "一般"
        case .ungraded: return "—"
        }
    }
    
    /// Sort order: A < B < C < ungraded (A is best, comes first)
    var sortOrder: Int {
        switch self {
        case .A: return 0
        case .B: return 1
        case .C: return 2
        case .ungraded: return 3
        }
    }
    
    static func < (lhs: PerformanceGrade, rhs: PerformanceGrade) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Grade History Entry
struct GradeHistoryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let grade: PerformanceGrade
    let date: Date
    let wasManual: Bool  // true if coach override, false if auto-computed
    
    init(id: UUID = UUID(), grade: PerformanceGrade, date: Date = Date(), wasManual: Bool = false) {
        self.id = id
        self.grade = grade
        self.date = date
        self.wasManual = wasManual
    }
}

// MARK: - Parental Touchpoint Log
struct ParentalTouchpoint: Codable, Hashable, Identifiable {
    let id: UUID
    var date: Date
    var type: TouchpointType
    var notes: String?
    var followUpNeeded: Bool
    var followUpDate: Date?
    
    enum TouchpointType: String, Codable, CaseIterable {
        case call = "Phone Call"
        case message = "Message/WeChat"
        case inPerson = "In Person"
        case email = "Email"
        case reportCard = "Report Card Sent"
        case meeting = "Parent Meeting"
        
        var icon: String {
            switch self {
            case .call: return "phone.fill"
            case .message: return "message.fill"
            case .inPerson: return "person.2.fill"
            case .email: return "envelope.fill"
            case .reportCard: return "doc.text.fill"
            case .meeting: return "calendar.badge.clock"
            }
        }
    }
    
    init(id: UUID = UUID(), date: Date = Date(), type: TouchpointType = .message,
         notes: String? = nil, followUpNeeded: Bool = false, followUpDate: Date? = nil) {
        self.id = id
        self.date = date
        self.type = type
        self.notes = notes
        self.followUpNeeded = followUpNeeded
        self.followUpDate = followUpDate
    }
}

// MARK: - Media Asset Status
struct MediaAssetStatus: Codable, Hashable, Sendable {
    var photoReady: Bool
    var videoHighlightPending: Bool
    var lastPhotoDate: Date?
    var lastVideoDate: Date?
    var notes: String?
    var photoUrls: [String]
    var videoUrls: [String]
    
    init(photoReady: Bool = false, videoHighlightPending: Bool = false,
         lastPhotoDate: Date? = nil, lastVideoDate: Date? = nil, notes: String? = nil,
         photoUrls: [String] = [], videoUrls: [String] = []) {
        self.photoReady = photoReady
        self.videoHighlightPending = videoHighlightPending
        self.lastPhotoDate = lastPhotoDate
        self.lastVideoDate = lastVideoDate
        self.notes = notes
        self.photoUrls = photoUrls
        self.videoUrls = videoUrls
    }
    
    // Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photoReady = try container.decodeIfPresent(Bool.self, forKey: .photoReady) ?? false
        videoHighlightPending = try container.decodeIfPresent(Bool.self, forKey: .videoHighlightPending) ?? false
        lastPhotoDate = try container.decodeIfPresent(Date.self, forKey: .lastPhotoDate)
        lastVideoDate = try container.decodeIfPresent(Date.self, forKey: .lastVideoDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        photoUrls = try container.decodeIfPresent([String].self, forKey: .photoUrls) ?? []
        videoUrls = try container.decodeIfPresent([String].self, forKey: .videoUrls) ?? []
    }
}

struct Student: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var chineseName: String?
    var avatarColor: AvatarColor
    var attendanceStatus: AttendanceStatus
    var categoryId: UUID?
    var coachId: UUID?
    var programId: UUID?
    var birthdate: Date?
    var birthMonth: Int?  // 1-12, for month/year only input
    var birthYear: Int?   // For month/year only input
    var schoolGrade: SchoolGrade?  // Alternative to birthdate for age estimation
    var profileImageUrl: String?
    var createdByCoachId: UUID?
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Intelligence Fields
    var parentalTouchpoints: [ParentalTouchpoint]
    var lastParentContact: Date?
    var mediaAssets: MediaAssetStatus
    var personalBests: [String: Double]  // e.g., "ppg": 15.2, "3pt%": 0.42
    var performanceGrade: PerformanceGrade?  // Manual override; nil = auto-computed
    var gradeHistory: [GradeHistoryEntry]  // Track grade changes over time
    
    init(id: UUID = UUID(), name: String, chineseName: String? = nil,
         avatarColor: AvatarColor = .blue, attendanceStatus: AttendanceStatus = .present,
         categoryId: UUID? = nil, coachId: UUID? = nil, programId: UUID? = nil,
         birthdate: Date? = nil, birthMonth: Int? = nil, birthYear: Int? = nil,
         schoolGrade: SchoolGrade? = nil, profileImageUrl: String? = nil,
         createdByCoachId: UUID? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date(),
         parentalTouchpoints: [ParentalTouchpoint] = [],
         lastParentContact: Date? = nil,
         mediaAssets: MediaAssetStatus = MediaAssetStatus(),
         personalBests: [String: Double] = [:],
         performanceGrade: PerformanceGrade? = nil,
         gradeHistory: [GradeHistoryEntry] = []) {
        self.id = id
        self.name = name
        self.chineseName = chineseName
        self.avatarColor = avatarColor
        self.attendanceStatus = attendanceStatus
        self.categoryId = categoryId
        self.coachId = coachId
        self.programId = programId
        self.birthdate = birthdate
        self.birthMonth = birthMonth
        self.birthYear = birthYear
        self.schoolGrade = schoolGrade
        self.profileImageUrl = profileImageUrl
        self.createdByCoachId = createdByCoachId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentalTouchpoints = parentalTouchpoints
        self.lastParentContact = lastParentContact
        self.mediaAssets = mediaAssets
        self.personalBests = personalBests
        self.performanceGrade = performanceGrade
        self.gradeHistory = gradeHistory
    }
    
    // Custom decoder to handle missing new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        chineseName = try container.decodeIfPresent(String.self, forKey: .chineseName)
        avatarColor = try container.decodeIfPresent(AvatarColor.self, forKey: .avatarColor) ?? .blue
        attendanceStatus = try container.decodeIfPresent(AttendanceStatus.self, forKey: .attendanceStatus) ?? .present
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        coachId = try container.decodeIfPresent(UUID.self, forKey: .coachId)
        programId = try container.decodeIfPresent(UUID.self, forKey: .programId)
        birthdate = try container.decodeIfPresent(Date.self, forKey: .birthdate)
        birthMonth = try container.decodeIfPresent(Int.self, forKey: .birthMonth)
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        schoolGrade = try container.decodeIfPresent(SchoolGrade.self, forKey: .schoolGrade)
        profileImageUrl = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
        createdByCoachId = try container.decodeIfPresent(UUID.self, forKey: .createdByCoachId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        parentalTouchpoints = try container.decodeIfPresent([ParentalTouchpoint].self, forKey: .parentalTouchpoints) ?? []
        lastParentContact = try container.decodeIfPresent(Date.self, forKey: .lastParentContact)
        mediaAssets = try container.decodeIfPresent(MediaAssetStatus.self, forKey: .mediaAssets) ?? MediaAssetStatus()
        personalBests = try container.decodeIfPresent([String: Double].self, forKey: .personalBests) ?? [:]
        performanceGrade = try container.decodeIfPresent(PerformanceGrade.self, forKey: .performanceGrade)
        gradeHistory = try container.decodeIfPresent([GradeHistoryEntry].self, forKey: .gradeHistory) ?? []
    }
    
    /// Check if student has a profile image
    var hasProfileImage: Bool {
        profileImageUrl != nil && !profileImageUrl!.isEmpty
    }
    
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    /// Display name based on current language setting
    /// In Chinese: Shows Chinese name (or English if no Chinese name)
    /// In English: Shows English name
    var displayName: String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return chineseName ?? name
        }
        return name
    }
    
    /// Primary name for display (Chinese name when in Chinese mode, English otherwise)
    var primaryDisplayName: String {
        if LocalizationManager.shared.currentLanguage == .chinese {
            return chineseName ?? name
        }
        return name
    }
    
    /// Secondary name for display (English name when in Chinese mode with Chinese name available)
    var secondaryDisplayName: String? {
        if LocalizationManager.shared.currentLanguage == .chinese && chineseName != nil {
            return name
        }
        return nil
    }
    
    var age: Int? {
        guard let birthdate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year
    }
    
    /// Determine AgeGroup based on student's age
    var ageGroup: AgeGroup? {
        guard let age = age else { return nil }
        switch age {
        case 0...7: return .u8
        case 8...9: return .u10
        case 10...11: return .u12
        case 12...13: return .u14
        case 14...15: return .u16
        case 16...17: return .u18
        default: return .adult
        }
    }
    
    static let samples: [Student] = [
        Student(name: "Michael Chen", chineseName: "陈明", avatarColor: .blue,
                birthdate: Calendar.current.date(byAdding: .year, value: -12, to: Date())),
        Student(name: "Sarah Wang", chineseName: "王莎", avatarColor: .purple,
                birthdate: Calendar.current.date(byAdding: .year, value: -14, to: Date())),
        Student(name: "David Liu", chineseName: "刘大卫", avatarColor: .green,
                birthdate: Calendar.current.date(byAdding: .year, value: -10, to: Date())),
        Student(name: "Emily Zhang", chineseName: "张艾米", avatarColor: .orange,
                birthdate: Calendar.current.date(byAdding: .year, value: -13, to: Date())),
        Student(name: "Kevin Wu", chineseName: "吴凯文", avatarColor: .teal,
                birthdate: Calendar.current.date(byAdding: .year, value: -11, to: Date()))
    ]
}
