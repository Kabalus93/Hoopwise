import Foundation
import SwiftUI

// MARK: - Team
struct Team: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var shortName: String
    var colorHex: String
    var secondaryColorHex: String
    var logoSystemImage: String
    var mascotTypeRaw: String?  // Stores TeamMascotType.rawValue
    var playerIds: [UUID]
    var coachId: UUID?          // Assigned coach from Organization
    var coachName: String?
    var homeVenue: String?
    var createdByCoachId: UUID? // Coach who created this team (for access control)
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        shortName: String,
        colorHex: String = "#E94560",
        secondaryColorHex: String = "#1A1A2E",
        logoSystemImage: String = "basketball.fill",
        mascotType: TeamMascotType? = nil,
        playerIds: [UUID] = [],
        coachId: UUID? = nil,
        coachName: String? = nil,
        homeVenue: String? = nil,
        createdByCoachId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.shortName = String(shortName.uppercased().prefix(3))
        self.colorHex = colorHex
        self.secondaryColorHex = secondaryColorHex
        self.logoSystemImage = logoSystemImage
        self.mascotTypeRaw = mascotType?.rawValue
        self.playerIds = playerIds
        self.coachId = coachId
        self.coachName = coachName
        self.homeVenue = homeVenue
        self.createdByCoachId = createdByCoachId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var primaryColor: Color { Color(hex: colorHex) }
    var secondaryColor: Color { Color(hex: secondaryColorHex) }
    var accentColor: Color { Color(hex: mascotType?.accentColorHex ?? colorHex) }
    var playerCount: Int { playerIds.count }
    
    /// The mascot type for this team (if using preset mascot)
    var mascotType: TeamMascotType? {
        get { mascotTypeRaw.flatMap { TeamMascotType(rawValue: $0) } }
        set { mascotTypeRaw = newValue?.rawValue }
    }
    
    /// Whether this team has a custom mascot logo
    var hasMascot: Bool { mascotType != nil }
    
    static let samples: [Team] = [
        Team(name: "Siberian Strikers", shortName: "STR", colorHex: "#F97316", secondaryColorHex: "#7C2D12", logoSystemImage: "cat.fill", mascotType: .tiger),
        Team(name: "Golden Eagle Talons", shortName: "GET", colorHex: "#CA8A04", secondaryColorHex: "#1C1917", logoSystemImage: "bird.fill", mascotType: .eagle),
        Team(name: "Giant Panda Fury", shortName: "GPF", colorHex: "#1F2937", secondaryColorHex: "#F9FAFB", logoSystemImage: "circle.hexagongrid.fill", mascotType: .panda),
        Team(name: "Moon Bear Rage", shortName: "MBR", colorHex: "#1F2937", secondaryColorHex: "#EF4444", logoSystemImage: "moon.fill", mascotType: .bear)
    ]
}

// MARK: - Game Status
enum GameStatus: String, Codable, CaseIterable {
    case scheduled = "Scheduled"
    case live = "Live"
    case finished = "Finished"
    case cancelled = "Cancelled"
    case postponed = "Postponed"
    
    var color: Color {
        switch self {
        case .scheduled: return Color(hex: "#5B8DEF")
        case .live: return Color(hex: "#EF4444")
        case .finished: return Color(hex: "#6BCB77")
        case .cancelled: return Color(hex: "#9CA3AF")
        case .postponed: return Color(hex: "#F59E0B")
        }
    }
    
    var icon: String {
        switch self {
        case .scheduled: return "calendar"
        case .live: return "circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .postponed: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Game
struct Game: Identifiable, Codable, Hashable {
    let id: UUID
    var homeTeamId: UUID
    var awayTeamId: UUID
    var homeScore: Int
    var awayScore: Int
    var date: Date
    var venue: String?
    var locationId: UUID?               // Reference to Location from Organization
    var refereeId: UUID?                // Reference to StaffCoach acting as referee
    var status: GameStatus
    var quarter: Int?
    var timeRemaining: String?
    var notes: String?
    var playerStats: [PlayerGameStats]
    var scoringPlays: [ScoringPlay]      // Track all scoring events
    var quarterScores: [QuarterScore]    // Track scores per quarter
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        homeTeamId: UUID,
        awayTeamId: UUID,
        homeScore: Int = 0,
        awayScore: Int = 0,
        date: Date,
        venue: String? = nil,
        locationId: UUID? = nil,
        refereeId: UUID? = nil,
        status: GameStatus = .scheduled,
        quarter: Int? = nil,
        timeRemaining: String? = nil,
        notes: String? = nil,
        playerStats: [PlayerGameStats] = [],
        scoringPlays: [ScoringPlay] = [],
        quarterScores: [QuarterScore] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.homeTeamId = homeTeamId
        self.awayTeamId = awayTeamId
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.date = date
        self.venue = venue
        self.locationId = locationId
        self.refereeId = refereeId
        self.status = status
        self.quarter = quarter
        self.timeRemaining = timeRemaining
        self.notes = notes
        self.playerStats = playerStats
        self.scoringPlays = scoringPlays
        self.quarterScores = quarterScores
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var isLive: Bool { status == .live }
    var isFinished: Bool { status == .finished }
    var isUpcoming: Bool { status == .scheduled && date > Date() }
    
    var scoreDisplay: String {
        "\(homeScore) - \(awayScore)"
    }
    
    var quarterDisplay: String? {
        guard let q = quarter else { return nil }
        if q <= 4 {
            return "Q\(q)"
        } else {
            return "OT\(q - 4)"
        }
    }
    
    // Get score for a specific quarter
    func quarterScore(for q: Int) -> QuarterScore? {
        quarterScores.first { $0.quarter == q }
    }
    
    // Get all scoring plays for a team
    func scoringPlays(for teamId: UUID) -> [ScoringPlay] {
        scoringPlays.filter { $0.teamId == teamId }
    }
    
    // Get scoring plays for a specific quarter
    func scoringPlays(forQuarter q: Int) -> [ScoringPlay] {
        scoringPlays.filter { $0.quarter == q }
    }
    
    // Calculate total points from scoring plays
    var calculatedHomeScore: Int {
        scoringPlays.filter { $0.teamId == homeTeamId }.reduce(0) { $0 + $1.points }
    }
    
    var calculatedAwayScore: Int {
        scoringPlays.filter { $0.teamId == awayTeamId }.reduce(0) { $0 + $1.points }
    }
}

// MARK: - Player Game Stats
struct PlayerGameStats: Identifiable, Codable, Hashable {
    let id: UUID
    var gameId: UUID
    var playerId: UUID
    var teamId: UUID
    var points: Int
    var rebounds: Int
    var assists: Int
    var steals: Int
    var blocks: Int
    var turnovers: Int
    var fouls: Int
    var minutesPlayed: Int
    var fieldGoalsMade: Int
    var fieldGoalsAttempted: Int
    var threePointersMade: Int
    var threePointersAttempted: Int
    var freeThrowsMade: Int
    var freeThrowsAttempted: Int
    
    init(
        id: UUID = UUID(),
        gameId: UUID,
        playerId: UUID,
        teamId: UUID,
        points: Int = 0,
        rebounds: Int = 0,
        assists: Int = 0,
        steals: Int = 0,
        blocks: Int = 0,
        turnovers: Int = 0,
        fouls: Int = 0,
        minutesPlayed: Int = 0,
        fieldGoalsMade: Int = 0,
        fieldGoalsAttempted: Int = 0,
        threePointersMade: Int = 0,
        threePointersAttempted: Int = 0,
        freeThrowsMade: Int = 0,
        freeThrowsAttempted: Int = 0
    ) {
        self.id = id
        self.gameId = gameId
        self.playerId = playerId
        self.teamId = teamId
        self.points = points
        self.rebounds = rebounds
        self.assists = assists
        self.steals = steals
        self.blocks = blocks
        self.turnovers = turnovers
        self.fouls = fouls
        self.minutesPlayed = minutesPlayed
        self.fieldGoalsMade = fieldGoalsMade
        self.fieldGoalsAttempted = fieldGoalsAttempted
        self.threePointersMade = threePointersMade
        self.threePointersAttempted = threePointersAttempted
        self.freeThrowsMade = freeThrowsMade
        self.freeThrowsAttempted = freeThrowsAttempted
    }
    
    var fieldGoalPercentage: Double {
        guard fieldGoalsAttempted > 0 else { return 0 }
        return Double(fieldGoalsMade) / Double(fieldGoalsAttempted) * 100
    }
    
    var threePointPercentage: Double {
        guard threePointersAttempted > 0 else { return 0 }
        return Double(threePointersMade) / Double(threePointersAttempted) * 100
    }
    
    var freeThrowPercentage: Double {
        guard freeThrowsAttempted > 0 else { return 0 }
        return Double(freeThrowsMade) / Double(freeThrowsAttempted) * 100
    }
    
    var efficiency: Double {
        Double(points + rebounds + assists + steals + blocks - turnovers)
    }
}

// MARK: - Season Stats (Aggregated)
struct SeasonStats: Identifiable, Codable, Hashable {
    let id: UUID
    var playerId: UUID
    var gamesPlayed: Int
    var totalPoints: Int
    var totalRebounds: Int
    var totalAssists: Int
    var totalSteals: Int
    var totalBlocks: Int
    var totalTurnovers: Int
    var totalMinutes: Int
    
    init(
        id: UUID = UUID(),
        playerId: UUID,
        gamesPlayed: Int = 0,
        totalPoints: Int = 0,
        totalRebounds: Int = 0,
        totalAssists: Int = 0,
        totalSteals: Int = 0,
        totalBlocks: Int = 0,
        totalTurnovers: Int = 0,
        totalMinutes: Int = 0
    ) {
        self.id = id
        self.playerId = playerId
        self.gamesPlayed = gamesPlayed
        self.totalPoints = totalPoints
        self.totalRebounds = totalRebounds
        self.totalAssists = totalAssists
        self.totalSteals = totalSteals
        self.totalBlocks = totalBlocks
        self.totalTurnovers = totalTurnovers
        self.totalMinutes = totalMinutes
    }
    
    var ppg: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(totalPoints) / Double(gamesPlayed)
    }
    
    var rpg: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(totalRebounds) / Double(gamesPlayed)
    }
    
    var apg: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(totalAssists) / Double(gamesPlayed)
    }
    
    var spg: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(totalSteals) / Double(gamesPlayed)
    }
    
    var bpg: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(totalBlocks) / Double(gamesPlayed)
    }
    
    var mpg: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(totalMinutes) / Double(gamesPlayed)
    }
}

// MARK: - Scoring Play
/// Represents a single scoring event in a game
struct ScoringPlay: Identifiable, Codable, Hashable {
    let id: UUID
    var gameId: UUID
    var playerId: UUID
    var teamId: UUID
    var points: Int          // 1, 2, or 3
    var playType: ScoringPlayType
    var quarter: Int
    var timestamp: Date
    var assistedById: UUID?  // Player who assisted (optional)
    
    init(
        id: UUID = UUID(),
        gameId: UUID,
        playerId: UUID,
        teamId: UUID,
        points: Int,
        playType: ScoringPlayType,
        quarter: Int,
        timestamp: Date = Date(),
        assistedById: UUID? = nil
    ) {
        self.id = id
        self.gameId = gameId
        self.playerId = playerId
        self.teamId = teamId
        self.points = points
        self.playType = playType
        self.quarter = quarter
        self.timestamp = timestamp
        self.assistedById = assistedById
    }
}

enum ScoringPlayType: String, Codable, CaseIterable {
    case freeThrow = "Free Throw"
    case layup = "Layup"
    case jumpShot = "Jump Shot"
    case dunk = "Dunk"
    case threePointer = "3-Pointer"
    case hookShot = "Hook Shot"
    case tipIn = "Tip-In"
    case putback = "Putback"
    
    var icon: String {
        switch self {
        case .freeThrow: return "1.circle.fill"
        case .layup: return "figure.basketball"
        case .jumpShot: return "basketball.fill"
        case .dunk: return "arrow.down.circle.fill"
        case .threePointer: return "3.circle.fill"
        case .hookShot: return "arrow.turn.up.right"
        case .tipIn: return "hand.point.up.fill"
        case .putback: return "arrow.uturn.up"
        }
    }
    
    var defaultPoints: Int {
        switch self {
        case .freeThrow: return 1
        case .threePointer: return 3
        default: return 2
        }
    }
    
    static func typesFor(points: Int) -> [ScoringPlayType] {
        switch points {
        case 1: return [.freeThrow]
        case 2: return [.layup, .jumpShot, .dunk, .hookShot, .tipIn, .putback]
        case 3: return [.threePointer]
        default: return []
        }
    }
}

// MARK: - Quarter Score
struct QuarterScore: Codable, Hashable {
    var quarter: Int
    var homeScore: Int
    var awayScore: Int
    
    init(quarter: Int, homeScore: Int = 0, awayScore: Int = 0) {
        self.quarter = quarter
        self.homeScore = homeScore
        self.awayScore = awayScore
    }
}

// MARK: - Team Standing
struct TeamStanding: Identifiable, Codable, Hashable {
    let id: UUID
    var teamId: UUID
    var wins: Int
    var losses: Int
    var pointsFor: Int
    var pointsAgainst: Int
    var streak: Int // Positive = win streak, negative = loss streak
    var lastFiveResults: [Bool] // true = win, false = loss
    
    init(
        id: UUID = UUID(),
        teamId: UUID,
        wins: Int = 0,
        losses: Int = 0,
        pointsFor: Int = 0,
        pointsAgainst: Int = 0,
        streak: Int = 0,
        lastFiveResults: [Bool] = []
    ) {
        self.id = id
        self.teamId = teamId
        self.wins = wins
        self.losses = losses
        self.pointsFor = pointsFor
        self.pointsAgainst = pointsAgainst
        self.streak = streak
        self.lastFiveResults = lastFiveResults
    }
    
    var gamesPlayed: Int { wins + losses }
    
    var winPercentage: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(wins) / Double(gamesPlayed)
    }
    
    var pointDifferential: Int { pointsFor - pointsAgainst }
    
    var record: String { "\(wins)-\(losses)" }
    
    var streakDisplay: String {
        if streak > 0 {
            return "W\(streak)"
        } else if streak < 0 {
            return "L\(abs(streak))"
        }
        return "-"
    }
}
