import Foundation

enum BallSize: String, Codable, CaseIterable {
    case size5 = "5", size6 = "6", size7 = "7"
    var displayName: String { "Size \(rawValue)" }
}

enum RimHeight: String, Codable, CaseIterable {
    case feet8 = "8ft", feet9 = "9ft", feet10 = "10ft"
    var displayName: String { rawValue }
    var centimeters: Int {
        switch self {
        case .feet8: return 244
        case .feet9: return 274
        case .feet10: return 305
        }
    }
}

enum AgeGroup: String, Codable, CaseIterable {
    case u6 = "U6", u8 = "U8", u10 = "U10", u12 = "U12", u14 = "U14", u16 = "U16", u18 = "U18", adult = "Adult"
    
    var displayName: String {
        switch self {
        case .u6: return "Under 6"
        case .u8: return "Under 8"
        case .u10: return "Under 10"
        case .u12: return "Under 12"
        case .u14: return "Under 14"
        case .u16: return "Under 16"
        case .u18: return "Under 18"
        case .adult: return "Adult"
        }
    }
    
    // MARK: - Mascot (tied to age group)
    var mascotName: String {
        switch self {
        case .u6: return "Koalas"
        case .u8: return "Bunnies"
        case .u10: return "Monkeys"
        case .u12: return "Cheetahs"
        case .u14: return "Wolves"
        case .u16: return "Panthers"
        case .u18: return "Eagles"
        case .adult: return "Lions"
        }
    }
    
    var mascotNameChinese: String {
        switch self {
        case .u6: return "考拉"
        case .u8: return "小兔"
        case .u10: return "小猴"
        case .u12: return "猎豹"
        case .u14: return "狼群"
        case .u16: return "黑豹"
        case .u18: return "雄鹰"
        case .adult: return "雄狮"
        }
    }
    
    /// SF Symbol icon name (used for most mascots)
    var mascotIcon: String {
        switch self {
        case .u6: return "teddybear.fill"      // Koala (fallback SF Symbol)
        case .u8: return "hare.fill"           // Bunny
        case .u10: return "pawprint.fill"      // Monkey
        case .u12: return "bolt.fill"          // Cheetah (speed)
        case .u14: return "dog.fill"           // Wolf
        case .u16: return "cat.fill"           // Panther
        case .u18: return "bird"               // Eagle
        case .adult: return "crown.fill"       // Lion (apex)
        }
    }
    
    /// Custom asset name (if using custom icon instead of SF Symbol)
    var customIconAsset: String? {
        switch self {
        case .u6: return "koala-icon"
        default: return nil
        }
    }
    
    /// Whether this age group uses a custom asset icon
    var usesCustomIcon: Bool {
        customIconAsset != nil
    }
    
    var mascotDescription: String {
        switch self {
        case .u6: return "Cuddly, curious, clinging to basics, learning through comfort and play"
        case .u8: return "Quick, erratic, still learning to move with purpose"
        case .u10: return "Energetic, imitative, skill acquisition through mimicry"
        case .u12: return "Speed emerging, coordination not yet locked"
        case .u14: return "Pack mentality, tactical awareness developing, competitive"
        case .u16: return "Athleticism sharpening, controlled aggression"
        case .u18: return "Aerial vision, precision, near-full predator capability"
        case .adult: return "Apex, territorial, full physical and mental maturity"
        }
    }
    
    var categoryName: String {
        switch self {
        case .u6: return "Discovery"
        case .u8: return "Introductory"
        case .u10, .u12: return "Mini"
        case .u14: return "Junior"
        case .u16, .u18: return "Elite Youth"
        case .adult: return "Pro"
        }
    }
    
    var ageRange: String {
        switch self {
        case .u6: return "4-5 years"
        case .u8: return "6-7 years"
        case .u10: return "8-9 years"
        case .u12: return "10-11 years"
        case .u14: return "12-13 years"
        case .u16: return "14-15 years"
        case .u18: return "16-17 years"
        case .adult: return "18+ years"
        }
    }
    
    var gradeEquivalent: String {
        switch self {
        case .u6: return "Pre-K"
        case .u8: return "K - 2nd"
        case .u10: return "3rd - 4th"
        case .u12: return "5th - 6th"
        case .u14: return "7th - 9th"
        case .u16: return "10th - 11th"
        case .u18: return "11th - 12th"
        case .adult: return "Post-Grad"
        }
    }
    
    var ballSizeDescription: String {
        switch self {
        case .u6: return "Size 3 (55-58 cm)"
        case .u8: return "Size 4 (65-67 cm)"
        case .u10, .u12: return "Size 5 (69-71 cm)"
        case .u14: return "Size 6 (F) / Size 7 (M)"
        case .u16, .u18: return "Size 6 (F) / Size 7 (M)"
        case .adult: return "Size 6 (F) / Size 7 (M)"
        }
    }
    
    var rimHeightDescription: String {
        switch self {
        case .u6: return "1.5m - 1.8m (Low)"
        case .u8: return "1.8m - 2.6m (Variable)"
        case .u10, .u12: return "2.60m - 3.05m"
        case .u14, .u16, .u18, .adult: return "3.05m (Standard)"
        }
    }
    
    var focusDescription: String {
        switch self {
        case .u6:
            return "Play & Discovery: Maximum fun, minimum structure. Focus on movement exploration, basic motor skills, and positive first experiences with basketball. Short attention spans require constant variety and games."
        case .u8:
            return "Psychomotor Development & Fun: Focus on body awareness, coordination, balance, and enjoyment of movement. Basic interaction with the ball (catching, simple dribbling, throwing). Introduction to very basic rules through play, often in 3x3 format on reduced courts to maximize touches."
        case .u10, .u12:
            return "Skill Acquisition & Fundamental Tactics: Priority on correct execution of individual fundamentals (shooting mechanics, varied passing, dribbling with both hands). Introduction to basic individual tactics (1v1, creating space, defensive stance) and simple collective concepts (pass & move, spacing, 2v1/3v2 situations). Emphasis on technical development over complex team systems."
        case .u14:
            return "Consolidation & Tactical Introduction: Refinement of individual technique under pressure. Introduction to structured team tactics (on-ball and off-ball screens, basic defensive rotations, zone principles). Integration of physical development (speed, agility, initial strength). Developing 'game intelligence' and decision-making."
        case .u16, .u18:
            return "Specialization & Competition: Positional specialization and role definition. Advanced collective concepts (complex offensive systems, varied defensive strategies, scouting). Intensive physical conditioning (power, strength, endurance) integrated with skill work. Mental preparation for high-level competition. Focus on efficiency and execution."
        case .adult:
            return "High Performance & Career: Results-oriented. Maximizing individual and team efficiency. Tactical execution at the highest level, adaptability to game plans and opponents. Career management, injury prevention, and maintaining peak physical and mental condition."
        }
    }
    
    var defaultObjectives: [String] {
        switch self {
        case .u6:
            return ["Fun & play", "Basic motor skills", "Ball familiarity", "Social interaction", "Positive experiences"]
        case .u8:
            return ["Body awareness & coordination", "Basic ball handling", "Fun through play", "3x3 game introduction"]
        case .u10, .u12:
            return ["Shooting mechanics", "Dribbling with both hands", "1v1 fundamentals", "Pass & move concepts", "2v1/3v2 situations"]
        case .u14:
            return ["Technique under pressure", "Screen plays", "Defensive rotations", "Speed & agility", "Game intelligence"]
        case .u16, .u18:
            return ["Positional specialization", "Complex offensive systems", "Physical conditioning", "Mental preparation", "Competition readiness"]
        case .adult:
            return ["Peak performance", "Tactical execution", "Game plan adaptability", "Career management", "Injury prevention"]
        }
    }
    
    var recommendedBallSize: BallSize {
        switch self {
        case .u6, .u8, .u10: return .size5
        case .u12, .u14: return .size6
        case .u16, .u18, .adult: return .size7
        }
    }
    
    var recommendedRimHeight: RimHeight {
        switch self {
        case .u6, .u8: return .feet8
        case .u10, .u12: return .feet9
        case .u14, .u16, .u18, .adult: return .feet10
        }
    }
    
    var colorHex: String {
        switch self {
        case .u6: return "#FFD93D"      // Bright yellow (duckling)
        case .u8: return "#F8A5C2"      // Pink (bunny)
        case .u10: return "#FFB347"     // Orange (monkey)
        case .u12: return "#FFE066"     // Yellow-gold (cheetah)
        case .u14: return "#6B7280"     // Gray (wolf)
        case .u16: return "#1F2937"     // Dark gray (panther)
        case .u18: return "#3B82F6"     // Blue (eagle)
        case .adult: return "#EAB308"   // Gold (lion)
        }
    }
    
    var color: String {
        switch self {
        case .u6: return "yellow"
        case .u8: return "pink"
        case .u10: return "orange"
        case .u12: return "yellow"
        case .u14: return "gray"
        case .u16: return "black"
        case .u18: return "blue"
        case .adult: return "gold"
        }
    }
}

struct BasketballCategory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var ageGroup: AgeGroup
    var ballSize: BallSize
    var rimHeight: RimHeight
    var focusAreas: [String]
    var description: String?
    var maxPlayersPerSession: Int
    var sessionDurationMinutes: Int
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, ageGroup: AgeGroup, ballSize: BallSize? = nil,
         rimHeight: RimHeight? = nil, focusAreas: [String] = [], description: String? = nil,
         maxPlayersPerSession: Int = 12, sessionDurationMinutes: Int = 60,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ageGroup = ageGroup
        self.ballSize = ballSize ?? ageGroup.recommendedBallSize
        self.rimHeight = rimHeight ?? ageGroup.recommendedRimHeight
        self.focusAreas = focusAreas
        self.description = description
        self.maxPlayersPerSession = maxPlayersPerSession
        self.sessionDurationMinutes = sessionDurationMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    static let samples: [BasketballCategory] = [
        BasketballCategory(name: "Little Dribblers", ageGroup: .u8,
                          focusAreas: ["Fun & Movement", "Basic Ball Handling", "Coordination"],
                          maxPlayersPerSession: 10, sessionDurationMinutes: 45),
        BasketballCategory(name: "Junior Hoopers", ageGroup: .u10,
                          focusAreas: ["Dribbling Fundamentals", "Passing", "Layups"],
                          sessionDurationMinutes: 60),
        BasketballCategory(name: "Rising Stars", ageGroup: .u12,
                          focusAreas: ["Shooting Form", "1v1 Moves", "Team Defense"],
                          sessionDurationMinutes: 75),
        BasketballCategory(name: "Elite Development", ageGroup: .u14,
                          focusAreas: ["Advanced Shooting", "Pick & Roll", "Game IQ"],
                          maxPlayersPerSession: 14, sessionDurationMinutes: 90)
    ]
}
