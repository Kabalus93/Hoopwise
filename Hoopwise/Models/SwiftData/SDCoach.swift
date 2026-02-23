import Foundation
import SwiftData

@Model
final class SDCoach {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String
    var phone: String?
    var profileImageUrl: String?
    @Attribute(.externalStorage) var profileImageData: Data?
    var introduction: String
    var yearsOfExperience: Int
    var certifications: [String]
    var specializations: [String]
    var achievements: [String]
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String = "",
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
    @Attribute(.unique) var id: UUID
    var notificationsEnabled: Bool
    var sessionReminders: Bool
    var reminderMinutesBefore: Int
    var darkModeEnabled: Bool
    var hapticFeedbackEnabled: Bool
    var autoSyncEnabled: Bool
    var language: String
    // New fields - optional to support migration from older schemas
    var currencyRawValue: String?
    var coachAssistantEnabled: Bool?
    var claudeApiKey: String?
    var groqApiKey: String?
    
    init(
        id: UUID = UUID(),
        notificationsEnabled: Bool = true,
        sessionReminders: Bool = true,
        reminderMinutesBefore: Int = 30,
        darkModeEnabled: Bool = false,
        hapticFeedbackEnabled: Bool = true,
        autoSyncEnabled: Bool = true,
        language: String = "en",
        currencyRawValue: String? = "CNY",
        coachAssistantEnabled: Bool? = true,
        claudeApiKey: String? = "",
        groqApiKey: String? = ""
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
        self.coachAssistantEnabled = coachAssistantEnabled
        self.claudeApiKey = claudeApiKey
        self.groqApiKey = groqApiKey
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
            currency: CurrencyType(rawValue: currencyRawValue ?? "CNY") ?? .rmb,
            coachAssistantEnabled: coachAssistantEnabled ?? true,
            claudeApiKey: claudeApiKey ?? "",
            groqApiKey: groqApiKey ?? ""
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
            currencyRawValue: settings.currency.rawValue,
            coachAssistantEnabled: settings.coachAssistantEnabled,
            claudeApiKey: settings.claudeApiKey,
            groqApiKey: settings.groqApiKey
        )
    }
    
    /// Default settings
    static var defaultSettings: SDAppSettings {
        SDAppSettings()
    }
}
