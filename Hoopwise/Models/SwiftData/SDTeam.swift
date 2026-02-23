import Foundation
import SwiftData

@Model
final class SDTeam {
    @Attribute(.unique) var id: UUID
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
    var createdByCoachId: UUID? // For access control
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        shortName: String,
        colorHex: String = "#E94560",
        secondaryColorHex: String = "#1A1A2E",
        logoSystemImage: String = "basketball.fill",
        mascotTypeRaw: String? = nil,
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
        self.shortName = shortName
        self.colorHex = colorHex
        self.secondaryColorHex = secondaryColorHex
        self.logoSystemImage = logoSystemImage
        self.mascotTypeRaw = mascotTypeRaw
        self.playerIds = playerIds
        self.coachId = coachId
        self.coachName = coachName
        self.homeVenue = homeVenue
        self.createdByCoachId = createdByCoachId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Conversion Methods
    static func from(_ team: Team) -> SDTeam {
        SDTeam(
            id: team.id,
            name: team.name,
            shortName: team.shortName,
            colorHex: team.colorHex,
            secondaryColorHex: team.secondaryColorHex,
            logoSystemImage: team.logoSystemImage,
            mascotTypeRaw: team.mascotTypeRaw,
            playerIds: team.playerIds,
            coachId: team.coachId,
            coachName: team.coachName,
            homeVenue: team.homeVenue,
            createdByCoachId: team.createdByCoachId,
            createdAt: team.createdAt,
            updatedAt: team.updatedAt
        )
    }
    
    func toTeam() -> Team {
        var team = Team(
            id: id,
            name: name,
            shortName: shortName,
            colorHex: colorHex,
            secondaryColorHex: secondaryColorHex,
            logoSystemImage: logoSystemImage,
            playerIds: playerIds,
            coachId: coachId,
            coachName: coachName,
            homeVenue: homeVenue,
            createdByCoachId: createdByCoachId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        team.mascotTypeRaw = mascotTypeRaw
        return team
    }
}
