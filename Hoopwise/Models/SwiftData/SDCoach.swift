import Foundation
import SwiftData

@Model
final class SDCoach {
    var id: UUID = UUID()
    var name: String = ""
    /// Optional Chinese name. Defaults to nil so old CloudKit records keep
    /// validating without a migration.
    var chineseName: String?
    var email: String = ""
    var phone: String?
    var profileImageUrl: String?
    @Attribute(.externalStorage) var profileImageData: Data?
    var introduction: String = ""
    var yearsOfExperience: Int = 0
    var certifications: [String] = []
    var specializations: [String] = []
    var achievements: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        chineseName: String? = nil,
        email: String = "",
        phone: String? = nil,
        profileImageUrl: String? = nil,
        profileImageData: Data? = nil,
        introduction: String = "",
        yearsOfExperience: Int = 0,
        certifications: [String] = [],
        specializations: [String] = [],
        achievements: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.chineseName = chineseName
        self.email = email
        self.phone = phone
        self.profileImageUrl = profileImageUrl
        self.profileImageData = profileImageData
        self.introduction = introduction
        self.yearsOfExperience = yearsOfExperience
        self.certifications = certifications
        self.specializations = specializations
        self.achievements = achievements
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    /// Convert to legacy Coach struct
    func toStruct() -> Coach {
        Coach(
            id: id,
            name: name,
            chineseName: chineseName,
            email: email,
            phone: phone,
            profileImageUrl: profileImageUrl,
            profileImageData: profileImageData,
            introduction: introduction,
            yearsOfExperience: yearsOfExperience,
            certifications: certifications,
            specializations: specializations,
            achievements: achievements,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Create from legacy Coach struct
    static func from(_ coach: Coach) -> SDCoach {
        SDCoach(
            id: coach.id,
            name: coach.name,
            chineseName: coach.chineseName,
            email: coach.email,
            phone: coach.phone,
            profileImageUrl: coach.profileImageUrl,
            profileImageData: coach.profileImageData,
            introduction: coach.introduction,
            yearsOfExperience: coach.yearsOfExperience,
            certifications: coach.certifications,
            specializations: coach.specializations,
            achievements: coach.achievements,
            createdAt: coach.createdAt,
            updatedAt: coach.updatedAt
        )
    }
    
    /// Default sample coach (for previews only)
    static var sample: SDCoach {
        SDCoach(
            name: "Coach Mike",
            email: "coach@example.com",
            phone: "+86 138 0000 0000",
            introduction: "Passionate basketball coach dedicated to developing young athletes and building strong fundamentals.",
            yearsOfExperience: 8,
            certifications: ["FIBA Level 2", "Youth Development Certified", "First Aid Certified"],
            specializations: ["Youth Development", "Shooting Mechanics", "Team Defense"],
            achievements: ["Regional U14 Champions 2023", "Best Youth Coach Award 2022"]
        )
    }
    
    /// Default empty coach for production
    static var `default`: SDCoach {
        SDCoach(
            name: "",
            email: "",
            phone: nil,
            introduction: "",
            yearsOfExperience: 0,
            certifications: [],
            specializations: [],
            achievements: []
        )
    }
}

@Model
final class SDAppSettings {
    var id: UUID = UUID()
    var notificationsEnabled: Bool = true
    var sessionReminders: Bool = true
    var reminderMinutesBefore: Int = 30
    var darkModeEnabled: Bool = false
    var hapticFeedbackEnabled: Bool = true
    var autoSyncEnabled: Bool = true
    var language: String = "en"
    // Optional to support migration from older schemas — coachAssistantEnabled,
    // claudeApiKey, and groqApiKey were removed when the AI assistant feature
    // was retired. The properties are gone; their on-disk columns are simply
    // unread.
    var currencyRawValue: String?

    init(
        id: UUID = UUID(),
        notificationsEnabled: Bool = true,
        sessionReminders: Bool = true,
        reminderMinutesBefore: Int = 30,
        darkModeEnabled: Bool = false,
        hapticFeedbackEnabled: Bool = true,
        autoSyncEnabled: Bool = true,
        language: String = "en",
        currencyRawValue: String? = "CNY"
    ) {
        self.id = id
        self.notificationsEnabled = notificationsEnabled
        self.sessionReminders = sessionReminders
        self.reminderMinutesBefore = reminderMinutesBefore
        self.darkModeEnabled = darkModeEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.autoSyncEnabled = autoSyncEnabled
        self.language = language
        self.currencyRawValue = currencyRawValue
    }

    /// Convert to legacy AppSettings struct
    func toStruct() -> AppSettings {
        AppSettings(
            notificationsEnabled: notificationsEnabled,
            sessionReminders: sessionReminders,
            reminderMinutesBefore: reminderMinutesBefore,
            darkModeEnabled: darkModeEnabled,
            hapticFeedbackEnabled: hapticFeedbackEnabled,
            autoSyncEnabled: autoSyncEnabled,
            language: language,
            currency: CurrencyType(rawValue: currencyRawValue ?? "CNY") ?? .rmb
        )
    }

    /// Create from legacy AppSettings struct
    static func from(_ settings: AppSettings) -> SDAppSettings {
        SDAppSettings(
            notificationsEnabled: settings.notificationsEnabled,
            sessionReminders: settings.sessionReminders,
            reminderMinutesBefore: settings.reminderMinutesBefore,
            darkModeEnabled: settings.darkModeEnabled,
            hapticFeedbackEnabled: settings.hapticFeedbackEnabled,
            autoSyncEnabled: settings.autoSyncEnabled,
            language: settings.language,
            currencyRawValue: settings.currency.rawValue
        )
    }
    
    /// Default settings
    static var defaultSettings: SDAppSettings {
        SDAppSettings()
    }
}
