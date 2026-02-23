import Foundation

enum TrainingFocus: String, Codable, CaseIterable {
    case shooting, ballHandling, passing, defense, conditioning, teamPlay, gamePrep, recovery
    
    var displayName: String {
        switch self {
        case .shooting: return "Shooting"
        case .ballHandling: return "Ball Handling"
        case .passing: return "Passing"
        case .defense: return "Defense"
        case .conditioning: return "Conditioning"
        case .teamPlay: return "Team Play"
        case .gamePrep: return "Game Preparation"
        case .recovery: return "Recovery"
        }
    }
    
    var icon: String {
        switch self {
        case .shooting: return "target"
        case .ballHandling: return "hand.raised"
        case .passing: return "arrow.left.arrow.right"
        case .defense: return "shield"
        case .conditioning: return "figure.run"
        case .teamPlay: return "person.3"
        case .gamePrep: return "sportscourt"
        case .recovery: return "heart"
        }
    }
}

struct MicroCycle: Identifiable, Codable, Hashable {
    let id: UUID
    var programId: UUID
    var phaseNumber: Int
    var title: String
    var focus: [TrainingFocus]
    var durationWeeks: Int
    var description: String?
    var objectives: [String]
    var startDate: Date?
    var endDate: Date?
    var intensity: Int
    var volume: Int
    var createdAt: Date
    var updatedAt: Date
    
    // Legacy support for durationDays
    var durationDays: Int {
        get { durationWeeks * 7 }
        set { durationWeeks = max(1, newValue / 7) }
    }
    
    init(id: UUID = UUID(), programId: UUID, phaseNumber: Int, title: String,
         focus: [TrainingFocus] = [], durationWeeks: Int = 2, description: String? = nil,
         objectives: [String] = [], startDate: Date? = nil, endDate: Date? = nil,
         intensity: Int = 5, volume: Int = 5,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.programId = programId
        self.phaseNumber = phaseNumber
        self.title = title
        self.focus = focus
        self.durationWeeks = durationWeeks
        self.description = description
        self.objectives = objectives
        self.startDate = startDate
        self.endDate = endDate
        self.intensity = intensity
        self.volume = volume
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var focusDisplayText: String { focus.map { $0.displayName }.joined(separator: ", ") }
    
    static func samples(for programId: UUID) -> [MicroCycle] {
        [
            MicroCycle(programId: programId, phaseNumber: 1, title: "Foundation Phase",
                      focus: [.ballHandling, .passing], durationWeeks: 2,
                      description: "Building fundamental skills", intensity: 4, volume: 6),
            MicroCycle(programId: programId, phaseNumber: 2, title: "Skill Development",
                      focus: [.shooting, .ballHandling], durationWeeks: 2,
                      description: "Intensive skill work", intensity: 6, volume: 7),
            MicroCycle(programId: programId, phaseNumber: 3, title: "Competition Prep",
                      focus: [.defense, .teamPlay, .gamePrep], durationWeeks: 2,
                      description: "Game-like situations", intensity: 8, volume: 6),
            MicroCycle(programId: programId, phaseNumber: 4, title: "Peak & Recovery",
                      focus: [.gamePrep, .recovery], durationWeeks: 1,
                      description: "Final preparation", intensity: 5, volume: 4)
        ]
    }
}
