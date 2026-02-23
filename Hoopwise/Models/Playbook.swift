import Foundation

enum PlayCategory: String, Codable, CaseIterable {
    case motionOffense, setPlays, zoneOffense, zoneDefense, manDefense, pressBreak, fastBreak, outOfBounds
    
    var displayName: String {
        switch self {
        case .motionOffense: return "Motion Offense"
        case .setPlays: return "Set Plays"
        case .zoneOffense: return "Zone Offense"
        case .zoneDefense: return "Zone Defense"
        case .manDefense: return "Man-to-Man Defense"
        case .pressBreak: return "Press Breaks"
        case .fastBreak: return "Fast Break"
        case .outOfBounds: return "Out of Bounds"
        }
    }
    
    var icon: String {
        switch self {
        case .motionOffense: return "arrow.triangle.2.circlepath"
        case .setPlays: return "list.clipboard"
        case .zoneOffense: return "square.grid.3x3"
        case .zoneDefense: return "shield.lefthalf.filled"
        case .manDefense: return "person.2"
        case .pressBreak: return "arrow.up.forward"
        case .fastBreak: return "hare"
        case .outOfBounds: return "rectangle.portrait.arrowtriangle.2.outward"
        }
    }
}

struct PlayStep: Identifiable, Codable, Hashable {
    let id: UUID
    var stepNumber: Int
    var description: String
    var playerActions: [String: String]
    var keyPoint: String?
    
    init(id: UUID = UUID(), stepNumber: Int, description: String,
         playerActions: [String: String] = [:], keyPoint: String? = nil) {
        self.id = id
        self.stepNumber = stepNumber
        self.description = description
        self.playerActions = playerActions
        self.keyPoint = keyPoint
    }
}

struct Play: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: PlayCategory
    var formation: String
    var description: String
    var keyTeachingPoints: [String]
    var steps: [PlayStep]
    var variations: [String]
    var bestUsedAgainst: String?
    var difficulty: DifficultyLevel
    var diagramUrl: String?
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, category: PlayCategory, formation: String = "",
         description: String = "", keyTeachingPoints: [String] = [], steps: [PlayStep] = [],
         variations: [String] = [], bestUsedAgainst: String? = nil,
         difficulty: DifficultyLevel = .intermediate, diagramUrl: String? = nil,
         tags: [String] = [], isFavorite: Bool = false,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.category = category
        self.formation = formation
        self.description = description
        self.keyTeachingPoints = keyTeachingPoints
        self.steps = steps
        self.variations = variations
        self.bestUsedAgainst = bestUsedAgainst
        self.difficulty = difficulty
        self.diagramUrl = diagramUrl
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    static let samples: [Play] = [
        Play(name: "5-Out Motion", category: .motionOffense, formation: "5-Out",
             description: "Spread floor motion offense with constant movement",
             keyTeachingPoints: ["Maintain 15-18 foot spacing", "Cut hard", "Ball reversal"],
             steps: [
                PlayStep(stepNumber: 1, description: "Start in 5-out formation", keyPoint: "Spacing"),
                PlayStep(stepNumber: 2, description: "Pass and cut to basket or away", keyPoint: "Read defender"),
                PlayStep(stepNumber: 3, description: "Fill the vacated spot", keyPoint: "Move on pass")
             ],
             variations: ["Dribble-at action", "Screen away"], bestUsedAgainst: "Man-to-man"),
        Play(name: "2-3 Zone", category: .zoneDefense, formation: "2-3",
             description: "Classic zone defense with two guards up top",
             keyTeachingPoints: ["Active hands in passing lanes", "Close out on shooters", "Box out"],
             bestUsedAgainst: "Poor outside shooting teams"),
        Play(name: "Press Break - 1-4", category: .pressBreak, formation: "1-4 High",
             description: "Breaking full court press with 1-4 alignment",
             keyTeachingPoints: ["Stay calm", "Create passing angles", "Attack middle"],
             difficulty: .intermediate),
        Play(name: "Sideline Out of Bounds", category: .outOfBounds, formation: "Box",
             description: "Quick hitter from sideline",
             keyTeachingPoints: ["Timing", "Screen angles", "Multiple options"],
             difficulty: .beginner)
    ]
}

struct PlaybookCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    var playIds: [UUID]
    var category: PlayCategory?
    var colorHex: String
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, description: String? = nil, playIds: [UUID] = [],
         category: PlayCategory? = nil, colorHex: String = "#2563EB",
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.playIds = playIds
        self.category = category
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var playCount: Int { playIds.count }
}
