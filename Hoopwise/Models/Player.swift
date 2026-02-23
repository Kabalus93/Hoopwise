import Foundation

enum Handedness: String, Codable, CaseIterable {
    case right, left, ambidextrous
    var displayName: String { rawValue.capitalized }
    var shortName: String {
        switch self {
        case .right: return "R"
        case .left: return "L"
        case .ambidextrous: return "Both"
        }
    }
}

struct ParentInfo: Codable, Hashable, Sendable {
    var name: String
    var relationship: String
    var phone: String
    var email: String?
    var wechatId: String?
    
    init(name: String = "", relationship: String = "Parent", phone: String = "",
         email: String? = nil, wechatId: String? = nil) {
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.email = email
        self.wechatId = wechatId
    }
    
    // Custom decoder to handle missing keys with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? "Parent"
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        wechatId = try container.decodeIfPresent(String.self, forKey: .wechatId)
    }
}

enum ContractStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case active = "Active"
    case completed = "Completed"
    case expired = "Expired"
    case cancelled = "Cancelled"
    
    var color: String {
        switch self {
        case .pending: return "orange"
        case .active: return "green"
        case .completed: return "blue"
        case .expired: return "red"
        case .cancelled: return "gray"
        }
    }
    
    var localizedName: String {
        return rawValue
    }
    
    var localizedNameChinese: String {
        switch self {
        case .pending: return "待定"
        case .active: return "活跃"
        case .completed: return "已完成"
        case .expired: return "已过期"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - Contract Type (Sessions per week + Duration)
enum ContractType: String, Codable, CaseIterable {
    case payAsYouGo = "Pay As You Go"
    case onePerWeek6Months = "1x/week - 6 months"
    case onePerWeek12Months = "1x/week - 12 months"
    case twoPerWeek6Months = "2x/week - 6 months"
    case twoPerWeek12Months = "2x/week - 12 months"
    
    /// Whether this is a pay-as-you-go contract (no fixed sessions)
    var isPayAsYouGo: Bool {
        self == .payAsYouGo
    }
    
    var sessionsPerWeek: Int? {
        switch self {
        case .payAsYouGo: return nil  // No fixed schedule
        case .onePerWeek6Months, .onePerWeek12Months: return 1
        case .twoPerWeek6Months, .twoPerWeek12Months: return 2
        }
    }
    
    var durationMonths: Int? {
        switch self {
        case .payAsYouGo: return nil  // No fixed duration
        case .onePerWeek6Months, .twoPerWeek6Months: return 6
        case .onePerWeek12Months, .twoPerWeek12Months: return 12
        }
    }
    
    var totalSessions: Int? {
        guard let sessionsPerWeek = sessionsPerWeek, let durationMonths = durationMonths else {
            return nil  // Pay as you go has no fixed total
        }
        // Approximately 4.33 weeks per month
        let weeksInDuration = Double(durationMonths) * 4.33
        return Int(Double(sessionsPerWeek) * weeksInDuration)
    }
    
    var displayName: String {
        switch self {
        case .payAsYouGo: return "Pay As You Go"
        case .onePerWeek6Months: return "1 session/week (6 months)"
        case .onePerWeek12Months: return "1 session/week (12 months)"
        case .twoPerWeek6Months: return "2 sessions/week (6 months)"
        case .twoPerWeek12Months: return "2 sessions/week (12 months)"
        }
    }
    
    var displayNameChinese: String {
        switch self {
        case .payAsYouGo: return "按次付费"
        case .onePerWeek6Months: return "1节课/周 (6月)"
        case .onePerWeek12Months: return "1节课/周 (12月)"
        case .twoPerWeek6Months: return "2节课/周 (6月)"
        case .twoPerWeek12Months: return "2节课/周 (12月)"
        }
    }
    
    var shortName: String {
        switch self {
        case .payAsYouGo: return "PAYG"
        case .onePerWeek6Months: return "1x/wk • 6mo"
        case .onePerWeek12Months: return "1x/wk • 12mo"
        case .twoPerWeek6Months: return "2x/wk • 6mo"
        case .twoPerWeek12Months: return "2x/wk • 12mo"
        }
    }
    
    var description: String {
        switch self {
        case .payAsYouGo: return "Flexible scheduling, pay per session. Ideal for 1-on-1 training."
        case .onePerWeek6Months: return "26 sessions over 6 months"
        case .onePerWeek12Months: return "52 sessions over 12 months"
        case .twoPerWeek6Months: return "52 sessions over 6 months"
        case .twoPerWeek12Months: return "104 sessions over 12 months"
        }
    }
    
    var descriptionChinese: String {
        switch self {
        case .payAsYouGo: return "灵活安排，按次付费。适合一对一训练。"
        case .onePerWeek6Months: return "6个月内26节课"
        case .onePerWeek12Months: return "12个月内52节课"
        case .twoPerWeek6Months: return "6个月内52节课"
        case .twoPerWeek12Months: return "12个月内104节课"
        }
    }
}

// MARK: - Weekly Attendance Record (Legacy - kept for backward compatibility)
struct WeeklyAttendanceRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var weekStartDate: Date
    var expectedSessions: Int
    var attendedSessions: Int
    var sessionDates: [Date]
    var notes: String?
    
    init(id: UUID = UUID(), weekStartDate: Date, expectedSessions: Int = 1, 
         attendedSessions: Int = 0, sessionDates: [Date] = [], notes: String? = nil) {
        self.id = id
        self.weekStartDate = weekStartDate
        self.expectedSessions = expectedSessions
        self.attendedSessions = attendedSessions
        self.sessionDates = sessionDates
        self.notes = notes
    }
    
    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }
    
    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStartDate)) - \(formatter.string(from: weekEndDate))"
    }
    
    var isComplete: Bool { attendedSessions >= expectedSessions }
    var missedSessions: Int { max(0, expectedSessions - attendedSessions) }
}

// MARK: - Attended Session Record
/// Links a contract to a specific session that was attended
struct AttendedSessionRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var sessionEventId: UUID
    var sessionDate: Date
    var sessionTitle: String
    var programName: String?
    
    init(id: UUID = UUID(), sessionEventId: UUID, sessionDate: Date, 
         sessionTitle: String, programName: String? = nil) {
        self.id = id
        self.sessionEventId = sessionEventId
        self.sessionDate = sessionDate
        self.sessionTitle = sessionTitle
        self.programName = programName
    }
}

// MARK: - Contract (Simplified)
/// Simplified contract model tracking enrollment and session attendance
struct Contract: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var contractNumber: Int  // 1st contract, 2nd contract, etc.
    
    // MARK: - Core Fields (Simplified)
    var contractType: ContractType  // PAYG, 1x/6mo, 1x/12mo, 2x/6mo, 2x/12mo
    var enrollmentDate: Date  // When student enrolled
    var expiryDate: Date?  // Auto-calculated from contract type, nil for PAYG
    var attendedSessionIds: [UUID]  // Session event IDs attended
    var notes: String?
    
    // MARK: - Legacy Fields (kept for backward compatibility)
    var totalSessions: Int  // Auto-calculated from contract type
    var attendedSessions: Int  // Now derived from attendedSessionIds.count
    var weeklyAttendance: [WeeklyAttendanceRecord]  // Deprecated
    var startDate: Date?  // Maps to enrollmentDate
    var pricePerSession: Double  // Legacy payment tracking
    var totalAmount: Double
    var amountPaid: Double
    var isSigned: Bool
    var signedDate: Date?
    var jerseyGiven: Bool
    var jerseyGivenDate: Date?
    var ballGiven: Bool
    var ballGivenDate: Date?
    var jerseyNumber: Int?
    var jerseySize: String?
    var createdByCoachId: UUID?
    var manualStatus: ContractStatus?
    var programAssignments: [UUID]
    var historicalSessionsConsumed: Int
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Simplified Initializer
    init(
        id: UUID = UUID(),
        studentId: UUID,
        contractNumber: Int = 1,
        contractType: ContractType = .payAsYouGo,
        enrollmentDate: Date = Date(),
        attendedSessionIds: [UUID] = [],
        notes: String? = nil,
        createdByCoachId: UUID? = nil
    ) {
        self.id = id
        self.studentId = studentId
        self.contractNumber = contractNumber
        self.contractType = contractType
        self.enrollmentDate = enrollmentDate
        self.attendedSessionIds = attendedSessionIds
        self.notes = notes
        self.createdByCoachId = createdByCoachId
        
        // Auto-calculate from contract type
        self.totalSessions = contractType.totalSessions ?? 0
        self.expiryDate = contractType.durationMonths.flatMap {
            Calendar.current.date(byAdding: .month, value: $0, to: enrollmentDate)
        }
        
        // Legacy fields - set sensible defaults
        self.attendedSessions = attendedSessionIds.count
        self.weeklyAttendance = []
        self.startDate = enrollmentDate
        self.pricePerSession = 0
        self.totalAmount = 0
        self.amountPaid = 0
        self.isSigned = true  // Simplified: assume signed
        self.signedDate = enrollmentDate
        self.jerseyGiven = false
        self.jerseyGivenDate = nil
        self.ballGiven = false
        self.ballGivenDate = nil
        self.jerseyNumber = nil
        self.jerseySize = nil
        self.manualStatus = nil
        self.programAssignments = []
        self.historicalSessionsConsumed = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Full Initializer (backward compatibility)
    init(
        id: UUID = UUID(),
        studentId: UUID,
        contractNumber: Int = 1,
        contractType: ContractType? = nil,
        totalSessions: Int = 0,
        attendedSessions: Int = 0,
        weeklyAttendance: [WeeklyAttendanceRecord] = [],
        startDate: Date? = nil,
        expiryDate: Date? = nil,
        pricePerSession: Double = 0,
        totalAmount: Double = 0,
        amountPaid: Double = 0,
        isSigned: Bool = false,
        signedDate: Date? = nil,
        jerseyGiven: Bool = false,
        jerseyGivenDate: Date? = nil,
        ballGiven: Bool = false,
        ballGivenDate: Date? = nil,
        jerseyNumber: Int? = nil,
        jerseySize: String? = nil,
        notes: String? = nil,
        createdByCoachId: UUID? = nil,
        manualStatus: ContractStatus? = nil,
        programAssignments: [UUID] = [],
        historicalSessionsConsumed: Int = 0,
        attendedSessionIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.contractNumber = contractNumber
        self.contractType = contractType ?? .payAsYouGo
        self.enrollmentDate = startDate ?? createdAt
        self.expiryDate = expiryDate
        self.attendedSessionIds = attendedSessionIds
        self.notes = notes
        self.totalSessions = totalSessions
        self.attendedSessions = attendedSessions
        self.weeklyAttendance = weeklyAttendance
        self.startDate = startDate
        self.pricePerSession = pricePerSession
        self.totalAmount = totalAmount
        self.amountPaid = amountPaid
        self.isSigned = isSigned
        self.signedDate = signedDate
        self.jerseyGiven = jerseyGiven
        self.jerseyGivenDate = jerseyGivenDate
        self.ballGiven = ballGiven
        self.ballGivenDate = ballGivenDate
        self.jerseyNumber = jerseyNumber
        self.jerseySize = jerseySize
        self.createdByCoachId = createdByCoachId
        self.manualStatus = manualStatus
        self.programAssignments = programAssignments
        self.historicalSessionsConsumed = historicalSessionsConsumed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties
    
    /// Sessions attended (from attendedSessionIds count)
    var sessionCount: Int {
        attendedSessionIds.count
    }
    
    /// Whether this is a pay-as-you-go contract
    var isPayAsYouGo: Bool {
        contractType.isPayAsYouGo
    }
    
    /// Sessions per week based on contract type
    var sessionsPerWeek: Int? {
        contractType.sessionsPerWeek
    }
    
    /// Remaining sessions (nil for PAYG)
    var remainingSessions: Int? {
        guard !isPayAsYouGo else { return nil }
        return max(0, totalSessions - sessionCount)
    }
    
    var remainingSessionsDisplay: Int {
        remainingSessions ?? 0
    }
    
    var progressPercentage: Double {
        guard !isPayAsYouGo, totalSessions > 0 else { return 0 }
        return Double(sessionCount) / Double(totalSessions)
    }
    
    var isExpired: Bool {
        guard !isPayAsYouGo, let expiryDate else { return false }
        return Date() > expiryDate
    }
    
    var isFullyPaid: Bool {
        if isPayAsYouGo { return true }  // PAYG always "paid"
        return amountPaid >= totalAmount
    }
    
    var outstandingBalance: Double {
        max(0, totalAmount - amountPaid)
    }
    
    var status: ContractStatus {
        if let manual = manualStatus { return manual }
        if isPayAsYouGo { return .active }
        if isExpired { return .expired }
        if remainingSessions == 0 { return .completed }
        return .active
    }
    
    var typeLabel: String {
        contractType.shortName
    }
    
    var typeLabelChinese: String {
        contractType.displayNameChinese
    }
    
    var contractLabel: String {
        let suffix: String
        switch contractNumber {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(contractNumber)\(suffix) Contract"
    }
    
    func localizedContractLabel(isChinese: Bool) -> String {
        isChinese ? "第\(contractNumber)份合同" : contractLabel
    }
    
    /// Add a session to attended list
    mutating func recordAttendance(sessionEventId: UUID) {
        if !attendedSessionIds.contains(sessionEventId) {
            attendedSessionIds.append(sessionEventId)
            attendedSessions = attendedSessionIds.count
            updatedAt = Date()
        }
    }
    
    /// Remove a session from attended list
    mutating func removeAttendance(sessionEventId: UUID) {
        attendedSessionIds.removeAll { $0 == sessionEventId }
        attendedSessions = attendedSessionIds.count
        updatedAt = Date()
    }
    
    /// Legacy: Generate weekly records (deprecated)
    mutating func generateWeeklyRecords() {
        // No longer used - kept for backward compatibility
    }
    
    /// Legacy: Calculate attended sessions (deprecated)
    var calculatedAttendedSessions: Int {
        sessionCount
    }
    
    // MARK: - Sample Data
    static let sample = Contract(
        studentId: UUID(),
        contractType: .onePerWeek6Months,
        enrollmentDate: Calendar.current.date(byAdding: .month, value: -2, to: Date())!
    )
}

// Legacy support - maps to current contract
struct ContractInfo: Codable, Hashable, Sendable {
    var totalSessions: Int
    var completedSessions: Int
    var startDate: Date?
    var expiryDate: Date?
    var pricePerSession: Double
    var totalPaid: Double
    var notes: String?
    
    init(totalSessions: Int = 0, completedSessions: Int = 0, startDate: Date? = nil,
         expiryDate: Date? = nil, pricePerSession: Double = 0, totalPaid: Double = 0, notes: String? = nil) {
        self.totalSessions = totalSessions
        self.completedSessions = completedSessions
        self.startDate = startDate
        self.expiryDate = expiryDate
        self.pricePerSession = pricePerSession
        self.totalPaid = totalPaid
        self.notes = notes
    }
    
    // Custom decoder to handle missing keys with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSessions = try container.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        pricePerSession = try container.decodeIfPresent(Double.self, forKey: .pricePerSession) ?? 0
        totalPaid = try container.decodeIfPresent(Double.self, forKey: .totalPaid) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    var remainingSessions: Int { max(0, totalSessions - completedSessions) }
    var progressPercentage: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }
    var isExpired: Bool {
        guard let expiryDate else { return false }
        return Date() > expiryDate
    }
}

/// 6-axis skills evaluation matching the performance radar diagram
/// Each skill is rated 1-10 by the coach. These blend with game stats for final radar values.
struct SkillsEvaluation: Codable, Hashable, Sendable {
    // 6 skills matching radar axes (1-10 scale)
    var scoring: Int        // Shooting ability, shot selection, finishing
    var playmaking: Int     // Passing, vision, basketball IQ
    var rebounding: Int     // Boxing out, positioning, effort on boards
    var defense: Int        // On-ball defense, help defense, communication
    var athleticism: Int    // Speed, agility, vertical, endurance
    var intangibles: Int    // Teamwork, coachability, attitude, hustle
    
    var lastEvaluatedDate: Date?
    var notes: String?
    
    // MARK: - Legacy properties (computed for backward compatibility)
    var shooting: Int { scoring }
    var ballHandling: Int { playmaking }
    var basketballIQ: Int { playmaking }
    var teamwork: Int { intangibles }
    var coachability: Int { intangibles }
    
    init(scoring: Int = 5, playmaking: Int = 5, rebounding: Int = 5, defense: Int = 5,
         athleticism: Int = 5, intangibles: Int = 5,
         lastEvaluatedDate: Date? = nil, notes: String? = nil) {
        self.scoring = scoring
        self.playmaking = playmaking
        self.rebounding = rebounding
        self.defense = defense
        self.athleticism = athleticism
        self.intangibles = intangibles
        self.lastEvaluatedDate = lastEvaluatedDate
        self.notes = notes
    }
    
    // Custom decoder to handle both old 7-skill and new 6-skill formats
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
            
            // Map old skills to new
            scoring = oldShooting
            playmaking = (oldBallHandling + oldBasketballIQ) / 2
            rebounding = 5  // No direct mapping, use default
            intangibles = (oldTeamwork + oldCoachability) / 2
        }
        
        defense = try container.decodeIfPresent(Int.self, forKey: .defense) ?? 5
        athleticism = try container.decodeIfPresent(Int.self, forKey: .athleticism) ?? 5
        lastEvaluatedDate = try container.decodeIfPresent(Date.self, forKey: .lastEvaluatedDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    private enum CodingKeys: String, CodingKey {
        // New 6-skill keys only for encoding
        case scoring, playmaking, rebounding, defense, athleticism, intangibles
        // Legacy 7-skill keys for decoding migration
        case shooting, ballHandling, basketballIQ, teamwork, coachability
        // Common
        case lastEvaluatedDate, notes
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scoring, forKey: .scoring)
        try container.encode(playmaking, forKey: .playmaking)
        try container.encode(rebounding, forKey: .rebounding)
        try container.encode(defense, forKey: .defense)
        try container.encode(athleticism, forKey: .athleticism)
        try container.encode(intangibles, forKey: .intangibles)
        try container.encodeIfPresent(lastEvaluatedDate, forKey: .lastEvaluatedDate)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
    
    var overallRating: Double {
        Double(scoring + playmaking + rebounding + defense + athleticism + intangibles) / 6.0
    }
    
    /// Returns array of values in radar order (0-10 scale)
    var radarValues: [Double] {
        [Double(scoring), Double(playmaking), Double(rebounding), 
         Double(defense), Double(athleticism), Double(intangibles)]
    }
}

struct Player: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var heightCm: Double?
    var weightKg: Double?
    var wingspanCm: Double?
    var handedness: Handedness
    var position: String?
    var jerseyNumber: Int?
    var parentInfo: ParentInfo
    var secondaryParentInfo: ParentInfo?
    var contractInfo: ContractInfo
    var skills: SkillsEvaluation
    var coachNotes: String?
    var medicalNotes: String?
    var profileImageData: Data?  // Profile picture stored as Data
    var headerImageURL: String?   // Background image URL for profile card
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), studentId: UUID, heightCm: Double? = nil, weightKg: Double? = nil,
         wingspanCm: Double? = nil, handedness: Handedness = .right, position: String? = nil,
         jerseyNumber: Int? = nil, parentInfo: ParentInfo = ParentInfo(),
         secondaryParentInfo: ParentInfo? = nil, contractInfo: ContractInfo = ContractInfo(),
         skills: SkillsEvaluation = SkillsEvaluation(), coachNotes: String? = nil,
         medicalNotes: String? = nil, profileImageData: Data? = nil,
         headerImageURL: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.studentId = studentId
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.wingspanCm = wingspanCm
        self.handedness = handedness
        self.position = position
        self.jerseyNumber = jerseyNumber
        self.parentInfo = parentInfo
        self.secondaryParentInfo = secondaryParentInfo
        self.contractInfo = contractInfo
        self.skills = skills
        self.coachNotes = coachNotes
        self.medicalNotes = medicalNotes
        self.profileImageData = profileImageData
        self.headerImageURL = headerImageURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var heightFormatted: String? {
        guard let h = heightCm else { return nil }
        return "\(Int(h / 30.48))'\(Int((h.truncatingRemainder(dividingBy: 30.48)) / 2.54))\" (\(Int(h))cm)"
    }
    
    var weightFormatted: String? {
        guard let w = weightKg else { return nil }
        return "\(Int(w * 2.205))lbs (\(Int(w))kg)"
    }
}
