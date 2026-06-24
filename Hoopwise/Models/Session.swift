import Foundation
import SwiftUI

// MARK: - Curriculum Section
enum CurriculumSection: String, CaseIterable {
    case warmup = "WARMUP"
    case main = "SKILLS"
    case cooldown = "GAME"
    
    var displayName: String {
        switch self {
        case .warmup: return "Warmup"
        case .main: return "Skills"
        case .cooldown: return "Game"
        }
    }
    
    var icon: String {
        switch self {
        case .warmup: return "flame.fill"
        case .main: return "figure.basketball"
        case .cooldown: return "trophy.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .warmup: return .orange
        case .main: return .blue
        case .cooldown: return .green
        }
    }
}

// MARK: - Session Access Mode
/// Controls CRUD permissions based on entry point
enum SessionAccessMode {
    case architect   // Full CRUD - accessed from Program/Phase view
    case execution   // Read/Update only - accessed from Calendar view
    
    var canCreate: Bool { self == .architect }
    var canDelete: Bool { self == .architect }  // Execution mode is read/update only — no destructive ops
    var canEdit: Bool { true }
    var canTakeAttendance: Bool { true }
    var canAddNotes: Bool { true }
}

enum SessionType: String, Codable, CaseIterable {
    case training, scrimmage, gamePrep, recovery, assessment
    
    var displayName: String {
        switch self {
        case .training: return "Training"
        case .scrimmage: return "Scrimmage"
        case .gamePrep: return "Game Prep"
        case .recovery: return "Recovery"
        case .assessment: return "Assessment"
        }
    }
    
    var icon: String {
        switch self {
        case .training: return "figure.basketball"
        case .scrimmage: return "sportscourt"
        case .gamePrep: return "clipboard"
        case .recovery: return "heart.circle"
        case .assessment: return "checklist"
        }
    }
}

// MARK: - Session Curriculum
/// Represents the plan/curriculum for a session (Skills, Warmup, Game sections)
struct SessionCurriculum: Codable, Hashable {
    var warmupDrillIds: [UUID]
    var skillDrillIds: [UUID]
    var gameDrillIds: [UUID]
    var warmupMinutes: Int
    var skillsMinutes: Int
    var gameMinutes: Int
    var notes: String?
    
    init(warmupDrillIds: [UUID] = [], skillDrillIds: [UUID] = [], gameDrillIds: [UUID] = [],
         warmupMinutes: Int = 30, skillsMinutes: Int = 30, gameMinutes: Int = 30, notes: String? = nil) {
        self.warmupDrillIds = warmupDrillIds
        self.skillDrillIds = skillDrillIds
        self.gameDrillIds = gameDrillIds
        self.warmupMinutes = warmupMinutes
        self.skillsMinutes = skillsMinutes
        self.gameMinutes = gameMinutes
        self.notes = notes
    }
    
    var totalDrillCount: Int { warmupDrillIds.count + skillDrillIds.count + gameDrillIds.count }
    var totalMinutes: Int { warmupMinutes + skillsMinutes + gameMinutes }
}

enum SessionEventStatus: String, Codable, CaseIterable {
    case scheduled, inProgress, completed, cancelled, skipped
    
    var displayName: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .skipped: return "Skipped"
        }
    }
    
    var color: String {
        switch self {
        case .scheduled: return "blue"
        case .inProgress: return "orange"
        case .completed: return "green"
        case .cancelled: return "red"
        case .skipped: return "gray"
        }
    }
}

struct PhaseSession: Identifiable, Codable, Hashable {
    let id: UUID
    var microCycleId: UUID
    var sessionNumber: Int
    var title: String
    var sessionType: SessionType
    var objectives: [String]
    var drillIds: [UUID]
    var scheduledDate: Date?
    var durationMinutes: Int
    var notes: String?
    var warmUpMinutes: Int
    var coolDownMinutes: Int
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), microCycleId: UUID, sessionNumber: Int, title: String,
         sessionType: SessionType = .training, objectives: [String] = [], drillIds: [UUID] = [],
         scheduledDate: Date? = nil, durationMinutes: Int = 60, notes: String? = nil,
         warmUpMinutes: Int = 10, coolDownMinutes: Int = 5,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.microCycleId = microCycleId
        self.sessionNumber = sessionNumber
        self.title = title
        self.sessionType = sessionType
        self.objectives = objectives
        self.drillIds = drillIds
        self.scheduledDate = scheduledDate
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.warmUpMinutes = warmUpMinutes
        self.coolDownMinutes = coolDownMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var mainActivityMinutes: Int { durationMinutes - warmUpMinutes - coolDownMinutes }
    var drillCount: Int { drillIds.count }
}

// MARK: - Session Game Models

/// Type of in-session game
enum SessionGameType: String, Codable, CaseIterable {
    case twoTeam = "twoTeam"              // Traditional 2 teams, winner stays on
    case continuousFullCourt = "continuous" // 3 teams: one attacks, two defend each basket
    case battleRoyal = "battleRoyal"      // 1v all - individual competition, no teams
    
    var displayName: String {
        switch self {
        case .twoTeam: return "Regular"
        case .continuousFullCourt: return "Continuous"
        case .battleRoyal: return "Battle Royal"
        }
    }
    
    var localizedName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .twoTeam: return isChinese ? "常规赛" : "Regular"
        case .continuousFullCourt: return isChinese ? "全场轮转" : "Continuous"
        case .battleRoyal: return isChinese ? "大乱斗" : "Battle Royal"
        }
    }
    
    var description: String {
        switch self {
        case .twoTeam: return "2 teams on court, winner stays, loser rotates out"
        case .continuousFullCourt: return "3 teams: one attacks, two defend each basket"
        case .battleRoyal: return "1 vs All - ball holder attacks, everyone else defends"
        }
    }
    
    var localizedDescription: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .twoTeam: return isChinese ? "两队上场，赢的留下，输的轮换" : "2 teams on court, winner stays"
        case .continuousFullCourt: return isChinese ? "3队轮转：1队进攻，2队防守" : "3 teams rotate: 1 attacks, 2 defend"
        case .battleRoyal: return isChinese ? "一人对所有人，持球者进攻" : "1 vs All - ball holder attacks"
        }
    }
    
    var icon: String {
        switch self {
        case .twoTeam: return "person.2.fill"
        case .continuousFullCourt: return "arrow.triangle.2.circlepath"
        case .battleRoyal: return "crown.fill"
        }
    }
    
    var requiredTeams: Int {
        switch self {
        case .twoTeam: return 2
        case .continuousFullCourt: return 3
        case .battleRoyal: return 0  // No teams needed
        }
    }
    
    /// Whether this game type uses teams or individual players
    var isIndividual: Bool {
        self == .battleRoyal
    }
    
    /// Whether assists are tracked for this game type
    var tracksAssists: Bool {
        self != .battleRoyal  // No assists in 1v all
    }
}

/// Team role in continuous full court game
enum TeamRole: String, Codable {
    case attacking    // Team with the ball, attacks both baskets
    case defendingA   // Defends basket A
    case defendingB   // Defends basket B
    case waiting      // Off-court, waiting to play
    
    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .attacking: return isChinese ? "进攻" : "Attacking"
        case .defendingA: return isChinese ? "防守A" : "Defense A"
        case .defendingB: return isChinese ? "防守B" : "Defense B"
        case .waiting: return isChinese ? "等待" : "Waiting"
        }
    }
}

/// A team created for an in-session scrimmage game
struct GameTeam: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var colorHex: String
    var playerIds: [UUID]
    var role: TeamRole?           // For continuous full court games
    var wins: Int                 // Track wins for winner-stays-on
    var losses: Int               // Track losses
    
    init(id: UUID = UUID(), name: String, colorHex: String, playerIds: [UUID] = [], 
         role: TeamRole? = nil, wins: Int = 0, losses: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.playerIds = playerIds
        self.role = role
        self.wins = wins
        self.losses = losses
    }
    
    // Custom decoder for backward compatibility (wins/losses may be missing)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        playerIds = try container.decode([UUID].self, forKey: .playerIds)
        role = try container.decodeIfPresent(TeamRole.self, forKey: .role)
        wins = try container.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try container.decodeIfPresent(Int.self, forKey: .losses) ?? 0
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex, playerIds, role, wins, losses
    }
    
    static let presetColors: [(name: String, hex: String)] = [
        ("Yellow", "#FFD700"), ("Blue", "#4A90D9"), ("Red", "#E74C3C"), ("Green", "#2ECC71"),
        ("Purple", "#9B59B6"), ("Orange", "#F39C12"), ("Pink", "#E91E63"), ("Cyan", "#00BCD4"),
        ("Black", "#1A1A1A"), ("White", "#F5F5F5")
    ]
    
    /// Get localized color name
    static func localizedColorName(_ englishName: String) -> String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        guard isChinese else { return englishName }
        switch englishName.lowercased() {
        case "yellow": return "黄队"
        case "blue": return "蓝队"
        case "red": return "红队"
        case "green": return "绿队"
        case "purple": return "紫队"
        case "orange": return "橙队"
        case "pink": return "粉队"
        case "cyan": return "青队"
        case "black": return "黑队"
        case "white": return "白队"
        default: return englishName
        }
    }
}

/// Stored team configuration for remembering player assignments between games
struct SavedTeamConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var programId: UUID?           // Associate with program for reuse
    var sessionId: UUID?           // Or specific session
    var teams: [GameTeam]
    var gameType: SessionGameType
    var lastUsed: Date
    var name: String?              // Optional name for the configuration
    
    init(id: UUID = UUID(), programId: UUID? = nil, sessionId: UUID? = nil,
         teams: [GameTeam], gameType: SessionGameType = .twoTeam,
         lastUsed: Date = Date(), name: String? = nil) {
        self.id = id
        self.programId = programId
        self.sessionId = sessionId
        self.teams = teams
        self.gameType = gameType
        self.lastUsed = lastUsed
        self.name = name
    }
}

/// Individual player stats for a single in-session game
struct SessionPlayerStats: Codable, Hashable, Identifiable {
    let id: UUID
    var playerId: UUID
    var gameId: UUID
    var teamId: UUID
    var points: Int
    var rebounds: Int
    var assists: Int
    var steals: Int
    var blocks: Int
    var fouls: Int
    
    init(id: UUID = UUID(), playerId: UUID, gameId: UUID, teamId: UUID,
         points: Int = 0, rebounds: Int = 0, assists: Int = 0,
         steals: Int = 0, blocks: Int = 0, fouls: Int = 0) {
        self.id = id
        self.playerId = playerId
        self.gameId = gameId
        self.teamId = teamId
        self.points = points
        self.rebounds = rebounds
        self.assists = assists
        self.steals = steals
        self.blocks = blocks
        self.fouls = fouls
    }
    
    var hasStats: Bool { points > 0 || rebounds > 0 || assists > 0 || steals > 0 || blocks > 0 }
}

enum SessionGameStatus: String, Codable, CaseIterable {
    case setup, ready, inProgress, paused, completed
    
    var displayName: String {
        switch self {
        case .setup: return "Setup"
        case .ready: return "Ready"
        case .inProgress: return "In Progress"
        case .paused: return "Paused"
        case .completed: return "Completed"
        }
    }
}

enum StatType {
    case points(Int), rebound, assist, steal, block, foul
}

/// A single scrimmage game within a session
struct SessionGame: Codable, Hashable, Identifiable {
    let id: UUID
    var sessionId: UUID
    var gameNumber: Int
    var gameType: SessionGameType     // Type of game (2-team or continuous)
    var teams: [GameTeam]
    var activeTeamIds: [UUID]         // Teams currently on court (2 for twoTeam, 3 for continuous)
    var teamScores: [UUID: Int]
    var playerStats: [SessionPlayerStats]
    var durationMinutes: Int
    var roundNumber: Int              // Current round within this game series
    var status: SessionGameStatus
    var startedAt: Date?
    var endedAt: Date?
    var winningTeamId: UUID?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), sessionId: UUID, gameNumber: Int = 1,
         gameType: SessionGameType = .twoTeam, teams: [GameTeam] = [], 
         activeTeamIds: [UUID]? = nil, teamScores: [UUID: Int] = [:],
         playerStats: [SessionPlayerStats] = [], durationMinutes: Int = 10,
         roundNumber: Int = 1, status: SessionGameStatus = .setup, 
         startedAt: Date? = nil, endedAt: Date? = nil,
         winningTeamId: UUID? = nil, notes: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.gameNumber = gameNumber
        self.gameType = gameType
        self.teams = teams
        // Default active teams to first N teams based on game type
        self.activeTeamIds = activeTeamIds ?? Array(teams.prefix(gameType.requiredTeams).map { $0.id })
        self.teamScores = teamScores
        self.playerStats = playerStats
        self.durationMinutes = durationMinutes
        self.roundNumber = roundNumber
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.winningTeamId = winningTeamId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom decoder to handle missing gameType (for backward compatibility)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        gameNumber = try container.decode(Int.self, forKey: .gameNumber)
        // Default to .twoTeam if gameType is missing (backward compatibility)
        gameType = try container.decodeIfPresent(SessionGameType.self, forKey: .gameType) ?? .twoTeam
        teams = try container.decode([GameTeam].self, forKey: .teams)
        activeTeamIds = try container.decodeIfPresent([UUID].self, forKey: .activeTeamIds) ?? []
        teamScores = try container.decode([UUID: Int].self, forKey: .teamScores)
        playerStats = try container.decode([SessionPlayerStats].self, forKey: .playerStats)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        roundNumber = try container.decodeIfPresent(Int.self, forKey: .roundNumber) ?? 1
        status = try container.decode(SessionGameStatus.self, forKey: .status)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        winningTeamId = try container.decodeIfPresent(UUID.self, forKey: .winningTeamId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, sessionId, gameNumber, gameType, teams, activeTeamIds, teamScores
        case playerStats, durationMinutes, roundNumber, status, startedAt, endedAt
        case winningTeamId, notes, createdAt, updatedAt
    }
    
    /// Get teams currently on court
    var activeTeams: [GameTeam] {
        teams.filter { activeTeamIds.contains($0.id) }
    }
    
    /// Get teams waiting off court
    var waitingTeams: [GameTeam] {
        teams.filter { !activeTeamIds.contains($0.id) }
    }
    
    /// Rotate teams for winner-stays-on (2-team game)
    mutating func rotateTeamsForWinner(winnerId: UUID) {
        guard gameType == .twoTeam, teams.count > 2 else { return }
        
        // Find the losing team (the other active team)
        let losingTeamId = activeTeamIds.first { $0 != winnerId }
        
        // Find next waiting team
        if let nextTeam = waitingTeams.first {
            // Replace losing team with waiting team
            if let losingId = losingTeamId {
                activeTeamIds = activeTeamIds.map { $0 == losingId ? nextTeam.id : $0 }
            }
        }
        
        // Update win/loss records
        if let winnerIndex = teams.firstIndex(where: { $0.id == winnerId }) {
            teams[winnerIndex].wins += 1
        }
        if let losingId = losingTeamId, let loserIndex = teams.firstIndex(where: { $0.id == losingId }) {
            teams[loserIndex].losses += 1
        }
        
        roundNumber += 1
        updatedAt = Date()
    }
    
    /// Rotate teams for continuous full court (3-team game)
    mutating func rotateTeamsForContinuous(scoringTeamId: UUID) {
        guard gameType == .continuousFullCourt else { return }
        
        // In continuous: scoring team becomes defending, defending team that got scored on goes to attack
        // The other defending team stays
        // This creates a rotation based on who scores
        
        for i in teams.indices {
            if teams[i].id == scoringTeamId {
                // Scorer moves to defense
                teams[i].role = teams[i].role == .attacking ? .defendingA : .attacking
            }
        }
        
        roundNumber += 1
        updatedAt = Date()
    }
    
    func score(for teamId: UUID) -> Int { teamScores[teamId] ?? 0 }
    func stats(for playerId: UUID) -> SessionPlayerStats? { playerStats.first { $0.playerId == playerId } }
    
    /// For Battle Royal: get individual player score (uses playerId as pseudo-teamId)
    func individualScore(for playerId: UUID) -> Int {
        guard gameType.isIndividual else { return 0 }
        return playerStats.first { $0.playerId == playerId }?.points ?? 0
    }
    
    /// For Battle Royal: get all players sorted by score (leaderboard)
    var individualLeaderboard: [(playerId: UUID, points: Int)] {
        guard gameType.isIndividual else { return [] }
        return playerStats
            .map { ($0.playerId, $0.points) }
            .sorted { $0.points > $1.points }
    }
    
    /// All player IDs participating in this game (for Battle Royal where there are no teams)
    var allPlayerIds: [UUID] {
        if gameType.isIndividual {
            return playerStats.map { $0.playerId }
        } else {
            return teams.flatMap { $0.playerIds }
        }
    }
    
    mutating func addStat(_ stat: StatType, for playerId: UUID, teamId: UUID) {
        if let index = playerStats.firstIndex(where: { $0.playerId == playerId }) {
            switch stat {
            case .points(let pts): playerStats[index].points += pts; teamScores[teamId, default: 0] += pts
            case .rebound: playerStats[index].rebounds += 1
            case .assist: playerStats[index].assists += 1
            case .steal: playerStats[index].steals += 1
            case .block: playerStats[index].blocks += 1
            case .foul: playerStats[index].fouls += 1
            }
        } else {
            var newStats = SessionPlayerStats(playerId: playerId, gameId: id, teamId: teamId)
            switch stat {
            case .points(let pts): newStats.points = pts; teamScores[teamId, default: 0] += pts
            case .rebound: newStats.rebounds = 1
            case .assist: newStats.assists = 1
            case .steal: newStats.steals = 1
            case .block: newStats.blocks = 1
            case .foul: newStats.fouls = 1
            }
            playerStats.append(newStats)
        }
        updatedAt = Date()
    }
    
    /// Remove a stat (undo mistakenly awarded stat)
    mutating func removeStat(_ stat: StatType, for playerId: UUID, teamId: UUID) {
        guard let index = playerStats.firstIndex(where: { $0.playerId == playerId }) else { return }
        switch stat {
        case .points(let pts):
            let newPoints = max(0, playerStats[index].points - pts)
            let diff = playerStats[index].points - newPoints
            playerStats[index].points = newPoints
            teamScores[teamId, default: 0] = max(0, (teamScores[teamId] ?? 0) - diff)
        case .rebound: playerStats[index].rebounds = max(0, playerStats[index].rebounds - 1)
        case .assist: playerStats[index].assists = max(0, playerStats[index].assists - 1)
        case .steal: playerStats[index].steals = max(0, playerStats[index].steals - 1)
        case .block: playerStats[index].blocks = max(0, playerStats[index].blocks - 1)
        case .foul: playerStats[index].fouls = max(0, playerStats[index].fouls - 1)
        }
        updatedAt = Date()
    }
}

struct SessionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var microCycleId: UUID?      // Parent Phase (required for architect flow)
    var programId: UUID?          // Parent Program (for quick lookup)
    var sessionType: SessionType
    var title: String
    var date: Date                // Required timestamp for calendar query
    var startTime: Date
    var endTime: Date
    var location: String?
    var status: SessionEventStatus
    
    // Curriculum (Plan tab)
    var curriculum: SessionCurriculum
    
    // Attendance
    var attendeeIds: [UUID]       // Expected attendees (from program enrollment)
    var actualAttendeeIds: [UUID] // Who actually showed up
    var excusedAbsences: [UUID]   // Students who notified absence in advance (session preserved)
    var attendancePhotoPath: String? // Local path to compressed attendance photo
    
    // Notes
    var notes: String?            // Pre-session notes/plan
    var coachNotes: String?       // Post-session coach reflections
    
    // Development focus (theme for phase-less programs)
    var developmentFocus: [TrainingFocus]  // Training focus for this session (e.g., Shooting, Defense)
    
    // Post-session data
    var manOfTheMatchId: UUID?
    var drillsCompleted: [UUID]
    var rating: Int?
    var createdByCoachId: UUID?   // Coach who created this session (for access control)
    var assignedCoachIds: [UUID]  // Coaches assigned to co-coach this session
    
    // In-session games (scrimmages with team assignments and stats)
    var games: [SessionGame]
    
    // Header image URL (from Unsplash)
    var headerImageURL: String?
    
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), microCycleId: UUID? = nil, programId: UUID? = nil,
         sessionType: SessionType = .training, title: String, date: Date, startTime: Date, endTime: Date,
         location: String? = nil, status: SessionEventStatus = .scheduled,
         curriculum: SessionCurriculum = SessionCurriculum(),
         attendeeIds: [UUID] = [], actualAttendeeIds: [UUID] = [], excusedAbsences: [UUID] = [], attendancePhotoPath: String? = nil,
         notes: String? = nil, coachNotes: String? = nil,
         developmentFocus: [TrainingFocus] = [],
         manOfTheMatchId: UUID? = nil, drillsCompleted: [UUID] = [], rating: Int? = nil,
         createdByCoachId: UUID? = nil, assignedCoachIds: [UUID] = [], games: [SessionGame] = [],
         headerImageURL: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.microCycleId = microCycleId
        self.programId = programId
        self.sessionType = sessionType
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.status = status
        self.curriculum = curriculum
        self.attendeeIds = attendeeIds
        self.actualAttendeeIds = actualAttendeeIds
        self.excusedAbsences = excusedAbsences
        self.attendancePhotoPath = attendancePhotoPath
        self.notes = notes
        self.coachNotes = coachNotes
        self.developmentFocus = developmentFocus
        self.manOfTheMatchId = manOfTheMatchId
        self.drillsCompleted = drillsCompleted
        self.rating = rating
        self.createdByCoachId = createdByCoachId
        self.assignedCoachIds = assignedCoachIds
        self.games = games
        self.headerImageURL = headerImageURL ?? SessionEvent.randomUnsplashURL()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Generate a random image URL for session headers from Nature, Space, or Art categories
    static func randomUnsplashURL() -> String {
        // Curated image IDs from Unsplash for Nature, Space, and Art
        // These are reliable direct image URLs that won't break
        let curatedImages = [
            // Nature
            "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1426604966848-d7adac402bff?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?w=800&h=400&fit=crop",
            // Space
            "https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1464802686167-b939a6910659?w=800&h=400&fit=crop",
            // Art
            "https://images.unsplash.com/photo-1549490349-8643362247b5?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1547826039-bfc35e0f1ea8?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1482160549825-59d1b23cb208?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=800&h=400&fit=crop",
            "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&h=400&fit=crop"
        ]
        return curatedImages.randomElement() ?? curatedImages[0]
    }
    
    /// Check if session belongs to a phase (architect flow)
    var belongsToPhase: Bool { microCycleId != nil }
    
    var attendanceRate: Double {
        guard !attendeeIds.isEmpty else { return 0 }
        return Double(actualAttendeeIds.count) / Double(attendeeIds.count)
    }
    
    var durationMinutes: Int { Int(endTime.timeIntervalSince(startTime) / 60) }
    var isUpcoming: Bool { date > Date() && status == .scheduled }
    var isPast: Bool { date < Date() || status == .completed }
    
    static let samples: [SessionEvent] = {
        let cal = Calendar.current
        let today = Date()
        return [
            SessionEvent(title: "U12 Skills Training",
                        date: cal.date(byAdding: .day, value: -1, to: today)!,
                        startTime: cal.date(bySettingHour: 16, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: today)!)!,
                        endTime: cal.date(bySettingHour: 17, minute: 30, second: 0, of: cal.date(byAdding: .day, value: -1, to: today)!)!,
                        location: "Main Gym", status: .completed, rating: 4),
            SessionEvent(title: "U14 Team Practice", date: today,
                        startTime: cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!,
                        endTime: cal.date(bySettingHour: 19, minute: 30, second: 0, of: today)!,
                        location: "Court A", status: .scheduled),
            SessionEvent(title: "U10 Fundamentals",
                        date: cal.date(byAdding: .day, value: 1, to: today)!,
                        startTime: cal.date(bySettingHour: 15, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: today)!)!,
                        endTime: cal.date(bySettingHour: 16, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: today)!)!,
                        location: "Training Center", status: .scheduled),
            SessionEvent(title: "Elite Scrimmage",
                        date: cal.date(byAdding: .day, value: 3, to: today)!,
                        startTime: cal.date(bySettingHour: 17, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 3, to: today)!)!,
                        endTime: cal.date(bySettingHour: 19, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 3, to: today)!)!,
                        location: "Main Gym", status: .scheduled)
        ]
    }()
}

struct SessionAttendee: Identifiable, Codable, Hashable {
    let id: UUID
    var sessionEventId: UUID
    var studentId: UUID
    var status: AttendanceStatus
    var arrivalTime: Date?
    var departureTime: Date?
    var performanceRating: Int?
    var notes: String?
    
    init(id: UUID = UUID(), sessionEventId: UUID, studentId: UUID,
         status: AttendanceStatus = .present, arrivalTime: Date? = nil,
         departureTime: Date? = nil, performanceRating: Int? = nil, notes: String? = nil) {
        self.id = id
        self.sessionEventId = sessionEventId
        self.studentId = studentId
        self.status = status
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.performanceRating = performanceRating
        self.notes = notes
    }
}

// MARK: - Training Session Stats (for Parent Reports)
/// Aggregated stats from in-session scrimmage games for a student
struct TrainingSessionStats {
    let studentId: UUID
    let gamesPlayed: Int
    let totalPoints: Int
    let totalRebounds: Int
    let totalAssists: Int
    let totalSteals: Int
    let totalBlocks: Int
    
    var ppg: Double { gamesPlayed > 0 ? Double(totalPoints) / Double(gamesPlayed) : 0 }
    var rpg: Double { gamesPlayed > 0 ? Double(totalRebounds) / Double(gamesPlayed) : 0 }
    var apg: Double { gamesPlayed > 0 ? Double(totalAssists) / Double(gamesPlayed) : 0 }
    var spg: Double { gamesPlayed > 0 ? Double(totalSteals) / Double(gamesPlayed) : 0 }
    var bpg: Double { gamesPlayed > 0 ? Double(totalBlocks) / Double(gamesPlayed) : 0 }
    
    var hasStats: Bool { gamesPlayed > 0 }
    
    /// Calculate training session stats for a student from all sessions
    static func calculate(for studentId: UUID, from sessions: [SessionEvent]) -> TrainingSessionStats {
        var gamesPlayed = 0
        var totalPoints = 0
        var totalRebounds = 0
        var totalAssists = 0
        var totalSteals = 0
        var totalBlocks = 0
        
        for session in sessions {
            for game in session.games where game.status == .completed {
                if let stats = game.stats(for: studentId) {
                    gamesPlayed += 1
                    totalPoints += stats.points
                    totalRebounds += stats.rebounds
                    totalAssists += stats.assists
                    totalSteals += stats.steals
                    totalBlocks += stats.blocks
                }
            }
        }
        
        return TrainingSessionStats(
            studentId: studentId,
            gamesPlayed: gamesPlayed,
            totalPoints: totalPoints,
            totalRebounds: totalRebounds,
            totalAssists: totalAssists,
            totalSteals: totalSteals,
            totalBlocks: totalBlocks
        )
    }
}

// MARK: - Program Relative Radar Metrics
/// Radar chart values based on relative performance within program + coach evaluation
/// Standard model: 8 points from program percentile + 2 points from coach evaluation (except Effort)
struct ProgramRelativeRadarMetrics {
    let scoring: Double      // 0-10
    let playmaking: Double   // 0-10
    let rebounding: Double   // 0-10
    let defense: Double      // 0-10
    let athleticism: Double  // 0-10
    let effort: Double       // 0-10
    let hasGameData: Bool
    let gamesPlayed: Int
    
    /// Normalized values for radar chart (0-1 scale)
    var normalizedValues: [Double] {
        [scoring / 10, playmaking / 10, rebounding / 10, defense / 10, athleticism / 10, effort / 10]
    }
    
    /// Compute radar metrics for a student relative to their program peers
    /// - Parameters:
    ///   - studentId: The student to compute metrics for
    ///   - programId: The program to compare against (nil = all students)
    ///   - sessions: All session events containing game data
    ///   - allStudentIds: All student IDs in the program for comparison
    ///   - skills: Coach's skill evaluation for this student
    static func compute(
        for studentId: UUID,
        programId: UUID?,
        sessions: [SessionEvent],
        allStudentIds: [UUID],
        skills: SkillsEvaluation
    ) -> ProgramRelativeRadarMetrics {
        // Calculate stats for target student
        let studentStats = TrainingSessionStats.calculate(for: studentId, from: sessions)
        
        // Calculate stats for all peers in program
        var allPeerStats: [(id: UUID, stats: TrainingSessionStats)] = []
        for peerId in allStudentIds {
            let peerStats = TrainingSessionStats.calculate(for: peerId, from: sessions)
            if peerStats.hasStats {
                allPeerStats.append((peerId, peerStats))
            }
        }
        
        // If no peer data or student has no stats, fall back to coach evaluation only
        guard studentStats.hasStats, allPeerStats.count > 0 else {
            return fromCoachEvaluationOnly(skills: skills)
        }
        
        // Calculate percentiles (0-1 where 1 = top performer)
        let ppgPercentile = percentile(value: studentStats.ppg, in: allPeerStats.map { $0.stats.ppg })
        let apgPercentile = percentile(value: studentStats.apg, in: allPeerStats.map { $0.stats.apg })
        let rpgPercentile = percentile(value: studentStats.rpg, in: allPeerStats.map { $0.stats.rpg })
        let defenseValue = studentStats.spg + studentStats.bpg
        let defensePercentile = percentile(value: defenseValue, in: allPeerStats.map { $0.stats.spg + $0.stats.bpg })
        
        // Scoring: 8 from percentile + 2 from coach
        let scoringRelative = ppgPercentile * 8.0
        let scoringCoach = Double(skills.scoring) / 5.0  // 1-10 scaled to 0-2
        let scoring = min(10, scoringRelative + scoringCoach)
        
        // Playmaking: 8 from percentile + 2 from coach
        let playmakingRelative = apgPercentile * 8.0
        let playmakingCoach = Double(skills.playmaking) / 5.0
        let playmaking = min(10, playmakingRelative + playmakingCoach)
        
        // Rebounding: 8 from percentile + 2 from coach
        let reboundingRelative = rpgPercentile * 8.0
        let reboundingCoach = Double(skills.rebounding) / 5.0
        let rebounding = min(10, reboundingRelative + reboundingCoach)
        
        // Defense: 8 from percentile + 2 from coach
        let defenseRelative = defensePercentile * 8.0
        let defenseCoach = Double(skills.defense) / 5.0
        let defense = min(10, defenseRelative + defenseCoach)
        
        // Athleticism: No tangible stat, use coach evaluation scaled to 10
        // 8 points from coach athleticism + 2 bonus for having game data
        let athleticism = min(10, Double(skills.athleticism) * 0.8 + 2.0)
        
        // Effort: 6 from coach (intangibles) + 4 from aggregate stats
        let coachEffort = Double(skills.intangibles) / 10.0 * 6.0
        let aggregatePercentile = (ppgPercentile + rpgPercentile + apgPercentile + defensePercentile) / 4.0
        let statsEffort = aggregatePercentile * 4.0
        let effort = min(10, coachEffort + statsEffort)
        
        return ProgramRelativeRadarMetrics(
            scoring: scoring,
            playmaking: playmaking,
            rebounding: rebounding,
            defense: defense,
            athleticism: athleticism,
            effort: effort,
            hasGameData: true,
            gamesPlayed: studentStats.gamesPlayed
        )
    }
    
    /// Fallback when no game data exists - uses coach evaluation only
    private static func fromCoachEvaluationOnly(skills: SkillsEvaluation) -> ProgramRelativeRadarMetrics {
        // Scale coach ratings (1-10) directly, with slight reduction since no game validation
        return ProgramRelativeRadarMetrics(
            scoring: Double(skills.scoring) * 0.8,
            playmaking: Double(skills.playmaking) * 0.8,
            rebounding: Double(skills.rebounding) * 0.8,
            defense: Double(skills.defense) * 0.8,
            athleticism: Double(skills.athleticism) * 0.8,
            effort: Double(skills.intangibles) * 0.8,
            hasGameData: false,
            gamesPlayed: 0
        )
    }
    
    /// Calculate percentile rank (0-1) of a value within a distribution
    private static func percentile(value: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.5 }
        if values.count == 1 { return 0.5 } // Solo student gets neutral
        
        let sorted = values.sorted()
        let belowCount = sorted.filter { $0 < value }.count
        let equalCount = sorted.filter { $0 == value }.count
        
        // Percentile = (below + 0.5 * equal) / total
        return (Double(belowCount) + 0.5 * Double(equalCount)) / Double(values.count)
    }
}

// MARK: - Student Performance Grader (A/B/C)
/// Computes performance grades by comparing students within the same school grade
struct StudentPerformanceGrader {
    
    /// Minimum games required for auto-grading
    static let minimumGamesRequired = 2
    
    /// Minimum peers with sufficient games for valid comparison
    static let minimumPeersRequired = 3
    
    /// Estimate school grade from age (fallback when schoolGrade is nil)
    static func estimateGradeFromAge(_ age: Int?) -> String? {
        guard let age = age else { return nil }
        if age <= 3 { return "K1" }
        if age <= 4 { return "K2" }
        if age <= 5 { return "K3" }
        if age <= 6 { return "P1" }
        if age <= 7 { return "P2" }
        if age <= 8 { return "P3" }
        if age <= 9 { return "P4" }
        if age <= 10 { return "P5" }
        if age <= 11 { return "P6" }
        if age <= 12 { return "M1" }
        if age <= 13 { return "M2" }
        if age <= 14 { return "M3" }
        return "H+"
    }
    
    /// Get effective grade string for a student (explicit or age-estimated)
    static func effectiveGradeKey(for student: Student) -> String? {
        if let grade = student.schoolGrade {
            return grade.rawValue
        }
        return estimateGradeFromAge(student.age)
    }
    
    /// Compute performance grade for a student based on school grade peers
    /// - Parameters:
    ///   - student: The student to grade
    ///   - allStudents: All students for peer comparison
    ///   - sessions: All session events containing game data
    ///   - skills: Coach's skill evaluations keyed by student ID
    /// - Returns: Computed grade (A/B/C) or .ungraded if insufficient data
    static func computeGrade(
        for student: Student,
        allStudents: [Student],
        sessions: [SessionEvent],
        skills: [UUID: SkillsEvaluation]
    ) -> PerformanceGrade {
        // If student has manual override, return that
        if let override = student.performanceGrade {
            return override
        }
        
        // Get student's effective school grade (explicit or age-estimated)
        guard let studentGradeKey = effectiveGradeKey(for: student) else {
            return .ungraded
        }
        
        // Find peers in same effective school grade
        let peers = allStudents.filter { effectiveGradeKey(for: $0) == studentGradeKey }
        
        // Calculate stats for all peers
        var peerScores: [(id: UUID, score: Double, gamesPlayed: Int)] = []
        
        for peer in peers {
            let stats = TrainingSessionStats.calculate(for: peer.id, from: sessions)
            let peerSkills = skills[peer.id] ?? SkillsEvaluation()
            
            // Calculate overall performance score (average of radar metrics)
            let metrics = ProgramRelativeRadarMetrics.compute(
                for: peer.id,
                programId: nil,
                sessions: sessions,
                allStudentIds: peers.map { $0.id },
                skills: peerSkills
            )
            
            let overallScore = (metrics.scoring + metrics.playmaking + metrics.rebounding +
                               metrics.defense + metrics.athleticism + metrics.effort) / 6.0
            
            peerScores.append((peer.id, overallScore, stats.gamesPlayed))
        }
        
        // Filter to peers with minimum games
        let eligiblePeers = peerScores.filter { $0.gamesPlayed >= minimumGamesRequired }
        
        // Check if student has enough games
        guard let studentData = peerScores.first(where: { $0.id == student.id }),
              studentData.gamesPlayed >= minimumGamesRequired else {
            return .ungraded
        }
        
        // Need minimum peers for valid comparison
        guard eligiblePeers.count >= minimumPeersRequired else {
            return .ungraded
        }
        
        // Calculate percentile rank
        let studentScore = studentData.score
        let allScores = eligiblePeers.map { $0.score }
        let percentile = calculatePercentile(value: studentScore, in: allScores)
        
        // Assign grade based on percentile
        if percentile >= 0.75 {
            return .A  // Top 25%
        } else if percentile >= 0.25 {
            return .B  // Middle 50%
        } else {
            return .C  // Bottom 25%
        }
    }
    
    /// Calculate percentile rank (0-1) of a value within a distribution
    private static func calculatePercentile(value: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.5 }
        if values.count == 1 { return 0.5 }
        
        let sorted = values.sorted()
        let belowCount = sorted.filter { $0 < value }.count
        let equalCount = sorted.filter { $0 == value }.count
        
        return (Double(belowCount) + 0.5 * Double(equalCount)) / Double(values.count)
    }
}

