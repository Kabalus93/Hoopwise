import Foundation
import SwiftUI

enum ProgramStatus: String, Codable, CaseIterable {
    case draft, active, completed, archived
    var displayName: String { rawValue.capitalized }
}

enum ProgramType: String, Codable, CaseIterable {
    case group = "Group Training"
    case privateSessions = "Private Sessions"
    case team = "Team Program"
    case clinic = "Clinic/Camp"
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .group: return "person.3.fill"
        case .privateSessions: return "person.fill"
        case .team: return "sportscourt.fill"
        case .clinic: return "flag.fill"
        }
    }
    
    var description: String {
        switch self {
        case .group: return "Regular group training sessions"
        case .privateSessions: return "One-on-one or small group private training"
        case .team: return "Team-based program with competitive focus"
        case .clinic: return "Short-term clinic or camp program"
        }
    }
    
    /// Whether this program type typically has multiple students
    var isMultiStudent: Bool {
        switch self {
        case .privateSessions: return false
        case .group, .team, .clinic: return true
        }
    }
    
    /// Recommended max students for this program type
    var recommendedMaxStudents: Int? {
        switch self {
        case .privateSessions: return 3
        case .group: return 15
        case .team: return 20
        case .clinic: return 30
        }
    }
}

enum EnrollmentStatus: String, Codable, CaseIterable {
    case active, paused, completed, dropped
    var displayName: String { rawValue.capitalized }
}

// MARK: - Program Mascot
enum ProgramMascot: String, Codable, CaseIterable {
    case tiger = "Tigers"
    case lion = "Lions"
    case eagle = "Eagles"
    case wolf = "Wolves"
    case bear = "Bears"
    case hawk = "Hawks"
    case panther = "Panthers"
    case falcon = "Falcons"
    case dragon = "Dragons"
    case phoenix = "Phoenix"
    case shark = "Sharks"
    case cobra = "Cobras"
    case bull = "Bulls"
    case mustang = "Mustangs"
    case jaguar = "Jaguars"
    case viper = "Vipers"
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .tiger: return "cat.fill"
        case .lion: return "crown.fill"
        case .eagle: return "bird.fill"
        case .wolf: return "dog.fill"
        case .bear: return "pawprint.fill"
        case .hawk: return "bird"
        case .panther: return "cat"
        case .falcon: return "wind"
        case .dragon: return "flame.fill"
        case .phoenix: return "sparkles"
        case .shark: return "fish.fill"
        case .cobra: return "bolt.fill"
        case .bull: return "horn.fill"
        case .mustang: return "hare.fill"
        case .jaguar: return "leaf.fill"
        case .viper: return "bolt.horizontal.fill"
        }
    }
    
    var colorHex: String {
        switch self {
        case .tiger: return "#F97316"      // Orange
        case .lion: return "#EAB308"       // Yellow/Gold
        case .eagle: return "#3B82F6"      // Blue
        case .wolf: return "#6B7280"       // Gray
        case .bear: return "#92400E"       // Brown
        case .hawk: return "#DC2626"       // Red
        case .panther: return "#1F2937"    // Dark Gray
        case .falcon: return "#0891B2"     // Cyan
        case .dragon: return "#7C3AED"     // Purple
        case .phoenix: return "#F59E0B"    // Amber
        case .shark: return "#0EA5E9"      // Sky Blue
        case .cobra: return "#16A34A"      // Green
        case .bull: return "#B91C1C"       // Dark Red
        case .mustang: return "#8B5CF6"    // Violet
        case .jaguar: return "#059669"     // Emerald
        case .viper: return "#84CC16"      // Lime
        }
    }
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    var gradient: LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Program Stars (Tier/Quality Rating)
enum ProgramStars: Int, Codable, CaseIterable {
    case one = 1    // Green tier
    case two = 2    // Gold tier
    case three = 3  // Platinum tier
    case four = 4   // Centurion/Black tier
    
    var displayName: String {
        switch self {
        case .one: return "Green"
        case .two: return "Gold"
        case .three: return "Platinum"
        case .four: return "Centurion"
        }
    }
    
    var tierName: String {
        switch self {
        case .one: return "GREEN"
        case .two: return "GOLD"
        case .three: return "PLATINUM"
        case .four: return "CENTURION"
        }
    }
}

// MARK: - Weekday for recurring sessions
enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    var displayName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
    
    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
}

// MARK: - Program Skill Targets (6 skills matching radar)
/// Expected skill levels for athletes in a program - used to compare individual progress
struct ProgramSkillTargets: Codable, Hashable {
    var scoring: Int        // Target scoring ability
    var playmaking: Int     // Target playmaking ability
    var rebounding: Int     // Target rebounding ability
    var defense: Int        // Target defensive ability
    var athleticism: Int    // Target athleticism
    var intangibles: Int    // Target intangibles (teamwork, coachability, hustle)
    var lastUpdatedDate: Date?
    
    // Legacy computed properties for backward compatibility
    var shooting: Int { scoring }
    var ballHandling: Int { playmaking }
    var basketballIQ: Int { playmaking }
    var teamwork: Int { intangibles }
    var coachability: Int { intangibles }
    
    init(scoring: Int = 5, playmaking: Int = 5, rebounding: Int = 5, defense: Int = 5,
         athleticism: Int = 5, intangibles: Int = 5, lastUpdatedDate: Date? = nil) {
        self.scoring = scoring
        self.playmaking = playmaking
        self.rebounding = rebounding
        self.defense = defense
        self.athleticism = athleticism
        self.intangibles = intangibles
        self.lastUpdatedDate = lastUpdatedDate
    }
    
    // Decoder to handle both old 7-skill and new 6-skill formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try new 6-skill format first
        if let s = try container.decodeIfPresent(Int.self, forKey: .scoring) {
            scoring = s
            playmaking = try container.decodeIfPresent(Int.self, forKey: .playmaking) ?? 5
            rebounding = try container.decodeIfPresent(Int.self, forKey: .rebounding) ?? 5
            intangibles = try container.decodeIfPresent(Int.self, forKey: .intangibles) ?? 5
        } else {
            // Migrate from old 7-skill format
            let oldShooting = try container.decodeIfPresent(Int.self, forKey: .shooting) ?? 5
            let oldBallHandling = try container.decodeIfPresent(Int.self, forKey: .ballHandling) ?? 5
            let oldBasketballIQ = try container.decodeIfPresent(Int.self, forKey: .basketballIQ) ?? 5
            let oldTeamwork = try container.decodeIfPresent(Int.self, forKey: .teamwork) ?? 5
            let oldCoachability = try container.decodeIfPresent(Int.self, forKey: .coachability) ?? 5
            
            scoring = oldShooting
            playmaking = (oldBallHandling + oldBasketballIQ) / 2
            rebounding = 5
            intangibles = (oldTeamwork + oldCoachability) / 2
        }
        
        defense = try container.decodeIfPresent(Int.self, forKey: .defense) ?? 5
        athleticism = try container.decodeIfPresent(Int.self, forKey: .athleticism) ?? 5
        lastUpdatedDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedDate)
    }
    
    private enum CodingKeys: String, CodingKey {
        case scoring, playmaking, rebounding, defense, athleticism, intangibles
        case shooting, ballHandling, basketballIQ, teamwork, coachability
        case lastUpdatedDate
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scoring, forKey: .scoring)
        try container.encode(playmaking, forKey: .playmaking)
        try container.encode(rebounding, forKey: .rebounding)
        try container.encode(defense, forKey: .defense)
        try container.encode(athleticism, forKey: .athleticism)
        try container.encode(intangibles, forKey: .intangibles)
        try container.encodeIfPresent(lastUpdatedDate, forKey: .lastUpdatedDate)
    }
    
    var overallTarget: Double {
        Double(scoring + playmaking + rebounding + defense + athleticism + intangibles) / 6.0
    }
    
    /// Compare a student's skills against these targets
    func compare(to skills: SkillsEvaluation) -> [String: Int] {
        [
            "Scoring": skills.scoring - scoring,
            "Playmaking": skills.playmaking - playmaking,
            "Rebounding": skills.rebounding - rebounding,
            "Defense": skills.defense - defense,
            "Athleticism": skills.athleticism - athleticism,
            "Intangibles": skills.intangibles - intangibles
        ]
    }
    
    /// Check if a student meets all skill targets
    func meetsAllTargets(_ skills: SkillsEvaluation) -> Bool {
        skills.scoring >= scoring &&
        skills.playmaking >= playmaking &&
        skills.rebounding >= rebounding &&
        skills.defense >= defense &&
        skills.athleticism >= athleticism &&
        skills.intangibles >= intangibles
    }
    
    /// Count how many skills are below target
    func skillsBelowTarget(_ skills: SkillsEvaluation) -> Int {
        var count = 0
        if skills.scoring < scoring { count += 1 }
        if skills.playmaking < playmaking { count += 1 }
        if skills.rebounding < rebounding { count += 1 }
        if skills.defense < defense { count += 1 }
        if skills.athleticism < athleticism { count += 1 }
        if skills.intangibles < intangibles { count += 1 }
        return count
    }
    
    /// Get the skills that are below target
    func getSkillsBelowTarget(_ skills: SkillsEvaluation) -> [String] {
        var below: [String] = []
        if skills.scoring < scoring { below.append("Scoring") }
        if skills.playmaking < playmaking { below.append("Playmaking") }
        if skills.rebounding < rebounding { below.append("Rebounding") }
        if skills.defense < defense { below.append("Defense") }
        if skills.athleticism < athleticism { below.append("Athleticism") }
        if skills.intangibles < intangibles { below.append("Intangibles") }
        return below
    }
}

struct Program: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var programType: ProgramType  // Type of program (group, private, team, clinic)
    var ageGroup: AgeGroup
    var durationWeeks: Int
    var description: String?
    var objectives: [String]
    var enrolledStudentIds: [UUID]
    var coachId: UUID?  // Assigned coach from Organization
    var createdByCoachId: UUID?  // Coach who created this program (for access control)
    var status: ProgramStatus
    var colorHex: String
    var mascot: ProgramMascot
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var imageData: Data?  // Store program cover image
    var stars: ProgramStars  // Quality/tier rating (1-4 stars)
    
    // Recurring session schedule
    var recurringDays: [Weekday]  // Days of the week sessions occur
    var defaultSessionTime: Date?  // Default start time for sessions (only time component used)
    var defaultSessionDurationMinutes: Int  // Default duration in minutes
    
    // Skill targets for program athletes
    var skillTargets: ProgramSkillTargets?  // Expected skill levels for athletes in this program
    
    // Location
    var locationId: UUID?  // Reference to Location from Organization
    var locationName: String?  // Cached location name for display
    
    // Phase-less programs
    var usesPhases: Bool  // If false, sessions are created directly without phases
    
    init(id: UUID = UUID(), name: String, programType: ProgramType = .group, ageGroup: AgeGroup, durationWeeks: Int = 12,
         description: String? = nil, objectives: [String] = [], enrolledStudentIds: [UUID] = [],
         coachId: UUID? = nil, createdByCoachId: UUID? = nil, status: ProgramStatus = .draft, 
         colorHex: String? = nil, mascot: ProgramMascot = .eagle, startDate: Date? = nil, 
         endDate: Date? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), imageData: Data? = nil,
         stars: ProgramStars = .one, recurringDays: [Weekday] = [.saturday], 
         defaultSessionTime: Date? = nil, defaultSessionDurationMinutes: Int = 90,
         skillTargets: ProgramSkillTargets? = nil,
         locationId: UUID? = nil, locationName: String? = nil,
         usesPhases: Bool = true) {
        self.id = id
        self.name = name
        self.programType = programType
        self.ageGroup = ageGroup
        self.durationWeeks = durationWeeks
        self.description = description
        self.objectives = objectives
        self.enrolledStudentIds = enrolledStudentIds
        self.coachId = coachId
        self.createdByCoachId = createdByCoachId
        self.status = status
        self.colorHex = colorHex ?? mascot.colorHex
        self.mascot = mascot
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageData = imageData
        self.stars = stars
        self.recurringDays = recurringDays
        self.defaultSessionTime = defaultSessionTime
        self.defaultSessionDurationMinutes = defaultSessionDurationMinutes
        self.skillTargets = skillTargets
        self.locationId = locationId
        self.locationName = locationName
        self.usesPhases = usesPhases
    }
    
    var enrolledCount: Int { enrolledStudentIds.count }
    var isActive: Bool { status == .active }
    
    /// Full display name: Location + Mascot + Category (e.g., "义蓬 Cheetahs U12")
    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        var parts: [String] = []
        
        // Location first
        if let location = locationName, !location.isEmpty {
            parts.append(location)
        }
        
        // Mascot name (from age group)
        let mascotName = isChinese ? ageGroup.mascotNameChinese : ageGroup.mascotName
        parts.append(mascotName)
        
        // Age group (category)
        parts.append(ageGroup.rawValue)
        
        return parts.joined(separator: " ")
    }
    
    /// Short name using mascot + category
    var shortName: String {
        "\(ageGroup.mascotName) \(ageGroup.rawValue)"
    }
    
    /// Legacy display name with mascot
    var mascotDisplayName: String {
        "\(ageGroup.mascotName) - \(name)"
    }
    
    /// Color derived from age group
    var mascotColor: Color {
        Color(hex: ageGroup.colorHex)
    }
    
    /// Icon derived from age group (SF Symbol)
    var mascotIcon: String {
        ageGroup.mascotIcon
    }
    
    /// Custom icon asset name (if any)
    var customIconAsset: String? {
        ageGroup.customIconAsset
    }
    
    /// Whether this program uses a custom icon
    var usesCustomIcon: Bool {
        ageGroup.usesCustomIcon
    }
    
    static let samples: [Program] = [
        Program(name: "Summer Skills Camp 2024", ageGroup: .u12, durationWeeks: 8,
                description: "Intensive summer program focusing on fundamental skill development",
                objectives: ["Improve shooting mechanics", "Develop ball handling", "Learn team defense"],
                status: .active, mascot: .eagle, startDate: Date(), stars: .one),
        Program(name: "Elite Development Program", ageGroup: .u14, durationWeeks: 16,
                description: "Year-round development program for competitive players",
                objectives: ["Advanced offensive moves", "Defensive positioning", "Game IQ"],
                status: .active, mascot: .dragon, stars: .three),
        Program(name: "Beginner Fundamentals", ageGroup: .u10, durationWeeks: 10,
                description: "Introduction to basketball for young players",
                objectives: ["Basic dribbling", "Passing fundamentals", "Layup technique"],
                status: .draft, mascot: .tiger, stars: .one)
    ]
}

struct ProgramEnrollment: Identifiable, Codable, Hashable {
    let id: UUID
    var programId: UUID
    var studentId: UUID
    var enrollmentDate: Date
    var status: EnrollmentStatus
    var notes: String?
    
    init(id: UUID = UUID(), programId: UUID, studentId: UUID,
         enrollmentDate: Date = Date(), status: EnrollmentStatus = .active, notes: String? = nil) {
        self.id = id
        self.programId = programId
        self.studentId = studentId
        self.enrollmentDate = enrollmentDate
        self.status = status
        self.notes = notes
    }
}
