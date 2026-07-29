import Foundation

struct Coach: Identifiable, Codable {
    let id: UUID
    var name: String
    /// Optional Chinese name. Surfaced in the attendance-photo watermark
    /// when present (since those photos are shared with Chinese-reading
    /// managers in WeChat) and elsewhere we want a name that reads
    /// natively in CN.
    var chineseName: String?
    var email: String
    var phone: String?
    var profileImageUrl: String?
    var profileImageData: Data?  // Backup storage for profile image
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

    // MARK: - Codable (backward-compatible)
    /// `chineseName` is new — bundles encoded before this field existed
    /// don't carry it. Decode it as nil when absent so old payloads keep
    /// working.
    private enum CodingKeys: String, CodingKey {
        case id, name, chineseName, email, phone, profileImageUrl, profileImageData
        case introduction, yearsOfExperience, certifications, specializations, achievements
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        chineseName = try c.decodeIfPresent(String.self, forKey: .chineseName)
        email = try c.decode(String.self, forKey: .email)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        profileImageUrl = try c.decodeIfPresent(String.self, forKey: .profileImageUrl)
        profileImageData = try c.decodeIfPresent(Data.self, forKey: .profileImageData)
        introduction = try c.decode(String.self, forKey: .introduction)
        yearsOfExperience = try c.decode(Int.self, forKey: .yearsOfExperience)
        certifications = try c.decode([String].self, forKey: .certifications)
        specializations = try c.decode([String].self, forKey: .specializations)
        achievements = try c.decode([String].self, forKey: .achievements)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    static let sample = Coach(
        name: "Coach Mike",
        email: "coach@example.com",
        phone: "+86 138 0000 0000",
        introduction: "Passionate basketball coach dedicated to developing young athletes and building strong fundamentals.",
        yearsOfExperience: 8,
        certifications: ["FIBA Level 2", "Youth Development Certified", "First Aid Certified"],
        specializations: ["Youth Development", "Shooting Mechanics", "Team Defense"],
        achievements: ["Regional U14 Champions 2023", "Best Youth Coach Award 2022"]
    )
    
    static let `default` = Coach(
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

// MARK: - Currency Type
enum CurrencyType: String, Codable, CaseIterable {
    case rmb = "CNY"
    case usd = "USD"
    case eur = "EUR"
    
    var symbol: String {
        switch self {
        case .rmb: return "¥"
        case .usd: return "$"
        case .eur: return "€"
        }
    }
    
    var displayName: String {
        switch self {
        case .rmb: return "RMB (¥)"
        case .usd: return "USD ($)"
        case .eur: return "Euro (€)"
        }
    }
    
    var currencyCode: String { rawValue }
}

// MARK: - App Settings
struct AppSettings: Codable, Equatable {
    var notificationsEnabled: Bool
    var sessionReminders: Bool
    var reminderMinutesBefore: Int
    var darkModeEnabled: Bool
    var hapticFeedbackEnabled: Bool
    var autoSyncEnabled: Bool
    var language: String
    var currency: CurrencyType

    init(
        notificationsEnabled: Bool = true,
        sessionReminders: Bool = true,
        reminderMinutesBefore: Int = 30,
        darkModeEnabled: Bool = false,
        hapticFeedbackEnabled: Bool = true,
        autoSyncEnabled: Bool = true,
        language: String = "en",
        currency: CurrencyType = .rmb
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.sessionReminders = sessionReminders
        self.reminderMinutesBefore = reminderMinutesBefore
        self.darkModeEnabled = darkModeEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.autoSyncEnabled = autoSyncEnabled
        self.language = language
        self.currency = currency
    }

    static let `default` = AppSettings()
}
