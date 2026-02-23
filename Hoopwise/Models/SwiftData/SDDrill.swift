import Foundation
import SwiftData

@Model
final class SDDrill {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRaw: String
    var difficultyRaw: String
    var durationMinutes: Int
    var drillDescription: String
    var instructions: [String]
    var keyPoints: [String]
    var equipmentNeeded: [String]
    var minPlayers: Int
    var maxPlayers: Int?
    var variations: [String]
    var videoUrl: String?
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        category: DrillCategory,
        difficulty: DifficultyLevel = .beginner,
        durationMinutes: Int = 10,
        description: String = "",
        instructions: [String] = [],
        keyPoints: [String] = [],
        equipmentNeeded: [String] = [],
        minPlayers: Int = 1,
        maxPlayers: Int? = nil,
        variations: [String] = [],
        videoUrl: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.difficultyRaw = difficulty.rawValue
        self.durationMinutes = durationMinutes
        self.drillDescription = description
        self.instructions = instructions
        self.keyPoints = keyPoints
        self.equipmentNeeded = equipmentNeeded
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.variations = variations
        self.videoUrl = videoUrl
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var category: DrillCategory {
        get { DrillCategory(rawValue: categoryRaw) ?? .skills }
        set { categoryRaw = newValue.rawValue }
    }
    
    var difficulty: DifficultyLevel {
        get { DifficultyLevel(rawValue: difficultyRaw) ?? .beginner }
        set { difficultyRaw = newValue.rawValue }
    }
    
    var playerRange: String {
        if let max = maxPlayers { return "\(minPlayers)-\(max) players" }
        return "\(minPlayers)+ players"
    }
    
    /// Convert to legacy DrillItem struct
    func toStruct() -> DrillItem {
        DrillItem(
            id: id,
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: drillDescription,
            instructions: instructions,
            keyPoints: keyPoints,
            equipmentNeeded: equipmentNeeded,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            variations: variations,
            videoUrl: videoUrl,
            tags: tags,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    /// Create from legacy DrillItem struct
    static func from(_ drill: DrillItem) -> SDDrill {
        SDDrill(
            id: drill.id,
            name: drill.name,
            category: drill.category,
            difficulty: drill.difficulty,
            durationMinutes: drill.durationMinutes,
            description: drill.description,
            instructions: drill.instructions,
            keyPoints: drill.keyPoints,
            equipmentNeeded: drill.equipmentNeeded,
            minPlayers: drill.minPlayers,
            maxPlayers: drill.maxPlayers,
            variations: drill.variations,
            videoUrl: drill.videoUrl,
            tags: drill.tags,
            isFavorite: drill.isFavorite,
            createdAt: drill.createdAt,
            updatedAt: drill.updatedAt
        )
    }
}
