import Foundation
import SwiftData

@Model
final class SDGame {
    @Attribute(.unique) var id: UUID
    var homeTeamId: UUID
    var awayTeamId: UUID
    var homeScore: Int
    var awayScore: Int
    var date: Date
    var venue: String?
    var locationId: UUID?
    var refereeId: UUID?
    var statusRaw: String
    var quarter: Int?
    var timeRemaining: String?
    var notes: String?
    var playerStatsData: Data? // JSON encoded PlayerGameStats array
    var scoringPlaysData: Data? // JSON encoded ScoringPlay array
    var quarterScoresData: Data? // JSON encoded QuarterScore array
    var createdAt: Date
    var updatedAt: Date
    
    var status: GameStatus {
        get { GameStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }
    
    var playerStats: [PlayerGameStats] {
        get {
            guard let data = playerStatsData else { return [] }
            return (try? JSONDecoder().decode([PlayerGameStats].self, from: data)) ?? []
        }
        set {
            playerStatsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var scoringPlays: [ScoringPlay] {
        get {
            guard let data = scoringPlaysData else { return [] }
            return (try? JSONDecoder().decode([ScoringPlay].self, from: data)) ?? []
        }
        set {
            scoringPlaysData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var quarterScores: [QuarterScore] {
        get {
            guard let data = quarterScoresData else { return [] }
            return (try? JSONDecoder().decode([QuarterScore].self, from: data)) ?? []
        }
        set {
            quarterScoresData = try? JSONEncoder().encode(newValue)
        }
    }
    
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
        self.statusRaw = status.rawValue
        self.quarter = quarter
        self.timeRemaining = timeRemaining
        self.notes = notes
        self.playerStatsData = try? JSONEncoder().encode(playerStats)
        self.scoringPlaysData = try? JSONEncoder().encode(scoringPlays)
        self.quarterScoresData = try? JSONEncoder().encode(quarterScores)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Conversion Methods
    static func from(_ game: Game) -> SDGame {
        SDGame(
            id: game.id,
            homeTeamId: game.homeTeamId,
            awayTeamId: game.awayTeamId,
            homeScore: game.homeScore,
            awayScore: game.awayScore,
            date: game.date,
            venue: game.venue,
            locationId: game.locationId,
            refereeId: game.refereeId,
            status: game.status,
            quarter: game.quarter,
            timeRemaining: game.timeRemaining,
            notes: game.notes,
            playerStats: game.playerStats,
            scoringPlays: game.scoringPlays,
            quarterScores: game.quarterScores,
            createdAt: game.createdAt,
            updatedAt: game.updatedAt
        )
    }
    
    func toGame() -> Game {
        Game(
            id: id,
            homeTeamId: homeTeamId,
            awayTeamId: awayTeamId,
            homeScore: homeScore,
            awayScore: awayScore,
            date: date,
            venue: venue,
            locationId: locationId,
            refereeId: refereeId,
            status: status,
            quarter: quarter,
            timeRemaining: timeRemaining,
            notes: notes,
            playerStats: playerStats,
            scoringPlays: scoringPlays,
            quarterScores: quarterScores,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
